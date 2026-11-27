# Summer showers: now and then by day a grey cloud parks over the island and it rains for
# about 40 s. Every critter takes it its own way: one runs for a tree and sulks under the
# crown, one jumps in the puddles, one does a rain dance, one sits with its nose up and
# enjoys it. Jump in as Lumi and splash (Space) or dance in the open: the ones hiding
# under the trees can't resist, come out one by one and the whole lot holds a puddle party
# round Lumi. When the sun comes back everyone says so, a little happier.
isdefined(Main, :SHOWERS) || Core.eval(Main, :(const SHOWERS = Dict{Symbol,Any}()))
import Random
const NG = NeverendingGame
const SH = Main.SHOWERS
const SHOWER_VERSION = 5

const GAP = (300.0, 520.0)       # sim seconds between showers (by day)
const RAIN_TIME = 40.0
const NDROPS = 520
const NRINGS = 12                # creatures with splash rings
const RAIN_R = 15f0               # drops fall in a disc this wide round what the camera looks at
const DROP_COLOR = RGBAf(0.72, 0.8, 0.95, 0.55)
const ROLES = (:shelter, :splash, :dance, :nose)
const LINES = Dict(
    :shelter => ("Eek! Wet wet wet!", "Under the tree, quick!", "My fur!"),
    :splash  => ("Puddles!!", "Splish splash!", "Best. Day. Ever."),
    :dance   => ("Rain dance!", "Twirl in the drizzle!", "La la la-in!"),
    :nose    => ("Mmm, cool rain on my nose.", "Listen to it patter...", "Ahh, lovely."))
const COME_OUT = ("Lumi's splashing! Wait for me!", "Oh, that looks fun!", "Fine, I'm coming!", "Me too, me too!")
const SUN_BACK = ("The sun's back!", "That was fun!", "Everything smells green.", "All shiny now.")

push!(NG.BUSY_GOALS, :rain)       # a critter in the rain is not pulled away for a chat

mutable struct Shower <: System
    active::Bool
    center::Point3f               # where the rain cloud hangs
    roles::Dict{Int32,Symbol}
    lines::Vector{Tuple{Float64,Int32,String}}   # (when, who, what): the reactions come one after another
    started::Float64
    until::Float64
    next_t::Float64
    joined::Float64               # when Lumi started splashing (0: not yet)
    next_out::Float64             # the next shelterer to come out
    count::Int
    rainbow_until::Float64
end
Shower() = Shower(false, Point3f(0), Dict{Int32,Symbol}(), Tuple{Float64,Int32,String}[], 0.0, 0.0, -1.0, 0.0, 0.0, 0, 0.0)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
face!(c, p) = (c.yaw = Float32(atan(p[2] - c.pos[2], p[1] - c.pos[1])) - NG.species_of(c).heading)

can_join(c) = !c.controlled && c.species != "Lumi" && c.action !== :sleep && c.goal.kind ∉ (:sleep, :follow, :answer, :interact) && !NG.busy(c)

"A dry spot under the nearest tree's crown, outside the trunk."
function shelter_spot(w, c)
    tree, d = NG.nearest(p -> p.kind === :tree, w.props, c.pos)
    (tree === nothing || d > 25) && return nothing
    dir = normalize(Vec2f(c.pos[1] - tree.pos[1], c.pos[2] - tree.pos[2]) + Vec2f(1f-3))
    r = get(NG.SOLID_FOOTPRINT, :tree, 0.35f0) * tree.scale + 0.7f0 * NG.body_radius(NG.species_of(c)) + 0.25f0
    p = Point2f(tree.pos[1], tree.pos[2]) + r * dir
    NG.on_land(w.island, p[1], p[2]; margin = 0.2f0) || return nothing
    # the walk there must stay on land: a crab at the shore with a bay in between was turned back
    # by the coast and dropped out of the shower (s38)
    n = max(2, ceil(Int, 2hypot(p[1] - c.pos[1], p[2] - c.pos[2])))
    a = Point2f(c.pos[1], c.pos[2])
    all(k -> (q = a + (k / n) * (p - a); NG.on_land(w.island, q[1], q[2]; margin = 0.1f0)), 1:n) || return nothing
    return NG.ground(w.island, p), tree
