# Lumi's First Flight (session 66): Lumi is a bird, after all. Once in a while it announces "Today... I FLY!",
# friends hurry over to watch in a ring, Lumi takes a run-up, flaps, and actually lifts off: up and up in a
# wobbly loop over the meadow, shedding golden feathers, the friends' heads following it round. Then the
# flapping stops... a long dive... THUNK: Lumi lands beak first and is planted in the meadow up to its neck
# like one of its own cabbages. The friends rush over and tug, it pops out with a "...I meant to do that."
# Jumped in as Lumi: G (for "go!") tries it.
isdefined(Main, :FLIGHT) || Core.eval(Main, :(const FLIGHT = Dict{Symbol,Any}()))
const NG = NeverendingGame

# One of Lumi's island moments at a time (s85, todo 389): when one ends, the flight, the hiccups and a sneeze all
# grabbed Lumi in the same frame. Each claims Lumi for a while in a shared Main dict; the others wait.
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Float64}()))
party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)
const F = Main.FLIGHT

const GAP = (600.0, 1000.0)       # sim seconds between two attempts
const CALL = 18f0                 # friends this close come to watch
const RING = 3.6f0                # where they stand
const MAXW = 8
const GATHER_T = 4.0              # announce + friends gather
const RUN_T = 1.6                 # the run-up
const FLY_T = 7.5                 # up, round, and the dive
const STUCK_T = 4.0               # planted
const POP_T = 0.9
const LOOP_R = 5.5f0
const TOP = 8.5f0
const NF = 48
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :paint, :giant, :storm, :toadstool, :blossom, :swing, :bottle, :leaves, :pumpkin)
const WATCH_SAY = ("Go Lumi!", "Is it safe?", "Ooooh!", "Higher!", "Flap harder!", "Wheee!")
const RUSH_SAY = ("Lumi?!", "LUMI!", "Are you OK?", "Pull!", "Heave!", "Is it... planted?")

push!(NG.BUSY_GOALS, :flight)

mutable struct Flight <: System
    state::Symbol                 # :idle, :gather, :run, :fly, :stuck, :pop
    t0::Float64
    next_t::Float64
    lumi::Int32
    watchers::Vector{Int32}
    start::Point3f                # where the run-up begins
    dir::Vec2f                    # run-up direction
    land::Point3f                 # where it ends up planted
    fpos::Vector{Point3f}
    fvel::Vector{Vec3f}
    fage::Vector{Float32}
    nextf::Int
    lastf::Float64
end
Flight() = Flight(:idle, 0.0, -1.0, 0, Int32[], Point3f(0), Vec2f(1, 0), Point3f(0),
                  fill(Point3f(0, 0, -50), NF), fill(Vec3f(0), NF), fill(99f0, NF), 1, 0.0)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free(c) = !c.controlled && c.goal.kind ∉ KEEP && c.action !== :sleep && c.goal.kind !== :sleep
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
hold!(c, w, act; target = c.pos) = (c.goal = NG.Goal(:flight, target, act, 60.0, w.t + 60, true, 0, false))

# ---------------------------------------------------------------- feathers

function feather_plot!(game)
    haskey(F, :plot) && F[:plot].parent !== nothing && delete!(F[:plot].parent, F[:plot])
    F[:plot] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), NF); marker = Rect3f(Vec3f(-0.5, -0.5, -0.5), Vec3f(1)),
                            markersize = fill(Vec3f(0), NF), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), NF),
                            color = RGBf(1.0, 0.78, 0.25), name = :flight_feathers)
end

function feather!(s::Flight, w, p)
    i = s.nextf; s.nextf = mod1(i + 1, NF)
    s.fpos[i] = p + Point3f(0.3f0 * randn(w.rng), 0.3f0 * randn(w.rng), 0.6f0)
    s.fvel[i] = Vec3f(0.8f0 * randn(w.rng), 0.8f0 * randn(w.rng), 0.3f0)
    s.fage[i] = 0f0
end

