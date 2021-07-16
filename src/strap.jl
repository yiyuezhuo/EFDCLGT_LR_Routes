
"""
Strap, a strap of routes. ArchLinux: "pacstrap"?
"""
struct Strap
    inflow_vec::Vector{Inflow}
    ditch_vec::Vector{Ditch}
    overflow_vec::Vector{Overflow}
    pump_natural_vec::Vector{Pump}  # to "natural" direction, such as lake.
    pump_null_vec::Vector{Pump}  # irrigation, redirect to "null" so loading is not counted.
end

