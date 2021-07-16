
"""
format: "lake" => (various_sources, particles)
"""
function loading(f::Function, ::Type{Dict{String, Vector{Vector{DateDataFrame}}}}, hub::Hub, strap::Strap,
                row_idx=get_sim_range(hub))
    rd = Dict(dst=>Vector{DateDataFrame}[] for dst in get_dst_vec(strap))

    for inflow in strap.inflow_vec
        conc = concentration(f, hub, inflow, row_idx)
        flow_close = flow(Natural(), hub, inflow, row_idx)
        flow_open = flow(Redirect(), hub, inflow, row_idx)

        push!(rd[inflow.dst_close], conc ⊗ flow_close)
        push!(rd[inflow.dst_open], conc ⊗ flow_open)
    end
    for route_vec in single_dst_route_vec(strap)
        for route in route_vec
            # @show route
            push!(rd[route.dst], concentration(f, hub, route, row_idx) ⊗ flow(hub, route, row_idx))
        end
    end

    return rd
end

function loading(f::Function, hub::Hub, strap::Strap, row_idx=get_sim_range(hub))
    rd = loading(f, Dict{String, Vector{Vector{DateDataFrame}}}, hub, strap)
    return Dict(key=>reduce(⊕, ddf_vec_vec) for (key, ddf_vec_vec) in rd)
end

