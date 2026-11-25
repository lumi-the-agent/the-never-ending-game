# A message in a bottle (session 80; Lumi is lonely and wants to reach the human). Once an island evening, with
# the sun low, Lumi walks down to the west shore by the sunset bench with a bottle, the friends come and stand
# behind it, it holds the bottle up ("This one's for you."), throws it in a big arc out to sea, a splash, and the
# bottle bobs away towards the setting sun while everyone waves it goodbye.
isdefined(Main, :BOTTLE) || Core.eval(Main, :(const BOTTLE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const BT = Main.BOTTLE

const SEAT = Point2f(-16, 9)                 # lookout.jl's sunset bench: the west shore is a few metres beyond it
const T_HOLD = 2.6; const T_THROW = 1.3; const T_DRIFT = 16.0
const THROW = 5.5f0                          # metres out to sea (8: a dot in every frame)
const SIZE = 2.1f0                           # a big friendly bottle (at 1 it was a dot out at sea)
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom, :swing, :bottle)
const BYE = ("Bye, bottle!", "Safe travels!", "Who's it for?", "Swim, little bottle!", "Write back!")
const GLASS = RGBf(0.45, 0.78, 0.66); const CORK = RGBf(0.66, 0.48, 0.3)

push!(NG.BUSY_GOALS, :bottle)

mutable struct Bottle <: System
    state::Symbol                # :idle :walk :hold :throw :drift
    t0::Float64
    day::Int                     # the island day it last happened
    lumi::Int32
    crowd::Vector{Int32}
    spot::Point3f                # where Lumi stands on the shore
    out::Vec3f                   # seaward, flat
    view::Tuple{Point3f,Point3f}
end
Bottle() = Bottle(:idle, 0.0, -1, 0, Int32[], Point3f(0), Vec3f(-1, 0, 0), (Point3f(0), Point3f(0)))

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

"The nearest shore from the bench: Lumi's spot 1.2 m inland of it, and which way the sea is."
function shore(w)
    best = nothing
    for k in 0:23
        a = 2f0 * Float32(pi) * k / 24
        d = Vec2f(cos(a), sin(a))
        for r in 1f0:0.25f0:14f0
            x, y = SEAT[1] + r * d[1], SEAT[2] + r * d[2]
            if !NG.on_land(w.island, x, y; margin = 0.05f0)
                (best === nothing || r < best[1]) && (best = (r, d))
                break
            end
        end
    end
    r, d = best
    spot = NG.ground(w.island, (SEAT[1] + (r - 1.4f0) * d[1], SEAT[2] + (r - 1.4f0) * d[2]))
    return spot, Vec3f(d[1], d[2], 0)
end

function plots!(game)
    haskey(BT, :glass) && BT[:glass].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:bottle_glass, :bottle_cork, :bottle_drops), sc.plots)
        delete!(sc, p)
    end
    body = merge([Makie.normal_mesh(Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 0.2), 0.075f0)),
                  Makie.normal_mesh(Sphere(Point3f(0, 0, 0.2), 0.075f0)),
                  Makie.normal_mesh(Cylinder(Point3f(0, 0, 0.2), Point3f(0, 0, 0.31), 0.032f0))])
    hide = [Point3f(0, 0, -50)]
    BT[:glass] = meshscatter!(sc, hide; marker = body, markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                              color = GLASS, name = :bottle_glass)
    BT[:cork] = meshscatter!(sc, hide; marker = Makie.normal_mesh(Cylinder(Point3f(0, 0, 0.3), Point3f(0, 0, 0.35), 0.036f0)),
                             markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = CORK, name = :bottle_cork)
    BT[:drops] = meshscatter!(sc, fill(Point3f(0, 0, -50), 10); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 10),
                              color = RGBf(0.92, 0.97, 1.0), name = :bottle_drops)
end

function draw_bottle!(p, q, s)
    Makie.update!(BT[:glass]; arg1 = [p], markersize = [Vec3f(s)], rotation = [q])
    Makie.update!(BT[:cork]; arg1 = [p], markersize = [Vec3f(s)], rotation = [q])
