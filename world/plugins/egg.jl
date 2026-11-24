# Lumi's egg (session 70): a big golden egg turns up in the meadow in front of Lumi. "An egg?!" The friends
# hurry over and stand round it ("Is it yours, Lumi?"). It wobbles... wobbles harder... CRACK: the top flies
# off and out hops a tiny Lumi, "PEEP!". Everyone goes "Awww!", and from then on the chick follows Lumi
# wherever it goes, hopping to keep up, and sleeps beside it at night.
# The chick is Lumi's own body parts drawn at 0.38 size (no new species: a saved world must load without it).
isdefined(Main, :EGG) || Core.eval(Main, :(const EGG = Dict{Symbol,Any}()))
const NG = NeverendingGame
const E = Main.EGG

const K = 0.38f0                  # chick size when it hatches
const GROW = 0.03f0               # a little bigger every island day (s71, a wish)
const K_MAX = 0.6f0

"How big the chick is now: 0.38 of Lumi at hatching, 0.03 more every island day, at most 0.6."
size_now(w) = min(K_MAX, K + GROW * Float32(max(0.0, w.t - get(chick(), :born, w.t)) / w.day_length))
const T_FIND = 3.0
const T_WOBBLE = 5.0
const T_HATCH = 4.0
const REACH = 14f0
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :giant)
const SHELL = RGBf(1.0, 0.9, 0.62)
const COME = ("An egg!", "Whose egg is that?", "Is it yours, Lumi?", "Ooooh!")
const WOBBLE = ("Did it move?!", "It moved!", "Shhh!", "Something's in there!")
const AWW = ("Awww!", "A baby Lumi!", "It's so tiny!", "Hello, little one!", "PEEP!")

push!(NG.BUSY_GOALS, :egg)

mutable struct Egg <: System
    state::Symbol                 # :idle :find :wobble :hatch
    t0::Float64
    next_t::Float64
    lumi::Int32
    friends::Vector{Int32}
    egg::Point3f
    said::Int
end
Egg() = Egg(:idle, 0.0, -1.0, 0, Int32[], Point3f(0), 0)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free(c) = !c.controlled && c.goal.kind ∉ KEEP && c.goal.kind !== :egg && c.action !== :sleep
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
mine(c) = c !== nothing && c.goal.kind === :egg
hold!(c, w, action) = (c.goal.until = w.t + 60; c.goal.action = action; c.action = action)
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

# ---------------------------------------------------------------- the chick: Lumi's parts, small

chick() = E[:chick]
state_file(game) = joinpath(game.paths.state, "chick.json")

function save_chick!(game)
    game.dash === nothing && return              # quiet copies (films, stills) never write
    c = chick()
    NG.write_json(state_file(game), Dict("hatched" => c[:hatched], "x" => c[:pos][1], "y" => c[:pos][2],
                                         "born" => get(c, :born, game.world.t)))
end

function load_chick!(game)
    E[:chick] = Dict{Symbol,Any}(:hatched => false, :pos => Point3f(0, 0, -50), :yaw => 0f0, :phase => 0f0,
                                 :action => :idle, :hop => -1.0, :saved => 0.0)
    f = state_file(game)
    if game.dash !== nothing && isfile(f)
        d = NG.read_json(f)
        if d["hatched"] === true
            w = game.world
            chick()[:hatched] = true
            chick()[:pos] = NG.ground(w.island, (Float32(d["x"]), Float32(d["y"])))
            chick()[:born] = Float64(get(d, "born", w.t))     # chicks from before s71 start growing now
        end
    end
end

function chick_plots!(game)
    for p in get(E, :parts, Any[])
        p.parent !== nothing && delete!(p.parent, p)
    end
    me = lumi_of(game.world)
    sp = me === nothing ? NG.SPECIES["Lumi"] : NG.species_of(me)
    E[:species] = sp
    E[:parts] = Any[]
    for (j, part) in enumerate(sp.parts)
        uv = NG.paints(part.motion) ? (; uv_transform = [Makie.Mat{2,3,Float32}(1, 0, 0, 1, 0, 0)]) : (;)
        push!(E[:parts], meshscatter!(game.stage.scene, [Point3f(0, 0, -50)]; marker = NG.shape(part.shape),
                                      material = part.material, markersize = [Vec3f(0)],
                                      rotation = [Makie.Quaternionf(0, 0, 0, 1)], uv..., part.attributes...,
                                      name = Symbol(:chick_, j)))
    end
