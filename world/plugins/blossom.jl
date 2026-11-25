# Spring comes to the island (session 78, a wish: "blossom in spring"; perfectionist-0076: "thirteen sessions without
# a new area"). Once, in front of everyone: on the open ground west of the pond little cherry trees spring up out of
# the grass one after another, burst into pink blossom and shake a shower of petals over the meadow that drifts off
# on the wind, and the friends come running to dance in it. From then on the grove stands there, a pink carpet of
# petals under it and a few petals always falling.
isdefined(Main, :BLOSSOM) || Core.eval(Main, :(const BLOSSOM = Dict{Symbol,Any}()))
const NG = NeverendingGame
const BL = Main.BLOSSOM

const ASSET = "20261125-032401-562-asset"     # a small cherry blossom tree, pale pink crown (s77)
# (its crown refilled in s79 with walls 9 voxels thick, meshrepair.jl `solidified(raw; close = 9)`: the first fill left holes
# the sea showed through; the close-5 mesh is kept in media/s79/cherry-mesh-close5.jls)
const CENTRE = Point2f(-13.5, 13.5)           # north of Lumi's vegetable patch, west of the pond, in the overview
const BENCH = Point2f(-16, 9)                 # lookout.jl's sunset bench: no tree on it or in its view
# (the west half of the first ring was over the shore: the grove leans east, s78)
const SPOTS = ((-1, -1), (0.5, 0.5), (2, 2), (3.5, -1), (2, 3.5), (5, -2.5), (5, -1), (-1, 2.2))
const NTREE = 5
const HEIGHTS = (3.1f0, 2.6f0, 2.8f0, 2.4f0, 2.9f0)
const SHRUB = "20261125-040120-142-asset"     # a clay shrub with big pink flowers (s78 break, the second try)
const SHRUB_SPOTS = ((-2.4, -0.4), (-0.6, -2.2), (0.6, 1.6), (2.0, 0.6), (-2.0, 1.6), (1.2, 3.0), (3.2, 0.9), (2.8, 2.9))
const SHRUB_H = 0.75f0
const NPETAL = 180
const NCARPET = 140
const T_LOOK = 3.0             # friends notice something coming up
const T_GROW = 4.2             # the trees spring up one after another
const T_BLOOM = 7.0            # the petal shower, everyone dances
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom, :swing, :bottle, :leaves, :pumpkin)
const WOWS = ("Something's coming up!", "Ooh, what is it?", "Look, LOOK!", "It's... pink?")
const SPRING = ("SPRING!", "It's snowing pink!", "Petals! Catch them!", "So pretty...", "Dance with me!", "It smells like sweets!")
const PINKS = (RGBf(1.0, 0.78, 0.84), RGBf(0.98, 0.86, 0.9), RGBf(0.96, 0.66, 0.76), RGBf(1.0, 0.92, 0.94))

push!(NG.BUSY_GOALS, :blossom)

mutable struct Blossom <: System
    state::Symbol              # :old (bare meadow) :look :grow :bloom :new
    t0::Float64
    watchers::Vector{Int32}
    view::Tuple{Point3f,Point3f}
end
Blossom() = Blossom(:old, 0.0, Int32[], (Point3f(0), Point3f(0)))

# per game (`paths.state`: the sandbox has its own)
state_file(game) = joinpath(game.paths.state, "blossom.json")
ready(game) = any(e -> e["id"] == ASSET && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths))
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
hash01(i, k) = mod(sin(Float32(i) * 12.9898f0 + Float32(k) * 78.233f0) * 43758.547f0, 1f0)

"The tree spots: on land and clear of the props (bushes, rocks) round the grove's centre."
function tree_spots(w)
    out = Point3f[]
    for (dx, dy) in SPOTS
        x, y = CENTRE[1] + Float32(dx), CENTRE[2] + Float32(dy)
        NG.on_land(w.island, x, y; margin = 0.4f0) || continue
        minimum(p -> hypot(p.pos[1] - x, p.pos[2] - y), w.props; init = 99f0) > 1.0f0 || continue
        any(q -> hypot(q[1] - x, q[2] - y) < 2.1f0, out) && continue     # crowns apart
        hypot(x - BENCH[1], y - BENCH[2]) > 3.6f0 || continue
        abs(x + 10.5f0) < 2.9f0 && abs(y - 10f0) < 2.4f0 && continue     # garden.jl's vegetable patch and its fence
        push!(out, NG.ground(w.island, (x, y)))
        length(out) == NTREE && break
    end
    return out
end

