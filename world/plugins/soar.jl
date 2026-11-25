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
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :giant, :egg, :lesson, :snowman, :storm, :toadstool)
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

const HOVER = 0.8f0               # how high the takeoff hop ends, where the circle begins

"""
Where Lumi is `u` (0..1) round the circle: it starts at the takeoff hop over `s.start` and lands there.
It climbs and comes down with no speed at either end, and flies slower near them (s75, goal 6: the old
`sin(pi u)^0.6` height dropped the last 1.7 m in a third of a second, a slam instead of a landing).
"""
function loop_pos(s::Soar, w, u)
    u = Float32(clamp(u, 0, 1))
    a = s.a0 + 2f0 * Float32(pi) * (u - 0.85f0 * sin(2f0 * Float32(pi) * u) / (2f0 * Float32(pi)))
    x = s.centre[1] + s.radius * cos(a); y = s.centre[2] + s.radius * sin(a)
    h = u <= 0.5f0 ? HOVER + (HEIGHT - HOVER) * Float32(ease(u / 0.3)) : HEIGHT * Float32(ease((1 - u) / 0.3))
    g = NG.ground(w.island, (x, y))[3]
    z = max(g, s.start[3]) + h + 0.3f0 * sin(9f0 * u) * sin(Float32(pi) * u)   # a gentle bob, none at the ends
    return Point3f(x, y, max(z, g)), a
end

"How hard Lumi flaps (`extra` of the `:fly` pose, engine species.jl): hard at the takeoff and the landing flare."
effort(u) = u < 0.12 ? 0.6f0 * (1f0 - Float32(ease(u / 0.12))) : u > 0.86 ? Float32(ease((u - 0.86) / 0.12)) : 0f0

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
    delete!(S, :hop_from)
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
    end
    puffs!(s, game)
    s.state === :idle && return
    me = NG.creature(w, s.lumi)
    if me === nothing || me.controlled || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    me.goal.kind === :soar || (me.goal = NG.Goal(:soar, me.pos, :proud, 60.0, w.t + 60, true, 0, false))
    me.goal.until = w.t + 60
    el = w.t - s.t0
    if s.state === :up
        # wings out, flap, flap, a hop... and it keeps going up
        # wings out, then beating hard upright (flapping `:fly`), the hop, and it tips forward into the flight
        me.pos = s.start + Point3f(0, 0, el < 1.2 ? 0f0 : HOVER * Float32(ease((el - 1.2) / 1.0)))
        me.action = el < 0.5 ? :proud : :fly; me.goal.action = me.action
        me.extra = el < 1.2 ? 1f0 : 1f0 - 0.4f0 * Float32(ease((el - 1.2) / 1.0))
        p1, a = loop_pos(s, w, 0.005)
        # turn towards the flying direction over the run-up (it snapped round in one frame, s74, goal 6)
        dyaw = mod(a + Float32(pi / 2) - me.yaw + Float32(pi), 2f0 * Float32(pi)) - Float32(pi)
        me.yaw += dyaw * min(1f0, 3f0 * Float32(dt))
        if el >= T_UP
            s.state = :loop; s.t0 = w.t
        end
    elseif s.state === :loop
        u = el / get(S, :loop_t, T_LOOP)     # a film can make the circle shorter
        p, a = loop_pos(s, w, u)
        me.pos = p
        me.yaw = a + Float32(pi / 2)            # along the circle (counter-clockwise)
        me.action = :fly; me.goal.action = :fly
        me.extra = effort(u)
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
            # on the back, which tips forward with the flying body (species.jl `:fly`: pitch, lift)
            seat = me.pos + Point3f(-0.12f0 * cos(me.yaw), -0.12f0 * sin(me.yaw), 1.5f0)
            if me.action === :fly
                p = 0.95f0 - 0.75f0 * me.extra
                bx, bz = -0.3f0, 1.3f0
                fx = bx * cos(p) + bz * sin(p); fz = -bx * sin(p) + bz * cos(p) + 0.3f0 * (1 - me.extra)
                seat = me.pos + Point3f(fx * cos(me.yaw), fx * sin(me.yaw), fz)
            end
            # the little one hops up onto the back during the run-up, in an arc (it appeared there in one frame)
            if s.state === :up
                haskey(S, :hop_from) || (S[:hop_from] = c[:pos])
                u = Float32(clamp(el / 0.9, 0, 1))
                p = S[:hop_from] + (seat - S[:hop_from]) * u
                c[:pos] = p + Point3f(0, 0, 0.6f0 * 4u * (1 - u))
            else
                c[:pos] = seat
            end
            c[:action] = s.state === :loop ? :dance : :proud
        end
        c[:yaw] = me.yaw
    end
    return
end

# ── a ring of cloud (s75): little puffs left behind in the air all the way round, which drift off with the wind ──
const NPUFF = 90                  # a fixed set of instances, reused round and round (the browser gets every update)
const PUFF_EVERY = 0.12           # sim s between two puffs
const PUFF_LIFE = 45.0            # s a puff stays (it grows, drifts, then shrinks away)
const PUFF_DRAW = 1 / 12          # s between two redraws

