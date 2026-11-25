# Statues (session 62): now and then a bored Lumi shouts "FREEZE!" and EVERYONE awake on the island
# stops dead where they are, mid-stride, mid-hop, mid-bite, like statues. Seconds tick by... then one
# friend cannot hold it, snorts and bursts out laughing, and the whole island laughs with it.
# Jumped in as Lumi? Move while the island is frozen and they all shout that you lost.
isdefined(Main, :FREEZE) || Core.eval(Main, :(const FREEZE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const F = Main.FREEZE

const GAP = (300.0, 540.0)     # sim seconds between two freezes
const HOLD = (6.0, 9.0)        # how long the statues hold before someone cracks
const CALLS = ("FREEZE!", "Statues! Nobody move!", "Freeze! ...I'm watching you!")
const CRACKS = ("Pffff... HAHAHA!", "I can't... hee hee!", "My nose itches! HAHA!", "*snort* HAHAHA!")
const LAUGHS = ("Ha ha ha!", "Hee hee!", "You moved!", "Again! Again!", "Ho ho!")
const POSES = (:dance, :wave, :jump, :dance, :wave)
const STILL = ("...", "*holds still*", "*doesn't blink*", "mmmf...", "*wobbles*")
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk, :sleep, :hide, :found, :paint, :giant, :egg, :storm, :toadstool, :blossom, :swing, :bottle, :leaves, :pumpkin)

push!(NG.BUSY_GOALS, :freeze)

mutable struct Freeze <: System
    state::Symbol                    # :idle, :frozen, :crack
    frozen::Dict{Int32,Any}          # id => (pos, yaw, action, phase)
    caller::Int32
    cracker::Int32
    until::Float64
    next_t::Float64
    lumi_pos::Point3f
    caught::Bool
end
Freeze() = Freeze(:idle, Dict{Int32,Any}(), Int32(0), Int32(0), 0.0, -1.0, Point3f(0), false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
can_freeze(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ KEEP

function freeze!(s::Freeze, game)
    w = game.world
    cs = [c for c in w.creatures if can_freeze(c)]
    length(cs) < 3 && return false
    me = lumi_of(w)
    caller = me !== nothing && (me.controlled || can_freeze(me)) ? me : cs[1]
    empty!(s.frozen)
    for c in cs
        c === caller && continue
        NG.leave_interactions!(w, c)
        # everyone strikes a silly statue pose: frozen mid-dance, mid-wave, mid-hop
        a = rand(w.rng, POSES)
        s.frozen[c.id] = (pos = c.pos, yaw = c.yaw, action = a, phase = 0.15f0 + 0.7f0 * rand(w.rng, Float32))
        rand(w.rng) < 0.6 && NG.say!(w, c, rand(w.rng, STILL); duration = 4)
        c.goal = NG.Goal(:freeze, c.pos, a, 60.0, w.t + 60, true, 0, false)
    end
    NG.say!(w, caller, rand(w.rng, CALLS); duration = 2.5)
    s.caller = caller.id
    ids = collect(keys(s.frozen))
    s.cracker = rand(w.rng, ids)
    s.state = :frozen
    s.until = w.t + HOLD[1] + (HOLD[2] - HOLD[1]) * rand(w.rng)
    s.lumi_pos = me === nothing ? Point3f(0) : me.pos
    s.caught = false
    caller.controlled || NG.feel!(w, caller, :think; seconds = s.until - w.t)   # Lumi watches them all, chin in hand
    NG.emit!(w, :freeze; n = length(ids), who = join([NG.creature(w, id).name for id in ids], ", "))
    return true
end

function hold!(s::Freeze, w)
    for (id, f) in s.frozen
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :freeze) && continue
        c.pos = f.pos; c.yaw = f.yaw; c.phase = f.phase
        c.action = f.action; c.goal.action = f.action
        c.goal.until = w.t + 60
    end
end

function thaw!(s::Freeze, game)
    w = game.world
    for id in keys(s.frozen)
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :freeze) && continue
        NG.remember!(c, w.t, "played statues with the whole island")
        c.mood = min(1f0, c.mood + 0.1f0)
        NG.choose_goal!(c, w)
        NG.feel!(w, c, :laugh; seconds = 2.0 + rand(w.rng))
    end
    # Lumi laughs too, but only when it is free or played: feel! replaces the goal, and a Lumi flying its kite
    # let go of the string every time a statues game ended (s73: kite_land 'let_go' twice in the second of freeze_end)
    me = lumi_of(w)
    if me !== nothing && !me.controlled && (me.goal.kind ∉ KEEP && me.goal.kind ∉ NG.BUSY_GOALS || me.goal.kind === :freeze)
        NG.feel!(w, me, :laugh; seconds = 2.5)
    end
    empty!(s.frozen)
    s.state = :idle
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :freeze_end)
end

function NG.step!(s::Freeze, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 40.0)
    testing = game.tests !== nothing && NG.running(game.tests)
    busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
    boing = isdefined(Main, :BOING) && haskey(Main.BOING, :sys) && Main.BOING[:sys].state !== :idle
    if s.state === :idle
        if w.t >= s.next_t && !testing && !busy_game && !boing && 7.5 < 24 * NG.daytime(w) < 20
            freeze!(s, game) || (s.next_t = w.t + 60)
        end
        return
    end
    busy_game && return thaw!(s, game)
    hold!(s, w)
    me = lumi_of(w)
    if s.state === :frozen
        # the player moved while everyone stands still: caught!
        if me !== nothing && me.controlled && !s.caught && hypot(me.pos[1] - s.lumi_pos[1], me.pos[2] - s.lumi_pos[2]) > 0.6
            s.caught = true
            near = sort([NG.creature(w, id) for id in keys(s.frozen)], by = c -> hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]))
            isempty(near) || NG.say!(w, near[1], "Lumi moved! Lumi moved!"; duration = 2)
            NG.emit!(w, :freeze_caught; who = me.name)
        end
        if w.t >= s.until
            c = NG.creature(w, s.cracker)
            if c !== nothing && c.goal.kind === :freeze
                delete!(s.frozen, c.id)
                NG.say!(w, c, rand(w.rng, CRACKS); duration = 2.2)
                NG.feel!(w, c, :laugh; seconds = 3.0)
                NG.emit!(w, :freeze_crack; who = c.name)
            end
            s.state = :crack
            s.until = w.t + 1.4
        end
    elseif w.t >= s.until
        ids = collect(keys(s.frozen))
        for id in ids[1:min(2, end)]
            NG.say!(w, NG.creature(w, id), rand(w.rng, LAUGHS); duration = 2)
        end
        foreach(id -> emote(id, :heart), ids)
        thaw!(s, game)
    end
    return
end

watch_freeze(w) = (s = F[:sys]; s.state === :idle ? nothing : s.state === :crack ? s.cracker : s.cracker)

function NG.start!(s::Freeze, game)
    F[:sys] = s
    NG.CAMERA_MOMENTS["freeze"] = watch_freeze
end

function NG.stop!(s::Freeze, game)
    delete!(NG.CAMERA_MOMENTS, "freeze")
    s.state === :idle || thaw!(s, game)
end

register!(Freeze())