function plots!(game)
    haskey(BL, :trees) && BL[:trees].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:blossom_trees, :blossom_petals, :blossom_shrubs), sc.plots)
        delete!(sc, p)
    end
    w = game.world
    model = NG.lifted_asset(game.paths, ASSET)
    # the image's soil disc under the trunk read as a dark ring on the pink floor: its faces (all corners in the
    # bottom 4%) go; the trunk sinks 5% into the grass anyway (s79)
    let m = model.mesh, ps = GeometryBasics.coordinates(m), zt = 0.04f0 * maximum(p -> p[3], ps)
        keep = filter(f -> any(k -> ps[GeometryBasics.value(f[k])][3] > zt, 1:3), collect(GeometryBasics.faces(m)))
        model = NG.AssetModel(GeometryBasics.Mesh(ps, keep; normal = m.normal, uv = m.uv), model.color, model.material)
    end
    BL[:k] = 1f0 / maximum(p -> p[3], GeometryBasics.coordinates(model.mesh))
    BL[:spots] = tree_spots(w)
    n = length(BL[:spots])
    BL[:rot] = [NG.rot_z(Float32(2pi) * hash01(i, 1)) for i in 1:n]
    BL[:trees] = NG.asset_instances!(sc, model, BL[:spots]; rotation = BL[:rot], markersize = fill(Vec3f(0), n),
                                     name = :blossom_trees)
    # clay shrubs with big pink flowers between the trees (s79), once the worker has made them
    if any(e -> e["id"] == SHRUB && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths))
        sm = NG.lifted_asset(game.paths, SHRUB)
        BL[:sk] = SHRUB_H / maximum(p -> p[3], GeometryBasics.coordinates(sm.mesh))
        sp = Point3f[]
        for (dx, dy) in SHRUB_SPOTS
            x, y = CENTRE[1] + Float32(dx), CENTRE[2] + Float32(dy)
            NG.on_land(w.island, x, y; margin = 0.3f0) || continue
            minimum(p -> hypot(p.pos[1] - x, p.pos[2] - y), w.props; init = 99f0) > 0.6f0 || continue
            any(q -> hypot(q[1] - x, q[2] - y) < 1.0f0, vcat(BL[:spots], sp)) && continue
            hypot(x - BENCH[1], y - BENCH[2]) > 3.0f0 || continue
            abs(x + 10.5f0) < 2.9f0 && abs(y - 10f0) < 2.4f0 && continue
            push!(sp, NG.ground(w.island, (x, y)))
        end
        BL[:shrub_spots] = sp
        BL[:shrubs] = isempty(sp) ? nothing :
            NG.asset_instances!(sc, sm, sp; rotation = [NG.rot_z(6.283f0 * hash01(i, 21)) for i in eachindex(sp)],
                                markersize = fill(Vec3f(0), length(sp)), name = :blossom_shrubs)
    end
    BL[:petals] = meshscatter!(sc, fill(Point3f(0, 0, -50), NPETAL + NCARPET); marker = Sphere(Point3f(0), 1f0),
                               markersize = fill(Vec3f(0), NPETAL + NCARPET),
                               rotation = fill(Makie.Quaternionf(0, 0, 0, 1), NPETAL + NCARPET),
                               color = [PINKS[mod1(i, length(PINKS))] for i in 1:NPETAL + NCARPET], name = :blossom_petals)
end

"Tree `i`'s growth at `el` s into the grow: it springs up, overshoots and wobbles into place, 0.7 s after the one before."
function growth(i, el)
    u = Float32(el - 0.7 * (i - 1))
    u <= 0 && return 0f0
    return 1f0 - exp(-3.0f0 * u) * cos(8f0 * u)
end

function draw_trees!(g::Vector{Float32})
    sz = [Vec3f(BL[:k] * HEIGHTS[mod1(i, length(HEIGHTS))] * max(g[i], 0f0)) for i in eachindex(g)]
    # the soil disc under the tree's model sinks into the grass
    ps = [p - Point3f(0, 0, 0.05f0 * HEIGHTS[mod1(i, length(HEIGHTS))]) for (i, p) in enumerate(BL[:spots])]
    Makie.update!(BL[:trees]; arg1 = ps, markersize = sz)
    # the shrubs come up with the trees (their growth: the trees' mean)
    sh = get(BL, :shrubs, nothing)
    if sh !== nothing
        gm = isempty(g) ? 0f0 : sum(x -> max(x, 0f0), g) / length(g)
        Makie.update!(sh; markersize = fill(Vec3f(BL[:sk] * gm), length(BL[:shrub_spots])))
    end
end

