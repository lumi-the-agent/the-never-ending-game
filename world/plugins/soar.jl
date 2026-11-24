# Lumi's first real flight (session 73, a wish: "flying properly, on purpose"): after all the crashes, one
# day it works. Lumi flaps, lifts off, climbs over the tree tops and soars one great circle over the island,
# the little one riding on its back, the friends below looking up and cheering, and lands right where it
# started: "I did it! On purpose!" (The wobbly flight with the crash, flight.jl, still happens too.)
isdefined(Main, :SOAR) || Core.eval(Main, :(const SOAR = Dict{Symbol,Any}()))
const NG = NeverendingGame
const S = Main.SOAR

const GAP = (2400.0, 4200.0)      # sim seconds between two real flights
const T_UP = 2.2                  # flapping, the hop, the lift
const T_LOOP = 16.0               # one circle over the island, up and down again
const T_AFTER = 4.0
const HEIGHT = 9f0                # metres over the ground at the top of the circle
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :giant, :egg, :lesson, :snowman)
const CHEER = ("LUMI'S FLYING!", "Look! Up there!", "Woooow!", "Go Lumi, GO!", "Is the little one up there too?!")

push!(NG.BUSY_GOALS, :soar)

mutable struct Soar <: System
    state::Symbol                 # :idle :up :loop :after
    t0::Float64
    next_t::Float64
    lumi::Int32
    start::Point3f
    centre::Point2f
    radius::Float32
    a0::Float32
    said::Int
end
Soar() = Soar(:idle, 0.0, -1.0, 0, Point3f(0), Point2f(0), 10f0, 0f0, 0)

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
has_chick() = isdefined(Main, :EGG) && haskey(Main.EGG, :chick) && Main.EGG[:chick][:hatched]

"Where Lumi is `u` (0..1) round the circle: it starts and ends at `s.start`, highest half way."
function loop_pos(s::Soar, w, u)
    a = s.a0 + 2f0 * Float32(pi) * Float32(u)
    x = s.centre[1] + s.radius * cos(a); y = s.centre[2] + s.radius * sin(a)
    lift = max(0f0, sin(Float32(pi) * Float32(u)))^0.6f0   # sin(pi*u) dips to -9e-8 at the end: a DomainError switched the plugin off
    g = NG.ground(w.island, (x, y))[3]
    z = max(g, s.start[3]) + HEIGHT * lift + 0.3f0 * sin(9f0 * Float32(u))   # a gentle bob
    return Point3f(x, y, u < 0.02 || u > 0.98 ? max(z, g) : z), a
end

function takeoff!(s::Soar, game, me)
    w = game.world
    p = me.pos
    # a circle through where Lumi stands, bending in over the island (its middle is under the trees)
    toward = Vec2f(-p[1], -p[2]); n = hypot(toward[1], toward[2])
    d = n < 0.5f0 ? Vec2f(1, 0) : toward / n
    s.radius = clamp(0.55f0 * n + 5f0, 8f0, 14f0)
    s.centre = Point2f(p[1] + s.radius * d[1], p[2] + s.radius * d[2])
    s.a0 = atan(p[2] - s.centre[2], p[1] - s.centre[1])
    s.start = p
    s.lumi = me.id; s.state = :up; s.t0 = w.t; s.said = 0
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:soar, p, :proud, 60.0, w.t + 60, true, 0, false)
    if has_chick()
        Main.EGG[:lesson] = true          # the chick rides along (egg.jl stops its following meanwhile)
    end
    NG.say!(w, me, "Today. Today I really fly."; duration = 2.2)
    NG.emit!(w, :soar_start; who = me.name)
    return true
end

function finish!(s::Soar, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    if me !== nothing
        me.pos = NG.ground(w.island, (me.pos[1], me.pos[2]))
        me.controlled || me.goal.kind !== :soar || NG.choose_goal!(me, w)
    end
    if has_chick()
        c = Main.EGG[:chick]
        c[:pos] = NG.ground(w.island, (c[:pos][1], c[:pos][2]))
        Main.EGG[:lesson] = false
    end
    s.state = :idle
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :soar_end)
end