function step_feathers!(s::Flight, w, dt)
    any(<(9f0), s.fage) || get(F, :drawn, true) || return
    ms = fill(Vec3f(0), NF)
    rot = fill(Makie.Quaternionf(0, 0, 0, 1), NF)
    for i in 1:NF
        s.fage[i] >= 9f0 && continue
        s.fage[i] += Float32(dt)
        a = s.fage[i]
        g = NG.ground(w.island, (s.fpos[i][1], s.fpos[i][2]))[3]
        if s.fpos[i][3] > g + 0.03f0          # see-saw down like a real feather
            sw = sin(2.6f0 * a + i)
            s.fpos[i] += Point3f(Float32(dt) * (0.6f0 * sw + 0.3f0 * s.fvel[i][1]), Float32(dt) * 0.3f0 * s.fvel[i][2], -Float32(dt) * 0.55f0)
        end
        ms[i] = Vec3f(0.07f0, 0.28f0, 0.015f0) * min(1f0, 3a) * (a > 8f0 ? 9f0 - a : 1f0)
        rot[i] = Makie.qrotation(Vec3f(0, 0, 1), Float32(i)) * Makie.qrotation(Vec3f(1, 0, 0), 0.5f0 * sin(2.6f0 * a + i))
    end
    F[:drawn] = any(m -> m[1] > 0, ms)
    Makie.update!(F[:plot]; arg1 = copy(s.fpos), markersize = ms, rotation = rot)
end

# ---------------------------------------------------------------- the flight path

"Lumi's place `u` ∈ [0,1] into the flight: a climbing loop round the meadow, a stall, a dive onto `land`."
function flight_pos(s::Flight, w, u)
    o = s.start + Point3f(RUN_T * 3.2f0 * s.dir[1], RUN_T * 3.2f0 * s.dir[2], 0)    # take-off point
    ctr = o + Point3f(LOOP_R * s.dir[1], LOOP_R * s.dir[2], 0)
    a0 = atan(o[2] - ctr[2], o[1] - ctr[1])
    if u < 0.72                                    # one and a bit loops, climbing, wobbling
        v = u / 0.72
        a = a0 + 2.3f0 * pi * v
        r = LOOP_R * (1 + 0.15f0 * sin(9v))
        h = TOP * sin(Float32(pi) / 2 * min(1f0, 1.6f0 * v)) + 0.6f0 * sin(17v)
        g = NG.ground(w.island, (ctr[1] + r * cos(a), ctr[2] + r * sin(a)))[3]
        return Point3f(ctr[1] + r * cos(a), ctr[2] + r * sin(a), max(g, o[3]) + h), a + Float32(pi) / 2
    end
    v = (u - 0.72) / 0.28                          # the stall (a moment of hanging) and the dive
    a1 = a0 + 2.3f0 * pi
    p1 = Point3f(ctr[1] + LOOP_R * cos(a1), ctr[2] + LOOP_R * sin(a1), 0)
    x = p1[1] + (s.land[1] - p1[1]) * v
    y = p1[2] + (s.land[2] - p1[2]) * v
    top = max(NG.ground(w.island, (p1[1], p1[2]))[3], o[3]) + TOP + 0.6f0 * sin(17f0)
    z = v < 0.25 ? top + 0.5f0 * sin(Float32(pi) * v / 0.25) : top + (s.land[3] - get(F, :depth, 1.05f0) - top) * ((v - 0.25f0) / 0.75f0)^2
    return Point3f(x, y, z), atan(s.land[2] - p1[2], s.land[1] - p1[1])
end

# ---------------------------------------------------------------- the attempt

function open_spot(w, p)
    best, bd = p, -1f0
    for dx in -6f0:1.5f0:6f0, dy in -6f0:1.5f0:6f0
        q = (p[1] + dx, p[2] + dy)
        NG.on_land(w.island, q[1], q[2]; margin = 0.6f0) || continue
        haskey(F, :pond) && flat(F[:pond][1], q) < F[:pond][2] + 2.5f0 && continue
        d = minimum((flat(pr.pos, q) - 2.6f0 * pr.scale for pr in w.props); init = 99f0)
        d > bd && (bd = d; best = Point3f(q[1], q[2], 0))
    end
    return NG.ground(w.island, (best[1], best[2]))
end

