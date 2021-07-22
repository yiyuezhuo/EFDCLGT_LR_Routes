module EFDCLGT_LR_Routes

export AbstractRoute, Inflow, Ditch, Overflow, Pump,
        Natural, Redirect, Limit,
        open!, close!, flow, concentration,
        AbstractHub, Hub, HubBacktrackView, 
        fork, get_qser_ref, get_wqpsc_ref, particles,
        Strap, loading,
        HubRunningMode, NormalBatch, AutoRestartCutScheduler, pure_sheduler,
        # It's expected Routes user don't need to using EFDCLGT_LR_Files and EFDCLGT_LR_Routes
        set_sim_length!, get_sim_length, set_begin_day!, get_begin_day, get_sim_range, get_undecided_range,
        SimulationTemplate, SubSimulationTemplate, get_replacer,
        efdc_inp, qser_inp, wqpsc_inp, wqini,
        run_simulation!, is_over, fork

using Base: Float64

using Dates

using DateDataFrames
using DateDataFrames: DateDataFrameVecEnd
using EFDCLGT_LR_Files
import EFDCLGT_LR_Files: name, get_template, get_replacer, set_sim_length!, get_sim_length, set_begin_day!, get_begin_day,
                        get_sim_range, get_undecided_range
using EFDCLGT_LR_Runner
import EFDCLGT_LR_Runner: run_simulation!, is_over

include("frozen_encoding.jl")
include("hubs.jl")
include("routes.jl")
include("routes_ops.jl")
include("strap.jl")
include("loading.jl")
include("auto_restart_cut_scheduler.jl")
include("infer.jl")

end # module
