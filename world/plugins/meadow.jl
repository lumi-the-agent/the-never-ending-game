# Meadow: the island's grass is no longer one flat green. The terrain's vertex colours are
# painted anew once (and again when the props change):
#   - big soft patches: warm sunlit yellow-green clearings and deep lush green hollows,
#   - a fine grain of lighter and darker tufts, so the ground reads near the camera,
#   - cool dark shade pools under every tree crown (the trees stand IN the meadow, not on it),
#   - a dark contact ring round bushes and rocks.
# Nothing per frame: one colour update of the terrain plot. The engine colours come back on stop.
isdefined(Main, :MEADOW) || Core.eval(Main, :(const MEADOW = Dict{Symbol,Any}()))

const NG = NeverendingGame
using Serialization
const MEADOW_VERSION = 21

const SUNNY = RGBf(0.62, 0.73, 0.27)    # warm clearing
const LUSH = RGBf(0.17, 0.40, 0.17)     # deep hollow
const MID = RGBf(0.42, 0.60, 0.23)
const SHADE = RGBf(0.09, 0.22, 0.15)    # under a crown: cool and dark
const CONTACT = RGBf(0.20, 0.33, 0.15)
# the flower meadow south of the cottage (todo #87): a warm golden field
# the blossom grove (blossom.jl, s78): a soft petal blush on the ground round the cherry trees
const BLOSSOM_GROUND = (Point2f(-12.6, 13.6), 4.4f0)
const PETAL = RGBf(0.98, 0.70, 0.80)   # green grass + a pale pink at 0.65 came out as sand-beige (s78): strong and saturated
const FLOWER_FIELD = (Point2f(8.5, -6.5), 4.8f0)   # open meadow south-east, in front of the overview camera (s42; it was hidden behind the pines at (-7, -2))
const GOLD = RGBf(0.86, 0.72, 0.26)   # s43: warmer, so the field reads as its own place in the overview
# the beach cove on the flat south shore (todo #87, review s40 "the island is one green hill"):
# wide warm sand from the waterline up the gentle slope, darker wet sand where the swash reaches
# coves: (direction from the island's middle (rad), half width (rad), metres of sand inland from the waterline)
const COVES = ((4.85f0, 0.5f0, 6.5f0),    # shell beach, the flat south shore
               (2.72f0, 0.28f0, 6.0f0))   # a cove on the north-west shore, left of the cottage in the overview (s41: no trees to clear)
const BEACH_A, BEACH_HALF, BEACH_DEPTH = COVES[1]
const SAND = RGBf(0.93, 0.83, 0.62)
const WET_SAND = RGBf(0.74, 0.63, 0.46)

"Where the terrain meets the sea along the ray at angle `a`."
function coast_r(is, a)
    lo, hi = 0.3f0 * is.radius, 2.0f0 * is.radius
    for _ in 1:30
        m = 0.5f0 * (lo + hi)
        NG.terrain_height(is, m * cos(a), m * sin(a)) > 0 ? (lo = m) : (hi = m)
    end
    return 0.5f0 * (lo + hi)
end
function coast_table(is)
    get(Main.MEADOW, :coast_seed, nothing) == is.seed && return Main.MEADOW[:coast]
    Main.MEADOW[:coast] = [coast_r(is, Float32(2pi * i / 720)) for i in 0:719]
    Main.MEADOW[:coast_seed] = is.seed
    return Main.MEADOW[:coast]
end

"How sandy (x, y) is: 1 on the beach cove, 0 off it (soft, wavy edges). Also the metres inland from the waterline."
function beach_weight(is, x, y)
    a = atan(y, x)
    rc = coast_table(is)[mod(round(Int, a / (2pi) * 720), 720) + 1]
    d = Float32(rc - hypot(x, y))
    best = 0f0
    for (ca, half, depth) in COVES
        da = abs(mod(a - ca + pi, 2pi) - pi)
        da > half + 0.1f0 && continue
        wob = NG.fbm(x / 3, y / 3, is.seed + 77) - 0.5f0
        side = 1 - smooth01(0.6f0 * half, half + 0.1f0, da + 0.3f0 * half * wob)
        inland = 1 - smooth01(depth - 2.5f0, depth, d + 2.5f0 * wob * (1 - 0.6f0 * side) + 3f0 * (1 - side))
        best = max(best, Float32(side * inland))
    end
    return best, d
end

smooth01(a, b, x) = (t = clamp((x - a) / (b - a), 0f0, 1f0); t * t * (3 - 2t))
mix(a, b, t) = Makie.lerp_oklab(a, b, Float32(t))

terrain_plot(scene) = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :terrain, scene.plots)

"How much shade falls on (x, y): 0 in the open, up to 1 under a crown, darker near the trunk."
function shade_at(trees, x, y)
    s = 0f0
    for t in trees
        d = hypot(x - t.pos[1], y - t.pos[2]) / (1.7f0 * t.scale)
        d < 1.7f0 && (s = max(s, 1 - smooth01(0.3f0, 1.7f0, d)))
    end
    return s