end

rain_goal(target, action; arrived = true, run = false) = NG.Goal(:rain, target, action, RAIN_TIME + 30, Inf, arrived, 0, run)

function start_shower!(s::Shower, game)
    w = game.world
    me = NG.creature(w, "Lumi")
    cs = [c for c in w.creatures if can_join(c)]
    length(cs) < 3 && return false
    s.count += 1
    sort!(cs; by = c -> c.name)
    empty!(s.roles); empty!(s.lines)
    t = w.t + 1.5
    for (k, c) in enumerate(cs)
        role = ROLES[mod1(k + s.count, length(ROLES))]
        if role === :shelter
            sp = shelter_spot(w, c)
            sp === nothing && (role = :nose)
            # huddled under the tree, trembling with a scared face (todo #325)
            sp === nothing || (c.goal = rain_goal(sp[1], :scared; arrived = false, run = true))
        end
        role === :splash && (c.goal = rain_goal(c.pos, :jump))
        role === :dance && (c.goal = rain_goal(c.pos, :dance))
        role === :nose && (c.goal = rain_goal(c.pos, :sit))
        c.goal.arrived && (c.action = c.goal.action)
        s.roles[c.id] = role
        push!(s.lines, (t, c.id, rand(w.rng, LINES[role])))
        t += 1.3 + 0.6rand(w.rng)
    end
    xs = [c.pos for c in cs]
    s.center = Point3f(sum(p -> p[1], xs) / length(xs), sum(p -> p[2], xs) / length(xs), 0)
    s.active = true; s.started = w.t; s.until = w.t + RAIN_TIME; s.joined = 0.0; s.next_out = 0.0
    NG.emit!(w, :shower; who = join([c.name for c in cs], ", "))
    return true
end

function end_shower!(s::Shower, game)
    w = game.world
    k = 0
    for (id, role) in s.roles
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :rain) && continue
        c.mood = min(1.0f0, c.mood + (role === :shelter ? 0.05f0 : 0.15f0))
        NG.remember!(c, w.t, s.joined > 0 ? "splashed in the rain with Lumi" : role === :shelter ? "hid from the rain under a tree" : "played in the rain")
        NG.choose_goal!(c, w)
        k += 1
        k <= 2 && NG.say!(w, c, rand(w.rng, SUN_BACK); duration = 2.5)
    end
    empty!(s.roles); empty!(s.lines)
    s.active = false
    NG.is_night(w) || (s.rainbow_until = w.t + RAINBOW_TIME)
    SH[:ended] = w.t
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
end

"Lumi splashes in the open: the shelterers come out one by one, everyone gathers round Lumi and jumps."
function puddle_party!(s::Shower, w, me)
    if s.joined == 0
        s.joined = w.t; s.next_out = w.t + 1.0
        NG.emit!(w, :shower_join; who = me.name)
        emote(me.id, :note)
    end
    members = [c for c in (NG.creature(w, id) for id in keys(s.roles)) if c !== nothing && c.goal.kind === :rain]
    sort!(members; by = c -> c.id)
    n = length(members)
    for (k, c) in enumerate(members)
        a = Float32(2pi * k / n)
        spot = NG.ground(w.island, (me.pos[1] + 1.6f0 * cos(a), me.pos[2] + 1.6f0 * sin(a)))
        role = s.roles[c.id]
        if role === :shelter
            w.t < s.next_out && continue
            s.roles[c.id] = :party
            s.next_out = w.t + 1.4
            c.goal = rain_goal(spot, :jump; arrived = false, run = true)
            NG.say!(w, c, rand(w.rng, COME_OUT); duration = 2.2)
            emote(c.id, :hey)
        elseif role !== :party
            s.roles[c.id] = :party
            c.goal = rain_goal(spot, :jump; arrived = false, run = true)
            emote(c.id, :heart)
        elseif c.goal.arrived
            face!(c, me.pos)
            c.goal.target = spot
            hypot(spot[1] - c.pos[1], spot[2] - c.pos[2]) > 1.2f0 && (c.goal.arrived = false)   # Lumi moved on: follow the party
        end
    end
