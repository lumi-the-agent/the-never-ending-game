# Lumi's vegetable patch (wish: "a vegetable patch of my own", perfectionist-0049 #251): a little
# fenced garden just north of the cottage with three dug rows, cabbages, carrots and seedlings that
# grow a bit every real day, a watering can by the gate. When a row is ripe for a day Lumi picks it
# and sows again, so the patch never stops growing. Growth is saved in state/garden.json (only by the
# human's or the sandbox game, never by a quiet copy).
# Plots: soil (one mesh), fence (one meshscatter), plants (one instanced plot per kind), the can.
# Generated meshes are used once the worker has made them (checked every 20 s); until then simple
# shapes stand in.
isdefined(Main, :GARDEN) || Core.eval(Main, :(const GARDEN = Dict{Symbol,Any}()))

const NG = NeverendingGame
const GARDEN_VERSION = 4
const SPOT = (-10.5f0, 10.0f0)        # centre of the patch (open ground north-west of the cottage, beside the pond)
const W_HALF, D_HALF = 1.7f0, 1.25f0   # patch half size along x and y
const ROWS = (-0.75f0, 0.0f0, 0.75f0)  # row offsets in y
const PER_ROW = 6
const GROW_DAYS = 3.0                  # real days from sowing to ripe
const ASSETS = Dict(                   # kind => (asset id, full-grown height in m)
    :cabbage  => ("20261124-014117-487-asset", 0.34f0),
    :seedling => ("20261124-004844-471-asset", 0.22f0),
    :carrot   => ("20261124-004844-475-asset", 0.26f0),
    :fence    => ("20261124-004844-478-asset", 0.5f0),
    :can      => ("20261124-004844-481-asset", 0.32f0))
const ROW_KIND = (:cabbage, :carrot, :seedling)
const SOIL = RGBf(0.36, 0.23, 0.14)
const SOIL_DARK = RGBf(0.25, 0.15, 0.09)
const WOOD = RGBf(0.72, 0.52, 0.3)

garden_file(game) = joinpath(game.paths.state, "garden.json")

"Sowing time of each row (unix seconds); new rows start a day grown so the patch is never bare."
function garden_state(game)
    haskey(Main.GARDEN, :state) && return Main.GARDEN[:state]
    f = garden_file(game)
    st = isfile(f) ? NG.JSON.parsefile(f) : Dict{String,Any}("sown" => [time() - 86400.0 * (1.2 + 0.6i) for i in 0:2])
    Main.GARDEN[:state] = st
    return st
end

function save_garden!(game)
    game.dash === nothing && return      # a quiet copy (clip, still) never writes
    mkpath(dirname(garden_file(game)))
    open(io -> NG.JSON.print(io, Main.GARDEN[:state]), garden_file(game), "w")
end

"Growth 0..1 of a row: 0.15 when sown, 1 after GROW_DAYS."
row_growth(st, i) = clamp(0.15 + 0.85 * (time() - st["sown"][i]) / (GROW_DAYS * 86400), 0.15, 1.0)

"A row ripe for a day is picked and sown again (the patch keeps growing)."
function replant!(game)
    st = garden_state(game)
    changed = false
    for i in eachindex(st["sown"])
        if time() - st["sown"][i] > (GROW_DAYS + 1) * 86400
            st["sown"][i] = time()
            changed = true
            NG.emit!(game.world, :garden_harvest; row = i, kind = ROW_KIND[i])
        end
    end
    changed && save_garden!(game)
    isfile(garden_file(game)) || save_garden!(game)
end

ground(is, x, y) = NG.terrain_height(is, x, y)

"Dug earth: a flat bed over the patch plus a raised mound per row, following the terrain."
function soil_mesh(is)
    pts = Point3f[]; cols = RGBf[]; faces = GLTriangleFace[]
    nx, ny = 34, 26
    base = length(pts)
    for i in 0:nx, j in 0:ny
        u = -W_HALF + 2W_HALF * i / nx; v = -D_HALF + 2D_HALF * j / ny
        x, y = SPOT[1] + u, SPOT[2] + v
        m = 0.0f0
        for r in ROWS
            d = abs(v - r) / 0.24f0
            abs(u) < W_HALF - 0.15f0 && d < 1 && (m = max(m, 0.11f0 * (1 - d^2)))
        end
        edge = min(W_HALF - abs(u), D_HALF - abs(v))
        lift = edge < 0.08f0 ? 0.005f0 : 0.03f0
        push!(pts, Point3f(x, y, ground(is, x, y) + lift + m))
        n = 0.5f0 + 0.5f0 * sin(13x + 7y) * cos(11y - 5x)
        push!(cols, m > 0.02f0 ? RGBf((SOIL.r + 0.04n), SOIL.g + 0.03n, SOIL.b + 0.02n) : SOIL_DARK)
    end
    idx(i, j) = base + i * (ny + 1) + j + 1
    for i in 0:(nx - 1), j in 0:(ny - 1)
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.normal_mesh(pts, faces), cols
end

