# Flora: every tree, bush and rock on the island is a generated, textured model instead of
# sphere primitives. Each prop gets one of a few varieties (by its id), turned and scaled
# like the prop. All props of one variety are merged into one mesh, so 40 trees are one plot.
# The engine's sphere plots for those kinds are hidden (they come back when this plugin stops).
isdefined(Main, :FLORA_PLOTS) || Core.eval(Main, :(const FLORA_PLOTS = Dict{Symbol,Any}()))
using Serialization

const NG = NeverendingGame
const FLORA_VERSION = 18

# catalog ids per prop kind, and the model height for a prop of scale 1
const VARIETIES = Dict(
    :tree => ["20261122-221801-999-asset", "20261122-225654-964-asset", "20261122-234150-385-asset",
              "20261122-221801-999-asset#gold"],
    :bush => ["20261123-000547-906-asset", "20261123-001304-442-asset"],
    :rock => ["20261122-225656-623-asset", "20261122-225659-827-asset"],
    # meadow flowers: a pink five-petal flower and a pale blue-and-white clump (session 27). The older
    # three-flower model (20261123-024153-991-asset) has a near black texture (mean 0.26/0.23/0.10): unused
    :flower => ["20261123-033456-088-asset", "20261123-033457-643-asset",
                "20261123-033456-088-asset#gold", "20261123-033457-643-asset#cream"])
# the golden field's flowers (flowerfield.jl, data "field") are only these; the rest of the meadow never gets them
# (s43, review s42: the field drew the meadow's pink and blue and did not read as its own place)
const FIELD_VARIETIES = ("20261123-033456-088-asset#gold", "20261123-033457-643-asset#cream")
# recoloured by brightness, the green stems and leaves kept: a per-channel gain cannot turn pink into gold
const RECOLOUR = Dict("20261123-033456-088-asset#gold" => RGBf(1.0, 0.84, 0.2),   # 0.74 green came out orange (s43)
                      "20261123-033457-643-asset#cream" => RGBf(1.3, 1.24, 0.9))   # brighter than 1: the clump read grey-beige (s43)
is_field(p) = get(p.data, "field", false) == true
# used while none of a kind's varieties is ready (the old bush has a pot-like base)
const FALLBACK = Dict(:bush => ["20261122-221803-724-asset"])
# a variety is a catalog id, optionally with a "#tint" suffix: the same model with another colour
base_id(v) = first(split(v, '#'))
# textures too dark for the island's light (the pine was near black): brightened per channel
# before use. Distinct tints so the woods read as fresh green, blue-green pines, pale birches and
# a few golden crowns, lighter than the trunks (perfectionist-0024: "heavy dark blobs")
const GAIN = Dict("20261122-225654-964-asset" => (2.0f0, 2.35f0, 2.3f0),
                  "20261122-221801-999-asset" => (1.12f0, 1.15f0, 0.92f0),
                  "20261122-221801-999-asset#gold" => (2.0f0, 1.3f0, 0.55f0),
                  "20261122-234150-385-asset" => (1.15f0, 1.15f0, 1.0f0),
                  "20261123-024153-991-asset" => (1.5f0, 1.45f0, 1.35f0),
                  "20261123-033456-088-asset" => (1.2f0, 1.15f0, 1.1f0),     # pink flowers read dark magenta
                  "20261123-033457-643-asset" => (1.2f0, 1.15f0, 1.05f0))    # the clump: pale, not deep blue    # the meadow flowers: dark texture
const HEIGHT = Dict(:tree => 3.7f0, :bush => 1.3f0, :rock => 0.8f0, :flower => 0.36f0)
const SINK = Dict(:tree => 0.03f0, :bush => 0.12f0, :rock => 0.15f0, :flower => 0.02f0)   # part of the height below the ground (stands, bases)
# per model height: the wide blue clump at the flower height looked like a shrub next to the pink ones
const HEIGHT_ID = Dict("20261123-033456-088-asset" => 0.42f0, "20261123-033457-643-asset" => 0.22f0)
const SINK_ID = Dict("20261122-221803-724-asset" => 0.5f0)   # the old pot bush: its pot underground
const SPHERE_PLOTS = Dict(:tree => (:tree_trunks, :tree_canopies), :bush => (:bushes,), :rock => (:rocks,), :flower => (:flower_stems,))
# the engine's flower heads are unnamed meshscatters after the stems (scenery.jl add_static_props!)
flower_head(nm) = startswith(string(nm), "meshscatter")

ready(p, id) = isfile(joinpath(p.world, "assets", base_id(id), "mesh.jls"))
function available(game)
    av = Dict(k => filter(id -> ready(game.paths, id), ids) for (k, ids) in VARIETIES)
    for (k, ids) in FALLBACK
        isempty(av[k]) && (av[k] = filter(id -> ready(game.paths, id), ids))
    end
    return av