function begin!(s::Flight, game, me)
    w = game.world
    s.state = :gather
    s.t0 = w.t
    s.lumi = me.id
    s.start = open_spot(w, me.pos)
    s.dir = Vec2f(cos(me.yaw), sin(me.yaw))
    # (it walks to its take-off spot while the friends gather: setting pos there jumped it up to 7 m in one frame, s85)
    # it comes down a few metres to the side of where it took off, so the watchers have to run
    s.land = open_spot(w, s.start + Point3f(-3f0 * s.dir[2] + 2f0 * s.dir[1], 3f0 * s.dir[1] + 2f0 * s.dir[2], 0))
    nest = get(F, :nest, nothing)
    r = rand(w.rng)
    F[:end] = get(F, :ending, nest !== nothing && flat(nest, s.start) < 30 && r < 0.3 ? :nest : r < 0.55 ? :landed : :planted)
    pop!(F, :ending, nothing)
    F[:end] === :nest && nest === nothing && (F[:end] = :planted)
    F[:end] === :nest && (s.land = nest)
    F[:depth] = F[:end] === :nest ? 0.3f0 : 1.05f0
    empty!(s.watchers)
    cand = sort([c for c in w.creatures if c !== me && free(c) && flat(c.pos, me.pos) < CALL]; by = c -> flat(c.pos, me.pos))
    for (k, c) in enumerate(Iterators.take(cand, MAXW))
        NG.leave_interactions!(w, c)
        a = atan(s.dir[2], s.dir[1]) + Float32(pi) * (0.35f0 + 1.3f0 * (k - 1) / max(1, MAXW - 1))
        spot = NG.ground(w.island, (s.start[1] + RING * cos(a), s.start[2] + RING * sin(a)))
        c.goal = NG.Goal(:flight, spot, :wave, 60.0, w.t + 60, false, 0, true)
        push!(s.watchers, c.id)
    end
    me.controlled || (flat(me.pos, s.start) > 0.3f0 ? (me.goal = NG.Goal(:flight, s.start, :walk, 60.0, w.t + 60, false, 0, false)) :
                                                       hold!(me, w, :proud))
    NG.say!(w, me, "Today... I FLY!", duration = 2.6)
    NG.emit!(w, :flight_announce; who = me.name, n = length(s.watchers))
end

function watchers(s, w)
    out = NG.Creature[]
    for id in s.watchers
        c = NG.creature(w, id)
        c === nothing || c.controlled || c.goal.kind !== :flight || push!(out, c)
    end
    return out
end

look_at!(c, p) = (c.yaw = atan(p[2] - c.pos[2], p[1] - c.pos[1]))

function finish!(s::Flight, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    if me !== nothing
        me.pos = NG.ground(w.island, (me.pos[1], me.pos[2]))
        me.controlled || me.goal.kind !== :flight || NG.choose_goal!(me, w)
    end
    for c in watchers(s, w)
        NG.choose_goal!(c, w)
    end
    s.state = :idle
    F[:punch] = false; F[:landed] = false; F[:uhoh] = false
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :flight_end)
end