"Positions along the fence: posts every ~0.55 m round the patch, a gap for the gate on the south side."
function fence_posts(is)
    out = Tuple{Point3f,Symbol}[]    # (foot, side) side = :x (runs along x) or :y
    for (side, n, half, other) in ((:x, 7, W_HALF + 0.2f0, D_HALF + 0.2f0), (:y, 5, D_HALF + 0.2f0, W_HALF + 0.2f0))
        for s in (-1, 1), k in 0:n
            t = -half + 2half * k / n
            side === :x && s == -1 && abs(t) < 0.4f0 && continue    # the gate
            x, y = side === :x ? (SPOT[1] + t, SPOT[2] + s * other) : (SPOT[1] + s * other, SPOT[2] + t)
            push!(out, (Point3f(x, y, ground(is, x, y)), side))
        end
    end
    return out
end

"The generated model of `kind` and its scale to the wanted height, or nothing while the worker makes it."
function garden_model(game, kind)
    id, h = ASSETS[kind]
    cache = get!(Main.GARDEN, :models, Dict{Symbol,Any}())
    haskey(cache, kind) && return cache[kind]
    any(e -> e["id"] == id && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths)) || return nothing
    model = NG.lifted_asset(game.paths, id)
    zs = [p[3] for p in GeometryBasics.coordinates(model.mesh)]
    cache[kind] = (model, h / maximum(zs))
    return cache[kind]
end

function clear_garden!()
    for k in (:soil, :fence, :rails, :plants, :can)
        haskey(Main.GARDEN, k) || continue
        for p in Main.GARDEN[k]
            delete!(p.parent, p)
        end
        delete!(Main.GARDEN, k)
    end
end

"Plant spots of row i (world positions on the mound) with a little jitter."
function plant_spots(is, i)
    [begin
        u = -W_HALF + 0.35f0 + (2W_HALF - 0.7f0) * (k - 1) / (PER_ROW - 1) + 0.05f0 * sin(3k + i)
        x, y = SPOT[1] + u, SPOT[2] + ROWS[i] + 0.04f0 * cos(5k + 2i)
        Point3f(x, y, ground(is, x, y) + 0.1f0)
    end for k in 1:PER_ROW]
end