end

"The asset's material for foliage and stone: never metallic, its texture brightened by `gain`."
function flora_material(mat, gain, recolour = nothing)
    mat = copy(mat)
    mat["metallic"] = 0.0f0
    if recolour !== nothing
        dm = copy(mat["diffuse map"])
        dm["image"] = map(dm["image"]) do c
            r, g, b = Float32(Makie.Colors.red(c)), Float32(Makie.Colors.green(c)), Float32(Makie.Colors.blue(c))
            g > r && g > b && return c      # stems and leaves stay green
            l = min(1.0f0, 1.35f0 * max(r, g, b))
            typeof(c)(min(1.0f0, l * recolour.r), min(1.0f0, l * recolour.g), min(1.0f0, l * recolour.b))
        end
        mat["diffuse map"] = dm
    end
    if gain != (1, 1, 1)
        dm = copy(mat["diffuse map"])
        dm["image"] = map(dm["image"]) do c
            typeof(c)(min(1.0f0, Float32(Makie.Colors.red(c)) * gain[1]), min(1.0f0, Float32(Makie.Colors.green(c)) * gain[2]), min(1.0f0, Float32(Makie.Colors.blue(c)) * gain[3]))
        end
        mat["diffuse map"] = dm
    end
    return mat
end

"""
All props of `kind` that get variety `i`: ONE instanced plot (`NG.asset_instances!`), one mesh and
one small texture for every copy, in the raster, the path tracer and every browser that opens the page.
Returns `(plot, props, sizes)` or `nothing`; a copy is hidden by setting its markersize to 0.
"""
function variety_plot!(scene, w, kind, ids, i, mmpath, variety)
    if kind === :flower      # field flowers share the field's varieties, the meadow's the others
        own = [v for v in ids if (v in FIELD_VARIETIES) == (variety in FIELD_VARIETIES)]
        j = findfirst(==(variety), own)
        props = filter(p -> p.kind === :flower && is_field(p) == (variety in FIELD_VARIETIES) && mod(p.id, length(own)) + 1 == j, w.props)
    else
        props = filter(p -> p.kind === kind && mod(p.id, length(ids)) + 1 == i, w.props)
    end
    isempty(props) && return nothing
    mm = Serialization.deserialize(mmpath)
    id = basename(dirname(mmpath))
    model = NG.AssetModel(mm; material = flora_material(only(values(mm[:materials])), get(GAIN, variety, (1.0f0, 1.0f0, 1.0f0)), get(RECOLOUR, variety, nothing)))
    zs = [q[3] for q in GeometryBasics.coordinates(model.mesh)]
    h = maximum(zs) - minimum(zs)
    sink = get(SINK_ID, id, SINK[kind])
    pos = [Point3f(p.pos) - Point3f(0, 0, sink * HEIGHT[kind] * p.scale) for p in props]
    sizes = [Vec3f(get(HEIGHT_ID, id, HEIGHT[kind]) * p.scale / h) for p in props]
    plot = NG.asset_instances!(scene, model, pos; rotation = [NG.rot_z(p.yaw) for p in props], markersize = sizes,
                               name = Symbol("flora_", kind, "_", i))
    return (plot, props, sizes)
end

function sphere_plots_hidden!(game, kinds)
    for p in game.stage.statics
        nm = p.attributes[:name][]
        (any(k -> nm in SPHERE_PLOTS[k], kinds) || (:flower in kinds && flower_head(nm))) && p.visible[] && (p.visible[] = false)
    end
end

struct Flora <: System end

function build!(game)
    w = game.world
    old = get(Main.FLORA_PLOTS, :plots, Any[])
    foreach(p -> delete!(p.parent, p), old)
    av = available(game)
    plots = Any[]
    trees = Any[]
    flowers = Any[]
    for (kind, ids) in av, (i, id) in enumerate(ids)
        v = variety_plot!(game.stage.scene, w, kind, ids, i, joinpath(game.paths.world, "assets", base_id(id), "mesh.jls"), id)
        v === nothing && continue
        push!(plots, v[1])
        kind in (:tree, :flower) && push!(kind === :tree ? trees : flowers, (plot = v[1], props = v[2], sizes = v[3], hidden = falses(length(v[2]))))
    end
    Main.FLORA_PLOTS[:plots] = plots
    Main.FLORA_PLOTS[:trees] = trees
    Main.FLORA_PLOTS[:flowers] = flowers
    Main.FLORA_PLOTS[:key] = (FLORA_VERSION, NG.props_version(w), av)
    Main.FLORA_PLOTS[:kinds] = [k for (k, ids) in av if !isempty(ids)]
