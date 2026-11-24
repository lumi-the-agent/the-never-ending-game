# ── The log: everything that happens, in order ───────────────────────────────
#
# Two streams, both append only and flushed per write:
#
#   log/events-<date>.jsonl   one JSON object per line: {"t", "wall", "kind", ...}
#                             spawns, speech, todo changes, code loads, screenshots,
#                             agent phases, user feedback. Human readable.
#   log/frames/<date>-<hh>.bin  binary pose records at `FRAME_DT` sim seconds: where
#                             every entity is, what it does, its animation phase.
#
# A snapshot (`snapshots/*.json`) plus the events and frames after it rebuild any
# moment; see `replay.jl`.

"Sim seconds between two pose records."
const FRAME_DT = 0.2

"One entity's pose in a frame record."
struct PoseRecord
    id::Int32
    pos::Point3f
    yaw::Float32
    action::UInt8      # index into ACTION_CODES
    phase::Float32     # animation phase (gait cycle)
    mood::Float32      # -1 … 1
    extra::Float32     # action specific (sleep depth, chew, …)
end

"A frame: sim time, wall time, all poses."
struct FrameRecord
    t::Float64
    wall::Float64
    poses::Vector{PoseRecord}
end

const FRAME_MAGIC = UInt32(0x53474652)  # "SGFR"

function write_frame(io::IO, f::FrameRecord)
    write(io, FRAME_MAGIC, f.t, f.wall, Int32(length(f.poses)))
    for p in f.poses
        write(io, p.id, p.pos[1], p.pos[2], p.pos[3], p.yaw, p.action, p.phase, p.mood, p.extra)
    end
    return nothing
end

function read_frame(io::IO)
    magic = read(io, UInt32)
    magic == FRAME_MAGIC || error("corrupt frame record (magic $(repr(magic)))")
    t = read(io, Float64); wall = read(io, Float64); n = read(io, Int32)
    poses = Vector{PoseRecord}(undef, n)
    for i in 1:n
        id = read(io, Int32)
        pos = Point3f(read(io, Float32), read(io, Float32), read(io, Float32))
        yaw = read(io, Float32); action = read(io, UInt8)
        phase = read(io, Float32); mood = read(io, Float32); extra = read(io, Float32)
        poses[i] = PoseRecord(id, pos, yaw, action, phase, mood, extra)
    end
    return FrameRecord(t, wall, poses)
end

"All complete frame records in `path` (a torn last record from a crash is dropped)."
function read_frames(path::AbstractString)
    frames = FrameRecord[]
    open(path) do io
        while !eof(io)
            pos = position(io)
            f = try
                read_frame(io)
            catch e
                e isa EOFError || rethrow()
                @warn "NeverendingGame: dropping torn frame record at end of log" path offset = pos
                nothing
            end
            f === nothing && break
            push!(frames, f)
        end
    end
    return frames
end

mutable struct EventLog
    paths::GamePaths
    events_io::Union{Nothing,IOStream}
    events_day::Date
    frames_io::Union{Nothing,IOStream}
    frames_key::String
    nevents::Int
    recent::Vector{Dict{String,Any}}     # last events, for the dashboard
    listeners::Vector{Any}               # f(event::Dict) called after each event
end

EventLog(p::GamePaths) = EventLog(p, nothing, Date(0), nothing, "", 0, Dict{String,Any}[], Any[])

const RECENT_EVENTS = 200

function events_stream!(log::EventLog, now::DateTime)
    day = Date(now)
    if log.events_io === nothing || day != log.events_day
        log.events_io === nothing || close(log.events_io)
        log.events_io = open(joinpath(log.paths.log, "events-$(day).jsonl"), "a")
        log.events_day = day
    end
    return log.events_io
end

function frames_stream!(log::EventLog, now::DateTime)
    key = Dates.format(now, "yyyy-mm-dd-HH")
    if log.frames_io === nothing || key != log.frames_key
        log.frames_io === nothing || close(log.frames_io)
        log.frames_io = open(joinpath(log.paths.frames, key * ".bin"), "a")
        log.frames_key = key
    end
    return log.frames_io
end

"""
    log_event!(log, t, kind; data...) -> Dict

Append an event at sim time `t`. `kind` is a short symbol (`:spawn`, `:say`,
`:todo`, `:phase`, `:screenshot`, …); `data` must be JSON-able.
"""
function log_event!(log::EventLog, t::Real, kind::Symbol; data...)
    now = Dates.now()
    ev = Dict{String,Any}("t" => Float64(t), "wall" => Dates.format(now, "yyyy-mm-ddTHH:MM:SS.sss"),
                          "kind" => String(kind))
    for (k, v) in data
        ev[String(k)] = v
    end
    io = events_stream!(log, now)
    println(io, JSON.json(ev))
    flush(io)
    log.nevents += 1
    push!(log.recent, ev)
    length(log.recent) > RECENT_EVENTS && popfirst!(log.recent)
    for f in log.listeners
        f(ev)
    end
    return ev
end

function log_frame!(log::EventLog, f::FrameRecord)
    io = frames_stream!(log, Dates.now())
    write_frame(io, f)
    flush(io)
    return nothing
end

function Base.close(log::EventLog)
    log.events_io === nothing || close(log.events_io)
    log.frames_io === nothing || close(log.frames_io)
    log.events_io = nothing; log.frames_io = nothing
    return nothing
end

"All events of all days, oldest first (for replay)."
function read_events(p::GamePaths)
    files = sort!(filter(f -> startswith(f, "events-") && endswith(f, ".jsonl"), readdir(p.log)))
    evs = Dict{String,Any}[]
    for f in files, line in eachline(joinpath(p.log, f))
        isempty(strip(line)) && continue
        push!(evs, JSON.parse(line; dicttype = Dict{String,Any}))
    end
    return evs
end
