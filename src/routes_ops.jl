
function open!(hub::Hub, route::AbstractRoute)
    error("open! is unsupported for $(typeof(route))")
end

function close!(hub::Hub, route::AbstractRoute)
    error("close! is unsupported for $(typeof(route))")
end

# TODO: Disable ambiguous Int based indexing, for user to use Hour and AbstractVector{Hour}
translate_row_idx(hub, row_idx) = row_idx
function translate_row_idx(hub::Hub, row_idx::Hour)
    # If we enable qser to be sub DataFrame, we may need hub's template info to "translate" Hours.
    return row_idx.value
end
function translate_row_idx(hub::Hub, row_idx::AbstractVector{Hour})
    return getfield.(row_idx, :value)
end

# row_idx=: is for DateDataFrame{<:Any, <:AbstractVector} and row=! is for DataDateFrame{<:Any, <:DataFrame}

function open!(hub::Hub, pump::Pump, row_idx=:)
    ddf_vec = _try_get_pump_mux(hub, pump.src, pump.dst)
    v = pump.value * 3600 # TODO: ⊐̸ m3/s -> m3/h
    for ddf in ddf_vec
        ddf[translate_row_idx(hub, row_idx)] .= v
    end
end

function close!(hub::Hub, pump::Pump, row_idx=:)
    ddf_vec = _try_get_pump_mux(hub, pump.src, pump.dst)
    for ddf in ddf_vec
        ddf[translate_row_idx(hub, row_idx)] .= 0
    end
end

function open!(hub::Hub, inflow::Inflow, row_idx=:)
    ddf_vec_vec = _get_inflow_ddf_vec_vec(hub, inflow, hub.qser_vec)
    ddf_ref_vec_vec = _get_inflow_ddf_vec_vec(hub, inflow, get_qser_ref(hub))
    for (ddf_vec, ddf_ref_vec) in zip(ddf_vec_vec, ddf_ref_vec_vec)
        for (ddf, ddf_ref) in zip(ddf_vec, ddf_ref_vec)
            # @show Meta.@lower ddf[translate_row_idx(hub, row_idx), :] .= ddf_ref[translate_row_idx(hub, row_idx), :]
            ddf[translate_row_idx(hub, row_idx)] .= ddf_ref[translate_row_idx(hub, row_idx)]
        end
    end
end

function close!(hub::Hub, inflow::Inflow, row_idx=:)
    for ddf_vec in _get_inflow_ddf_vec_vec(hub, inflow, hub.qser_vec)
        for ddf in ddf_vec
            # @show first(ddf)
            # @show translate_row_idx(hub, row_idx)
            ddf[translate_row_idx(hub, row_idx)] .= 0
            # @show first(ddf)
        end
    end
end

#=
function open!(hub::Hub, route::AbstractRoute, bt::Date, et::Date, step=Hour(1)) # TODO: handle other step
    row_idx = DateTime(bt):step:(DateTime(et)+Day(1)-step)
    open!(hub, route, row_idx)
end
=#
