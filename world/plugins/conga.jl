# The conga (session 62): every so often Lumi starts a conga line round the big toadstool (boing.jl) and
# every awake friend falls in behind, one after the other, snaking round and round to "da-da-da-da-da-da...
# HEY!", everyone kicking up on the HEY together. A player who walks into the line with Lumi gets cheered.
isdefined(Main, :CONGA) || Core.eval(Main, :(const CONGA = Dict{Symbol,Any}()))
const NG = NeverendingGame
const C = Main.CONGA

const GAP = (420.0, 660.0)      # sim seconds between congas
const SPEED = 1.5f0             # m/s along the line
const STEP = 1.15f0             # m between two dancers
const TIME = 36.0               # s of dancing
const BEAT = 3.2                # s per "da-da-da-da-da-da HEY!"
const KEEP = (:follow, :choir, :answer, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk, :freeze, :hide, :found, :sleep, :paint, :giant)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :interact)

push!(NG.BUSY_GOALS, :conga)

mutable struct Conga <: System
    state::Symbol           # :idle, :gather, :dance
    line::Vector{Int32}     # leader first
    t0::Float64
    started::Float64
    next_t::Float64
    next_beat::Float64
    hey_until::Float64
    center::Point3f
end
Conga() = Conga(:idle, Int32[], 0.0, 0.0, -1.0, 0.0, 0.0, Point3f(0))

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
joins(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ KEEP && (c.goal.kind ∉ NG.BUSY_GOALS || c.goal.kind in PULL)

"A wavy loop round the toadstool (inside the ring boing.jl keeps clear): the point `s` metres along it."
function curve(w, c0, s)
    θ = Float32(s / 3.4f0)
    r = 3.3f0 + 0.5f0 * sin(3θ)
    return NG.ground(w.island, (c0[1] + r * cos(θ), c0[2] + r * sin(θ)))
end
line_point(s::Conga, w, k, t) = curve(w, s.center, SPEED * t - STEP * (k - 1))

function start_conga!(s::Conga, game)
    w = game.world
    isdefined(Main, :BOING) && haskey(Main.BOING, :center) || return false
    cs = [c for c in w.creatures if joins(c)]
    length(cs) < 3 && return false
    s.center = Main.BOING[:center]
    i = findfirst(c -> c.name == "Lumi", cs)
    if i !== nothing          # Lumi leads
        cs[1], cs[i] = cs[i], cs[1]
    end
    sort!(view(cs, 2:length(cs)), by = c -> hypot(c.pos[1] - s.center[1], c.pos[2] - s.center[2]))
    s.line = [c.id for c in cs]
    for (k, c) in enumerate(cs)
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:conga, line_point(s, w, k, 0.0), :idle, 600.0, 0.0, false, 0, true)
    end
    NG.say!(w, cs[1], "Conga line! Everybody grab on!"; duration = 3)
    s.state = :gather; s.started = w.t
    NG.emit!(w, :conga; n = length(cs), who = join([c.name for c in cs], ", "))
    return true
end

function end_conga!(s::Conga, game; why = "done")
    w = game.world
    for id in s.line
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :conga) && continue
        NG.remember!(c, w.t, "danced in Lumi's conga line")
        c.mood = min(1f0, c.mood + 0.15f0)
        NG.choose_goal!(c, w)
        NG.feel!(w, c, :laugh; seconds = 1.5 + rand(w.rng))
    end
    NG.emit!(w, :conga_end; why)
    s.state = :idle; s.line = Int32[]
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
end

function NG.step!(s::Conga, game, dt)
    w = game.world
    game.stage === nothing && return
    s.next_t < 0 && (s.next_t = w.t + 150.0)
    testing = game.tests !== nothing && NG.running(game.tests)
    busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
    other = (isdefined(Main, :BOING) && haskey(Main.BOING, :sys) && Main.BOING[:sys].state !== :idle) ||
            (isdefined(Main, :FREEZE) && haskey(Main.FREEZE, :sys) && Main.FREEZE[:sys].state !== :idle)
    if s.state === :idle
        if w.t >= s.next_t && !testing && !busy_game && !other && 7.5 < 24 * NG.daytime(w) < 20
            start_conga!(s, game) || (s.next_t = w.t + 60)
        end
        return
    end
    busy_game && return end_conga!(s, game; why = "mini game")
    filter!(id -> (c = NG.creature(w, id); c !== nothing && c.goal.kind === :conga), s.line)
    length(s.line) < 3 && return end_conga!(s, game; why = "too few")
    cs = [NG.creature(w, id) for id in s.line]
    if s.state === :gather
        for c in cs
            c.goal.arrived && (c.goal.until = w.t + 600)
        end
        if all(c -> c.goal.arrived, cs) || w.t - s.started > 25
            # stragglers run after their place in the line and grab on when they reach it
            s.state = :dance; s.t0 = w.t; s.next_beat = w.t + BEAT
        end
        return
    end
    t = w.t - s.t0
    hey = w.t < s.hey_until
    for (k, c) in enumerate(cs)
        p = line_point(s, w, k, t)
        if !c.goal.arrived
            if hypot(c.pos[1] - p[1], c.pos[2] - p[2]) > 1.0f0 && t < TIME - 5
                c.goal.target = p; c.goal.until = 0.0
                continue
            end
            NG.say!(w, c, "Wait for me!"; duration = 1.5)
        end
        q = line_point(s, w, k, t + 0.2)
        c.pos = hey ? p + Point3f(0, 0, 0.25f0 * sin(Float32(pi) * Float32((s.hey_until - w.t) / 0.5))) : p
        c.yaw = atan(q[2] - p[2], q[1] - p[1]) - NG.species_of(c).heading
        a = hey ? :jump : :dance
        c.action = a; c.goal.action = a
        c.goal.arrived = true; c.goal.until = w.t + 600
    end
    if w.t >= s.next_beat
        s.next_beat = w.t + BEAT
        s.hey_until = w.t + 0.5
        NG.say!(w, cs[1], "da-da-da-da-da-da... HEY!"; duration = 1.8)
        for c in cs[2:end]
            rand(w.rng) < 0.35 && NG.say!(w, c, "HEY!"; duration = 1.0)
        end
    end
    t > TIME && end_conga!(s, game)
    return
end

watch_conga(w) = (s = C[:sys]; s.state === :dance && !isempty(s.line) ? first(s.line) : nothing)
function conga_group(w)
    id = watch_conga(w)
    id === nothing && return nothing
    return id, [c.pos for c in (NG.creature(w, m) for m in C[:sys].line) if c !== nothing]
end

function NG.start!(s::Conga, game)
    C[:sys] = s
    NG.CAMERA_MOMENTS["conga"] = watch_conga
    NG.CAMERA_GROUPS["conga"] = conga_group
end

function NG.stop!(s::Conga, game)
    delete!(NG.CAMERA_MOMENTS, "conga")
    delete!(NG.CAMERA_GROUPS, "conga")
    s.state === :idle || end_conga!(s, game; why = "reload")
end

register!(Conga())