function build_garden!(game)
    clear_garden!()
    sc = game.stage.scene
    is = game.world.island
    st = garden_state(game)
    m, cols = soil_mesh(is)
    Main.GARDEN[:soil] = [mesh!(sc, m; color = cols, name = :garden_soil)]
    # fence: generated sections between posts when there, else posts and two rails
    posts = fence_posts(is)
    fm = garden_model(game, :fence)
    if fm === nothing
        ps = [p for (p, _) in posts]
        Main.GARDEN[:fence] = [meshscatter!(sc, ps; marker = NG.shape(:cylinder), markersize = Vec3f(0.035, 0.035, 0.5),
            color = WOOD, name = :garden_posts)]
        rp = Point3f[]; rs = Vec3f[]; rr = Makie.Quaternionf[]
        for (side, half, other) in ((:x, W_HALF + 0.2f0, D_HALF + 0.2f0), (:y, D_HALF + 0.2f0, W_HALF + 0.2f0)), s in (-1, 1), z in (0.2f0, 0.4f0)
            segs = side === :x && s == -1 ? ((-half, -0.4f0), (0.4f0, half)) : ((-half, half),)
            for (a, b) in segs
                x, y = side === :x ? (SPOT[1] + a, SPOT[2] + s * other) : (SPOT[1] + s * other, SPOT[2] + a)
                push!(rp, Point3f(x, y, ground(is, x, y) + z))
                push!(rs, Vec3f(0.022, 0.022, b - a))
                push!(rr, side === :x ? Makie.qrotation(Vec3f(0, 1, 0), Float32(pi / 2)) : Makie.qrotation(Vec3f(1, 0, 0), -Float32(pi / 2)))
            end
        end
        Main.GARDEN[:rails] = [meshscatter!(sc, rp; marker = NG.shape(:cylinder), markersize = rs, rotation = rr,
            color = WOOD, name = :garden_rails)]
    else
        model, s = fm
        mids = Point3f[]; rots = Makie.Quaternionf[]
        for i in 1:(length(posts) - 1)
            (a, sa), (b, sb) = posts[i], posts[i + 1]
            sa === sb && hypot(a[1] - b[1], a[2] - b[2]) < 0.7f0 || continue
            push!(mids, (a + b) / 2); push!(rots, NG.rot_z(sa === :x ? 0f0 : Float32(pi / 2)))
        end
        Main.GARDEN[:fence] = [NG.asset_instances!(sc, model, mids; rotation = rots, markersize = Vec3f(s), name = :garden_fence)]
    end
    # plants: one plot per kind
    plots = Any[]
    for (i, kind) in enumerate(ROW_KIND)
        g = Float32(row_growth(st, i))
        spots = plant_spots(is, i)
        sizes = [Vec3f(g * (0.9f0 + 0.2f0 * sin(7k + i))) for k in eachindex(spots)]
        rots = [NG.rot_z(Float32(1.7k + i)) for k in eachindex(spots)]
        pm = garden_model(game, kind)
        if pm === nothing
            h = ASSETS[kind][2]
            col = kind === :carrot ? RGBf(0.42, 0.68, 0.25) : kind === :cabbage ? RGBf(0.55, 0.78, 0.4) : RGBf(0.5, 0.82, 0.35)
            push!(plots, meshscatter!(sc, spots; marker = NG.shape(:sphere), markersize = [s .* Vec3f(h * 0.6f0, h * 0.6f0, h * 0.5f0) for s in sizes],
                color = col, name = Symbol(:garden_, kind)))
        else
            model, s = pm
            push!(plots, NG.asset_instances!(sc, model, spots; rotation = rots, markersize = [s * v for v in sizes], name = Symbol(:garden_, kind)))
        end
    end
    Main.GARDEN[:plants] = plots
    # the watering can by the gate
    cm = garden_model(game, :can)
    cx, cy = SPOT[1] + 0.75f0, SPOT[2] - D_HALF - 0.5f0
    cp = Point3f(cx, cy, ground(is, cx, cy))
    Main.GARDEN[:can] = [cm === nothing ?
        meshscatter!(sc, [cp + Point3f(0, 0, 0.1)]; marker = NG.shape(:cylinder), markersize = Vec3f(0.09, 0.09, 0.16), color = RGBf(0.35, 0.6, 0.45), name = :garden_can) :
        NG.asset_instances!(sc, cm[1], [cp]; rotation = [NG.rot_z(2.3f0)], markersize = Vec3f(cm[2]), name = :garden_can)]
    Main.GARDEN[:key] = garden_key(game)
end

"What the plots show: the version, which models exist, each row's growth in 2% steps."
garden_key(game) = (GARDEN_VERSION, sort([k for k in keys(get(Main.GARDEN, :models, Dict{Symbol,Any}()))]),
                    [round(Int, 50 * row_growth(garden_state(game), i)) for i in 1:3])

struct Garden <: System end

function NG.start!(::Garden, game)
    game.stage === nothing && return
    delete!(Main.GARDEN, :state)
    NG.CAMERA_MOMENTS["garden"] = garden_moment
    replant!(game)
    build_garden!(game)
    Main.GARDEN[:check] = 0.0
    return
end

# ── Lumi tends its patch: every few minutes it walks to the gate, waters, and the rows grow a bit ──
const TEND_EVERY = 300.0     # s of game time between two visits
const TEND_TIME = 16.0       # s watering at the gate (10 s was over before the camera's 6 s hold let it come, s51)
const WATER_BOOST = 0.06     # days of growth one watering adds to each row
const TEND_WORDS = ("Grow, little ones!", "A drink for my cabbages.", "Look, they got bigger!", "Splish, splash, sprouts.")