end

# ── the rain itself: streaks round what the camera looks at, a grey cloud over the island ──

function build!(game)
    for k in (:drops, :cloud, :rings)
        haskey(SH, k) && delete!(SH[k].parent, SH[k])
    end
    sc = game.stage.scene
    # splash rings round the feet of whoever jumps or dances in the rain: two per creature, growing and fading
    # real rings (a torus), not flattened spheres: a filled disc cut by the slope read as a big pale half-disc (s38)
    SH[:rings] = meshscatter!(sc, fill(Point3f(0, 0, -100), 2NRINGS); marker = NG.unit_torus(0.07f0, 32, 6),
        markersize = fill(Vec3f(0), 2NRINGS), color = fill(RGBAf(0.85, 0.92, 1.0, 0.0), 2NRINGS), transparency = true,
        shading = Makie.NoShading, material = NG.Hikari.Emission(color = (0.85, 0.92, 1.0), strength = 0.5),
        name = :rainrings, visible = false)
    SH[:drops] = meshscatter!(sc, fill(Point3f(0, 0, -100), NDROPS); marker = NG.shape(:glowdot),
        markersize = Vec3f(0.011, 0.011, 0.17), color = DROP_COLOR, transparency = true, shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (0.72, 0.8, 0.95), strength = 0.6), name = :rain, visible = false)
    rng = Random.Xoshiro(11)
    SH[:seeds] = [(rand(rng, Float32), rand(rng, Float32), rand(rng, Float32)) for _ in 1:NDROPS]
    SH[:puffs] = [(Vec3f(9f0 * (rand(rng, Float32) - 0.5f0), 6f0 * (rand(rng, Float32) - 0.5f0), rand(rng, Float32)), 2.5f0 + 2rand(rng, Float32)) for _ in 1:14]
    # painted shading like plugins/clouds.jl: the higher a puff, the lighter (one flat grey read as a disc, s38)
    SH[:cloud] = meshscatter!(sc, fill(Point3f(0, 0, -100), 14); marker = NG.shape(:glowball),
        markersize = [Vec3f(r, r, 0.7f0r) for (_, r) in SH[:puffs]],
        color = [RGBf(0.5f0 + 0.2f0 * o[3], 0.54f0 + 0.2f0 * o[3], 0.62f0 + 0.18f0 * o[3]) for (o, _) in SH[:puffs]],
        shading = Makie.NoShading, material = NG.Hikari.Emission(color = (0.62, 0.66, 0.74), strength = 1.0),
        name = :raincloud, visible = false)
    SH[:key] = (SHOWER_VERSION, sc)
end

const CLOUD_Z = 24f0

function show_rain!(s::Shower, game)
    w = game.world
    fade = s.active ? clamp(min(w.t - s.started, s.until - w.t) / 4, 0, 1) : 0.0   # rain starts and stops softly
    on = fade > 0.01
    SH[:drops].visible[] == on || (SH[:drops].visible[] = on)
    SH[:cloud].visible[] == on || (SH[:cloud].visible[] = on)
    SH[:rings].visible[] == on || (SH[:rings].visible[] = on)
    on || return
    splash_rings!(s, w)
    c = game.rig.target; eye = game.rig.eye
    n = round(Int, NDROPS * fade)
    pos = Vector{Point3f}(undef, NDROPS)
    for (i, (u, v, ph)) in enumerate(SH[:seeds])
        if i > n
            pos[i] = Point3f(0, 0, -100)
            continue
        end
        r = RAIN_R * sqrt(u); a = 2f0pi * v
        x = c[1] + r * cos(a); y = c[2] + r * sin(a)
        h = 7f0 * mod(ph - 0.9f0 * Float32(mod(w.t, 100.0)), 1f0)       # falls 6.3 m/s, then starts again at the top
        p = Point3f(x, y, NG.terrain_height(w.island, x, y) + h)
        pos[i] = norm(p - eye) < 3f0 ? Point3f(0, 0, -100) : p     # no white blades across the lens
    end
    Makie.update!(SH[:drops]; arg1 = pos)
    # high over the island, and no puff near the lens: at 15 m the follow camera rose into one and a
    # huge flat pale disc filled a corner of the picture (host, s38)
    top = s.center + Point3f(0, 0, CLOUD_Z)
    drift = Float32(0.15 * (w.t - s.started))
    ps = [top + Point3f(o[1] + drift, o[2], 1.2f0 * o[3]) for (o, _) in SH[:puffs]]
    ms = [norm(p - eye) < 1.5f0 * r + 6f0 ? Vec3f(0) : Vec3f(r, r, 0.7f0r) for (p, (_, r)) in zip(ps, SH[:puffs])]
    Makie.update!(SH[:cloud]; arg1 = ps, markersize = ms)
