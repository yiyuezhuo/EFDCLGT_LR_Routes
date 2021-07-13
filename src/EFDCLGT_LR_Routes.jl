module EFDCLGT_LR_Routes

export Inflow, Ditch, Overflow, Pump,
        open!, close!, flow, concentration,
        Hub, fork#, get_qser_ref, get_wqpsc_ref


using Base: Float64

using TimeSeries

using EFDCLGT_LR_Files
using EFDCLGT_LR_Files: set_sim_length!, get_sim_length #, set_begin_day!, get_begin_day
using EFDCLGT_LR_Runner
import EFDCLGT_LR_Runner: run_simulation!

include("hubs.jl")
include("routes.jl")

# greet() = print("Hello World!")

end # module
