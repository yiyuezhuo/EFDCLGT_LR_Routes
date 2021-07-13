
# EFDCLGT_LR_Routes

Define some "routes", which provide pollutant load stats, high-level manipulation, based on [EFDCLGT_LR_Files](https://github.com/yiyuezhuo/EFDCLGT_LR_Files.jl).

## Expected API examples

```julia
Inflow("east_west", "lake", "basin")
Ditch("east_west_ditch", "basin")
Overflow(1, "lake")
Pump("pump_outflow", "lake", 1.5)
Pump("pump_outflow", "irrigation", 0.6)

control_range = DateTime(2020, 6, 4):Hour(1):DateTime(2021, 6, 4)

open!(inflow, control_range)
close!(inflow, control_range)
open!(pump_lake, control_range)
close!(pump_irrigation, control_range)
```
