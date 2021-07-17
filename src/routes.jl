
abstract type Direction end

struct Natural <: Direction end
struct Redirect <: Direction end
struct Limit <: Direction end

name(::Natural) = "Natural"
name(::Redirect) = "Redirect"
name(::Limit) = "Limit"

Base.broadcastable(direction::Direction) = Ref(direction)

#=
struct Position
    name::String
end

Base.broadcastable(pos::Position) = Ref(pos)
name(pos::Position) = pos.name
=#

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
    src::String
    dst::String
end

struct Pump <: AbstractRoute
    src::String
    dst::String
    value::Float64
end

const all_route_type_set = Set([Inflow, Ditch, Overflow, Pump])

name(r::Inflow) = "Inflow $(r.src)"
name(r::Ditch) = "Ditch $(r.src)"
name(r::Overflow) = "Overflow $(r.idx)"
name(r::Pump) = "Pump $(r.src)->$(r.dst)"

"""
This function will return a "view" for hub's qser, so qfactor should not be applied here.
"""
function _get_inflow_ddf_vec_vec(hub::Hub, inflow::Inflow, qser_vec::Vector{Dict{Tuple{String, Int}, DateDataFrame}})
    name_idx_vec_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_keys), inflow.src)
    #=
    name_idx_vec_vec = [
        [("inflow1", 1), ("inflow1", 2)], # particle 1
        [("inflow1", 1), ("inflow1", 2)], # particle 2
        ...
    ]
    =#
    return map(zip(qser_vec, name_idx_vec_vec)) do (qser, name_idx_vec)
        return getindex.([qser], name_idx_vec)
    end
end

function flow(::Union{Redirect, Limit}, hub::Hub, inflow::Inflow, qser_vec::Vector{Dict{Tuple{String, Int}, DateDataFrame}})
    qfactor_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_qfactor), inflow.src)
    #=
    qfactor_vec = [
        inflow1_qfactor, # particle 1
        inflow1_qfactor, # particle 2
        ...
    ]
    =#
    return map(zip(_get_inflow_ddf_vec_vec(hub, inflow, qser_vec), qfactor_vec)) do (ddf_vec, qfactor)
        return reduce(.+, ddf_vec)[!, :flow] .* qfactor
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
    # cn = names(fl[1])
    # @assert cn == names(fr[1])
    return fl ⊖ fr
end

function concentration(hub::Hub, inflow::Inflow)
    return getindex.(get_wqpsc_ref(hub), inflow.src)
end

function flow(hub::Hub, ditch::Ditch)
    qfactor_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_qfactor), ditch.src)
    ddf_vec = getindex.(getindex.(hub.qser_vec, ditch.src, 1), !, :flow) # TODO: other than 1?
    return ddf_vec ⊗ qfactor_vec
end

function concentration(hub::Hub, ditch::Ditch)
    # @show ditch.src 
    return getindex.(get_wqpsc_ref(hub), ditch.src) # TODO: other than 1
end

function flow(hub::Hub, overflow::Overflow)
    key_vec = getindex.(names.(hub.cumu_struct_vec), overflow.idx)
    return getindex.(hub.cumu_struct_vec, :, key_vec) # TODO: does it copy a column for every access? Maybe is it better to split it into multiple columns in File API.
end

function concentration(hub::Hub, overflow::Overflow)
    ij_vec = getindex.(getproperty.(hub.encoding_vec, :overflow_idx_to_ij), overflow.idx)
    return [W[ij[1], ij[2], 1] for (W, ij) in zip(hub.WQWCTS_vec, ij_vec)] # TODO: Is it useful to generalize level=1 ?
end

function flow(hub::Hub, pump::Pump)
    qfactor_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_qfactor), pump.src)
    ddf_vec = getindex.(getindex.(hub.qser_vec, pump.src, 1), !, :flow)
    return ddf_vec ⊗ qfactor_vec
end

function concentration(hub::Hub, pump::Pump)
    ij_vec = getindex.(getproperty.(hub.encoding_vec, :flow_name_to_ij), pump.src)
    return [W[ij[1], ij[2], 1] for (W, ij) in zip(hub.WQWCTS_vec, ij_vec)] # TODO: Is it useful to generalize level=1 ? 
end

"""
f can be some "statistics", such as ROP: `ddf->ddf[!, :ROP]`, `ddf->ddf[!, [:ROP]]`
or TP: `ddf->ddf[!, :ROP] .+ ddf[!, :LOP] .+ ddf[!, :LDP] .+ ddf[!, :RDP]`
or PO4, ...
"""
function concentration(f::Function, hub::Hub, route::AbstractRoute)
    return f.(concentration(hub, route))
end

_select_row(ddf_vec::Vector{<:DateDataFrame}, row_idx) = getindex.(ddf_vec, row_idx, :)
_select_row(ddf_vec::Vector{<:DateDataFrameVecEnd}, row_idx) = getindex.(ddf_vec, row_idx)

flow(hub::Hub, route::AbstractRoute, row_idx) = _select_row(flow(hub, route), row_idx)
flow(T::Direction, hub::Hub, inflow::Inflow, row_idx) = _select_row(flow(T, hub, inflow), row_idx)
concentration(f::Function, hub::Hub, route::AbstractRoute, row_idx) = _select_row(concentration(f, hub, route), row_idx)
concentration(hub::Hub, route::AbstractRoute, row_idx) = _select_row(concentration(hub, route), row_idx)
