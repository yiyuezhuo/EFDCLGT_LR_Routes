
struct Hub
    _collector_vec::Vector{Collector}
    encoding_vec::Vector{FrozenEncoding}

    _parent::Union{Nothing, Hub}
    _next_runner_vec::Vector{Collector{Restarter}}
    
    qser_vec::Vector{Dict{Tuple{String, Int}, DateDataFrame}}
    cumu_struct_vec::Vector{DateDataFrame}
    WQWCTS_vec::Vector{Dict{Tuple{Int, Int, Int}, DateDataFrame}}
end

function Hub(collector_vec::Vector{<:Collector}, encoding_vec::Vector{FrozenEncoding}, parent=nothing)
    replacer_vec = get_replacer.(collector_vec)
    template_vec = get_template.(replacer_vec)

    qser_f_vec = getindex.(replacer_vec, qser_inp)

    qser_vec = align.(template_vec, qser_f_vec)
    cumu_struct_vec = DateDataFrame[]
    WQWCTS_vec = Dict{Tuple{Int, Int, Int}, DateDataFrame}[]

    return Hub(collector_vec, encoding_vec, 
                parent, Restarter[], 
                qser_vec, cumu_struct_vec, WQWCTS_vec)
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

    encoding_vec = FrozenEncoding.(efdc_f_vec, qser_f_vec, wqpsc_f_vec)
    
    return Hub(collector_vec, encoding_vec)
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

function run_simulation!(hub::Hub)
    template_vec = get_template(hub)
    qser_f_vec = getindex.(get_replacer(hub), qser_inp)
    
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

function fork(hub::Hub, n::Int)
    return [fork(hub) for _ in 1:n]
end

function fork(hub::Hub)
    return Hub(copy.(hub._next_runner_vec), hub.encoding_vec, hub)
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

function get_sim_length(::Type, hub::Hub)
    length_vec = get_sim_length.(get_replacer(hub))
    @assert all(length_vec[1] .== length_vec[2:end])
    return first(length_vec)
end