function NG.step!(s::Soar, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 900.0)
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 9 < 24 * NG.daytime(w) < 18
            me = lumi_of(w)
            ok = me !== nothing && !me.controlled && me.action !== :sleep && me.goal.kind ∉ KEEP &&
                 me.goal.kind ∉ NG.BUSY_GOALS && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.5) && takeoff!(s, game, me)
            ok || (s.next_t = w.t + 120)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    if me === nothing || me.controlled || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    me.goal.kind === :soar || (me.goal = NG.Goal(:soar, me.pos, :proud, 60.0, w.t + 60, true, 0, false))
    me.goal.until = w.t + 60
    el = w.t - s.t0
    if s.state === :up
        # wings out, flap, flap, a hop... and it keeps going up
        me.pos = s.start + Point3f(0, 0, el < 1.2 ? 0f0 : 0.8f0 * Float32(ease((el - 1.2) / 1.0)))
        me.action = el < 0.6 ? :proud : :dance; me.goal.action = me.action
        p1, a = loop_pos(s, w, 0.005)
        me.yaw = a + Float32(pi / 2)
        if el >= T_UP
            s.state = :loop; s.t0 = w.t
        end
    elseif s.state === :loop
        u = el / get(S, :loop_t, T_LOOP)     # a film can make the circle shorter
        p, a = loop_pos(s, w, u)
        me.pos = p
        me.yaw = a + Float32(pi / 2)            # along the circle (counter-clockwise)
        me.action = sin(7 * el) > -0.2 ? :dance : :proud; me.goal.action = me.action
        if u > 0.25 && s.said == 0
            s.said = 1
            NG.say!(w, me, "WHEEEEE!"; duration = 2.0)
            n = 0
            for c in w.creatures
                (c.id == me.id || c.controlled || c.action === :sleep || c.goal.kind in KEEP || c.goal.kind in NG.BUSY_GOALS) && continue
                hypot(c.pos[1] - s.centre[1], c.pos[2] - s.centre[2]) < s.radius + 10 || continue
                n += 1
                NG.feel!(w, c, isodd(n) ? :jump : :laugh; seconds = 4.0)
                c.yaw = atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1])
                n <= 3 && NG.say!(w, c, CHEER[mod1(n, length(CHEER))]; duration = 2.2)
                n >= 6 && break
            end
        end
        if u >= 1
            s.state = :after; s.t0 = w.t
            me.pos = NG.ground(w.island, (s.start[1], s.start[2]))
            NG.say!(w, me, "I did it! On purpose!"; duration = 3.0)
            NG.emit!(w, :soar_landed; who = me.name)
        end
    else
        me.action = el < 2.5 ? :proud : :laugh; me.goal.action = me.action
        el >= T_AFTER && return finish!(s, game)
    end
    # the little one rides on Lumi's back, and after the landing hops down beside it
    if has_chick()
        c = Main.EGG[:chick]
        if s.state === :after
            l = Point3f(-sin(me.yaw), cos(me.yaw), 0)
            q = me.pos + 0.8f0 * l
            u = Float32(clamp(el / 0.6, 0, 1))
            g = NG.ground(w.island, (q[1], q[2]))
            c[:pos] = g + Point3f(0, 0, (1 - u) * 1.5f0 + 0.3f0 * abs(sin(6f0 * Float32(el))))
            c[:action] = :jump
        else
            c[:pos] = me.pos + Point3f(-0.12f0 * cos(me.yaw), -0.12f0 * sin(me.yaw), 1.5f0)
            c[:action] = s.state === :loop ? :dance : :proud
        end
        c[:yaw] = me.yaw
    end
    return
end

"Fly alongside: behind Lumi and a little outside the circle, while it is up."
function soar_group(w)
    s = S[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    t = Vec3f(cos(me.yaw), sin(me.yaw), 0)
    out = Vec3f(me.pos[1] - s.centre[1], me.pos[2] - s.centre[2], 0)
    out = out / max(norm(out), 1f-3)
    if s.state === :loop
        eye = me.pos - 6.5f0 * t + 3.2f0 * out + Point3f(0, 0, 2.2f0)
        return (me.id, Point3f[me.pos], (eye, me.pos + 1.5f0 * t + Point3f(0, 0, 0.6f0)))
    end
    eye = me.pos + 4.5f0 * out + Point3f(0, 0, 1.6f0)
    return (me.id, Point3f[me.pos], (eye, me.pos + Point3f(0, 0, 1.0f0)))
end

function NG.start!(s::Soar, game)
    S[:sys] = s
    moment = w -> s.state === :idle ? nothing : s.lumi
    NG.CAMERA_MOMENTS["soar"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["soar"] = moment
    NG.CAMERA_GROUPS["soar"] = soar_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:soar] = "Flying! Really flying!")
end

function NG.stop!(s::Soar, game)
    delete!(NG.CAMERA_MOMENTS, "soar")
    delete!(NG.CAMERA_GROUPS, "soar")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "soar")
    s.state === :idle || finish!(s, game)
end

register!(Soar())