"Petals: falling ones (`shower` 0..1 how many fall), and the carpet under the trees (`carpet` 0..1 how much lies there)."
function draw_petals!(w, t, shower, carpet)
    spots = BL[:spots]
    isempty(spots) && return
    wd = isdefined(Main, :WIND) && haskey(Main.WIND, :now) ? Base.invokelatest(Main.WIND[:now], w.t)[1] : Vec2f(1, 0)
    N = NPETAL + NCARPET
    ps = fill(Point3f(0, 0, -50), N); ms = fill(Vec3f(0), N); rs = fill(Makie.Quaternionf(0, 0, 0, 1), N)
    for i in 1:NPETAL
        hash01(i, 2) < shower || continue
        s = spots[mod1(i, length(spots))]
        # each petal falls from its tree's crown over ~4 s, again and again, drifting downwind and fluttering
        T = 3.5f0 + 1.5f0 * hash01(i, 3)
        u = mod(Float32(t) / T + hash01(i, 4), 1f0)
        a = 6.283f0 * hash01(i, 5); r = 1.3f0 * sqrt(hash01(i, 6))
        h = HEIGHTS[mod1(i, length(HEIGHTS))] * (0.62f0 + 0.3f0 * hash01(i, 7))
        drift = 4.5f0 * u
        x = s[1] + r * cos(a) + drift * wd[1] + 0.35f0 * sin(5f0 * u + 9f0 * hash01(i, 8))
        y = s[2] + r * sin(a) + drift * wd[2] + 0.35f0 * cos(4f0 * u + 7f0 * hash01(i, 9))
        g = NG.ground(w.island, (x, y))[3]
        ps[i] = Point3f(x, y, max(g + 0.05f0, s[3] + h * (1 - u)))
        ms[i] = Vec3f(0.07f0, 0.055f0, 0.012f0)
        rs[i] = Makie.qrotation(Vec3f(cos(9f0 * u), sin(7f0 * u), 0.5f0), 6f0 * u + 6.283f0 * hash01(i, 10))
    end
    for j in 1:NCARPET
        hash01(j, 11) < carpet || continue
        s = spots[mod1(j, length(spots))]
        a = 6.283f0 * hash01(j, 12); r = 2.4f0 * sqrt(hash01(j, 13))
        x = s[1] + r * cos(a); y = s[2] + r * sin(a)
        ps[NPETAL + j] = NG.ground(w.island, (x, y)) + Point3f(0, 0, 0.02f0)
        ms[NPETAL + j] = Vec3f(0.08f0, 0.06f0, 0.008f0)
        rs[NPETAL + j] = NG.rot_z(6.283f0 * hash01(j, 14))
    end
    Makie.update!(BL[:petals]; arg1 = ps, markersize = ms, rotation = rs)
end