function puff_plot!(game)
    haskey(S, :puff_plot) && S[:puff_plot].parent !== nothing && return S[:puff_plot]
    S[:puffs] = Tuple{Point3f,Float64,Float32}[]           # (where, born, size)
    # names are unique per scene: a reload or a failed start can leave the last one behind
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :soar_puffs, game.stage.scene.plots)
        delete!(game.stage.scene, p)
    end
    S[:puff_plot] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), 3NPUFF); marker = Sphere(Point3f(0), 1f0),
                                 markersize = fill(Vec3f(0), 3NPUFF), color = RGBf(0.97, 0.96, 0.93), name = :soar_puffs)
end

function puffs!(s::Soar, game)
    game.stage === nothing && return
    w = game.world
    plot = puff_plot!(game)
    tr = S[:puffs]
    if s.state === :loop && w.t - get(S, :last_puff, -Inf) > PUFF_EVERY
        me = NG.creature(w, s.lumi)
        # only high up: the climb and the descent stacked puffs into white columns by the landing spot (s75 preview)
        if me !== nothing && me.pos[3] - s.start[3] > 0.55f0 * HEIGHT
            back = Point3f(-cos(me.yaw), -sin(me.yaw), 0)
            push!(tr, (me.pos + 0.7f0 * back + Point3f(0, 0, 0.45f0), w.t, 0.45f0 + 0.3f0 * rand(w.rng, Float32)))
            length(tr) > NPUFF && popfirst!(tr)
            S[:last_puff] = w.t
        end
    end
    filter!(p -> w.t - p[2] < PUFF_LIFE, tr)
    isempty(tr) && !get(S, :puffs_shown, false) && return
    w.t - get(S, :puff_drawn, -Inf) < PUFF_DRAW && return
    S[:puff_drawn] = w.t
    wd = isdefined(Main, :WIND) && haskey(Main.WIND, :now) ? Base.invokelatest(Main.WIND[:now], w.t)[1] : Vec2f(1, 0)
    ps = fill(Point3f(0, 0, -50), 3NPUFF); ms = fill(Vec3f(0), 3NPUFF)
    for (i, (p, born, r)) in enumerate(tr)
        age = Float32(w.t - born)
        # small behind Lumi (it must not hide the flyer), full in 2 s, gone over the last 10
        k = clamp(age / 2f0, 0.15f0, 1f0) * clamp((Float32(PUFF_LIFE) - age) / 10f0, 0f0, 1f0) * (1f0 + 0.012f0 * age)
        c = p + Point3f(0.25f0 * age * wd[1], 0.25f0 * age * wd[2], 0.02f0 * age)
        # a little cluster, not one ball (the first film's ring was a string of pearls): two smaller lumps beside it
        a = 6.283f0 * mod(Float32(born) * 7.31f0, 1f0)
        for (j, (d, z, f)) in enumerate(((0f0, 0f0, 1f0), (0.75f0, 0.2f0, 0.7f0), (-0.7f0, -0.12f0, 0.6f0)))
            o = r * k * Point3f(d * cos(a), d * sin(a), z)
            ps[3i - 3 + j] = c + o
            ms[3i - 3 + j] = Vec3f(f * r * k, f * r * k, 0.75f0 * f * r * k)
        end
    end
    S[:puffs_shown] = !isempty(tr)
    Makie.update!(plot; arg1 = ps, markersize = ms)
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
    # one framing from takeoff to landing: switching to a side view at the landing swung the camera ~45 deg in
    # a third of a second (the human, landing-steps.jpg, s74)
    eye = me.pos - 6.5f0 * t + 3.2f0 * out + Point3f(0, 0, 2.2f0)
    return (me.id, Point3f[me.pos], (eye, me.pos + 1.5f0 * t + Point3f(0, 0, 0.6f0)))
end

function NG.start!(s::Soar, game)
    S[:sys] = s
    delete!(S, :puff_plot); empty!(get(S, :puffs, [])); S[:puffs_shown] = true    # a fresh scene (a reload, a quiet copy)
    game.stage === nothing || puff_plot!(game)
    :fly in NG.ACTION_CODES || NG.register_action!(:fly)     # the engine does it since s75
    moment = w -> s.state === :idle ? nothing : s.lumi
    NG.CAMERA_MOMENTS["soar"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["soar"] = moment
    NG.CAMERA_GROUPS["soar"] = soar_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:soar] = "Flying! Really flying!")
end

function NG.stop!(s::Soar, game)
    p = get(S, :puff_plot, nothing)
    p === nothing || p.parent === nothing || delete!(p.parent, p)
    delete!(S, :puff_plot)
    delete!(NG.CAMERA_MOMENTS, "soar")
    delete!(NG.CAMERA_GROUPS, "soar")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "soar")
    s.state === :idle || finish!(s, game)
end

register!(Soar())
