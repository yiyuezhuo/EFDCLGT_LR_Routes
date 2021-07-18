
"""
Strap, a strap of routes. ArchLinux: "pacstrap"?
"""
struct Strap
    inflow_vec::Vector{Inflow}
    ditch_vec::Vector{Ditch}
    overflow_vec::Vector{Overflow}
    pump_natural_vec::Vector{Pump}  # to "natural" direction, such as lake.
    pump_null_vec::Vector{Pump}  # irrigation, redirect to "null" so loading is not counted.
end

function single_dst_route_vec(strap::Strap)
    return [strap.ditch_vec, strap.overflow_vec, strap.pump_natural_vec, strap.pump_null_vec]
end

function get_dst_vec(strap::Strap)
    dst_vec = String[]
    for inflow in strap.inflow_vec
        push!(dst_vec, inflow.dst_close)
        push!(dst_vec, inflow.dst_open)
    end
    for route_vec in single_dst_route_vec(strap)
        for route in route_vec
            push!(dst_vec, route.dst)
        end
    end
    return unique(dst_vec)
end

Base.broadcastable(strap::Strap) = Ref(strap)