end

function draw_chick!(w)
    c = chick()
    sp = E[:species]
    out = [(Point3f[], Makie.Quaternionf[], Vec3f[], Makie.Mat{2,3,Float32}[]) for _ in sp.parts]
    shown = c[:hatched] || get(E, :peek, false)
    p = c[:pos]
    if shown
        NG.pose_parts!(out, sp, p, c[:yaw], c[:action], c[:phase], 0.8f0, 0f0, 7f0, Float32(w.t))
    end
    for (j, part) in enumerate(sp.parts)
        o = out[j]
        if !shown || isempty(o[1])
            Makie.update!(E[:parts][j]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)])
            continue
        end
        k = size_now(w)
        ps = [p + k * (q - p) for q in o[1]]
        if NG.paints(part.motion) && !isempty(o[4])
            Makie.update!(E[:parts][j]; arg1 = ps, rotation = o[2], markersize = [k * s for s in o[3]], uv_transform = o[4])
        else
            Makie.update!(E[:parts][j]; arg1 = ps, rotation = o[2], markersize = [k * s for s in o[3]])
        end
    end
end

"A \"peep!\" over the chick for a moment (the 2D overlay, like Lumi's thought bubble); hidden otherwise."
function draw_peep!(game)
    st = game.stage
    (st === nothing || st.overlay === nothing) && return
    if !haskey(E, :peep) || E[:peep].parent === nothing
        E[:peep] = text!(st.overlay, Point2f(-500, -500); text = "peep!", fontsize = 17, font = :bold,
                         color = RGBf(0.95, 0.62, 0.1), strokewidth = 2, strokecolor = RGBf(1, 1, 1),
                         align = (:center, :bottom), name = :chick_peep)
    end
    c = chick()
    px = c[:hatched] && game.world.t < get(E, :peep_until, -Inf) ? NG.on_screen(st.scene, c[:pos] + Point3f(0, 0, 0.6f0)) : nothing
    Makie.update!(E[:peep]; arg1 = px === nothing ? Point2f(-500, -500) : Point2f(px[1], px[2] + 6))
end

"The chick trots after Lumi (behind and to one side), hops to keep up, and sleeps when Lumi sleeps."
function follow!(w, game, dt)
    get(E, :lesson, false) && return              # a flying lesson (flylesson.jl) moves the chick itself
    c = chick()
    me = lumi_of(w)
    me === nothing && return
    f = Point3f(cos(me.yaw), sin(me.yaw), 0); l = Point3f(-sin(me.yaw), cos(me.yaw), 0)
    goal = me.pos - 0.3f0 * f + 0.8f0 * l     # at its side, a little back: behind it the follow camera (front three-quarter) hid it
    d = flat(goal, c[:pos])
    if me.action === :sleep
        c[:action] = :sleep
    elseif d > 0.25f0
        sp = 0.6f0 + 1.6f0 * min(d, 3f0)
        step = min(d, sp * Float32(dt))
        dir = (goal - c[:pos]) / d
        q = c[:pos] + step * Point3f(dir[1], dir[2], 0)
        if NG.on_land(w.island, q[1], q[2]; margin = 0.05)
            c[:pos] = NG.ground(w.island, (q[1], q[2]))
        end
        c[:yaw] = atan(dir[2], dir[1])
        c[:phase] += 2.5f0 * step / K
        c[:action] = d > 1.5f0 ? :run : :walk
        d > 6f0 && (c[:pos] = NG.ground(w.island, (goal[1], goal[2])))    # left far behind (a flight, a boing): it catches up
    else
        c[:yaw] = me.yaw
        c[:action] = me.action in (:proud, :laugh, :dance, :jump) ? me.action : :idle
        # now and then a little hop on the spot and a "peep!"
        if me.action !== :sleep && w.t > get(E, :next_peep, 0.0)
            E[:next_peep] = w.t + 7 + 9 * rand(w.rng)
            E[:peep_until] = w.t + 1.6
            c[:hop] = w.t
        end
        w.t - c[:hop] < 0.7 && (c[:action] = :jump)
    end
    if w.t - c[:saved] > 30
        c[:saved] = w.t
        save_chick!(game)
    end
