# Giant Lumi (session 69): a golden mushroom pops up in front of Lumi. "Ooh, a golden one!" *munch*...
# "uh oh." Lumi wobbles up to five times its size, taller than the trees. The friends scream and scatter,
# then come back: three climb onto its back for a ride ("Giddy up!"), the rest hop every time it stomps.
# Then POP, Lumi is small again, the riders tumble down, and Lumi says "...that was a big snack."
# Press M when you are Lumi.
isdefined(Main, :GIANT) || Core.eval(Main, :(const GIANT = Dict{Symbol,Any}()))
const NG = NeverendingGame
const G = Main.GIANT

const GAP = (1500.0, 2400.0)      # sim seconds between two golden mushrooms
const BIG = 5f0                   # how big Lumi gets
const T_FIND = 3.2                # mushroom up, Lumi eats it
const T_GROW = 3.0                # wobbling up
const T_GIANT = 13.0              # stomping about with riders
const T_POP = 0.7                 # back to small
const REACH = 12f0
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :egg)
const SCREAM = ("AAAH!", "Run!!!", "LUMI?!", "It's HUGE!", "Eeeek!")
const RIDE = ("Giddy up!", "Wheee!", "I can see the sea!", "So high!", "Faster, Lumi!")
const FEET = ("Look how tall!", "Do the stomp!", "Again! Again!", "Hello up there!")
const FALL = ("Oof!", "Whoa!", "Again!", "My tail!")
const GOLD = RGBf(1.0, 0.8, 0.2)

push!(NG.BUSY_GOALS, :giant)

mutable struct Giant <: System
    state::Symbol                 # :idle :find :grow :giant :pop :after
    t0::Float64
    next_t::Float64
    lumi::Int32
    friends::Vector{Int32}
    riders::Vector{Int32}
    falls::Dict{Int32,Any}        # rider id => (from, to, t0)
    shroom::Point3f
    s::Float32                    # Lumi's size now
    stomp::Float64
    player::Bool
end
Giant() = Giant(:idle, 0.0, -1.0, 0, Int32[], Int32[], Dict{Int32,Any}(), Point3f(0), 1f0, 0.0, false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free(c) = !c.controlled && c.goal.kind ∉ KEEP && c.goal.kind !== :giant && c.action !== :sleep
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
mine(c) = c !== nothing && c.goal.kind === :giant
hold!(c, w, action) = (c.goal.until = w.t + 60; c.goal.action = action; c.action = action)

# ---------------------------------------------------------------- looks

"A unit half sphere (z ≥ 0): the mushroom's cap."
function dome(n = 28, m = 10)
    pts = Point3f[]; fs = GeometryBasics.GLTriangleFace[]
    for j in 0:m, i in 0:n-1
        t = (pi / 2) * j / m; f = 2pi * i / n
        push!(pts, Point3f(sin(t) * cos(f), sin(t) * sin(f), cos(t)))
    end
    for j in 0:m-1, i in 0:n-1
        a = j * n + i + 1; b = j * n + mod(i + 1, n) + 1; c = (j + 1) * n + i + 1; d = (j + 1) * n + mod(i + 1, n) + 1
        push!(fs, GeometryBasics.GLTriangleFace(a, c, b), GeometryBasics.GLTriangleFace(b, c, d))
    end
    return GeometryBasics.Mesh(pts, fs; normal = Vec3f.(pts))
end

function plots!(game)
    for k in (:cap, :stem, :puff)
        haskey(G, k) && G[k].parent !== nothing && delete!(G[k].parent, G[k])
    end
    sc = game.stage.scene
    G[:cap] = mesh!(sc, dome(); color = GOLD, shading = Makie.NoShading, visible = false, name = :giant_cap)
    G[:stem] = mesh!(sc, Makie.normal_mesh(Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0)); color = RGBf(1, 0.95, 0.82),
                     visible = false, name = :giant_stem)
    G[:puff] = meshscatter!(sc, fill(Point3f(0, 0, -50), 16); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 16),
                            color = RGBf(1, 0.97, 0.9), name = :giant_puff)
end

function show_shroom!(s::Giant, w, k)
    p = s.shroom
    for key in (:cap, :stem)
        G[key].visible = k > 0
    end
    k > 0 || return
    Makie.scale!(G[:stem], 0.07f0 * k, 0.07f0 * k, 0.22f0 * k)
    Makie.translate!(G[:stem], p[1], p[2], p[3])
    Makie.scale!(G[:cap], 0.2f0 * k, 0.2f0 * k, 0.16f0 * k)
    Makie.translate!(G[:cap], p[1], p[2], p[3] + 0.2f0 * k)
end

