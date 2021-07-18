
struct Hub
    _collector_vec::Vector{Collector}
    encoding_vec::Vector{FrozenEncoding}

    qser_vec::Vector{Dict{Tuple{String, Int}, DateDataFrame}}
    pump_mux_map_vec::Vector{Dict{Tuple{String, String}, DateDataFrame}} # pump: src => dst => date_dataframe
    # `pump_mux_map_vec` is a lazy object, the corresponding pairs will be created when `open!`, `close!` is firstly called.

    _parent::Union{Nothing, Hub}

    # Following will alway be detached in `copy` and `fork`
    _next_runner_vec::Vector{Collector{Restarter}}
    cumu_struct_vec::Vector{DateDataFrame}
    WQWCTS_vec::Vector{Dict{Tuple{Int, Int, Int}, DateDataFrame}}
end

function Hub(collector_vec::Vector{<:Collector}, encoding_vec::Vector{FrozenEncoding}, 
                qser_vec, pump_mux_map_vec, parent=nothing)
    #=
    replacer_vec = get_replacer.(collector_vec)
    template_vec = get_template.(replacer_vec)

    qser_f_vec = getindex.(replacer_vec, qser_inp)

    qser_vec = align.(template_vec, qser_f_vec)
    =#
    cumu_struct_vec = DateDataFrame[]
    WQWCTS_vec = Dict{Tuple{Int, Int, Int}, DateDataFrame}[]

    return Hub(collector_vec, encoding_vec, 
                qser_vec, pump_mux_map_vec,
                parent, 
                Collector{Restarter}[], cumu_struct_vec, WQWCTS_vec)
end

function Hub(collector_vec::Vector{<:Collector})

    replacer_vec = get_replacer.(collector_vec)
    template_vec = get_template.(replacer_vec)

    qser_f_vec = getindex.(replacer_vec, qser_inp)
    efdc_f_vec = getindex.(replacer_vec, efdc_inp)

    if wqpsc_inp in keys(replacer_vec[1])
        wqpsc_f_vec = getindex.(replacer_vec, wqpsc_inp)
    else
        wqpsc_f_vec = getindex.(template_vec, wqpsc_inp)
    end

    qser_vec = align.(template_vec, qser_f_vec)
    encoding_vec = FrozenEncoding.(efdc_f_vec, qser_f_vec, wqpsc_f_vec)

    pump_mux_map_vec = [Dict{Tuple{String, String}, DateDataFrame}() for _ in 1:length(collector_vec)]
    
    return Hub(collector_vec, encoding_vec, qser_vec, pump_mux_map_vec)
end

function Hub(runner_vec::Vector{<:Union{Replacer, Restarter}})
    collector_vec = Collector.(runner_vec, [[cumu_struct_outflow_out, WQWCTS_OUT]])
    return Hub(collector_vec)
end

function Hub(template_vec::Vector{<:AbstractSimulationTemplate})
    replacer_vec = Replacer.(template_vec, [[efdc_inp, qser_inp]])
    return Hub(replacer_vec)
end

function get_template(hub::Hub)
    return get_template.(hub._collector_vec)
end

function get_replacer(hub::Hub)
    return get_replacer.(hub._collector_vec)
end

Base.broadcastable(hub::Hub) = Ref(hub) 

function is_over(hub::Hub)
    return !isempty(hub._next_runner_vec)
end

function Base.show(io::IO, hub::Hub)
    cumu_struct_str = isempty(hub.cumu_struct_vec) ? "" : "cumu_struct_size->$(size(hub.cumu_struct_vec[1])), "
    WQWCTS_str = isempty(hub.WQWCTS_vec) ? "" : "WQWCTS_size->$(size(first(values(hub.WQWCTS_vec[1])))), "
    print(io, "Hub(particles->$(length(hub._collector_vec)), has_parent->$(isnothing(hub._parent)), " *
        "is_over->$(is_over(hub)), qser_size->$(size(first(values(hub.qser_vec[1]))))," *
        "$cumu_struct_str$WQWCTS_str first_collector->$(first(hub._collector_vec)))")