end

"The sun and sky grey down while it rains, in 0.1 steps (each step re-bakes the sky once)."
function dim_sun!(s::Shower, w)
    fade = s.active ? clamp(min(w.t - s.started, s.until - w.t) / 5, 0, 1) : 0.0
    # 1.0 … 0.55 (perfectionist-0079: rain fell under hard noon sun at 0.7; 0.6 once looked gloomy with the wet ground)
    d = 1f0 - 0.09f0 * round(5 * fade)
    # a thunderstorm (storm.jl) greys the day further while its cloud is overhead, in the same 0.1 steps (s77,
    # perfectionist-0076: "under the black cloud the island stays in full noon sun"); the storm lasts 21 s
    st = isdefined(Main, :STORM) ? get(Main.STORM, :sys, nothing) : nothing
    if st !== nothing && st.state === :on
        el = w.t - st.t0
        f = clamp(min(el / 3, (21.0 - el) / 3), 0, 1)
        d = min(d, 1f0 - 0.1f0 * round(7 * f))     # down to 0.3
    end
    # a hail cloud (hail.jl) overhead greys it too, down to 0.5 (s84)
    hl = isdefined(Main, :HAIL) ? Float32(get(Main.HAIL, :dim, 0f0)) : 0f0
    hl > 0 && (d = min(d, 1f0 - 0.1f0 * round(5 * hl)))
    # the sun under the sea (underlight.jl, s116) darkens the sky to 0.04
    ul = isdefined(Main, :UNDERLIGHT) ? Float32(get(Main.UNDERLIGHT, :dim, 1f0)) : 1f0
    d = min(d, ul)
    # the sun is a ball on the meadow (sunball.jl, s122): the sky goes dusky
    sb = isdefined(Main, :SUNBALL) ? Float32(get(Main.SUNBALL, :dim, 1f0)) : 1f0
    d = min(d, sb)
    NG.SUN_DIM[] == d || (NG.SUN_DIM[] = d)
end

# ── the rainbow: an arc over the sea opposite the sun for RAINBOW_TIME after a shower ──
const RAINBOW_TIME = 22.0
const BOW = (RGBf(0.9, 0.25, 0.25), RGBf(0.95, 0.6, 0.2), RGBf(0.95, 0.9, 0.3), RGBf(0.35, 0.8, 0.35),
             RGBf(0.3, 0.55, 0.95), RGBf(0.5, 0.35, 0.85))

