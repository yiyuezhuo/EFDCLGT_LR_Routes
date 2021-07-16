
#=
Since the model text configuration is ill-defined, this inference mechanism may not work.

Manually defining Strap is very likely required. Manually defining itself doesn't need to load real file.
=#

"""
For retension basin, basin="basin", natureal_name="lake", removed_name="irrigation"
"""
function infer_strap(template::AbstractSimulationTemplate, basin::String, natural::String, null::String,
                pump_natrual_flow = 1.5, pump_null_flow=0.6, ditch_threshold=0.5, pump_threshold=-0.5)

    inflow_vec = Inflow[]
    ditch_vec = Ditch[]
    # overflow_vec = Overflow[]
    pump_natural_vec = Pump[]  # to "natural" direction, such as lake.
    pump_null_vec = Pump[]  # irrigation, redirect to "null" so loading is not counted.

    efdc = load(template, efdc_inp)
    qser = load(template, qser_inp)

    C08 = efdc["C08"]
    name_vec = unique(map(x->x[1], keys(qser))) # keys of qser is ordered

    for (c08_row, na) in zip(eachrow(C08), name_vec)
        if c08_row.Qfactor < pump_threshold
            pump_natrual = Pump(na, natural, pump_natrual_flow)
            pump_null = Pump(na, null, pump_null_flow)
            push!(pump_natural_vec, pump_natrual)
            push!(pump_null_vec, pump_null)
        elseif c08_row.Qfactor < ditch_threshold
            ditch = Ditch(na, basin)
            push!(ditch_vec, ditch)
        else
            inflow = Inflow(na, natural, basin)
            push!(inflow_vec, inflow)
        end
    end

    C10 = efdc["C10"]

    overflow_vec = [Overflow(i, basin, natural) for i in 1:size(C10, 1)]

    strap = Strap(inflow_vec, ditch_vec, overflow_vec, pump_natural_vec, pump_null_vec)

    return strap
end
