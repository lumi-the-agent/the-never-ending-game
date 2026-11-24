# Lumi's shovel (session 61, a wish from WISHES.md: "a shovel for the garden and for planting new
# trees"): a generated shovel stuck in the ground at the corner of the vegetable patch, blade down,
# leaning a little, the way a gardener leaves it between jobs. Nothing appears until the worker has
# made the mesh (checked every 20 s), so it never pops in as a stand-in.
isdefined(Main, :SHOVEL) || Core.eval(Main, :(const SHOVEL = Dict{Symbol,Any}()))
const NG = NeverendingGame
const ASSET = "20261124-140100-365-asset"
const HEIGHT = 1.05f0                       # m, about Lumi's shoulder
const SPOT = (-10.5f0 + 2.15f0, 10.0f0 - 1.6f0)   # outside the garden fence's south-east corner (garden.jl SPOT, W_HALF, D_HALF)
const YAW = 2.4f0

struct Shovel <: System end

function clear_shovel!()
    p = get(Main.SHOVEL, :plot, nothing)
    p === nothing || delete!(p.parent, p)
    delete!(Main.SHOVEL, :plot)
end

function ready(game)
    any(e -> e["id"] == ASSET && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths))
end

function place!(game)
    model = NG.lifted_asset(game.paths, ASSET)
    zs = [p[3] for p in GeometryBasics.coordinates(model.mesh)]
    s = HEIGHT / maximum(zs)
    is = game.world.island
    # blade a hand deep in the soil, leaning 8° away from the patch
    pos = Point3f(SPOT[1], SPOT[2], NG.terrain_height(is, SPOT...) - 0.12f0)
    rot = NG.rot_z(YAW) * Makie.qrotation(Vec3f(1, 0, 0), 0.14f0)
    Main.SHOVEL[:plot] = NG.asset_instances!(game.stage.scene, model, [pos]; rotation = [rot], markersize = Vec3f(s), name = :lumi_shovel)
end

function NG.start!(::Shovel, game)
    clear_shovel!()
    Main.SHOVEL[:next] = 0.0
    nothing
end

function NG.step!(::Shovel, game, dt)
    game.stage === nothing && return
    haskey(Main.SHOVEL, :plot) && return
    time() < Main.SHOVEL[:next] && return
    Main.SHOVEL[:next] = time() + 20
    ready(game) && place!(game)
    return
end

NG.stop!(::Shovel, game) = (clear_shovel!(); nothing)

register!(Shovel())
