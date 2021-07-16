
using Test
using Logging
using Dates

using EFDCLGT_LR_Routes
using EFDCLGT_LR_Routes: infer_strap

debug_logger = SimpleLogger(stdout, Logging.Debug)
default_logger = global_logger()
global_logger(debug_logger)

basin = "basin"
natural = "lake"
null = "irrigation"

# template = SimulationTemplate(ENV["WATER_ROOT"], Day, Hour, [efdc_inp, qser_inp, wqpsc_inp])
template = SimulationTemplate(ENV["WATER_ROOT"], Day, Hour, [efdc_inp])
# While it's valueable to keep qser_inp, wqpsc_inp DateDataFrame in this, it may be confusing, so we create a `true_template` to contain these value instead.
sub_root_vec = [joinpath(ENV["WATER_UPSTREAM"], name) for name in readdir(ENV["WATER_UPSTREAM"])]
sub_template_vec = SubSimulationTemplate.(template, sub_root_vec, [[qser_inp, wqpsc_inp]]) 
# share_map is used to get DateDataFrame "limit", qser.inp, wqpsc.inp and wqini.inp will be copied to target even not listed here.
hub_base = Hub(sub_template_vec)

true_template = SimulationTemplate(ENV["WATER_ROOT"], Day, Hour, [efdc_inp, qser_inp, wqpsc_inp])

strap = infer_strap(template, basin, natural, null)
@show strap


@testset "EFDCLGT_LR_Routes" begin 

    hub = hub_base
    set_sim_length!(hub, Day(1))

    @time run_simulation!(hub)

    hub2 = fork(hub)

    @time run_simulation!(hub2)

    hub1 = hub

    for hub in [hub1, hub2]
    
        for inflow in strap.inflow_vec

            fr = flow(Redirect(), hub, inflow)
            fn = flow(Natural(), hub, inflow)
            fl = flow(Limit(), hub, inflow)

            s = fr[1] .+ fn[1] .- fl[1]
            @test all((s .== 0)[!, :flow].df)

            concentration(hub, inflow)
        end
    
        for route_vec in [strap.ditch_vec, strap.overflow_vec, strap.pump_natural_vec, strap.pump_null_vec]
            for route in route_vec
                flow(hub, route)
                concentration(hub, route)
            end
        end
    end
end