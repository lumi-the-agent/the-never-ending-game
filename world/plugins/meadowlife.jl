# Meadow life: the open meadows were one field of identical grass tufts (perfectionist s46, s49, s52:
# "nothing there was touched"). Little clusters now grow out in the grass: mossy stones with yellow
# daisies around them, red toadstool rings, pink flower clumps, and (once the worker has made them)
# mossy stumps and fallen logs. Each kind is one instanced plot (AGENTS.md: one plot per copy froze the
# page). Clusters keep clear of trees, bushes, rocks, houses, the pond, the path and the beach. Todo #238.
isdefined(Main, :MEADOWLIFE) || Core.eval(Main, :(const MEADOWLIFE = Dict{Symbol,Any}()))
using Serialization

const NG = NeverendingGame
const ML = Main.MEADOWLIFE
const VERSION_ML = 8

# kind => (asset id, longest side min..max (m), texture gain, members per cluster min..max, spread (m))
const KINDS = (
    stones = ("20261122-225659-827-asset", (0.55f0, 0.9f0), (1.2f0, 1.2f0, 1.15f0), (1, 2), 0.7f0),
    daisies = ("20261123-041652-323-asset", (0.3f0, 0.45f0), (1.15f0, 1.12f0, 1.0f0), (3, 6), 1.1f0),
    toadstools = ("20261122-214637-773-asset", (0.45f0, 0.7f0), (1.15f0, 1.1f0, 1.1f0), (1, 3), 0.8f0),
    pinks = ("20261123-024153-991-asset", (0.38f0, 0.55f0), (1.15f0, 1.1f0, 1.1f0), (2, 4), 0.9f0),
    stump = ("20261124-023909-261-asset", (0.6f0, 0.8f0), (1.1f0, 1.05f0, 1.0f0), (1, 1), 0.0f0),
    log = ("20261124-023909-355-asset", (1.3f0, 1.7f0), (1.1f0, 1.05f0, 1.0f0), (1, 1), 0.0f0),
)

# what grows together around a cluster's centre piece
# (no :pinks: that clump's texture drew near-black in the raster, s53 live screenshot media/s53/live-check.png)
const RECIPES = (
    (:stones, :daisies), (:toadstools, :daisies), (:stones, :toadstools), (:daisies, :toadstools),
    (:stump, :toadstools), (:log, :daisies), (:stump, :daisies), (:log, :stones),
)

const CLUSTERS = 34          # over the whole island
const FRONT = 6              # of them in the progress eye-level view's foreground (the shot a reviewer compares)

asset_file(game, id) = joinpath(game.paths.world, "assets", id, "mesh.jls")
# a mesh is ready once the worker has put it in the catalog: the file alone may still be half written
# (s53: the sandbox read the log's mesh.jls mid-write, EOFError, and the system was switched off)
function have(game, kind)
    id = KINDS[kind][1]
    isfile(asset_file(game, id)) || return false
    cat = joinpath(game.paths.world, "assets", "catalog.json")
    return isfile(cat) && occursin(id, read(cat, String))
end

"Open meadow at (x, y): on land, off the beach, the pond and the path, clear of solids and placed things."
function open_spot(game, x, y; room = 1.2f0)
    w = game.world
    NG.on_land(w.island, x, y; margin = 0.4f0) || return false
    m = get(game.plugins, "meadow", nothing)
    if m !== nothing && m.mod !== nothing && isdefined(m.mod, :beach_weight)
        first(Base.invokelatest(m.mod.beach_weight, w.island, x, y)) < 0.1f0 || return false
    end
    for p in w.props
        p.kind in (:tree, :bush, :rock) || continue
        hypot(x - p.pos[1], y - p.pos[2]) < get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale + room && return false
    end
    for a in w.actors
        hasproperty(a, :pos) || continue
        hypot(x - a.pos[1], y - a.pos[2]) < 2.5f0 && return false
    end
    a = get(game.plugins, "areas", nothing)
    if a !== nothing && a.mod !== nothing && isdefined(a.mod, :POND)
        hypot(x - a.mod.POND[1], y - a.mod.POND[2]) < a.mod.POND_R + 1.2f0 && return false
        path = get!(() -> Base.invokelatest(a.mod.catmull, a.mod.PATH_POINTS, 0.5), ML, :path)
        any(q -> hypot(x - q[1], y - q[2]) < 1.3f0, path) && return false
    end
    return true
end

