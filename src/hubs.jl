
struct Hub
    _collector_vec::Vector{Collector}

    _parent::Union{Nothing, Hub}
    _next_runner_vec::Vector{Collector{Restarter}}

    qser_vec::Vector{Dict{Tuple{String, Int}, TimeArray}}
    cumu_struct_vec::Vector{TimeArray}
    WQWCTS_vec::Vector{Dict{String, TimeArray}}
end

function Hub(collector_vec::Vector{<:Collector}, parent=nothing)
    qser_vec = getindex.(get_replacer.(collector_vec), qser_inp)
    
    qser_vec = align.(get_template.(collector_vec), qser_vec)
    cumu_struct_vec = TimeArray[]
    WQWCTS_vec = Dict{String, TimeArray}[]

    return Hub(collector_vec, parent, Restarter[], qser_vec, cumu_struct_vec, WQWCTS_vec)
end

function Hub(runner_vec::Vector{<:Union{Replacer, Restarter}})
    collector_vec = Collector.(runner_vec, [[cumu_struct_outflow_out, WQWCTS_OUT]])
    return Hub(collector_vec)
end

function Hub(template_vec::Vector{<:AbstractSimulationTemplate})
    replacer_vec = Replacer.(template_vec, [[efdc_inp, qser_inp]])
    return Hub(replacer_vec)
end

function is_post(hub::Hub)
    return !isempty(hub._next_runner_vec)
end

function Base.show(io::IO, hub::Hub)
    cumu_struct_str = isempty(hub.cumu_struct_vec) ? "" : "cumu_struct_size->$(size(hub.cumu_struct_vec[1])), "
    WQWCTS_str = isempty(hub.WQWCTS_vec) ? "" : "WQWCTS_size->$(size(first(values(hub.WQWCTS_vec[1])))), "
    print(io, "Hub(particles->$(length(hub._collector_vec)), has_parent->$(isnothing(hub._parent)), " *
        "is_post->$(is_post(hub)), qser_size->$(size(first(values(hub.qser_vec[1]))))," *
        "$cumu_struct_str$WQWCTS_str first_collector->$(first(hub._collector_vec)))")
end

# struct TimeArrayCollection

function run_simulation!(hub::Hub)
    template_vec = get_template.(hub._collector_vec)
    qser_f_vec = getindex.(get_replacer.(hub._collector_vec), qser_inp)
    
    update!.(template_vec, qser_f_vec, hub.qser_vec)

    empty!(hub._next_runner_vec)
    append!(hub._next_runner_vec, Collector{Restarter}.(hub._collector_vec)) # GO!

    cumu_struct_vec = align.(template_vec, getindex.(hub._collector_vec, cumu_struct_outflow_out))
    empty!(hub.cumu_struct_vec)
    append!(hub.cumu_struct_vec, cumu_struct_vec)

    WQWCTS_vec = align.(template_vec, getindex.(hub._collector_vec, WQWCTS_OUT))
    empty!(hub.WQWCTS_vec)
    append!(hub.WQWCTS_vec, WQWCTS_vec)
end

function fork(hub, n::Int)
    return [Hub(copy.(hub.collector_vec), hub) for _ in 1:n]
end

function get_qser_ref(hub::Hub)
    return getfield.(get_template.(hub._collector_vec), :qser_ref)
end

function get_wqpsc_ref(hub::Hub)
    return getfield.(get_template.(hub._collector_vec), :wqpsc_ref)
end

function set_sim_length!(hub::Hub, day_or_date::Union{Day, DateTime})
    return set_sim_length!.(get_replacer.(hub._collector_vec), day_or_date)
end

function get_sim_length(::Type, hub::Hub)
    return get_sim_length!.(get_replacer.(hub._collector_vec[1]))
end