
abstract type Direction end

struct Natural <: Direction end
struct Redirect <: Direction end
struct Limit <: Direction end

abstract type AbstractRoute end;

struct Inflow <: AbstractRoute
    src::String
    dst_close::String
    dst_open::String
end

struct Ditch <: AbstractRoute
    src::String
    dst::String
end

struct Overflow <: AbstractRoute
    idx::Int
    dst::String
end

struct Pump <: AbstractRoute
    src::String
    dst::String
    value::Float64
end

function open!(route::AbstractRoute)
    error("open! is unsupported for $(typeof(route))")
end

function close!(route::AbstractRoute)
    error("close! is unsupported for $(typeof(route))")
end

function flow(::Union{Redirect, Limit}, hub::Hub, inflow::Inflow, qser_vec)
    name_idx_vec_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_keys), inflow.src)
    return map(name_idx_vec_vec) do name_idx_vec
        ta = reduce(.+, getindex.(qser_vec, name_idx_vec))
        rename!(ta, colnames(qser_vec[1][name_idx_vec[1]]))
        return ta
    end
end

function flow(t::Redirect, hub::Hub, inflow::Inflow)
    return flow(t, hub, inflow, hub.qser_vec)
end

function flow(t::Limit, hub::Hub, inflow::Inflow)
    return flow(t, hub, inflow, get_qser_ref(hub))
end

function flow(::Natural, hub::Hub, inflow::Inflow)
    fl = flow(Limit(), hub, inflow)
    fr = flow(Redirect(), hub, inflow)
    cn = colnames(fl[1])
    @assert cn == colnames(fr[1])
    return [rename(l .- r, cn) for (l, r) in zip(fl, fr)]
end

function concentration(hub::Hub, inflow::Inflow)
    return getindex.(get_wqpsc_ref(hub), inflow.src)
end

function flow(hub::Hub, ditch::Ditch)
    return getindex.(hub.qser_vec, ditch.src, 1) # TODO: other than 1?
end

function concentration(hub::Hub, ditch::Ditch)
    # @show ditch.src 
    return getindex.(get_wqpsc_ref(hub), ditch.src) # TODO: other than 1
end

function flow(hub::Hub, overflow::Overflow)
    key_vec = getindex.(colnames.(hub.cumu_struct_vec), overflow.idx)
    return getindex.(hub.cumu_struct_vec, key_vec) # TODO: does it copy a column for every access? Maybe is it better to split it into multiple columns in File API.
end

function concentration(hub::Hub, overflow::Overflow)
    ij_vec = getindex.(getproperty.(hub.encoding_vec, :overflow_idx_to_ij), overflow.idx)
    return [W[ij[1], ij[2], 1] for (W, ij) in zip(hub.WQWCTS_vec, ij_vec)] # TODO: Is it useful to generalize level=1 ?
end

function flow(hub::Hub, pump::Pump)
    return getindex.(hub.qser_vec, pump.src, 1)
end

function concentration(hub::Hub, pump::Pump)
    ij_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_ij), pump.src)
    return [W[ij[1], ij[2], 1] for (W, ij) in zip(hub.WQWCTS_vec, ij_vec)] # TODO: Is it useful to generalize level=1 ? 
end


#=
Inflow("east_west", "lake", "basin")
Ditch("east_west_ditch", "basin")
Overflow(1, "lake")
Pump("pump_outflow", "lake", 1.5)
Pump("pump_outflow", "irrigation", 0.6)


=#