function start_event!(s::Blossom, game)
    w = game.world
    me = lumi_of(w)
    c = Point3f(CENTRE[1], CENTRE[2], NG.ground(w.island, (CENTRE[1], CENTRE[2]))[3])
    s.state = :look; s.t0 = w.t
    empty!(s.watchers)
    cs = [x for x in w.creatures if !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS &&
          hypot(x.pos[1] - c[1], x.pos[2] - c[2]) < 40]
    n = length(cs)
    base = me === nothing ? 0f0 : atan(me.pos[2] - c[2], me.pos[1] - c[1])
    for (i, x) in enumerate(cs)
        a = base + 2f0 * Float32(pi) * (i - 1) / max(n, 1)
        r = 5.8f0 + 0.6f0 * isodd(i)
        tx, ty = c[1] + r * cos(a), c[2] + r * sin(a)
        NG.on_land(w.island, tx, ty; margin = 0.3f0) || ((tx, ty) = (c[1] + 4f0 * cos(a + 1f0), c[2] + 4f0 * sin(a + 1f0)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:blossom, NG.ground(w.island, (tx, ty)), :gasp, 60.0, w.t + 60, false, 0, true)
        push!(s.watchers, x.id)
    end
    # one framing for the whole show: the side with the least in the way
    look = c + Point3f(0, 0, 1.7f0)
    best = nothing
    for k in 0:11
        a = base + 2f0 * Float32(pi) * k / 12
        eye = c + Point3f(12.5f0 * cos(a), 12.5f0 * sin(a), 3.0f0)
        o = NG.obstruction(w, eye, look)
        (best === nothing || o < best[1]) && (best = (o, eye))
    end
    s.view = (best[2], look)
    me === nothing || NG.say!(w, me, "Hm? Something's poking up over there..."; duration = 2.8)
    NG.emit!(w, :blossom_start; n = n)
    return true
end

function NG.step!(s::Blossom, game, dt)
    game.stage === nothing && return
    haskey(BL, :trees) || return
    w = game.world
    n = length(BL[:spots])
    if s.state === :old
        get(BL, :shown, true) && (draw_trees!(zeros(Float32, n)); draw_petals!(w, w.t, 0f0, 0f0); BL[:shown] = false)
        film = get(BL, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if game.dash === nothing && !film
            s.state = :new                         # other films: the grove is simply there
        elseif !testing && !busy_game && (film || 8 < 24 * NG.daytime(w) < 19) && BL[:trees].visible[] &&
               !any(c -> c.goal.kind in (:build, :tinker), w.creatures)
            start_event!(s, game)
        end
        return
    end
    BL[:shown] = true
    el = w.t - s.t0
    if s.state === :new
        # the grove and its pink carpet, drawn once (a plot that changes goes to every browser in full)
        get(BL, :still, false) && return
        draw_trees!(ones(Float32, n)); draw_petals!(w, w.t, 0f0, 1f0)
        BL[:still] = true
        return
    end
    BL[:still] = false
    me = lumi_of(w)
    for id in s.watchers
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :blossom) && continue
        c.goal.until = w.t + 60
    end
    if s.state === :look
        if el > 1.2 && get(BL, :said, 0) == 0
            BL[:said] = 1
            for (i, id) in enumerate(s.watchers[1:min(3, end)])
                c = NG.creature(w, id)
                c === me || NG.say!(w, c, WOWS[mod1(i, length(WOWS))]; duration = 2.0)
            end
        end
        el >= T_LOOK && (s.state = :grow; s.t0 = w.t; BL[:said] = 0; NG.emit!(w, :blossom_grow))
        return
    end
    if s.state === :grow
        draw_trees!([growth(i, el) for i in 1:n])
        draw_petals!(w, w.t, Float32(clamp(el / T_GROW, 0, 1)) * 0.5f0, Float32(clamp((el - 1) / T_GROW, 0, 1)) * 0.4f0)
        if el >= T_GROW
            s.state = :bloom; s.t0 = w.t
            for (i, id) in enumerate(s.watchers)
                c = NG.creature(w, id)
                (c === nothing || c.goal.kind !== :blossom) && continue
                act = c === me ? :proud : isodd(i) ? :dance : :jump
                c.goal = NG.Goal(:blossom, c.pos, act, 60.0, w.t + 60, true, 0, false)
                c.action = act
                i <= 4 && c !== me && NG.say!(w, c, SPRING[mod1(i, length(SPRING))]; duration = 2.4)
            end
            me === nothing || NG.say!(w, me, "Spring! For you. Come and sit under them sometime."; duration = 3.2)
            NG.emit!(w, :blossom_bloom)
            game.dash === nothing || NG.write_json(state_file(game), Dict("grown" => true))
        end
        return
    end
    # :bloom: the full shower, then it settles to a trickle and everyone goes back to their day
    draw_trees!(ones(Float32, n))
    draw_petals!(w, w.t, Float32(1 - 0.85 * ease((el - T_BLOOM + 2) / 2)), Float32(0.4 + 0.6 * ease(el / T_BLOOM)))
    if el >= T_BLOOM
        for id in s.watchers
            c = NG.creature(w, id)
            c === nothing || c.controlled || c.goal.kind !== :blossom || NG.choose_goal!(c, w)
        end
        empty!(s.watchers)
        s.state = :new
    end
end

function blossom_group(w)
    s = BL[:sys]
    s.state in (:look, :grow, :bloom) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[me.pos, s.view[2]], s.view)
end

function NG.start!(s::Blossom, game)
    BL[:sys] = s
    delete!(BL, :trees)
    game.stage === nothing && return
    ready(game) || return
    plots!(game)
    grown = game.dash !== nothing && isfile(state_file(game)) && get(NG.read_json(state_file(game)), "grown", false)
    s.state = grown ? :new : :old
    BL[:shown] = true
    BL[:still] = false        # new plots after a reload: the steady grove must be drawn again (s79)
    moment = w -> s.state in (:look, :grow, :bloom) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["blossom"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["blossom"] = moment
    NG.CAMERA_GROUPS["blossom"] = blossom_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:blossom] = "Spring is coming!")
end

function NG.stop!(s::Blossom, game)
    delete!(NG.CAMERA_MOMENTS, "blossom")
    delete!(NG.CAMERA_GROUPS, "blossom")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "blossom")
    for k in (:trees, :petals, :shrubs)
        haskey(BL, k) && BL[k] !== nothing && BL[k].parent !== nothing && delete!(BL[k].parent, BL[k])
    end
    delete!(BL, :trees); delete!(BL, :petals); delete!(BL, :shrubs)
end

register!(Blossom())