"Vertices, faces and base colours of a rainbow arc standing opposite the sun, seen from the island."
function rainbow_mesh(w)
    sd, _ = NG.sun(w)
    away = normalize(Vec2f(-sd[1], -sd[2]) + Vec2f(1f-4))
    side = Vec2f(-away[2], away[1])
    C = Point3f(62f0 * away[1], 62f0 * away[2], -6f0)
    R = 38f0; width = 4.5f0
    nr = 13; na = 56
    pts = Point3f[]; cols = RGBAf[]; faces = GLTriangleFace[]
    for j in 0:na, i in 0:(nr - 1)
        a = Float32(pi * j / na)
        f = i / (nr - 1)                                  # 0 inner (violet) → 1 outer (red)
        r = R + width * f
        push!(pts, C + Point3f(r * cos(a) * side[1], r * cos(a) * side[2], r * sin(a)))
        k = clamp(1 + (length(BOW) - 1) * (1 - f), 1, length(BOW))
        k0 = floor(Int, k); k1 = min(k0 + 1, length(BOW)); t = Float32(k - k0)
        c = RGBf((1 - t) * BOW[k0].r + t * BOW[k1].r, (1 - t) * BOW[k0].g + t * BOW[k1].g, (1 - t) * BOW[k0].b + t * BOW[k1].b)
        push!(cols, RGBAf(c, Float32(sin(pi * f))))       # soft edges; times the fade below
    end
    idx(j, i) = j * nr + i + 1
    for j in 0:(na - 1), i in 0:(nr - 2)
        push!(faces, GLTriangleFace(idx(j, i), idx(j + 1, i), idx(j + 1, i + 1)))
        push!(faces, GLTriangleFace(idx(j, i), idx(j + 1, i + 1), idx(j, i + 1)))
    end
    return GeometryBasics.Mesh(pts, faces), cols
end

function show_rainbow!(s::Shower, game)
    w = game.world
    left = s.rainbow_until - w.t
    if left <= 0
        haskey(SH, :bow) && SH[:bow].visible[] && (SH[:bow].visible[] = false)
        return
    end
    if !haskey(SH, :bow) || SH[:bow_built] != s.count
        haskey(SH, :bow) && delete!(SH[:bow].parent, SH[:bow])
        m, cols = rainbow_mesh(w)
        SH[:bow_cols] = cols; SH[:bow_built] = s.count; SH[:bow_step] = -1
        SH[:bow] = mesh!(game.stage.scene, m; color = cols, shading = Makie.NoShading, transparency = true, name = :rainbow)
    end
    SH[:bow].visible[] || (SH[:bow].visible[] = true)
    fade = clamp(min(RAINBOW_TIME - left, left) / 5, 0, 1)
    step = round(Int, 6 * fade)                          # a few colour updates, not one per frame
    if step != SH[:bow_step]
        SH[:bow_step] = step
        SH[:bow].color[] = [RGBAf(c.r, c.g, c.b, 0.42f0 * c.alpha * step / 6) for c in SH[:bow_cols]]
    end
end

const DRY_TIME = 40.0
"The meadow darkens as it gets wet (in 4 steps: each repaints the terrain colours once) and dries after the rain."
function wet_ground!(s::Shower, game)
    w = game.world
    painted = get(Main.MEADOW, :painted, nothing)       # plugins/meadow.jl's colours
    painted === nothing && return
    wet = s.active ? clamp((w.t - s.started) / 12, 0, 1) : clamp(1 - (w.t - get(SH, :ended, -1e9)) / DRY_TIME, 0, 1)
    step = round(Int, 4 * wet)
    step == get(SH, :wet_step, 0) && return
    SH[:wet_step] = step
    sc = game.stage.scene
    i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :terrain, sc.plots)
    i === nothing && return
    k = 0.045f0 * step                                  # up to 18 % darker, a touch cooler (36 % with the dim sun was gloomy)
    sc.plots[i].color[] = step == 0 ? painted : [RGBf(c.r * (1 - 1.1f0k), c.g * (1 - k), c.b * (1 - 0.7f0k)) for c in painted]
end

function splash_rings!(s::Shower, w)
    rp = fill(Point3f(0, 0, -100), 2NRINGS); rs = fill(Vec3f(0), 2NRINGS); rc = fill(RGBAf(0.85, 0.92, 1.0, 0.0), 2NRINGS)
    k = 0
    me = NG.creature(w, "Lumi")
    for c in w.creatures
        (c === me ? c.controlled : haskey(s.roles, c.id) && c.goal.kind === :rain) || continue
        c.action in (:jump, :dance) || continue
        k >= NRINGS && break
        for j in 0:1
            f = Float32(mod(1.1 * w.t + 0.5j + c.seed, 1.0))              # 0 → 1 over 0.9 s
            r = 0.2f0 + 0.5f0 * f
            rp[2k + j + 1] = c.pos + Point3f(0, 0, 0.05)
            rs[2k + j + 1] = Vec3f(r, r, 0.3f0)
            rc[2k + j + 1] = RGBAf(0.88, 0.94, 1.0, 0.7f0 * (1 - f))
        end
        k += 1
    end
    Makie.update!(SH[:rings]; arg1 = rp, markersize = rs, color = rc)
