
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

if "WATER_PARTICLES" in keys(ENV)
    particles = parse(Int, ENV["WATER_PARTICLES"])
    if particles > 0
        sub_root_vec = sub_root_vec[1:particles] # it may select "1", "10" instead of "1", "2".
    else
        sub_root_vec = [true_template]
    end
end

sub_template_vec = SubSimulationTemplate.(template, sub_root_vec, [[qser_inp, wqpsc_inp]]) 
# share_map is used to get DateDataFrame "limit", qser.inp, wqpsc.inp and wqini.inp will be copied to target even not listed here.
hub_base = Hub(sub_template_vec)

true_template = SimulationTemplate(ENV["WATER_ROOT"], Day, Hour, [efdc_inp, qser_inp, wqpsc_inp])

strap = infer_strap(template, basin, natural, null)
@show strap


@testset "EFDCLGT_LR_Routes" begin 

    @testset "run_simulation!, copy, fork and result collect" begin

        hub1 = copy(hub_base)
        set_sim_length!(hub1, Day(1))

        @time run_simulation!(hub1)

        hub2 = fork(hub1)

        @time run_simulation!(hub2)

        for hub in [hub1, hub2]
        
            for inflow in strap.inflow_vec

                fr = flow(Redirect(), hub, inflow)
                fn = flow(Natural(), hub, inflow)
                fl = flow(Limit(), hub, inflow)

                s = fr[1] .+ fn[1] .- fl[1]
                @test all((s .== 0).df)

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

    @testset "routes_ops" begin
        hub = copy(hub_base)
        inflow = strap.inflow_vec[1]
        
        @test flow(Redirect(), hub, inflow)[1][1] != 0  # (particle 1, row 1) 
        @test flow(Natural(), hub, inflow)[1][1] == 0

        close!(hub, inflow)

        @test flow(Redirect(), hub, inflow)[1][1] == 0
        @test flow(Natural(), hub, inflow)[1][1] != 0

        open!(hub, inflow, 1:1)

        @test flow(Redirect(), hub, inflow)[1][1] != 0
        @test flow(Natural(), hub, inflow)[1][1] == 0

        @test flow(Redirect(), hub, inflow)[1][2] == 0
        @test flow(Natural(), hub, inflow)[1][2] != 0

        pump_null = strap.pump_null_vec[1]

        @test flow(hub, pump_null)[1][1] == 0

        open!(hub, pump_null)

        @test flow(hub, pump_null)[1][1] != 0

        close!(hub, pump_null, 1:1)

        @test flow(hub, pump_null)[1][1] == 0
        @test flow(hub, pump_null)[1][2] != 0

        open!(hub, pump_null)
        for inflow in strap.inflow_vec
            open!(hub, inflow)
        end
        close!(hub, strap.inflow_vec[1])
        inflow1 = strap.inflow_vec[1]
        inflow2 = strap.inflow_vec[2]

        replacer = get_replacer(hub)[1]

        @test hub.qser_vec[1][inflow1.src, 1][1, :flow] == 0
        @test hub.qser_vec[1][inflow2.src, 1][1, :flow] != 0
        @test hub.qser_vec[1][pump_null.src, 1][1, :flow] == 0 # following values are updated lazyly.
        @test replacer[qser_inp][inflow1.src, 1][1, :flow] != 0
        @test replacer[qser_inp][inflow1.src, 1][1, :flow] != 0
        @test replacer[qser_inp][pump_null.src, 1][1, :flow] == 0

        set_sim_length!(hub, Day(1))
        run_simulation!(hub)

        @test hub.qser_vec[1][pump_null.src, 1][1, :flow] != 0
        @test replacer[qser_inp][inflow1.src, 1][1, :flow] == 0
        @test replacer[qser_inp][inflow2.src, 1][1, :flow] != 0
        @test replacer[qser_inp][pump_null.src, 1][1, :flow] != 0
    end
end