end

function _update_pump_mux(hub::Hub)
    # TODO: check pump is zero at beginning?
    for (qser, pump_mux_map, encoding) in zip(hub.qser_vec, hub.pump_mux_map_vec, hub.encoding_vec)
        set = Set{String}()
        for (src_dst, ddf) in pump_mux_map
            src = src_dst[1]
            if !(src in set)
                push!(set, src)
                for key in encoding.flow_name_to_keys[src]
                    qser[key] .= 0
                end
            end
            for key in encoding.flow_name_to_keys[src]
                qser[key] .+= ddf
            end
        end
    end
end

function run_simulation!(hub::Hub)
    template_vec = get_template(hub)
    qser_f_vec = getindex.(get_replacer(hub), qser_inp)

    _update_pump_mux(hub)

    update!.(template_vec, qser_f_vec, hub.qser_vec)

    empty!(hub._next_runner_vec)
    # TODO: How can we override "constructor.()"?
    # https://discourse.julialang.org/t/custom-broadcasting-for-constructors/64574
    # append!(hub._next_runner_vec, Collector{Restarter}.(hub._collector_vec)) # GO!
    append!(hub._next_runner_vec, Collector{Restarter}(hub._collector_vec)) # ugly hack

    cumu_struct_vec = align.(template_vec, getindex.(hub._collector_vec, cumu_struct_outflow_out))
    empty!(hub.cumu_struct_vec)
    append!(hub.cumu_struct_vec, cumu_struct_vec)

    WQWCTS_vec = align.(template_vec, getindex.(hub._collector_vec, WQWCTS_OUT))
    empty!(hub.WQWCTS_vec)
    append!(hub.WQWCTS_vec, WQWCTS_vec)
end

function run_simulation!(hub_vec::AbstractVector{Hub})
    # TODO: Add auto restart optimization
    task_vec = map(hub_vec) do hub
        return @async run_simulation!(hub)
    end
    return fetch.(task_vec)
end

function fork(hub::Hub, n::Int)
    return [fork(hub) for _ in 1:n]
end

function fork(hub::Hub)
    @assert is_over(hub)
    _next_runner_vec = copy.(hub._next_runner_vec)
    # _next_runner_vec =  length(hub._next_runner_vec) > 0 ? copy.(hub._next_runner_vec) : Collector{Restarter}[]
    return Hub(_next_runner_vec, hub.encoding_vec, deepcopy(hub.qser_vec), deepcopy(hub.pump_mux_map_vec), hub)
end

function Base.copy(hub::Hub)
    @assert !is_over(hub) && length(hub._collector_vec) > 0
    return Hub(copy.(hub._collector_vec), hub.encoding_vec, deepcopy(hub.qser_vec), deepcopy(hub.pump_mux_map_vec), hub._parent)
end

function get_qser_ref(hub::Hub)
    return getproperty.(get_template(hub), :qser_ref)
end

function get_wqpsc_ref(hub::Hub)
    return getproperty.(get_template(hub), :wqpsc_ref)
end

function set_sim_length!(hub::Hub, day_or_date::Union{Day, DateTime})
    return set_sim_length!.(get_replacer(hub), day_or_date)
end

function get_sim_length(T::Type, hub::Hub)
    length_vec = get_sim_length.(T, get_replacer(hub))
    @assert all(length_vec[1] .== length_vec[2:end])
    return first(length_vec)
end

function set_begin_day!(hub::Hub, day_or_date::Union{Day, DateTime})
    return set_begin_day!.(get_replacer(hub), day_or_date)
end

function get_begin_day!(T::Type, hub::Hub)
    return get_begin_day!.(T, get_replacer(hub))
end

get_sim_range(hub::Hub) = get_sim_range.(get_replacer(hub))