function NG.step!(s::Flight, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 150.0)
    step_feathers!(s, w, dt)
    haskey(F, :nest) || w.t < get(F, :nestcheck, 0.0) || (F[:nestcheck] = w.t + 20; place_nest!(game))
    gdown = Makie.Keyboard.g in game.keys_down
    me0 = lumi_of(w)
    if gdown && !get(F, :gdown, false) && s.state === :idle && me0 !== nothing && me0.controlled
        begin!(s, game, me0)
    end
    F[:gdown] = gdown
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 8.5 < 24 * NG.daytime(w) < 19
            me = lumi_of(w)
            near = me === nothing ? 0 : count(c -> c !== me && free(c) && flat(c.pos, me.pos) < CALL, w.creatures)
            if me !== nothing && free(me) && near >= 3 && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.6) && party_free(w)
                begin!(s, game, me); claim_party!(w, 25)
            else
                s.next_t = w.t + 45
            end
        end
        return
    end
    me = NG.creature(w, s.lumi)
    (me === nothing || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)) && return finish!(s, game)
    el = w.t - s.t0
    ws = watchers(s, w)
    if s.state === :gather
        walking = !me.controlled && flat(me.pos, s.start) > 0.3f0 && !me.goal.arrived
        me.controlled || walking || (me.yaw = atan(s.dir[2], s.dir[1]); me.action = el < 2.6 ? :proud : :idle)
        for c in ws
            c.goal.arrived && look_at!(c, me.pos)
        end
        if el > GATHER_T
            s.state = :run; s.t0 = w.t
            NG.say!(w, me, "Three... two... ONE!", duration = 1.6)
            # (not there yet: it takes off from where it is, no jump)
            me.controlled || (flat(me.pos, s.start) > 0.5f0 ? (s.start = NG.ground(w.island, (me.pos[1], me.pos[2]))) : (me.pos = s.start))
            for c in ws
                rand(w.rng) < 0.5 && NG.say!(w, c, rand(w.rng, WATCH_SAY); duration = 1.5)
            end
        end
    elseif s.state === :run
        me.yaw = atan(s.dir[2], s.dir[1])
        p = s.start + Point3f(el * 3.2f0 * s.dir[1], el * 3.2f0 * s.dir[2], 0)
        me.pos = NG.ground(w.island, (p[1], p[2]))
        me.action = :run
        for c in ws
            look_at!(c, me.pos)
        end
        if el > RUN_T
            s.state = :fly; s.t0 = w.t
            NG.say!(w, me, "FLAP FLAP FLAP!", duration = 2.0)
            NG.emit!(w, :flight_takeoff; who = me.name, n = length(ws))
            for c in ws
                emote(c.id, :what)
                c.goal.action = :gasp
            end
        end
    elseif s.state === :fly
        u = min(1.0, el / FLY_T)
        p, yaw = flight_pos(s, w, Float32(u))
        me.pos = p; me.yaw = yaw
        # a steered Lumi stays in the flying pose: the engine's jump-in step leaves a held creature alone (s105, #516)
        me.controlled && isdefined(NG, :HELD) && (NG.HELD[Int(me.id)] = w.t + 0.25)
        # flying (the engine's `:fly` pose since s75), flapping hard the whole wobbly way, then the panic
        me.action = u < 0.72 ? :fly : u < 0.79 ? :gasp : :scared
        me.extra = 0.35f0 + 0.25f0 * Float32(sin(11 * el))     # tipped forward, but wobbling (1 would be upright)
        if w.t - s.lastf > (u < 0.72 ? 0.22 : 0.08)
            s.lastf = w.t
            feather!(s, w, p)
        end
        u > 0.72 && !get(F, :uhoh, false) && (F[:uhoh] = true; NG.say!(w, me, "...uh oh.", duration = 1.4))
        for c in ws
            look_at!(c, me.pos)
            c.goal.action = u < 0.72 ? (isodd(c.id) ? :dance : :wave) : :scared
            rand(w.rng) < 0.25dt && NG.say!(w, c, rand(w.rng, WATCH_SAY); duration = 1.3)
        end
        if u >= 1 && F[:end] === :nest
            s.state = :nest; s.t0 = w.t
            me.pos = s.land - Point3f(0, 0, 0.3f0)
            NG.say!(w, me, "...oh! Cosy.", duration = 2.5)
            NG.emit!(w, :flight_nest; who = me.name, n = length(ws))
            for _ in 1:8
                feather!(s, w, s.land)
            end
            for c in ws
                c.goal.action = :laugh
                look_at!(c, s.land)
                rand(w.rng) < 0.5 && NG.say!(w, c, rand(w.rng, ("On the ROOF?!", "Lumi, come down!", "Is that a nest?", "Hee hee!")); duration = 2.0)
            end
        elseif u >= 1 && F[:end] === :landed
            # once in a while it works: a landing on its feet, wings wide, and the friends go wild
            pop!(F, :ending, nothing)
            s.state = :pop; s.t0 = w.t - POP_T - 0.01
            F[:punch] = true
            F[:landed] = true
            me.pos = s.land
            NG.say!(w, me, "TA-DAAA!", duration = 3.0)
            NG.emit!(w, :flight_landed; who = me.name, n = length(ws))
            me.controlled || hold!(me, w, :proud)
            me.action = :proud
            for c in ws
                c.goal.action = :dance
                emote(c.id, :heart)
                rand(w.rng) < 0.5 && NG.say!(w, c, rand(w.rng, ("WOW!", "Lumi can fly!", "Again! Again!", "Bravo!")); duration = 2.0)
            end
            for _ in 1:8
                feather!(s, w, s.land)
            end
        elseif u >= 1
            pop!(F, :ending, nothing)
            s.state = :stuck; s.t0 = w.t
            F[:uhoh] = false
            me.pos = s.land - Point3f(0, 0, 1.05f0)
            for _ in 1:10
                feather!(s, w, s.land)
            end
            NG.say!(w, me, "mmf!", duration = 2.0)
            NG.emit!(w, :flight_crash; who = me.name, n = length(ws))
            for (k, c) in enumerate(ws)
                a = 2f0 * Float32(pi) * k / max(1, length(ws))
                spot = NG.ground(w.island, (s.land[1] + 1.4f0 * cos(a), s.land[2] + 1.4f0 * sin(a)))
                c.goal = NG.Goal(:flight, spot, :scared, 60.0, w.t + 60, false, 0, true)
                k <= 3 && NG.say!(w, c, rand(w.rng, RUSH_SAY); duration = 1.6)
            end
        end
    elseif s.state === :nest
        # it sits in the nest on the roof a while, then hops down in front of the door
        if el < 6
            me.pos = s.land - Point3f(0, 0, 0.3f0)
            me.action = el < 2.5 ? :gasp : el < 4.5 ? :proud : :wave
            el > 3 && !get(F, :punch, false) && (F[:punch] = true; NG.say!(w, me, "I live up here now.", duration = 2.5))
            for c in ws
                look_at!(c, s.land)
            end
        else
            haskey(F, :down) || (F[:down] = NG.ground(w.island, (s.land[1] + 2.6f0 * F[:front][1], s.land[2] + 2.6f0 * F[:front][2])))
            u = Float32(min(1.0, (el - 6) / 1.0))
            a, b = s.land, F[:down]
            me.pos = Point3f(a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u + 4f0 * 1.2f0 * u * (1 - u))
            me.action = :proud
            if u >= 1
                pop!(F, :down)
                F[:punch] = false
                finish!(s, game)
            end
        end
    elseif s.state === :stuck
        # planted up to the neck, a little wiggle; the friends arrive and tug
        me.pos = s.land - Point3f(0, 0, 1.05f0 - 0.08f0 * Float32(el / STUCK_T))
        me.yaw += 3f0 * Float32(dt) * sin(Float32(9w.t))
        me.action = :scared
        for c in ws
            if c.goal.arrived
                look_at!(c, s.land)
                c.goal.action = :play
            end
        end
        if el > STUCK_T
            s.state = :pop; s.t0 = w.t
            NG.say!(w, me, "POP!", duration = 0.9)
            for _ in 1:6
                feather!(s, w, s.land)
            end
        end
    elseif s.state === :pop
        u = Float32(min(1.0, el / POP_T))
        me.pos = Point3f(s.land[1], s.land[2], s.land[3] - 1.05f0 * (1 - u)^3 + 5f0 * 0.6f0 * u * (1 - u))
        landed = get(F, :landed, false)
        me.action = landed ? :proud : :gasp
        for c in ws
            c.goal.action = landed ? :dance : :scared
        end
        if el > POP_T && !get(F, :punch, false)
            F[:punch] = true
            me.pos = s.land
            NG.say!(w, me, "...I meant to do that.", duration = 3.0)
            NG.emit!(w, :flight_punchline; who = me.name)
            me.controlled || hold!(me, w, :shy)
            for c in ws
                c.goal.action = :laugh
                look_at!(c, me.pos)
            end
        end
        if el > POP_T + 4
            F[:punch] = false
            F[:landed] = false
            finish!(s, game)
        end
    end
    return