end

function contact_at(objs, x, y)
    s = 0f0
    for o in objs
        r = (o.kind === :rock ? 0.55f0 : 0.75f0) * o.scale
        d = hypot(x - o.pos[1], y - o.pos[2]) / r
        d < 1.8f0 && (s = max(s, 1 - smooth01(0.7f0, 1.8f0, d)))
    end
    return s
end

const POND_MUD = (RGBf(0.62, 0.54, 0.38), RGBf(0.4, 0.36, 0.25))   # the pond's floor: pale sand at the edge, olive mud in the middle (s89: darker read as a navy lid when traced)

function meadow_color(is, base, x, y, h, slope, trees, objs)
    pd = isdefined(Main, :AREA_PLOTS) ? get(Main.AREA_PLOTS, :pond, nothing) : nothing
    if pd !== nothing
        u = hypot(x - pd[1][1], y - pd[1][2]) / (pd[2] * 1.12f0)
        u < 1 && return mix(mix(POND_MUD[2], POND_MUD[1], smooth01(0.3f0, 1f0, u)), base, smooth01(0.85f0, 1f0, u))
    end
    b, d = beach_weight(is, x, y)
    if h < 0.36f0                                # sand and seabed stay the engine's, but for the cove
        b > 0 || return base
        return mix(base, d < 0.9f0 ? mix(WET_SAND, SAND, smooth01(0.3f0, 0.9f0, d)) : SAND, b)
    end
    big = NG.fbm(x / 11, y / 11, is.seed + 311)    # clearings and hollows
    fine = NG.fbm(x / 1.7, y / 1.7, is.seed + 57) # tufts
    g = big > 0.5f0 ? mix(MID, SUNNY, smooth01(0.5f0, 0.68f0, big)) : mix(LUSH, MID, smooth01(0.32f0, 0.5f0, big))
    g = mix(g, fine > 0.5f0 ? SUNNY : LUSH, min(1f0, 0.8f0 * abs(fine - 0.5f0) * 2))
    c, r = FLOWER_FIELD
    f = 1 - smooth01(0.8f0 * r, r, hypot(x - c[1], y - c[2]) + 0.5f0 * (NG.fbm(x / 2.5, y / 2.5, is.seed + 91) - 0.5f0) * r)
    if f > 0      # a clear edge (s43: the soft 0.55r..r fade melted into the sunny grass)
        g = mix(g, GOLD, 0.88f0 * f)   # blossom freckles in the vertex colours came out as pink smudges (the grid is too coarse): flower props instead
    end
    b > 0 && (g = mix(g, d < 0.9f0 ? mix(WET_SAND, SAND, smooth01(0.3f0, 0.9f0, d)) : SAND, b))
    g = mix(g, SHADE, 0.9f0 * shade_at(trees, x, y))
    g = mix(g, CONTACT, 0.7f0 * contact_at(objs, x, y))
    # back to the engine's colours on the shore and on steep rock
    g = mix(g, base, (1 - b) * (1 - smooth01(0.36f0, 0.5f0, h)))
    c2, r2 = BLOSSOM_GROUND
    f2 = 1 - smooth01(0.6f0 * r2, r2, hypot(x - c2[1], y - c2[2]) + 0.5f0 * (NG.fbm(x / 2.5, y / 2.5, is.seed + 97) - 0.5f0) * r2)
    f2 > 0 && (g = mix(g, PETAL, 0.85f0 * f2))    # one soft blush, after the sand and the shore's engine colours (the grove is on low ground by the west shore), not freckles (the vertex grid is too coarse for those)
    return mix(g, base, smooth01(0.55f0, 0.9f0, slope))
end

function paint!(game)
    sc = game.stage.scene
    i = terrain_plot(sc)
    i === nothing && error("meadow: no :terrain plot in the stage")
    w = game.world
    m, base = NG.terrain_mesh(w.island)   # the engine's mesh and colours (same grid as the plot)
    pts = GeometryBasics.coordinates(m)
    nrm = GeometryBasics.normals(m)
    trees = [q for q in w.props if q.kind === :tree]
    objs = [q for q in w.props if q.kind in (:bush, :rock)]
    Main.MEADOW[:painted] = [meadow_color(w.island, base[k], pt[1], pt[2], pt[3], 1 - nrm[k][3], trees, objs) for (k, pt) in enumerate(pts)]
    sc.plots[i].color[] = Main.MEADOW[:painted]      # plugins/showers.jl darkens a copy while the ground is wet
    plant_tufts!(game)
    Main.MEADOW[:key] = (MEADOW_VERSION, length(w.props), objectid(sc), isfile(TUFT_MESH), cairn_site())
    return
end

# grass tufts: one light generated tuft (2500 faces), instanced a few hundred times in the lush
# hollows and round the feet of bushes and rocks, so the ground near the camera has something growing
const TUFT_MESH = joinpath(NG.world_paths().world, "assets", "20261123-082103-453-mesh", "mesh.jls")
const TUFT_HEIGHT = 0.22f0
const N_TUFTS = 280
const TUFT_GAIN = (1.7f0, 1.55f0, 1.1f0)

