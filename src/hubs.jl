
abstract type AbstractHub end

struct Hub <: AbstractHub
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
    print(io, "Hub(particles->$(length(hub._collector_vec)), has_parent->$(!isnothing(hub._parent)), " *
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

function run_simulation!_pre(hub::Hub)
    template_vec = get_template(hub)
    qser_f_vec = getindex.(get_replacer(hub), qser_inp)

    _update_pump_mux(hub)

    update!.(template_vec, qser_f_vec, hub.qser_vec)

    empty!(hub._next_runner_vec)
end

function run_simulation!_post(hub::Hub, next_runner_vec)
    template_vec = get_template(hub)

    append!(hub._next_runner_vec, next_runner_vec) # ugly hack

    cumu_struct_vec = align.(template_vec, getindex.(hub._collector_vec, cumu_struct_outflow_out))
    empty!(hub.cumu_struct_vec)
    append!(hub.cumu_struct_vec, cumu_struct_vec)

    WQWCTS_vec = align.(template_vec, getindex.(hub._collector_vec, WQWCTS_OUT))
    empty!(hub.WQWCTS_vec)
    append!(hub.WQWCTS_vec, WQWCTS_vec)
end

function run_simulation!(hub::Hub)
    run_simulation!_pre(hub)
    next_runner_vec = Collector{Restarter}(hub._collector_vec)
    run_simulation!_post(hub, next_runner_vec)
    return hub
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

function Base.copy(hub::Hub; detach=false)
    @assert !is_over(hub) && length(hub._collector_vec) > 0
    parent = detach ? nothing : hub._parent
    return Hub(copy.(hub._collector_vec), hub.encoding_vec, deepcopy(hub.qser_vec), deepcopy(hub.pump_mux_map_vec), parent)
end

function get_qser_ref(hub::AbstractHub)
    return getproperty.(get_template(hub), :qser_ref)
end

function get_wqpsc_ref(hub::AbstractHub)
    return getproperty.(get_template(hub), :wqpsc_ref)
end

function set_sim_length!(hub::Hub, day_or_date::Union{Day, DateTime})
    set_sim_length!.(get_replacer(hub), day_or_date)
    return hub
end

function get_sim_length(T::Type, hub::Hub)
    length_vec = get_sim_length.(T, get_replacer(hub))
    @assert all(length_vec[1] .== length_vec[2:end])
    return first(length_vec)
end

function set_begin_day!(hub::Hub, day_or_date::Union{Day, DateTime})
    hub = set_begin_day!.(get_replacer(hub), day_or_date)
    return hub
end

function get_begin_day(T::Type, hub::Hub)
    day_vec = get_begin_day.(T, get_replacer(hub))
    @assert all(day_vec[1:1] .== day_vec[2:end])
    return first(day_vec)
end

function get_sim_range(hub::Hub)
    sr_vec = get_sim_range.(get_replacer(hub))
    @assert all([sr_vec[1]] .== sr_vec[2:end])
    return sr_vec[1]
end

function get_undecided_range(hub::Hub)
    undecided_vec = get_undecided_range.(get_replacer(hub))
    @assert all(undecided_vec[1:1] .== undecided_vec[2:end])
    return undecided_vec[1]
end

function particles(hub::Hub)
    return length(hub._collector_vec)
end

struct HubBacktrackView{ST <: AbstractSimulationTemplate} <: AbstractHub
    _templates::Vector{ST}

    encoding_vec::Vector{FrozenEncoding}
    qser_vec::Vector{Dict{Tuple{String, Int}, DateDataFrame}}
    pump_mux_map_vec::Vector{Dict{Tuple{String, String}, DateDataFrame}}
    cumu_struct_vec::Vector{DateDataFrame}
    WQWCTS_vec::Vector{Dict{Tuple{Int, Int, Int}, DateDataFrame}}
end

function HubBacktrackView(hub_tail::Hub)
    # TODO: use a specific type for it?
    hub = hub_tail
    @assert is_over(hub)

    n = particles(hub)
    hub_vec = Hub[]
    while !isnothing(hub)
        push!(hub_vec, hub)
        hub = hub._parent
    end
    reverse!(hub_vec)

    cumu_struct_vec = deepcopy(hub_vec[1].cumu_struct_vec) # TODO: use proper shallow copy
    WQWCTS_vec = deepcopy(hub_vec[1].WQWCTS_vec)
    for hub in hub_vec[2:end]
        for i in 1:n
            # TODO: use true "view" style rather than copying and allocating.
            cumu_struct_vec[i] = vcat(cumu_struct_vec[i], hub.cumu_struct_vec[i])
            key_vec = collect(keys(WQWCTS_vec[1]))
            for key in key_vec
                WQWCTS_vec[i][key] = vcat(WQWCTS_vec[i][key], hub.WQWCTS_vec[i][key])
            end
        end
    end

    return HubBacktrackView(get_template(hub_tail), hub_tail.encoding_vec, hub_tail.qser_vec, hub_tail.pump_mux_map_vec,
             cumu_struct_vec, WQWCTS_vec)
end

function get_template(hub::HubBacktrackView)
    return return hub._templates
end

is_over(::HubBacktrackView) = true

function Base.show(io::IO, hub::HubBacktrackView)
    cumu_struct_str = isempty(hub.cumu_struct_vec) ? "" : "cumu_struct_size->$(size(hub.cumu_struct_vec[1])), "
    WQWCTS_str = isempty(hub.WQWCTS_vec) ? "" : "WQWCTS_size->$(size(first(values(hub.WQWCTS_vec[1])))), "
    print(io, "HubBacktrackView(particles->$(particles(hub)), " *
        "qser_size->$(size(first(values(hub.qser_vec[1])))), " *
        "$cumu_struct_str$WQWCTS_str")
end

particles(hub::HubBacktrackView) = length(hub.qser_vec)