garden_lumi(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
gate_spot(w) = (x = SPOT[1]; y = SPOT[2] - D_HALF - 0.75f0; Point3f(x, y, NG.terrain_height(w.island, x, y)))

"""
Lumi walks in a straight line and wedges between trunks on the way from the beach (s52: stuck at
(-3.5, -13) after 6 s, then unstick! dropped the walk). No 0.3 m of progress in 3 s: a clear spot
2.5 m to the side or back first (the builder's `unstuck!` does the same), then on to the gate.
"""
function tend_unstuck!(w, me)
    G = Main.GARDEN
    haskey(G, :progress) && haskey(G, :gate) || return
    d, t = G[:progress]
    dn = hypot(G[:gate][1] - me.pos[1], G[:gate][2] - me.pos[2])
    dn < d - 0.3f0 && (G[:progress] = (dn, w.t); return)
    w.t - t < 3 && return
    G[:progress] = (dn, w.t)
    a = atan(G[:gate][2] - me.pos[2], G[:gate][1] - me.pos[1])
    clear(x, y) = NG.on_land(w.island, x, y; margin = 0.15f0) &&
        !any(p -> p.kind in (:tree, :rock, :bush) && hypot(p.pos[1] - x, p.pos[2] - y) < get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale + 0.5f0, w.props)
    for da in (1.57f0, -1.57f0, 2.36f0, -2.36f0, 3.14f0), r in (2.5f0, 1.6f0)
        x, y = me.pos[1] + r * cos(a + da), me.pos[2] + r * sin(a + da)
        clear(x, y) && clear(me.pos[1] + 0.5f0r * cos(a + da), me.pos[2] + 0.5f0r * sin(a + da)) || continue
        me.goal = NG.Goal(:tend, NG.ground(w.island, (x, y)), :eat, TEND_TIME, w.t + 15.0, false, 0, false)
        G[:detour] = true
        return
    end
end

function tend!(game)
    w = game.world
    me = garden_lumi(w)
    me === nothing && return
    if me.goal.kind === :tend
        G = Main.GARDEN
        if get(G, :detour, false)
            me.goal.arrived || return
            # round the trees: on to the gate again
            G[:detour] = false; G[:progress] = (hypot(G[:gate][1] - me.pos[1], G[:gate][2] - me.pos[2]), w.t)
            me.goal = NG.Goal(:tend, G[:gate], :eat, TEND_TIME, w.t + 20.0 + 3.0 * G[:progress][1], false, 0, false)
            return
        end
        me.goal.arrived || (tend_unstuck!(w, me); return)
        if me.goal.arrived && !get(Main.GARDEN, :watered, true)
            Main.GARDEN[:watered] = true
            st = garden_state(game)
            st["sown"] .-= WATER_BOOST * 86400
            save_garden!(game)
            NG.say!(w, me, TEND_WORDS[mod1(round(Int, w.t / 7), length(TEND_WORDS))]; duration = 3)
            NG.emit!(w, :garden_water; growth = [round(row_growth(st, i), digits = 2) for i in 1:3])
            Main.GARDEN[:check] = 20.0      # show the growth now
        end
        return
    end
    w.t < get(Main.GARDEN, :next_tend, 0.0) && return
    Main.GARDEN[:next_tend] = w.t + TEND_EVERY
    # only a free, awake Lumi by day, with no game on and nobody steering it
    game.minigame === nothing && !me.controlled && me.action !== :sleep && me.goal.kind ∉ NG.BUSY_GOALS &&
        me.goal.kind !== :seek_friend &&     # on the way to a friend it misses (feelings.jl): the patch waits (s51 suite)
        NG.night_factor(w) < 0.3f0 || return
    NG.leave_interactions!(w, me)
    # the walk may take a while from the far beach: a fixed 45 s ran out on the way and Lumi went
    # sunbathing instead (s52 sandbox, 'never reached the gate')
    g = gate_spot(w)
    Main.GARDEN[:gate] = g; Main.GARDEN[:detour] = false
    Main.GARDEN[:progress] = (hypot(g[1] - me.pos[1], g[2] - me.pos[2]), w.t)
    me.goal = NG.Goal(:tend, g, :eat, TEND_TIME, w.t + 20.0 + 3.0 * hypot(g[1] - me.pos[1], g[2] - me.pos[2]), false, 0, false)
    Main.GARDEN[:watered] = false
end

function NG.step!(::Garden, game, dt)
    game.stage === nothing && return
    :tend in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :tend)
    tend!(game)
    Main.GARDEN[:check] += dt
    Main.GARDEN[:check] < 20 && return
    Main.GARDEN[:check] = 0.0
    replant!(game)
    for kind in keys(ASSETS)
        garden_model(game, kind)
    end
    garden_key(game) == Main.GARDEN[:key] || build_garden!(game)
    return
end

NG.stop!(::Garden, game) = (delete!(NG.CAMERA_MOMENTS, "garden"); clear_garden!())

"The follow camera watches Lumi while it waters the patch (a person watching sees the garden being tended)."
function garden_moment(w)
    me = garden_lumi(w)
    (me === nothing || me.controlled || me.goal.kind !== :tend) && return nothing
    # asked from the last steps to the gate on, so the camera is there when the watering starts
    me.goal.arrived || hypot(me.pos[1] - me.goal.target[1], me.pos[2] - me.goal.target[2]) < 6 ? me.id : nothing
end

register!(Garden())