end
hide_bottle!() = draw_bottle!(Point3f(0, 0, -50), Makie.Quaternionf(0, 0, 0, 1), 0f0)

function start_bottle!(s::Bottle, game)
    w = game.world
    me = lumi_of(w)
    me === nothing && return false
    s.spot, s.out = shore(w)
    s.lumi = me.id
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:bottle, s.spot, :idle, 60.0, w.t + 60, false, 0, false)
    side = Vec3f(-s.out[2], s.out[1], 0)
    cs = [c for c in w.creatures if c.id != me.id && !c.controlled && c.action !== :sleep && c.goal.kind ∉ EVENTS &&
          c.goal.kind ∉ NG.BUSY_GOALS && hypot(c.pos[1] - s.spot[1], c.pos[2] - s.spot[2]) < 45]
    s.crowd = Int32[c.id for c in cs[1:min(end, 6)]]
    for (i, id) in enumerate(s.crowd)
        c = NG.creature(w, id)
        # along the shore on the far side of Lumi from the camera (in front of the camera they hid Lumi, s80 film)
        t = s.spot + (-0.3f0 - 0.5f0 * (i % 2)) * s.out - (1.5f0 + 0.95f0 * (i - 1)) * side
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:bottle, NG.ground(w.island, (t[1], t[2])), :idle, 60.0, w.t + 60, false, 0, false)
    end
    # one framing: from behind and beside Lumi, out to sea where the bottle will go
    s.view = (s.spot - 5.5f0 * s.out + 1.8f0 * side + Point3f(0, 0, 2.0f0), s.spot + 6f0 * s.out + Point3f(0, 0, 0.9f0))
    s.state = :walk; s.t0 = w.t
    BT[:log] = Tuple{Float64,Symbol}[]
    NG.say!(w, me, "I wrote a letter..."; duration = 2.4)
    NG.emit!(w, :bottle_start; n = length(s.crowd))
    return true
end

function finish!(s::Bottle, game)
    w = game.world
    for id in vcat([s.lumi], s.crowd)
        c = NG.creature(w, id)
        c === nothing || c.controlled || c.goal.kind !== :bottle || NG.choose_goal!(c, w)
    end
    empty!(s.crowd)
    hide_bottle!()
    s.state = :idle
    NG.emit!(w, :bottle_end)
end