end

# ---------------------------------------------------------------- the egg

function egg_plots!(game)
    for k in (:egg, :top)
        haskey(E, k) && E[k].parent !== nothing && delete!(E[k].parent, E[k])
    end
    sc = game.stage.scene
    # one-instance meshscatters moved through positions/markersize/rotation: the path tracer ignores plot transforms
    for k in (:egg, :top)
        E[k] = meshscatter!(sc, [Point3f(0, 0, -50)]; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)],
                            rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = SHELL, name = Symbol(:egg_, k))
    end
end

put!(k, p, s, q) = Makie.update!(E[k]; arg1 = [p], markersize = [s], rotation = [q])
hide!(k) = put!(k, Point3f(0, 0, -50), Vec3f(0), Makie.Quaternionf(0, 0, 0, 1))

function show_egg!(s::Egg, w, grow, tilt, cracked, top_t)
    e = s.egg
    if grow <= 0
        hide!(:egg); hide!(:top)
        return
    end
    if !cracked
        put!(:egg, e + Point3f(0, 0, 0.42f0 * grow), Vec3f(0.3f0, 0.3f0, 0.42f0) * grow, Makie.qrotation(Vec3f(1, 0, 0), tilt))
        hide!(:top)
    else
        # the bottom stays as a cup; the top tumbles off in an arc
        put!(:egg, e + Point3f(0, 0, 0.12f0), Vec3f(0.3f0, 0.3f0, 0.22f0), Makie.Quaternionf(0, 0, 0, 1))
        u = Float32(clamp(top_t / 0.9, 0, 1))
        sd = get(E, :side, Point3f(1, 0, 0))
        put!(:top, e + 1.3f0 * u * sd + Point3f(0, 0, 0.6f0 + 2.2f0 * u * (1 - u) - 0.5f0 * u), Vec3f(0.27f0, 0.27f0, 0.2f0),
             Makie.qrotation(Vec3f(1, 0, 0), 4f0 * u))
    end
end

function begin!(s::Egg, game, me; least = 2)
    w = game.world
    f = Point3f(cos(me.yaw), sin(me.yaw), 0)
    q = me.pos + 1.3f0 * f
    NG.on_land(w.island, q[1], q[2]; margin = 0.2) || return false
    near = [c for c in w.creatures if c.id != me.id && free(c) && flat(c.pos, me.pos) < REACH]
    sort!(near; by = c -> flat(c.pos, me.pos))
    length(near) < least && return false
    s.lumi = me.id
    s.friends = [c.id for c in near[1:min(end, 6)]]
    s.egg = NG.ground(w.island, (q[1], q[2]))
    s.state = :find; s.t0 = w.t; s.said = 0
    E[:lumi_at] = me.pos
    E[:side] = Point3f(-f[2], f[1], 0)            # the shell top flies off to Lumi's left
    chick()[:hatched] = false
    NG.leave_interactions!(w, me)
    me.controlled || (me.goal = NG.Goal(:egg, me.pos, :gasp, 60.0, w.t + 60, true, 0, false))
    # the friends come and stand round the egg, on the side away from Lumi
    away = atan(s.egg[2] - me.pos[2], s.egg[1] - me.pos[1])
    for (k, id) in enumerate(s.friends)
        c = NG.creature(w, id)
        NG.leave_interactions!(w, c)
        # flanking Lumi behind the egg, so a camera looking at Lumi over the egg sees all of them (s70 preview:
        # standing at the egg's sides they walked through the foreground and hid it)
        a = away + Float32(pi) + (isodd(k) ? 1f0 : -1f0) * (0.75f0 + 0.35f0 * div(k - 1, 2))
        spot = s.egg + Point3f(2.2f0 * cos(a), 2.2f0 * sin(a), 0)
        spot = NG.on_land(w.island, spot[1], spot[2]; margin = 0.2) ? NG.ground(w.island, (spot[1], spot[2])) : c.pos
        c.goal = NG.Goal(:egg, spot, :gasp, 60.0, w.t + 60, false, 0, true)
    end
    NG.say!(w, me, "An egg?!"; duration = 2.0)
    NG.emit!(w, :egg_found; n = length(s.friends))
    return true
