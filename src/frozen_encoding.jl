
struct FrozenEncoding
    ij_to_flow_name::Dict{Tuple{Int, Int}, String}
    flow_name_to_ij::Dict{String, Tuple{Int, Int}}
    flow_name_to_keys::Dict{String, Vector{Tuple{String, Int}}}
    ij_to_overflow_idx::Dict{Tuple{Int, Int}, Int}
    overflow_idx_to_ij::Vector{Tuple{Int, Int}}
    flow_name_to_qfactor::Dict{String, Float64}
end

function FrozenEncoding(efdc::efdc_inp, qser::qser_inp, wqpsc::wqpsc_inp)
    ij_to_flow_name = Dict{Tuple{Int, Int}, String}()
    flow_name_to_ij = Dict{String, Tuple{Int, Int}}()
    flow_name_to_qfactor = Dict{String, Float64}()

    flow_keys = unique(map(x->x[1], keys(qser)))

    @assert size(efdc["C08"], 1) == length(flow_keys) # "pump" will be accounted in C08 and qser.inp but will not be accounted in wqpsc.inp
    for (C08_row, key) in zip(eachrow(efdc["C08"]), flow_keys)
        ij = (C08_row.IQS, C08_row.JQS)
        ij_to_flow_name[ij] = key
        flow_name_to_ij[key] = ij
        flow_name_to_qfactor[key] = C08_row.Qfactor
    end

    ij_to_overflow_idx = Dict{Tuple{Int, Int}, Int}()
    overflow_idx_to_ij = Tuple{Int, Int}[]

    for (idx, C10_row) in enumerate(eachrow(efdc["C10"]))
        ij = (C10_row.IQCTLU, C10_row.JQCTLU)
        ij_to_overflow_idx[ij] = idx
        push!(overflow_idx_to_ij, ij)
    end

    flow_name_to_keys = Dict{String, Vector{Tuple{String, Int}}}(key=>Tuple{String, Int}[] for key in flow_keys)
    for name_idx in keys(qser)
        push!(flow_name_to_keys[name_idx[1]], name_idx)
    end

    return FrozenEncoding(ij_to_flow_name, flow_name_to_ij, flow_name_to_keys, ij_to_overflow_idx, overflow_idx_to_ij, flow_name_to_qfactor)
end