"Lumi's own herd scaled by `s` about its feet (Lumi is the only one of its kind)."
function size!(game, me, s)
    h = get(game.stage.herds, NG.species_of(me).name, nothing)
    h === nothing && return
    p = me.pos
    Makie.scale!(h, s, s, s)
    Makie.translate!(h, p[1] - s * p[1], p[2] - s * p[2], p[3] - s * p[3])
end

function puff!(s::Giant, w, me, el)
    ps = Point3f[]; ms = Vec3f[]
    for i in 1:16
        a = 2pi * i / 16
        r = 0.6f0 + 4f0 * Float32(el)
        push!(ps, me.pos + Point3f(r * cos(a), r * sin(a), 1.2f0 + 2f0 * Float32(el) * sin(3a)^2))
        push!(ms, Vec3f(max(0f0, 0.9f0 * (1 - 1.4f0 * Float32(el)))))
    end
    Makie.update!(G[:puff]; arg1 = ps, markersize = ms)
end
hide_puff!() = Makie.update!(G[:puff]; arg1 = fill(Point3f(0, 0, -50), 16), markersize = fill(Vec3f(0), 16))

# where the riders sit, in Lumi's frame (x forward, y left) at size 1: on top of its head and on both
# shoulders (Lumi's part centres all sit at its feet point; the meshes carry the offsets)
const SEATS = (Point3f(0.02, 0, 1.66), Point3f(-0.04, 0.27, 1.2), Point3f(-0.04, -0.27, 1.2))
seats(w, me, s) = Tuple(me.pos + Point3f(q[1] * s * cos(me.yaw) - q[2] * s * sin(me.yaw), q[1] * s * sin(me.yaw) + q[2] * s * cos(me.yaw), q[3] * s) for q in SEATS)

# ---------------------------------------------------------------- the story

function begin!(s::Giant, game, me; least = 3)
    w = game.world
    near = [c for c in w.creatures if c.id != me.id && free(c) && flat(c.pos, me.pos) < REACH]
    sort!(near; by = c -> flat(c.pos, me.pos))
    length(near) < least && return false
    f = Point3f(cos(me.yaw), sin(me.yaw), 0)
    q = me.pos + 1.1f0 * f
    NG.on_land(w.island, q[1], q[2]; margin = 0.2) || return false
    s.lumi = me.id
    s.friends = [c.id for c in near[1:min(end, 7)]]
    s.riders = Int32[]; empty!(s.falls)
    s.shroom = NG.ground(w.island, (q[1], q[2]))
    s.state = :find; s.t0 = w.t; s.s = 1f0; s.stomp = w.t
    delete!(G, :eyedir)
    NG.leave_interactions!(w, me)
    me.controlled || (me.goal = NG.Goal(:giant, me.pos, :gasp, 60.0, w.t + 60, true, 0, false))
    for id in s.friends
        c = NG.creature(w, id)
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:giant, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
    end
    NG.say!(w, me, "Ooh, a golden one!"; duration = 1.6)
    NG.emit!(w, :giant_mushroom; n = length(s.friends))
    return true
end

function grow!(s::Giant, w, me)
    s.state = :grow; s.t0 = w.t
    G[:spot] = me.pos          # a giant stands its ground: Separation pushed it away from its own riders (s69)
    show_shroom!(s, w, 0)
    NG.say!(w, me, "*munch*... uh oh."; duration = 2.0)
    NG.emit!(w, :giant_grow; who = me.name)
end

function flee!(s::Giant, w, me)
    for id in s.friends
        c = NG.creature(w, id)
        mine(c) || continue
        d = flat(c.pos, me.pos)
        dir = d < 0.1 ? Vec2f(1, 0) : Vec2f(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]) / Float32(d)
        q = c.pos + Point3f(4f0 * dir[1], 4f0 * dir[2], 0)
        to = NG.on_land(w.island, q[1], q[2]; margin = 0.3) ? NG.ground(w.island, (q[1], q[2])) : c.pos
        c.goal = NG.Goal(:giant, to, :scared, 60.0, w.t + 60, false, 0, true)
        rand(w.rng) < 0.6 && NG.say!(w, c, rand(w.rng, SCREAM); duration = 1.6)
        emote(id, :what)
    end
end

function giant!(s::Giant, w, me)
    s.state = :giant; s.t0 = w.t
    NG.say!(w, me, "I'M HUGE!!!"; duration = 2.5)
    NG.emit!(w, :giant; who = me.name, n = length(s.friends))
end