"Cluster centres: a few in the eye-level view's foreground, the rest over the island (deterministic)."
function centres(game)
    is = game.world.island
    r = is.radius
    rng = Random.Xoshiro(is.seed + 4711)
    out = Point2f[]
    eye = Point2f(-0.7r, -0.2r); dir = normalize(Point2f(0.9r, 0.3r))
    side = Point2f(-dir[2], dir[1])
    k = 0
    while length(out) < FRONT && k < 5000
        k += 1
        q = eye + dir * (4.0f0 + 8 * rand(rng, Float32)) + side * (5 * (2rand(rng, Float32) - 1))
        open_spot(game, q...) && all(o -> norm(o - q) > 2.6f0, out) && push!(out, q)
    end
    k = 0
    while length(out) < CLUSTERS && k < 20_000
        k += 1
        a = 2f0pi * rand(rng, Float32); d = r * sqrt(rand(rng, Float32)) * 0.9f0
        q = Point2f(d * cos(a), d * sin(a))
        open_spot(game, q...) && all(o -> norm(o - q) > 4.0f0, out) && push!(out, q)
    end
    return out
end

"Every piece: kind => positions, sizes, turns."
function layout(game)
    w = game.world
    rng = Random.Xoshiro(w.island.seed + 99)
    pieces = Dict(k => Tuple{Point2f,Float32,Float32}[] for k in keys(KINDS))
    for (i, c) in enumerate(centres(game))
        main, extra = RECIPES[mod1(i, length(RECIPES))]
        have(game, main) || (main = main in (:stump, :log) ? :stones : main)
        for (j, kind) in enumerate((main, extra))
            _, len, _, (lo, hi), spread = KINDS[kind]
            n = rand(rng, lo:hi)
            for _ in 1:n
                q = j == 1 && n == 1 ? c : c + Point2f(spread * (2rand(rng, Float32) - 1), spread * (2rand(rng, Float32) - 1)) * (j == 1 ? 0.6f0 : 1.4f0)
                open_spot(game, q...; room = 0.6f0) || continue
                push!(pieces[kind], (q, len[1] + (len[2] - len[1]) * rand(rng, Float32), 2f0pi * rand(rng, Float32)))
            end
        end
    end
    return pieces
end

"The asset's material, never metallic, its texture brightened per channel (as the beach does)."
function bright(mat, gain)
    mat = copy(mat)
    mat["metallic"] = 0.0f0
    dm = copy(mat["diffuse map"])
    dm["image"] = map(c -> typeof(c)(min(1f0, Float32(Colors.red(c)) * gain[1]), min(1f0, Float32(Colors.green(c)) * gain[2]),
                                     min(1f0, Float32(Colors.blue(c)) * gain[3])), dm["image"])
    mat["diffuse map"] = dm
    return mat
end

function build!(game)
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), values(get(ML, :plots, Dict())))
    plots = Dict{Symbol,Any}()
    is = game.world.island
    pieces = layout(game)
    beach = get(game.plugins, "beach", nothing)
    for (kind, ps) in pieces
        isempty(ps) && continue
        id, _, gain = KINDS[kind]
        mm = Serialization.deserialize(asset_file(game, id))
        beach !== nothing && beach.mod !== nothing && isdefined(beach.mod, :trim_plate) && (mm = Base.invokelatest(beach.mod.trim_plate, mm; frac = 0.04f0))
        model = NG.AssetModel(mm; material = bright(only(values(mm[:materials])), gain))
        vs = GeometryBasics.coordinates(model.mesh)
        ext = maximum(maximum(p[i] for p in vs) - minimum(p[i] for p in vs) for i in 1:3)
        pos = [Point3f(q[1], q[2], NG.terrain_height(is, q[1], q[2]) - (kind === :log ? 0.1f0 : 0.03f0)) for (q, _, _) in ps]
        plots[kind] = NG.asset_instances!(sc, model, pos; rotation = [NG.rot_z(a) for (_, _, a) in ps],
                                          markersize = [Vec3f(s / ext) for (_, s, _) in ps], name = Symbol("meadowlife_", kind))
    end
    ML[:plots] = plots
    ML[:pieces] = pieces
    ML[:key] = (VERSION_ML, objectid(sc), count(k -> have(game, k), (:stump, :log)))
end

struct MeadowLife <: System end

NG.start!(::MeadowLife, game) = (delete!(ML, :key); delete!(ML, :path); ML[:check] = -Inf)

function NG.step!(::MeadowLife, game, dt)
    game.stage === nothing && return
    w = game.world
    # the stumps and logs come from the worker later: look for them every 20 s and rebuild once they are in
    key = get(ML, :key, nothing)
    if key !== nothing && key[1:2] == (VERSION_ML, objectid(game.stage.scene))
        w.t < ML[:check] + 20 && return
        ML[:check] = w.t
        count(k -> have(game, k), (:stump, :log)) == key[3] && return
    end
    all(k -> have(game, k), (:stones, :daisies, :toadstools)) || return
    build!(game)
    return
end

function NG.stop!(::MeadowLife, game)
    game.stage === nothing && return
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), values(get(ML, :plots, Dict())))
    empty!(get(ML, :plots, Dict()))
    delete!(ML, :key)
end

register!(MeadowLife())