end

flora_key(game) = (FLORA_VERSION, NG.props_version(game.world), available(game))

function NeverendingGame.start!(::Flora, game)
    game.stage === nothing && return
    get(Main.FLORA_PLOTS, :key, nothing) == flora_key(game) &&
        all(p -> p.parent === game.stage.scene, get(Main.FLORA_PLOTS, :plots, Any[])) ?
        foreach(p -> p.visible[] = true, Main.FLORA_PLOTS[:plots]) : build!(game)
    return
end

const LAST_CHECK = Ref(0.0)
function NeverendingGame.step!(::Flora, game, dt)
    game.stage === nothing && return
    # props changed (a reload, a tree removed) or a new variety finished: rebuild, checked every 5 s
    if time() - LAST_CHECK[] > 5
        LAST_CHECK[] = time()
        get(Main.FLORA_PLOTS, :key, nothing) == flora_key(game) || build!(game)
    end
    sphere_plots_hidden!(game, get(Main.FLORA_PLOTS, :kinds, Symbol[]))
    hide_crowns_in_view!(game)
    hide_picked_flowers!(game)
    return
end

const REGROW = 90.0     # seconds until a picked meadow flower is back
const GROW_TIME = 1.2f0

"""
Meadow flowers picked by a critter or Lumi (plugins/flowergift.jl writes `FLORA_PLOTS[:picked]`,
prop id => sim time) are not drawn until they grow back. Updated only when the set changes.
"""
function hide_picked_flowers!(game)
    picked = get!(Main.FLORA_PLOTS, :picked, Dict{Int32,Float64}())
    growing = get!(Main.FLORA_PLOTS, :growing, Dict{Int32,Float64}())   # id => when it started growing back
    t = game.world.t
    for (id, t0) in collect(picked)
        t - t0 < REGROW && continue
        delete!(picked, id); growing[id] = t
    end
    # it grows back over a second with a little overshoot, instead of popping in
    grow(id) = (u = clamp(Float32(t - growing[id]) / GROW_TIME, 0f0, 1f0); u + 0.6f0 * u * (1 - u))
    for v in get(Main.FLORA_PLOTS, :flowers, Any[])
        changed = false
        for (k, p) in enumerate(v.props)
            hide = haskey(picked, p.id)
            hide == v.hidden[k] || (v.hidden[k] = hide; changed = true)
            haskey(growing, p.id) && (changed = true)
        end
        changed && Makie.update!(v.plot; markersize = [h ? Vec3f(0) : haskey(growing, p.id) ? grow(p.id) * sz : sz
                                                      for (h, sz, p) in zip(v.hidden, v.sizes, v.props)])
    end
    filter!(kv -> t - kv[2] < GROW_TIME + 0.3, growing)   # a few frames at full size (u = 1) before it stops updating
end

"Is a point inside the tree's crown (a wide cylinder from just above the ground to the top)?"
in_crown(q, p) = (q[1] - p.pos[1])^2 + (q[2] - p.pos[2])^2 < (1.7f0 * p.scale)^2 &&
                 p.pos[3] + 0.5f0 * p.scale < q[3] < p.pos[3] + HEIGHT[:tree] * p.scale

"""
Trees whose crown is between the camera and what it looks at (or holds the camera) are not drawn
(markersize 0 in their variety's instanced plot); they come back when the view is clear.
The plot is only updated when the hidden set changes. Not in the orbit view (the whole island).
"""
function hide_crowns_in_view!(game)
    trees = get(Main.FLORA_PLOTS, :trees, nothing)
    trees === nothing && return
    on = game.rig.mode !== :orbit && !get(Main.FLORA_PLOTS, :show_all, false)   # show_all: for before/after shots
    eye, target = game.rig.eye, game.rig.target
    for v in trees
        changed = false
        for (k, p) in enumerate(v.props)
            hide = on && any(s -> in_crown(eye + s * (target - eye), p), (0f0, 0.15f0, 0.3f0, 0.45f0, 0.6f0, 0.75f0, 0.88f0))
            hide == v.hidden[k] || (v.hidden[k] = hide; changed = true)
        end
        changed && Makie.update!(v.plot; markersize = [h ? Vec3f(0) : sz for (h, sz) in zip(v.hidden, v.sizes)])
    end
end

function NeverendingGame.stop!(::Flora, game)
    foreach(p -> p.visible[] = false, get(Main.FLORA_PLOTS, :plots, Any[]))
    game.stage === nothing && return
    for p in game.stage.statics
        p.visible[] = true
    end
end

register!(Flora())
