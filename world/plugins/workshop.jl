# Lumi's workshop corner (wish: "a workbench, my tools on the wall, a crate pile, so everyone can see
# where I make new things"): beside the cottage, a generated workbench with a vice and wood shavings,
# a little pile of crates and (once the worker has carved it) a tool rack. Static: one instanced plot
# per kind, rebuilt only when a new mesh arrives from the worker (checked every 20 s). Todo #290.
isdefined(Main, :WORKSHOP) || Core.eval(Main, :(const WORKSHOP = Dict{Symbol,Any}()))
# footprints separation.jl pushes creatures out of: plugin => [(centre, radius)]
isdefined(Main, :EXTRA_SOLIDS) || Core.eval(Main, :(const EXTRA_SOLIDS = Dict{String,Vector{Tuple{NeverendingGame.Makie.Point2f,Float32}}}()))
using Serialization

const NG = NeverendingGame
const WS = Main.WORKSHOP
const VERSION_WS = 3
const COTTAGE = "cottage"

# kind => (asset id, longest side (m))
const PIECES = (
    bench = ("20261124-034756-569-asset", 1.25f0),
    crate = ("20261123-193127-127-asset", 0.5f0),
    rack = ("20261124-034756-627-asset", 1.1f0),
)

have(game, kind) = (id = PIECES[kind][1]; isfile(joinpath(game.paths.world, "assets", id, "mesh.jls")) &&
    occursin(id, read(joinpath(game.paths.world, "assets", "catalog.json"), String)))

function cottage(game)
    cat = NG.load_catalog(game.paths)
    ids = Set(e["id"] for e in cat if occursin(COTTAGE, lowercase(get(e, "prompt", ""))))
    for a in game.world.actors
        a isa NG.AssetActor && a.asset in ids && return a
    end
    return nothing
end

"Open ground beside the cottage (meadowlife's `open_spot`, the cottage itself not counted), not on a meadow cluster."
function corner(game)
    c = cottage(game)
    c === nothing && return nothing
    ml = game.plugins["meadowlife"].mod
    pieces = vcat([[q for (q, _, _) in ps] for ps in values(get(Main.MEADOWLIFE, :pieces, Dict()))]...)
    for r in (3.6f0, 4.2f0, 4.8f0, 5.4f0), da in (0.0f0, 0.35f0, -0.35f0, 0.7f0, -0.7f0, 1.0f0, -1.0f0, 1.5f0, -1.5f0, 2.0f0, -2.0f0, 2.5f0, -2.5f0, Float32(pi))
        a = c.yaw + da                         # the cottage's side (its local +x), then round towards front and back
        x, y = c.pos[1] + r * cos(a), c.pos[2] + r * sin(a)
        ok = NG.on_land(game.world.island, x, y; margin = 0.4f0)
        ok && (ok = all(p -> !(p.kind in (:tree, :bush, :rock)) || hypot(x - p.pos[1], y - p.pos[2]) > get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale + 1.0f0, game.world.props))
        ok && (ok = all(a2 -> a2 === c || !hasproperty(a2, :pos) || hypot(x - a2.pos[1], y - a2.pos[2]) > 2.2f0, game.world.actors))
        ok && (ok = all(q -> hypot(x - q[1], y - q[2]) > 1.6f0, pieces))
        if ok
            am = game.plugins["areas"].mod
            ok = hypot(x - am.POND[1], y - am.POND[2]) > am.POND_R + 1.5f0 &&
                 all(q -> hypot(x - q[1], y - q[2]) > 1.4f0, Base.invokelatest(am.catmull, am.PATH_POINTS, 0.5))
        end
        # off the vegetable patch and its gate: the bench stood 0.8 m in front of the gate and Lumi
        # never got in to water (s55 tests, stuck at (-9.7, 6.6))
        ok && (ok = !garden_blocked(game, x, y))
        ok && return (Point2f(x, y), a)
    end
    return nothing
end

"The patch (fence plus 1.6 m) or the 3 m round its gate, where Lumi walks in to water."
function garden_blocked(game, x, y)
    gp = get(game.plugins, "garden", nothing)
    gp === nothing && return false
    gm = gp.mod
    (cx, cy) = gm.SPOT
    abs(x - cx) < gm.W_HALF + 1.6f0 && abs(y - cy) < gm.D_HALF + 1.6f0 && return true
    gx, gy = cx, cy - gm.D_HALF - 0.75f0
    return hypot(x - gx, y - gy) < 3.0f0
