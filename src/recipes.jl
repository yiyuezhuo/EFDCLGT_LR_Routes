
@recipe function ff(f::Function, hub::AbstractHub, strap::Strap; first_particle=true)
    n = first_particle ? 1 : particles(hub)
    sim_range = get_sim_range(hub)
    for i in 1:n
        for inflow in strap.inflow_vec
            @series begin 
                label --> inflow.src
                seriescolor --> :red
                concentration(f, hub, inflow, sim_range)[i]
            end
        end
        for overflow in strap.overflow_vec
            @series begin
                label --> "overflow $(overflow.idx)"
                seriescolor --> :blue
                concentration(f, hub, overflow, sim_range)[i]
            end
        end
    end
end
