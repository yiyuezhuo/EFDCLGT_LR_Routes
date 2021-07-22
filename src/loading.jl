
"""
format: "lake" => (various_sources, particles)
"""
function loading(f::Function, ::Type{Dict{String, Vector{Vector{DateDataFrame}}}}, hub::Hub, strap::Strap,
                row_idx=get_sim_range(hub); selected_type_set=all_route_type_set)
    rd = Dict(dst=>Vector{DateDataFrame}[] for dst in get_dst_vec(strap))

    for inflow in strap.inflow_vec
        if !(typeof(inflow) in selected_type_set)
            continue
        end
        conc = concentration(f, hub, inflow, row_idx)
        flow_close = flow(Natural(), hub, inflow, row_idx)
        flow_open = flow(Redirect(), hub, inflow, row_idx)

        push!(rd[inflow.dst_close], conc ⊗ flow_close)
        push!(rd[inflow.dst_open], conc ⊗ flow_open)
    end
    for route_vec in single_dst_route_vec(strap)
        for route in route_vec
            if !(typeof(route) in selected_type_set)
                continue
            end
            # @show route
            push!(rd[route.dst], concentration(f, hub, route, row_idx) ⊗ flow(hub, route, row_idx))
        end
    end

    return rd
end

function loading(f::Function, ::Type{Dict{String, Vector{DateDataFrame}}}, hub::Hub, strap::Strap, row_idx=get_sim_range(hub); selected_type_set=all_route_type_set)
    rd = loading(f, Dict{String, Vector{Vector{DateDataFrame}}}, hub, strap, row_idx; selected_type_set=selected_type_set)
    return Dict(key=>reduce(⊕, ddf_vec_vec) for (key, ddf_vec_vec) in rd if length(ddf_vec_vec) > 0)
end

# This method support f which select one column, such as f=ddf->ddf[!, :ROP]
function loading(f::Function, ::Type{Dict{String, Float64}}, hub::Hub, strap::Strap, row_idx=get_sim_range(hub); selected_type_set=all_route_type_set)
    rd = loading(f, Dict{String, Vector{DateDataFrame}}, hub, strap, row_idx; selected_type_set=selected_type_set)
    return Dict(key=>sum.(ddf_vec) for (key, ddf_vec) in rd)
end

function loading(f::Function, key::String, hub::Hub, strap::Strap, row_idx=get_sim_range(hub); selected_type_set=all_route_type_set)
    rd = loading(f, Dict{String, Float64}, hub, strap, row_idx; selected_type_set=selected_type_set)
    return rd[key]
end
