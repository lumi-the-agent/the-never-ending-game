# ── How long things take ─────────────────────────────────────────────────────
#
# Every timed operation (renders, asset generation, jobs, agent phases) adds a
# sample under its label. `estimate` gives the agent a number to plan with, so
# it does not start something that blocks the game for an hour.

mutable struct TimingStats
    path::String
    samples::Dict{String,Vector{Float64}}
end

const MAX_SAMPLES = 50

function TimingStats(path::AbstractString)
    samples = Dict{String,Vector{Float64}}()
    if isfile(path)
        for (k, v) in read_json(path)
            samples[k] = Float64.(v)
        end
    end
    return TimingStats(String(path), samples)
end

function record!(ts::TimingStats, label::AbstractString, seconds::Real)
    v = get!(ts.samples, String(label), Float64[])
    push!(v, Float64(seconds))
    length(v) > MAX_SAMPLES && popfirst!(v)
    write_json(ts.path, ts.samples)
    return seconds
end

"Median duration of `label` in seconds, or `nothing` if it never ran."
function estimate(ts::TimingStats, label::AbstractString)
    v = get(ts.samples, label, nothing)
    (v === nothing || isempty(v)) && return nothing
    s = sort(v)
    return s[cld(length(s), 2)]
end