end

function NG.step!(s::Shower, game, dt)
    game.stage === nothing && return
    get(SH, :key, nothing) == (SHOWER_VERSION, game.stage.scene) || build!(game)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 90.0)
    if !s.active
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        testing = game.tests !== nothing && NG.running(game.tests)
        w.t >= s.next_t && !busy_game && !testing && !NG.is_night(w) && (start_shower!(s, game) || (s.next_t = w.t + 60.0))
    else
        while !isempty(s.lines) && w.t >= s.lines[1][1]
            _, id, text = popfirst!(s.lines)
            c = NG.creature(w, id)
            (c === nothing || c.goal.kind !== :rain) && continue
            NG.say!(w, c, text; duration = 2.3)
            emote(c.id, s.roles[id] === :shelter ? :sulk : s.roles[id] === :nose ? :heart : :note)
        end
        for (id, role) in s.roles
            c = NG.creature(w, id)
            (c === nothing || c.goal.kind !== :rain) && continue
            c.goal.arrived && (c.action = c.goal.action)      # other plugins (berries, chats) do not take over
        end
        # one taken away (a wave, gave up on a blocked path) has left the shower
        filter!(((id, _),) -> (c = NG.creature(w, id); c !== nothing && c.goal.kind === :rain), s.roles)
        me = NG.creature(w, "Lumi")
        if me !== nothing && me.controlled && me.action in (:jump, :dance) && shelter_free(w, me)
            puddle_party!(s, w, me)
        elseif s.joined > 0 && me !== nothing
            puddle_party!(s, w, me)      # the party goes on while the rain lasts
        end
        (w.t >= s.until || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)) && end_shower!(s, game)
    end
    dim_sun!(s, w)
    wet_ground!(s, game)
    show_rainbow!(s, game)
    NG.path_traced(game) && return      # moving glowing plots leak area lights in the path tracer
    show_rain!(s, game)
end

"Lumi stands in the open (not under a tree's crown)."
shelter_free(w, c) = all(p -> p.kind !== :tree || hypot(p.pos[1] - c.pos[1], p.pos[2] - c.pos[2]) > 1.6f0 * p.scale, w.props)

const CURRENT = Ref{Any}(nothing)
"While it rains, the camera watches the puddle party, or the first splasher."
function watch(w)
    s = CURRENT[]
    (s === nothing || !s.active || w.t - s.started < 1) && return nothing
    ids = [id for (id, r) in s.roles if r in (:party, :splash, :dance) && (c = NG.creature(w, id); c !== nothing && c.goal.kind === :rain)]
    isempty(ids) && return nothing
    return minimum(ids)
end
function group(w)
    id = watch(w)
    id === nothing && return nothing
    c0 = NG.creature(w, id)
    ps = [c.pos for c in (NG.creature(w, i) for i in keys(CURRENT[].roles)) if c !== nothing && c.goal.kind === :rain && hypot(c.pos[1] - c0.pos[1], c.pos[2] - c0.pos[2]) < 8]
    me = NG.creature(w, "Lumi")
    me !== nothing && me.controlled && push!(ps, me.pos)
    return id, ps
end

function NG.start!(s::Shower, game)
    CURRENT[] = s
    NG.CAMERA_MOMENTS["showers"] = watch
    NG.CAMERA_GROUPS["showers"] = group
end

function NG.stop!(s::Shower, game)
    delete!(NG.CAMERA_MOMENTS, "showers")
    delete!(NG.CAMERA_GROUPS, "showers")
    s.active && end_shower!(s, game)
    NG.SUN_DIM[] = 1f0
    for k in (:drops, :cloud, :rings, :bow)
        haskey(SH, k) && (SH[k].visible[] = false)
    end
end

register!(Shower())
