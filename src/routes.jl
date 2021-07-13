
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
    src::Int
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

function flow(::Redirect, hub::Hub, inflow::Inflow)
    return getindex.(hub.qser_vec, inflow.src)
end

function flow(::Limit, hub::Hub, inflow::Inflow)
    return get_qser_ref(hub)[inflow.src]
end

function flow(::Natural, hub::Hub, inflow::Inflow)
    fl = flow(Limit(), hub, inflow)
    fr = flow(Redirect(), hub, inflow)
    cn = colnames(fl[1])
    @assert cn == colnames(fr[1])
    return [rename(l .- r, cn) for (l, r) in zip(fl, fr)]
end

function concentration(hub::Hub, inflow::Inflow)
    return get_wqpsc_ref(hub)[inflow.src]
end

function flow(hub::Hub, ditch::Ditch)
    return getindex.(hub.qser_vec, ditch.src)
end

function concentration(hub::Hub, ditch::Ditch)
    return get_wqpsc_ref(hub)[ditch.src]
end

function flow(hub::Hub, overflow::Overflow)
    key = colnames(hub.cumu_struct_vec)[overflow.src]
    return getindex.(hub.cumu_struct_vec, key) # TODO: does it copy a column for every access? Maybe is it better to split it into multiple columns in File API.
end

function concentration(hub::Hub, overflow::Overflow)
end

function flow(hub::Hub, pump::Pump)
    return getindex.(hub.qser_vec, pump.src)
end

function concentration(hub::Hub, pump::Pump)
end


#=
Inflow("east_west", "lake", "basin")
Ditch("east_west_ditch", "basin")
Overflow(1, "lake")
Pump("pump_outflow", "lake", 1.5)
Pump("pump_outflow", "irrigation", 0.6)


=#