end

"The camera holds Lumi with its audience: on the ground the ring, in the air Lumi and the watchers below."
function flight_group(w)
    s = F[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    pts = Point3f[me.pos]
    for c in watchers(s, w)
        flat(c.pos, me.pos) < 9 && push!(pts, c.pos)
    end
    # back on the ground (planted or landed): the usual group view of Lumi and the friends round it
    s.state in (:stuck, :pop, :nest) && return (me.id, pts)
    # the follow view's pitch is capped, so a Lumi 9 m up leaves the picture: a view of its own from behind
    # the run-up, looking along the loop, that tilts up after Lumi
    o = s.start + Point3f(RUN_T * 3.2f0 * s.dir[1], RUN_T * 3.2f0 * s.dir[2], 0)
    ctr = o + Point3f(LOOP_R * s.dir[1], LOOP_R * s.dir[2], 0)
    eye = ctr + Point3f(-14f0 * s.dir[1] + 3f0 * s.dir[2], -14f0 * s.dir[2] - 3f0 * s.dir[1], 0)
    eye = Point3f(eye[1], eye[2], NG.ground(w.island, (eye[1], eye[2]))[3] + 2.6f0)
    # look at Lumi itself, and keep up with it: a look point easing 10% a frame towards the loop's middle left a
    # fast-rising Lumi out of the top of the picture, the view on empty sky (perfectionist-0070, steered G)
    want = Point3f(0.9f0 * me.pos[1] + 0.1f0 * ctr[1], 0.9f0 * me.pos[2] + 0.1f0 * ctr[2], me.pos[3] + 0.4f0)
    F[:look] = haskey(F, :look) && F[:lookt] > w.t - 1 ? F[:look] + 0.35f0 * (want - F[:look]) : want
    F[:lookt] = w.t
    return (me.id, pts, (eye, F[:look]))
end

# ---------------------------------------------------------------- the nest on the cottage roof

const NEST_AT = Point3f(0.12, 0, 0.84)   # in the cottage model's frame: on the ridge beside the chimney
const NEST_OK = false       # true once the generated nest (s88, asset 20261125-114654-365) has been looked at on the roof
const NEST_CUT = 0.62f0     # of the nest mesh's height: above it was the bird and eggs of the generated picture
const NEST_W = 0.95f0                    # metres across

"Draw the generated nest on the cottage ridge once the worker has made it; sets F[:nest] (where Lumi sits)."
function place_nest!(game)
    haskey(F, :nestplot) && F[:nestplot].parent !== nothing && return
    (NEST_OK || get(F, :try_nest, false)) || return
    cat = NG.load_catalog(game.paths)
    i = findfirst(e -> occursin("bird nest woven", lowercase(get(e, "prompt", ""))) && isfile(get(e, "mesh", "")), cat)
    i === nothing && return
    j = findfirst(e -> occursin("cottage", lowercase(get(e, "prompt", ""))), cat)
    j === nothing && return
    k = findfirst(a -> a isa NG.AssetActor && a.asset == cat[j]["id"], game.world.actors)
    k === nothing && return
    a = game.world.actors[k]
    q = NG.rot_z(a.yaw)
    spot = a.pos + Point3f(q * (a.scale * NEST_AT))
    model = NG.lifted_asset(game.paths, cat[i]["id"])
    # the generated nest came with a clay bird and eggs sitting in it (s88): keep the nest, below the rim
    ps = GeometryBasics.coordinates(model.mesh)
    z0, z1 = extrema(p -> p[3], ps)
    cut = z0 + NEST_CUT * (z1 - z0)
    keep = map(GeometryBasics.faces(model.mesh)) do f
        (ps[GeometryBasics.value(f[1])][3] + ps[GeometryBasics.value(f[2])][3] + ps[GeometryBasics.value(f[3])][3]) / 3 < cut
    end
    model = NG.AssetModel(NG.piece_of(model.mesh, keep, p -> p, n -> n), model.color, model.material)
    xs = [p[1] for p in GeometryBasics.coordinates(model.mesh)]
    sc = NEST_W / max(1f-3, maximum(xs) - minimum(xs))
    F[:nestplot] = NG.asset_instances!(game.stage.scene, model, [spot - Point3f(0, 0, 0.12f0)]; rotation = [NG.rot_z(a.yaw)],
                                       markersize = Vec3f(sc), name = :flight_nest)
    F[:nest] = spot
    fr = q * Vec3f(0, -1, 0)                       # the cottage's front (door side) is its model -y face
    F[:front] = Vec2f(fr[1], fr[2]) / max(1f-3, hypot(fr[1], fr[2]))
end

function NG.start!(s::Flight, game)
    F[:sys] = s
    F[:game] = game
    F[:drawn] = true
    haskey(game.plugins, "areas") && (am = game.plugins["areas"].mod; F[:pond] = (am.POND, am.POND_R))
    F[:uhoh] = false
    F[:punch] = false
    F[:landed] = false
    feather_plot!(game)
    haskey(F, :nestplot) && F[:nestplot].parent !== nothing && delete!(F[:nestplot].parent, F[:nestplot])
    pop!(F, :nestplot, nothing); pop!(F, :nest, nothing)
    place_nest!(game)
    NG.CAMERA_MOMENTS["flight"] = w -> s.state === :idle ? nothing : s.lumi
    NG.CAMERA_GROUPS["flight"] = flight_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:flight] = "today... I fly!")
end

function NG.stop!(s::Flight, game)
    delete!(NG.CAMERA_MOMENTS, "flight")
    delete!(NG.CAMERA_GROUPS, "flight")
    s.state === :idle || finish!(s, game)
    haskey(F, :plot) && F[:plot].parent !== nothing && delete!(F[:plot].parent, F[:plot])
    haskey(F, :nestplot) && F[:nestplot].parent !== nothing && delete!(F[:nestplot].parent, F[:nestplot])
    pop!(F, :nestplot, nothing); pop!(F, :nest, nothing)
end

register!(Flight())