function climb!(s::Giant, w, me)
    # the three nearest come back and climb on; the rest gather round the feet
    cs = [NG.creature(w, id) for id in s.friends]
    cs = sort([c for c in cs if mine(c)]; by = c -> flat(c.pos, me.pos))
    for (k, c) in enumerate(cs)
        if k <= 3
            push!(s.riders, c.id)
            NG.say!(w, c, rand(w.rng, RIDE); duration = 2.0)
            NG.emit!(w, :giant_ride; who = c.name)
        else
            a = 2pi * k / length(cs)
            q = me.pos + Point3f(3.2f0 * cos(a), 3.2f0 * sin(a), 0)
            NG.on_land(w.island, q[1], q[2]; margin = 0.3) &&
                (c.goal = NG.Goal(:giant, NG.ground(w.island, (q[1], q[2])), :jump, 60.0, w.t + 60, false, 0, true))
        end
    end
end

function burst!(s::Giant, w, me)
    s.state = :pop; s.t0 = w.t
    NG.say!(w, me, "POP!"; duration = 1.0)
    for id in s.riders
        c = NG.creature(w, id)
        mine(c) || continue
        a = 2pi * rand(w.rng)
        q = me.pos + Point3f(1.6f0 * cos(a), 1.6f0 * sin(a), 0)
        to = NG.on_land(w.island, q[1], q[2]; margin = 0.2) ? NG.ground(w.island, (q[1], q[2])) : me.pos
        s.falls[id] = (c.pos, to, w.t)
    end
    empty!(s.riders)
    NG.emit!(w, :giant_pop; who = me.name)
end

function finish!(s::Giant, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    me === nothing || size!(game, me, 1f0)
    s.s = 1f0
    show_shroom!(s, w, 0); hide_puff!()
    for id in [s.lumi; s.friends]
        c = NG.creature(w, id)
        (c === nothing || c.controlled || !mine(c)) && continue
        c.pos = NG.ground(w.island, (c.pos[1], c.pos[2]))
        id == s.lumi || NG.remember!(c, w.t, "rode on a giant Lumi after it ate a golden mushroom")
        NG.choose_goal!(c, w)
    end
    empty!(s.riders); empty!(s.falls)
    s.state = :idle; s.player = false
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :giant_end)
end

ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

function NG.step!(s::Giant, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 300.0)
    me0 = lumi_of(w)
    mdown = Makie.Keyboard.m in game.keys_down
    rising = mdown && !get(G, :mdown, false)
    G[:mdown] = mdown
    if rising && s.state === :idle && me0 !== nothing && me0.controlled
        begin!(s, game, me0; least = 0) && (s.player = true)
    end
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 9.5 < 24 * NG.daytime(w) < 18
            ok = me0 !== nothing && free(me0) && NG.on_land(w.island, me0.pos[1], me0.pos[2]; margin = 0.6) && begin!(s, game, me0)
            ok || (s.next_t = w.t + 90)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    if me === nothing || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    ours = !me.controlled && mine(me)
    el = w.t - s.t0
    if s.state === :find
        # the mushroom pushes up out of the grass, Lumi leans over and gobbles it
        show_shroom!(s, w, Float32(ease(el / 1.2)))
        ours && hold!(me, w, el < 1.8 ? :gasp : :proud)
        me.yaw = atan(s.shroom[2] - me.pos[2], s.shroom[1] - me.pos[1])
        for id in s.friends
            c = NG.creature(w, id)
            mine(c) && (c.yaw = atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1]); hold!(c, w, :idle))
        end
        el >= T_FIND && grow!(s, w, me)
    elseif s.state === :grow
        # wobbling up, overshooting a little each time
        u = Float32(el / T_GROW)
        s.s = 1f0 + (BIG - 1f0) * Float32(ease(u)) * (1f0 + 0.12f0 * sin(14f0 * u) * (1 - u))
        ours && hold!(me, w, :scared)
        el > 0.8 && !get(G, :scattered, false) && (flee!(s, w, me); G[:scattered] = true)
        el >= T_GROW && (G[:scattered] = false; giant!(s, w, me))
    elseif s.state === :giant
        s.s = BIG
        # stomp, stomp: a big hop every 2.6 s and everyone at its feet bounces
        if w.t - s.stomp > 2.6
            s.stomp = w.t
            ours && (me.action = :jump; me.goal.action = :jump)
            for id in s.friends
                c = NG.creature(w, id)
                mine(c) && !(id in s.riders) && flat(c.pos, me.pos) < 8 && (c.action = :jump; c.goal.action = :jump)
            end
        elseif ours && w.t - s.stomp > 0.8
            hold!(me, w, :proud)
        end
        el > 2.5 && isempty(s.riders) && !get(G, :climbed, false) && (climb!(s, w, me); G[:climbed] = true)
        st = seats(w, me, s.s)
        for (k, id) in enumerate(s.riders)
            c = NG.creature(w, id)
            mine(c) || continue
            c.pos = st[k] + Point3f(0, 0, 0.15f0 * abs(sin(Float32(6w.t) + k)))
            c.yaw = me.yaw
            hold!(c, w, isodd(k) ? :laugh : :proud)
            rand(w.rng) < 0.004 && NG.say!(w, c, rand(w.rng, RIDE); duration = 1.6)
        end
        for id in s.friends
            c = NG.creature(w, id)
            (mine(c) && !(id in s.riders) && c.goal.arrived && rand(w.rng) < 0.003) && NG.say!(w, c, rand(w.rng, FEET); duration = 1.6)
        end
        el >= T_GIANT && (G[:climbed] = false; burst!(s, w, me))
    elseif s.state === :pop
        u = Float32(el / T_POP)
        s.s = 1f0 + (BIG - 1f0) * (1f0 - Float32(ease(u)))
        puff!(s, w, me, el)
        for (id, (from, to, t0)) in collect(s.falls)
            c = NG.creature(w, id)
            mine(c) || (delete!(s.falls, id); continue)
            v = Float32(clamp((w.t - t0) / 0.9, 0, 1))
            p = from + (to - from) * v
            c.pos = Point3f(p[1], p[2], p[3] + 1.2f0 * 4v * (1 - v))
            c.action = :scared
            if v >= 1
                delete!(s.falls, id)
                c.pos = to
                NG.say!(w, c, rand(w.rng, FALL); duration = 1.4)
                c.goal = NG.Goal(:giant, to, :laugh, 60.0, w.t + 60, true, 0, false)
            end
        end
        if el > 1.2 && isempty(s.falls)
            s.state = :after; s.t0 = w.t; s.s = 1f0; hide_puff!()
            ours && (NG.say!(w, me, "...that was a big snack."; duration = 2.5); hold!(me, w, :shy))
        end
    else
        el > 3.0 && return finish!(s, game)
    end
    if !me.controlled && s.state in (:grow, :giant, :pop) && haskey(G, :spot)
        me.pos = G[:spot]
    end
    size!(game, me, s.s)
    return