end

function hatch!(s::Egg, w, me)
    s.state = :hatch; s.t0 = w.t
    c = chick()
    c[:hatched] = true
    c[:born] = w.t
    c[:pos] = s.egg + Point3f(0, 0, 0.12f0)
    c[:yaw] = atan(me.pos[2] - s.egg[2], me.pos[1] - s.egg[1]) + Float32(pi)
    c[:action] = :jump
    c[:hop] = w.t
    NG.emit!(w, :egg_hatch; who = me.name)
end

function finish!(s::Egg, game)
    w = game.world
    show_egg!(s, w, 0f0, 0f0, false, 0.0)
    for id in [s.lumi; s.friends]
        c = NG.creature(w, id)
        (c === nothing || c.controlled || !mine(c)) && continue
        id == s.lumi || NG.remember!(c, w.t, "saw Lumi's egg hatch into a tiny chick")
        NG.choose_goal!(c, w)
    end
    s.state = :idle
    save_chick!(game)
    NG.emit!(w, :egg_end)
end

function NG.step!(s::Egg, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 180.0)
    c = chick()
    if s.state === :idle
        c[:hatched] && follow!(w, game, dt)
        draw_chick!(w)
        draw_peep!(game)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if !c[:hatched] && w.t >= s.next_t && !testing && !busy_game && 9 < 24 * NG.daytime(w) < 18
            me = lumi_of(w)
            ok = me !== nothing && free(me) && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.6) && begin!(s, game, me)
            ok || (s.next_t = w.t + 60)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    if me === nothing || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        c[:hatched] = true; c[:pos] = s.egg
        return finish!(s, game)
    end
    # Lumi stays by its egg: another plugin's errand (a present, a pebble) took it away in the s70 preview
    if !me.controlled
        mine(me) || (me.goal = NG.Goal(:egg, E[:lumi_at], :gasp, 60.0, w.t + 60, true, 0, false))
        me.pos = E[:lumi_at]
    end
    ours = !me.controlled && mine(me)
    el = w.t - s.t0
    me.yaw = atan(s.egg[2] - me.pos[2], s.egg[1] - me.pos[1])
    for id in s.friends
        f = NG.creature(w, id)
        mine(f) && f.goal.arrived && (f.yaw = atan(s.egg[2] - f.pos[2], s.egg[1] - f.pos[1]))
    end
    if s.state === :find
        show_egg!(s, w, Float32(ease(el / 0.6)), 0f0, false, 0.0)
        ours && hold!(me, w, el < 1.5 ? :gasp : :think)
        if el > 1.2 && s.said < 2 && !isempty(s.friends)
            s.said += 1
            f = NG.creature(w, s.friends[s.said > length(s.friends) ? 1 : s.said])
            mine(f) && NG.say!(w, f, rand(w.rng, COME); duration = 1.8)
        end
        el >= T_FIND && (s.state = :wobble; s.t0 = w.t; s.said = 0)
    elseif s.state === :wobble
        # rocking harder and harder, little pauses between
        a = Float32(0.06 + 0.06 * el) * sin(Float32(9 * el)) * (sin(Float32(2.2 * el)) > -0.3 ? 1f0 : 0.2f0)
        show_egg!(s, w, 1f0, a, false, 0.0)
        ours && hold!(me, w, :gasp)
        if el > 1.5 * (s.said + 1) && s.said < 2 && !isempty(s.friends)
            s.said += 1
            f = NG.creature(w, s.friends[mod1(s.said + 1, length(s.friends))])
            mine(f) && (NG.say!(w, f, rand(w.rng, WOBBLE); duration = 1.6); hold!(f, w, :gasp))
        end
        if el >= T_WOBBLE
            NG.say!(w, me, "CRACK!"; duration = 1.2)
            hatch!(s, w, me)
        end
    elseif s.state === :hatch
        show_egg!(s, w, 1f0, 0f0, true, el)
        # PEEP! a hop out of the shell, then two little hops towards Lumi
        u = el
        if u < 0.5
            c[:pos] = s.egg + Point3f(0, 0, 0.12f0 + 0.6f0 * Float32(u / 0.5) * Float32(1 - u / 0.5) * 2)
            c[:action] = :jump
        elseif u < 2.2
            v = Float32((u - 0.5) / 1.7)
            to = s.egg + 0.45f0 * (me.pos - s.egg)
            p = s.egg + v * (to - s.egg)
            c[:pos] = NG.ground(w.island, (p[1], p[2])) + Point3f(0, 0, 0.25f0 * abs(sin(Float32(pi) * 3 * v)))
            c[:yaw] = atan(me.pos[2] - s.egg[2], me.pos[1] - s.egg[1])
            c[:action] = :jump
        else
            c[:pos] = NG.ground(w.island, (c[:pos][1], c[:pos][2]))
            c[:action] = :proud
        end
        if el > 0.3 && s.said == 0
            s.said = 1
            NG.say!(w, me, "...PEEP?"; duration = 1.4)
        end
        if el > 1.0 && s.said == 1
            s.said = 2
            for (k, id) in enumerate(s.friends)
                f = NG.creature(w, id)
                mine(f) || continue
                hold!(f, w, isodd(k) ? :jump : :laugh)
                k <= 3 && NG.say!(w, f, AWW[mod1(k, length(AWW))]; duration = 2.0)
                emote(id, :heart)
            end
        end
        if el > 2.4 && s.said == 2
            s.said = 3
            ours && hold!(me, w, :proud)
            NG.say!(w, me, "Hello, little one."; duration = 2.5)
        end
        el >= T_HATCH && finish!(s, game)
    end
    draw_chick!(w)
    return