end

function model_of(game, kind)
    mm = Serialization.deserialize(joinpath(game.paths.world, "assets", PIECES[kind][1], "mesh.jls"))
    beach = get(game.plugins, "beach", nothing)
    beach !== nothing && isdefined(beach.mod, :trim_plate) && (mm = Base.invokelatest(beach.mod.trim_plate, mm; frac = 0.04f0))
    model = NG.AssetModel(mm)
    vs = GeometryBasics.coordinates(model.mesh)
    ext = maximum(maximum(p[i] for p in vs) - minimum(p[i] for p in vs) for i in 1:3)
    return model, PIECES[kind][2] / ext
end

function build!(game)
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), values(get(WS, :plots, Dict())))
    plots = Dict{Symbol,Any}()
    spot = corner(game)
    WS[:spot] = spot
    spot === nothing && return
    (q, a) = spot
    is = game.world.island
    out = Vec2f(cos(a), sin(a)); side = Vec2f(-out[2], out[1])
    at(d_out, d_side) = (p = q + d_out * out + d_side * side; Point3f(p[1], p[2], NG.terrain_height(is, p[1], p[2]) - 0.03f0))
    yaw = a - Float32(pi / 2)                 # the model's front (-y) looks away from the cottage
    layout = Dict(
        :bench => ([at(0, 0)], [yaw]),
        :crate => ([at(-0.3f0, 1.15f0), at(0.25f0, 1.3f0), at(-0.05f0, 1.2f0) + Point3f(0, 0, 0.42f0)], [yaw + 0.3f0, yaw - 0.2f0, yaw + 0.05f0]),
        :rack => ([at(-0.6f0, -1.25f0)], [yaw + 0.25f0]),
    )
    for kind in keys(PIECES)
        have(game, kind) || continue
        model, s = model_of(game, kind)
        ps, ys = layout[kind]
        plots[kind] = NG.asset_instances!(sc, model, ps; rotation = [NG.rot_z(y) for y in ys],
                                          markersize = [Vec3f(s) for _ in ps], name = Symbol("workshop_", kind))
    end
    WS[:plots] = plots
    # the bench (two discs along its length) and the crate pile are solid: friends walk round them
    pts = [at(0, -0.35f0), at(0, 0.35f0), at(0, 1.2f0), at(-0.6f0, -1.25f0)]   # bench, bench, crates, tool rack
    Main.EXTRA_SOLIDS["workshop"] = [(Point2f(p[1], p[2]), r) for (p, r) in zip(pts, (0.45f0, 0.45f0, 0.45f0, 0.35f0))]
    WS[:key] = (VERSION_WS, objectid(sc), count(k -> have(game, k), keys(PIECES)))
end

struct Workshop <: System end

"Lumi tinkering in front of the bench faces it (builder.jl sends it there), hammering away."
function face_bench!(w)
    spot = get(WS, :spot, nothing)
    spot === nothing && return
    (q, a) = spot
    for c in w.creatures
        (c.name == "Lumi" && !c.controlled && c.goal.kind === :tinker && c.goal.arrived) || continue
        hypot(c.pos[1] - q[1], c.pos[2] - q[2]) < 1.6f0 || continue
        c.yaw = atan(q[2] - c.pos[2], q[1] - c.pos[1]) - NG.species_of(c).heading
    end
end

NG.start!(::Workshop, game) = (delete!(WS, :key); WS[:check] = -Inf)

function NG.step!(::Workshop, game, dt)
    game.stage === nothing && return
    w = game.world
    face_bench!(w)
    key = get(WS, :key, nothing)
    if key !== nothing && key[1:2] == (VERSION_WS, objectid(game.stage.scene))
        w.t < WS[:check] + 20 && return
        WS[:check] = w.t
        count(k -> have(game, k), keys(PIECES)) == key[3] && return
    end
    haskey(Main.MEADOWLIFE, :pieces) || return        # wait for the meadow clusters (the corner keeps off them)
    build!(game)
    return
end

function NG.stop!(::Workshop, game)
    game.stage === nothing && return
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), values(get(WS, :plots, Dict())))
    empty!(get(WS, :plots, Dict()))
    delete!(Main.EXTRA_SOLIDS, "workshop")
    delete!(WS, :key)
end

register!(Workshop())
