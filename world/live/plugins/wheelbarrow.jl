# Lumi's wheelbarrow (s60, wish "A wheelbarrow for carrying big new things"): a generated wooden
# barrow with a red wheel, parked beside the workshop corner (workshop.jl `WORKSHOP[:spot]`). It appears
# once the worker has made the mesh; until then nothing is drawn.
using GeometryBasics
const NG = NeverendingGame

const BARROW_ID = "20261124-122124-621-asset"
const BARROW_H = 0.75f0                       # metres, tub rim height
isdefined(Main, :BARROW) || Core.eval(Main, :(const BARROW = Dict{Symbol,Any}()))
const B = Main.BARROW

struct Wheelbarrow <: System end

"The model and its scale, or nothing while the worker still makes it (checked every 20 s)."
function barrow_model(game)
    haskey(B, :model) && return B[:model]
    t = time()
    t < get(B, :checked, 0.0) + 20 && return nothing
    B[:checked] = t
    any(e -> e["id"] == BARROW_ID && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths)) || return nothing
    model = NG.lifted_asset(game.paths, BARROW_ID)
    zs = [p[3] for p in GeometryBasics.coordinates(model.mesh)]
    B[:model] = (model, BARROW_H / maximum(zs))
    return B[:model]
end

function NG.start!(::Wheelbarrow, game)
    delete!(B, :checked); delete!(B, :key)
    return
end

function NG.step!(::Wheelbarrow, game, dt)
    game.stage === nothing && return
    sc = game.stage.scene
    haskey(B, :key) && B[:key] == objectid(sc) && return
    ws = isdefined(Main, :WORKSHOP) ? Base.invokelatest(getfield, Main, :WORKSHOP) : nothing
    (ws === nothing || get(ws, :spot, nothing) === nothing) && return
    m = barrow_model(game)
    m === nothing && return
    model, s = m
    (q, a) = ws[:spot]
    out = Vec2f(cos(a), sin(a)); side = Vec2f(-out[2], out[1])
    p = q + 0.4f0 * out - 2.3f0 * side                  # on the far side of the tool rack, a little forward
    is = game.world.island
    pos = Point3f(p[1], p[2], NG.terrain_height(is, p[1], p[2]) - 0.02f0)
    haskey(B, :plot) && B[:plot].parent === sc && delete!(sc, B[:plot])
    B[:plot] = NG.asset_instances!(sc, model, [pos]; rotation = [NG.rot_z(a + 0.6f0)],
                                   markersize = [Vec3f(s)], name = :wheelbarrow)
    isdefined(Main, :EXTRA_SOLIDS) && (Main.EXTRA_SOLIDS["wheelbarrow"] = [(Point2f(pos[1], pos[2]), 0.5f0)])
    B[:key] = objectid(sc)
    return
end

function NG.stop!(::Wheelbarrow, game)
    haskey(B, :plot) && B[:plot].parent !== nothing && delete!(B[:plot].parent, B[:plot])
    delete!(B, :plot); delete!(B, :key)
    isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "wheelbarrow")
    return
end

register!(Wheelbarrow())