"Spots for the tufts: on grass, in a hollow or beside a bush or rock, never on a path, the sand or under a crown."
function tuft_spots(w; in_the_way = q -> false)
    is = w.island
    rng = Random.Xoshiro(is.seed + 4242)
    trees = [q for q in w.props if q.kind === :tree]
    objs = [q for q in w.props if q.kind in (:bush, :rock)]
    out = Tuple{Point3f,Float32,Float32}[]
    k = 0
    while length(out) < N_TUFTS && k < 40_000
        k += 1
        x, y = (2rand(rng, Float32) - 1) * is.radius, (2rand(rng, Float32) - 1) * is.radius
        NG.on_land(is, x, y; margin = 1.5f0) || continue
        NG.walkway_height(x, y) === nothing || continue
        h = NG.terrain_height(is, x, y)
        in_the_way((pos = Point3f(x, y, h), kind = :flower)) && continue    # the dirt path, the pond, the pier (areas.jl)
        h > 0.6f0 || continue
        first(beach_weight(is, x, y)) < 0.05f0 || continue     # no meadow grass on the beach
        shade_at(trees, x, y) < 0.3f0 || continue
        any(o -> hypot(x - o.pos[1], y - o.pos[2]) < 0.8f0 * o.scale, objs) && continue     # not inside a bush
        hollow = NG.fbm(x / 11, y / 11, is.seed + 311) < 0.45f0
        feet = contact_at(objs, x, y) > 0.1f0
        (hollow || feet || rand(rng) < 0.08) || continue
        push!(out, (Point3f(x, y, h - 0.02f0), 2f0 * Float32(pi) * rand(rng, Float32), 0.7f0 + 0.6f0 * rand(rng, Float32)))
    end
    return out
end

"The critters' stone cairn with its three rings (plugins/cairns.jl), or nothing."
cairn_site() = isdefined(Main, :CAIRN_STATE) ? get(Main.CAIRN_STATE, :site, nothing) : nothing

"areas.jl's check for the dirt path, the pond and the pier (none without that plugin), and the cairn's rings (tufts grew between the stones, s40)."
function area_check(game)
    a = get(game.plugins, "areas", nothing)
    c = cairn_site()
    on_cairn(q) = c !== nothing && hypot(q.pos[1] - c[1], q.pos[2] - c[2]) < 2.6f0
    (a === nothing || a.mod === nothing) && return on_cairn
    return q -> on_cairn(q) || Base.invokelatest(a.mod.in_the_way, q)
end

function plant_tufts!(game)
    sc = game.stage.scene
    old = get(Main.MEADOW, :tufts, nothing)
    old === nothing || (old.parent === sc && delete!(sc, old))
    delete!(Main.MEADOW, :tufts)
    isfile(TUFT_MESH) || return     # the light mesh is still being made by the worker
    mm = Serialization.deserialize(TUFT_MESH)
    # the baked texture is far darker than the generated image: brightened per channel, never metallic
    mat = copy(only(values(mm[:materials])))
    mat["metallic"] = 0.0f0
    dm = copy(mat["diffuse map"])
    dm["image"] = map(c -> typeof(c)(min(1f0, Float32(Colors.red(c)) * TUFT_GAIN[1]), min(1f0, Float32(Colors.green(c)) * TUFT_GAIN[2]),
                                     min(1f0, Float32(Colors.blue(c)) * TUFT_GAIN[3])), dm["image"])
    mat["diffuse map"] = dm
    model = NG.AssetModel(mm; material = mat)
    zmax = maximum(p -> p[3], GeometryBasics.coordinates(model.mesh))
    spots = tuft_spots(game.world; in_the_way = area_check(game))
    Main.MEADOW[:tufts] = NG.asset_instances!(sc, model, [s[1] for s in spots];
        rotation = [NG.rot_z(s[2]) for s in spots], markersize = [Vec3f(s[3] * TUFT_HEIGHT / zmax) for s in spots], name = :grass_tufts)
    return
end

struct Meadow <: System end

function NG.start!(::Meadow, game)
    game.stage === nothing && return
    paint!(game)
end

function NG.step!(::Meadow, game, dt)
    game.stage === nothing && return
    get(Main.MEADOW, :key, nothing) == (MEADOW_VERSION, length(game.world.props), objectid(game.stage.scene), isfile(TUFT_MESH), cairn_site()) || paint!(game)
    return
end

function NG.stop!(::Meadow, game)
    game.stage === nothing && return
    i = terrain_plot(game.stage.scene)
    i === nothing && return
    game.stage.scene.plots[i].color[] = last(NG.terrain_mesh(game.world.island))
    t = get(Main.MEADOW, :tufts, nothing)
    t === nothing || (t.visible[] = false)
    delete!(Main.MEADOW, :key)
end

register!(Meadow())