end

"The camera stands on the far side of the egg from Lumi, low, so the egg, Lumi and the friends are in view."
function egg_group(w)
    s = E[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    pts = Point3f[me.pos, s.egg]
    for id in s.friends
        c = NG.creature(w, id)
        c === nothing || flat(c.pos, s.egg) > 6 || push!(pts, c.pos)
    end
    u = s.egg - me.pos
    n = hypot(u[1], u[2])
    d = n < 0.1 ? Point3f(1, 0, 0) : Point3f(u[1] / n, u[2] / n, 0)
    eye = s.egg + 4.6f0 * d + Point3f(0, 0, 1.7f0)
    return (me.id, pts, (eye, s.egg + Point3f(0, 0, 0.6f0)))
end

function NG.start!(s::Egg, game)
    E[:sys] = s
    load_chick!(game)
    chick_plots!(game)
    egg_plots!(game)
    NG.CAMERA_MOMENTS["egg"] = w -> s.state === :idle ? nothing : s.lumi
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["egg"] = NG.CAMERA_MOMENTS["egg"]      # before dance rings and the rest (garden.jl)
    NG.CAMERA_GROUPS["egg"] = egg_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:egg] = "An egg?!")
end

function NG.stop!(s::Egg, game)
    delete!(NG.CAMERA_MOMENTS, "egg")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "egg")
    delete!(NG.CAMERA_GROUPS, "egg")
    s.state === :idle || (chick()[:hatched] = true; finish!(s, game))
    for p in get(E, :parts, Any[])
        p.parent !== nothing && delete!(p.parent, p)
    end
    haskey(E, :peep) && E[:peep].parent !== nothing && delete!(E[:peep].parent, E[:peep])
    for k in (:egg, :top)
        haskey(E, k) && E[k].parent !== nothing && delete!(E[k].parent, E[k])
    end
end

register!(Egg())
