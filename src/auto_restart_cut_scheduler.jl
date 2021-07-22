
abstract type HubRunningMode end

struct NormalBatch <: HubRunningMode end

function run_simulation!(::NormalBatch, hub_vec::AbstractVector{Hub})
    # TODO: Add auto restart optimization
    task_vec = map(hub_vec) do hub
        return @async run_simulation!(hub)
    end
    return fetch.(task_vec)
end


struct PureWork
    id::Int
    idx_vec::Vector{Int}
    span_begin::Int
    span_end::Int
    prev::Int
    finished::Bool
end

function Base.show(io::IO, work::PureWork)
    print(io, "PureWork(id=$(work.id), idx_vec=$(work.idx_vec), span_begin=$(work.span_begin), " * 
              "span_end=$(work.span_end), prev=$(work.prev), finished=$(work.finished))")
end

struct PureGroup
    index_vec::Vector{Int}
    prev::Int # 0 denotes "no prev"
end

"""
Scan same input part and split works, "pure" means that it's not related to specific data structure, 
such as Vector{Vector{Hub}}

Example:

dummy_data = [
    [1,1,1],
    [1,1,2],
    [1,3,3],
    [4,4,4]
]

eq(idx1::Int, idx2::Int, t::Int) = dummy_data[idx1][t] == dummy_data[idx2][t]
index_vec = 1:length(dummy_data)
turns = length(dummy_data[1])

pure_sheduler(eq, index_vec, turns)

6-element Vector{EFDCLGT_LR_Routes.PureWork}:
 PureWork(id=1, idx_vec=[4], span_begin=1, span_end=3, prev=0, finished=true)
 PureWork(id=2, idx_vec=[1, 2, 3], span_begin=1, span_end=1, prev=0, finished=false)
 PureWork(id=3, idx_vec=[3], span_begin=2, span_end=3, prev=2, finished=true)
 PureWork(id=4, idx_vec=[1, 2], span_begin=2, span_end=2, prev=2, finished=false)
 PureWork(id=5, idx_vec=[1], span_begin=3, span_end=3, prev=4, finished=true)
 PureWork(id=6, idx_vec=[2], span_begin=3, span_end=3, prev=4, finished=true)
"""
function pure_sheduler(eq::Function, index_vec::AbstractVector{Int}, turns::Int)
    work_vec = PureWork[]
    group_vec = [PureGroup(index_vec, 0)]

    for t in 1:turns
        if length(group_vec) == 0
            break
        end

        # split
        _group_vec = PureGroup[]
        proceeding_vec = group_vec
        while length(proceeding_vec) > 0
            _proceeding_vec = PureGroup[]
            for g in proceeding_vec
                eq_idx_vec = Int[g.index_vec[1]]
                neq_idx_vec = Int[]
                for idx in g.index_vec[2:end]
                    if eq(g.index_vec[1], idx, t)
                        push!(eq_idx_vec, idx)
                    else
                        push!(neq_idx_vec, idx)
                    end
                end
                if length(neq_idx_vec) > 0
                    prev_span_end = g.prev == 0 ? 0 : work_vec[g.prev].span_end
                    share_length = t - 1 - prev_span_end
                    if share_length == 0 # rebase
                        push!(_group_vec, PureGroup(eq_idx_vec, g.prev))
                        push!(_proceeding_vec, PureGroup(neq_idx_vec, g.prev))
                    else # fork
                        id = length(work_vec) + 1
                        work = PureWork(id, g.index_vec, prev_span_end + 1, prev_span_end + share_length, g.prev, false)
                        push!(work_vec, work)
                        push!(_group_vec, PureGroup(eq_idx_vec, id))
                        push!(_proceeding_vec, PureGroup(neq_idx_vec, id))
                    end
                else
                    push!(_group_vec, g)
                end
            end
            proceeding_vec = _proceeding_vec
        end
        
        # resolve length 1 group
        empty!(group_vec)
        for g in _group_vec
            if length(g.index_vec) == 1
                id = length(work_vec) + 1
                prev_span_end = g.prev == 0 ? 0 : work_vec[g.prev].span_end
                work = PureWork(id, g.index_vec, prev_span_end + 1, turns, g.prev, true)
                push!(work_vec, work)
            else
                push!(group_vec, g)
            end
        end
    end

    for g in group_vec
        @warn "Duplication detected, useless input or problematic scheduler? $g"
        id = length(work_vec) + 1
        prev_span_end = g.prev == 0 ? 0 : work_vec[g.prev].span_end
        work = PureWork(id, g.index_vec, prev_span_end + 1, turns, g.prev, true)
        push!(work_vec, work)
    end

    return work_vec