end

"The camera stands back far enough for a giant, a little below its head."
function giant_group(w)
    s = G[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    pts = Point3f[me.pos]
    for id in s.friends
        c = NG.creature(w, id)
        c === nothing || flat(c.pos, me.pos) > 12 || push!(pts, c.pos)
    end
    d = get(G, :eyedir, nothing)
    d === nothing && (d = G[:eyedir] = clear_side(w, me))
    far = 5f0 + 2.6f0 * s.s
    eye = me.pos + Point3f(far * d[1], far * d[2], 1.2f0 + 0.6f0 * s.s)
    return (me.id, pts, (eye, me.pos + Point3f(0, 0, 0.75f0 * s.s)))
end

"A side out from Lumi with no tree, bush or rock in the line of sight; Lumi's own side first."
function clear_side(w, me)
    # Lumi's side first, the one nearer the camera: the riders on its head and shoulders show in profile
    rig = G[:game].rig
    ac = atan(rig.eye[2] - me.pos[2], rig.eye[1] - me.pos[1])
    a0 = me.yaw + (sin(ac - me.yaw) >= 0 ? 1f0 : -1f0) * Float32(pi / 2)
    blocks = [(Point2f(p.pos[1], p.pos[2]), (p.kind === :tree ? 2.4f0 : 1.2f0) * p.scale) for p in w.props if p.kind in (:tree, :bush, :rock)]
    for da in (0f0, 0.5f0, -0.5f0, 1f0, -1f0, 1.5f0, -1.5f0, 2f0, -2f0, 2.6f0, -2.6f0, Float32(pi))
        d = Vec2f(cos(a0 + da), sin(a0 + da))
        ok = all(b -> all(t -> hypot(me.pos[1] + 14f0t * d[1] - b[1][1], me.pos[2] + 14f0t * d[2] - b[1][2]) > b[2], 0.15f0:0.1f0:1.05f0), blocks)
        ok && return d
    end
    return Vec2f(cos(a0), sin(a0))
end

function NG.start!(s::Giant, game)
    G[:sys] = s
    G[:game] = game
    G[:scattered] = false; G[:climbed] = false
    delete!(G, :eyedir)
    plots!(game)
    NG.CAMERA_MOMENTS["giant"] = w -> s.state === :idle ? nothing : s.lumi
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["giant"] = NG.CAMERA_MOMENTS["giant"]      # before dance rings and the rest (garden.jl)
    NG.CAMERA_GROUPS["giant"] = giant_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:giant] = "I'M HUGE!!!")
end

function NG.stop!(s::Giant, game)
    delete!(NG.CAMERA_MOMENTS, "giant")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "giant")
    delete!(NG.CAMERA_GROUPS, "giant")
    s.state === :idle || finish!(s, game)
    for k in (:cap, :stem, :puff)
        haskey(G, k) && G[k].parent !== nothing && delete!(G[k].parent, G[k])
    end
end

register!(Giant())
