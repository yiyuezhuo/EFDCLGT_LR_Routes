module EFDCLGT_LR_Routes

export Inflow, Ditch, Overflow, Pump,
        Natural, Redirect, Limit,
        open!, close!, flow, concentration,
        Hub, fork, get_qser_ref, get_wqpsc_ref,
        Strap

using Base: Float64

using Dates

using DateDataFrames
using EFDCLGT_LR_Files
import EFDCLGT_LR_Files: name
using EFDCLGT_LR_Runner
import EFDCLGT_LR_Runner: run_simulation!, set_sim_length!, get_sim_length, #, set_begin_day!, get_begin_day,
                                is_over

include("frozen_encoding.jl")
include("hubs.jl")
include("routes.jl")
include("strap.jl")

end # module