end

struct AutoRestartCutScheduler <: HubRunningMode end

function run_simulation!(::AutoRestartCutScheduler, hub_vec::AbstractVector{Hub})
    run_simulation!_pre.(hub_vec)

    length_vec = map(hub->length(hub._collector_vec), hub_vec)
    @assert all(length_vec[1] .== length_vec[2:end])
    particles = length_vec[1]
    size_hub = length(hub_vec)

    next_runner_vec_vec = [Vector{Collector{Restarter}}(undef, particles) for _ in 1:size_hub]
    task_vec_vec = Vector{Task}[]
    @debug "Auto restarting mode size_hub=$size_hub, particles=$particles"
    for i in 1:particles
        collector_vec = [hub._collector_vec[i] for hub in hub_vec]
        qser_vec = [hub.qser_vec[i] for hub in hub_vec]
        
        begin_dt_vec = get_begin_day.(DateTime, collector_vec)
        end_day_vec = get_sim_length.(Day, collector_vec)
        
        @assert all(begin_dt_vec[1] .== begin_dt_vec[2:end])
        @assert all(end_day_vec[1] .== end_day_vec[2:end])

        key_set_vec = [Set(keys(qser)) for qser in qser_vec]
        # @show key_set_vec key_set_vec[1] key_set_vec[2:end] key_set_vec[1] == key_set_vec[2]
        @assert all([key_set_vec[1]] .== key_set_vec[2:end])
        key_set = key_set_vec[1]

        begin_dt = begin_dt_vec[1]
        end_day = end_day_vec[1]

        function eq(idx1::Int, idx2::Int, t::Int)
            q1 = qser_vec[idx1]
            q2 = qser_vec[idx2]

            row_idx = (begin_dt + Day(t-1)):Hour(1):(begin_dt + Day(t) - Hour(1)) # TODO: ⊐̸ Hour(1)

            for k in key_set
                if q1[k][row_idx, :flow] != q2[k][row_idx, :flow]
                    return false
                end
            end
            return true
        end

        index_vec = 1:size_hub
        turns = end_day.value

        work_vec = pure_sheduler(eq, index_vec, turns)

        @debug "pure_sheduler, particle: $i, $(size_hub)->$(length(work_vec)), $(size_hub*end_day.value)->" * 
               "$(sum(work->work.span_end - work.span_begin+1, work_vec)): $work_vec"

        task_vec = map(work_vec) do work
            return @async begin
                if work.prev != 0
                    collector = copy(fetch(task_vec[work.prev])) # TODO: while it will work due to async property, is it better to copy it to prevent potential bug?
                else
                    collector = copy(collector_vec[work.idx_vec[1]])
                end
                # @show collector 
                # @show get_replacer(collector)
                replacer = get_replacer(collector)

                day_length = Day(work.span_end - work.span_begin + 1)
                set_sim_length!(replacer, day_length)

                replacer[qser_inp] = get_replacer(collector_vec[work.idx_vec[1]])[qser_inp]

                next_collector = Collector{Restarter}(collector)

                for idx in work.idx_vec
                    orig_collector = collector_vec[idx]
                    append!(orig_collector, collector)
                end
                if work.finished
                    for idx in work.idx_vec
                        next_runner_vec_vec[idx][i] = next_collector
                    end
                end

                return next_collector
            end
        end

        push!(task_vec_vec, task_vec)
    end

    for task_vec in task_vec_vec
        for task in task_vec
            wait(task)
        end
    end

    run_simulation!_post.(hub_vec, next_runner_vec_vec)
    return nothing
end

# TODO: switch default implementation to `AutoRestartCutScheduler`
# run_simulation!(hub_vec::AbstractVector{Hub}) = run_simulation!(NormalBatch(), hub_vec)
run_simulation!(hub_vec::AbstractVector{Hub}) = run_simulation!(AutoRestartCutScheduler(), hub_vec)
