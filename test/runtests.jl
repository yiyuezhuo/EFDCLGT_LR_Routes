
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

    @testset "auto_restart_cut_scheduler" begin
        dummy_data = [
            [1,1,1],
            [1,1,2],
            [1,3,3],
            [4,4,4]
        ]

        eq(idx1::Int, idx2::Int, t::Int) = dummy_data[idx1][t] == dummy_data[idx2][t]
        index_vec = 1:length(dummy_data)
        turns = length(dummy_data[1])

        work_vec = pure_sheduler(eq, index_vec, turns)

        #=
        Expected:
        PureWork(id=1, idx_vec=[4], span_begin=1, span_end=3, prev=0, finished=true)
        PureWork(id=2, idx_vec=[1, 2, 3], span_begin=1, span_end=1, prev=0, finished=false)
        PureWork(id=3, idx_vec=[3], span_begin=2, span_end=3, prev=2, finished=true)
        PureWork(id=4, idx_vec=[1, 2], span_begin=2, span_end=2, prev=2, finished=false)
        PureWork(id=5, idx_vec=[1], span_begin=3, span_end=3, prev=4, finished=true)
        PureWork(id=6, idx_vec=[2], span_begin=3, span_end=3, prev=4, finished=true)     
        =#

        @test length(work_vec) == 6
        middle_vec = [work for work in work_vec if work.finished == false]
        @test length(middle_vec) == 2

        pump = strap.pump_natural_vec[1]

        hub_base2 = copy(hub_base)
        set_sim_length!(hub_base2, Day(3))        

        hub1 = copy(hub_base2)
        hub2 = copy(hub1)
        open!(hub2, pump, 49:72)
        hub3 = copy(hub2)
        open!(hub3, pump, 25:48)
        hub4 = copy(hub3)
        open!(hub4, pump, 1:24)

        hub_vec = [hub1, hub2, hub3, hub4]

        run_simulation!(AutoRestartCutScheduler(), hub_vec)
    end
end