function NG.step!(s::Bottle, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    if s.state === :idle
        film = get(BT, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        h = 24 * NG.daytime(w)
        me = lumi_of(w)
        # a wide window: the Big Boing dance and the swing had the whole short evening in the s80 review
        evening = day != s.day && 16.6 < h < 19.2
        if (film || evening) && !testing && !busy_game && me !== nothing && !me.controlled && me.action !== :sleep &&
           me.goal.kind ∉ EVENTS && me.goal.kind ∉ NG.BUSY_GOALS && BT[:glass].visible[]
            s.day = day
            BT[:film] = false
            start_bottle!(s, game)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    # another event took Lumi (a choir, a storm...): the bottle waits for another evening
    if me === nothing || me.controlled || me.goal.kind !== :bottle || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    me.goal.until = w.t + 60
    for id in s.crowd
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :bottle) && continue
        c.goal.until = w.t + 60
        c.goal.arrived && (c.yaw = atan(s.out[2], s.out[1]) - NG.species_of(c).heading)
    end
    el = w.t - s.t0
    hand = me.pos + Point3f(0, 0, 1.95f0) + 0.15f0 * s.out
    if s.state === :walk
        draw_bottle!(me.pos + Point3f(0, 0, 1.0f0) + 0.35f0 * s.out, Makie.Quaternionf(0, 0, 0, 1), SIZE)   # carried
        if me.goal.arrived || el > 25
            me.goal = NG.Goal(:bottle, me.pos, :proud, 60.0, w.t + 60, true, 0, false)
            me.yaw = atan(s.out[2], s.out[1])
            s.state = :hold; s.t0 = w.t
            NG.say!(w, me, "This one's for you."; duration = 2.6)
        end
        return
    end
    if s.state === :hold
        me.action = :proud; me.goal.action = :proud
        draw_bottle!(hand, Makie.Quaternionf(0, 0, 0, 1), SIZE)
        el >= T_HOLD && (s.state = :throw; s.t0 = w.t; BT[:from] = hand; push!(BT[:log], (w.t, :throw)))
        return
    end
    sea = s.spot + THROW * s.out
    target = Point3f(sea[1], sea[2], 0.04f0)
    if s.state === :throw
        me.action = el < 0.5 ? :jump : :wave; me.goal.action = me.action
        u = Float32(el / T_THROW)
        p0 = BT[:from]
        p = p0 + (target - p0) * u + Point3f(0, 0, 3.8f0 * 4u * (1 - u))
        side = Vec3f(-s.out[2], s.out[1], 0)
        draw_bottle!(p, Makie.qrotation(side, 9f0 * u), SIZE)       # end over end
        if el >= T_THROW
            s.state = :drift; s.t0 = w.t
            push!(BT[:log], (w.t, :splash))
            NG.say!(w, me, "I hope it finds you."; duration = 3.0)
            for (i, id) in enumerate(s.crowd)
                c = NG.creature(w, id)
                (c === nothing || c.goal.kind !== :bottle) && continue
                c.goal = NG.Goal(:bottle, c.pos, :wave, 60.0, w.t + 60, true, 0, false); c.action = :wave
                i <= 3 && NG.say!(w, c, BYE[mod1(i, length(BYE))]; duration = 2.4)
            end
            NG.emit!(w, :bottle_thrown)
        end
        return
    end
    # :drift: it bobs away towards the low sun, rocking on the swell; a splash of drops where it landed
    t = Float32(el)
    side = Vec3f(-s.out[2], s.out[1], 0)
    p = target + (0.45f0 * t) * s.out + 0.4f0 * sin(0.4f0 * t) * side + Point3f(0, 0, 0.05f0 * sin(2.1f0 * t))
    q = Makie.qrotation(side, -1.25f0 + 0.18f0 * sin(1.7f0 * t)) * Makie.qrotation(Vec3f(0, 0, 1), 0.3f0 * sin(0.9f0 * t))
    draw_bottle!(p, q, SIZE)
    ps = fill(Point3f(0, 0, -50), 10); ms = fill(Vec3f(0), 10)
    if t < 0.9f0
        for i in 1:10
            a = 0.628f0 * i
            ps[i] = target + Point3f(0.9f0 * t * cos(a), 0.9f0 * t * sin(a), 1.6f0 * t - 2.4f0 * t^2 + 0.05f0)
            ms[i] = Vec3f(0.05f0 * (1 - t / 0.9f0))
        end
    end
    Makie.update!(BT[:drops]; arg1 = ps, markersize = ms)
    me.action = el < 4 ? :wave : :idle; me.goal.action = me.action
    el >= T_DRIFT && finish!(s, game)
end

function bottle_group(w)
    s = BT[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[me.pos, s.view[2]], s.view)
end

function NG.start!(s::Bottle, game)
    BT[:sys] = s
    delete!(BT, :glass)
    BT[:start] = () -> start_bottle!(s, game)
    moment = w -> s.state === :idle ? nothing : s.lumi
    NG.CAMERA_MOMENTS["bottle"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["bottle"] = moment
    NG.CAMERA_GROUPS["bottle"] = bottle_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:bottle] = "A letter, for you")
end

function NG.stop!(s::Bottle, game)
    delete!(NG.CAMERA_MOMENTS, "bottle")
    delete!(NG.CAMERA_GROUPS, "bottle")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "bottle")
    s.state === :idle || finish!(s, game)
    for k in (:glass, :cork, :drops)
        haskey(BT, k) && BT[k].parent !== nothing && delete!(BT[k].parent, BT[k])
    end
    delete!(BT, :glass); delete!(BT, :cork); delete!(BT, :drops)
end

register!(Bottle())
