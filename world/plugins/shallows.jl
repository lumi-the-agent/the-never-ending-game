# Shallows: the sea is clear turquoise over the sand by the shore and deepens to blue further out,
# with a soft line of foam where the water meets the beach. One static ring mesh round the coast,
# per-vertex colour and alpha over the glass sea (perfectionist s36: "the sea is a flat navy slab,
# add depth colour from shore to open water, foam at the beach"). Its colours dim with the night
# (a NoShading look would glow in the dark): updated only when the light changes.
const NG = NeverendingGame

const SHALLOW_VERSION = 6
const N_ANGLES = 360
# distance from the coast (m, negative: under the beach, hidden by the sand) => colour, alpha
const BANDS = ((-0.6f0, RGBf(0.93, 0.97, 0.95), 0.0f0),
               (0.05f0, RGBf(0.96, 0.99, 0.97), 0.65f0),     # a thin line of foam on the wet sand (0.85 and 0.45 m wide smeared close up)
               (0.25f0, RGBf(0.62, 0.92, 0.88), 0.5f0),
               (1.1f0, RGBf(0.36, 0.84, 0.80), 0.72f0),     # clear turquoise over the sand
               (3.5f0, RGBf(0.18, 0.62, 0.70), 0.62f0),
               (7.0f0, RGBf(0.12, 0.42, 0.60), 0.42f0),     # deepening blue
               (12.0f0, RGBf(0.12, 0.38, 0.60), 0.45f0),
               # the open sea: a lit mid blue over the glass, which from above showed a near-black navy
               # (review s38); it fades out far off so the horizon stays the sky's
               (40.0f0, RGBf(0.16, 0.45, 0.66), 0.5f0),
               (110.0f0, RGBf(0.24, 0.52, 0.70), 0.0f0))
const SEA_Z = 0.02f0
const N_GLINTS = 320
# the swash: a second, thin line of foam that washes up the beach and slides back (every SWASH_T s).
# Only its plot's scale about the island's middle changes, so no mesh goes to the browsers each frame.
const SWASH = ((-0.45f0, RGBf(0.95, 0.98, 0.97), 0.0f0),
               (-0.12f0, RGBf(0.97, 0.99, 0.98), 0.7f0),
               (0.12f0, RGBf(0.85, 0.96, 0.94), 0.45f0),
               (0.5f0, RGBf(0.6, 0.9, 0.87), 0.0f0))
const SWASH_T = 5.5
const SWASH_M = 0.5f0       # metres up and down the beach

isdefined(Main, :SHALLOWS) || Core.eval(Main, :(const SHALLOWS = Dict{Symbol,Any}()))
const SHALLOWS = Main.SHALLOWS

struct Shallows <: System end

"Where the terrain meets the sea along the ray at angle `a` (bisection on terrain height = 0)."
function coast_radius(is, a)
    lo, hi = 0.3f0 * is.radius, 2.0f0 * is.radius
    for _ in 1:30
        m = 0.5f0 * (lo + hi)
        NG.terrain_height(is, m * cos(a), m * sin(a)) > 0 ? (lo = m) : (hi = m)
    end
    return 0.5f0 * (lo + hi)
end

function ring_mesh(is, bands = BANDS, z = SEA_Z)
    pts = Point3f[]; base = RGBAf[]; faces = GLTriangleFace[]
    nb = length(bands)
    for i in 0:(N_ANGLES - 1)
        a = Float32(2pi * i / N_ANGLES)
        rc = coast_radius(is, a)
        for (d, c, al) in bands
            r = rc + d
            push!(pts, Point3f(r * cos(a), r * sin(a), z))
            push!(base, RGBAf(c.r, c.g, c.b, al))
        end
    end
    idx(i, k) = mod(i, N_ANGLES) * nb + k
    for i in 0:(N_ANGLES - 1), k in 1:(nb - 1)
        a, b, c, d = idx(i, k), idx(i + 1, k), idx(i + 1, k + 1), idx(i, k + 1)
        push!(faces, GLTriangleFace(a, b, c), GLTriangleFace(a, c, d))
    end
    return GeometryBasics.Mesh(pts, faces), base
end

"The colours for the light now: full by day, dimmed and cooled at night, darker under rain clouds."
function lit_colors(base, w)
    nf = NG.night_factor(w)
    k = (1 - 0.72f0 * nf) * (0.75f0 + 0.25f0 * NG.SUN_DIM[])
    return [RGBAf(c.r * k * (1 - 0.15f0 * nf), c.g * k, c.b * k * (1 + 0.1f0 * nf), c.alpha) for c in base]
end

function build_shallows!(game)
    sc = game.stage.scene
    haskey(SHALLOWS, :plot) && SHALLOWS[:plot] in sc.plots && delete!(sc, SHALLOWS[:plot])
    m, base = ring_mesh(game.world.island)
    SHALLOWS[:base] = base
    SHALLOWS[:level] = round(Int, 40 * NG.night_factor(game.world)) + 1000 * round(Int, 20 * NG.SUN_DIM[])
    SHALLOWS[:plot] = mesh!(sc, m; color = lit_colors(base, game.world), shading = Makie.NoShading, transparency = true,
                            name = :shallows)
    haskey(SHALLOWS, :swash) && SHALLOWS[:swash] in sc.plots && delete!(sc, SHALLOWS[:swash])
    m2, base2 = ring_mesh(game.world.island, SWASH, SEA_Z + 0.006f0)
    SHALLOWS[:swash_base] = base2
    SHALLOWS[:swash] = mesh!(sc, m2; color = lit_colors(base2, game.world), shading = Makie.NoShading, transparency = true,
                             name = :swash)
    # sun glints that twinkle on the turquoise by day: tiny flat unlit flecks (Emission: no shadow blobs)
    haskey(SHALLOWS, :glints) && SHALLOWS[:glints] in sc.plots && delete!(sc, SHALLOWS[:glints])
    rng = Random.Xoshiro(5)
    gp = Point3f[]
    for _ in 1:N_GLINTS
        a = 2f0pi * rand(rng, Float32)
        r = coast_radius(game.world.island, a) + 1.2f0 + 5f0 * rand(rng, Float32)
        push!(gp, Point3f(r * cos(a), r * sin(a), SEA_Z + 0.012f0))
    end
    SHALLOWS[:glint_seeds] = [(rand(rng, Float32), 0.6f0 + 0.8f0 * rand(rng, Float32)) for _ in 1:N_GLINTS]
    SHALLOWS[:glints] = meshscatter!(sc, gp; marker = NG.shape(:glowdot), markersize = fill(Vec3f(0), N_GLINTS),
        color = RGBf(1.0, 0.98, 0.9), shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (1.0, 0.98, 0.9), strength = 1.5), name = :glints)
    SHALLOWS[:glint_t] = 0.0
    SHALLOWS[:key] = (SHALLOW_VERSION, sc)
end

function NG.start!(::Shallows, game)
    game.stage === nothing && return
    build_shallows!(game)
    return
end

function NG.step!(::Shallows, game, dt)
    game.stage === nothing && return
    get(SHALLOWS, :key, nothing) == (SHALLOW_VERSION, game.stage.scene) || build_shallows!(game)
    w = game.world
    level = round(Int, 40 * NG.night_factor(w)) + 1000 * round(Int, 20 * NG.SUN_DIM[])
    if level != SHALLOWS[:level]
        SHALLOWS[:level] = level
        SHALLOWS[:plot].color = lit_colors(SHALLOWS[:base], w)
        SHALLOWS[:swash].color = lit_colors(SHALLOWS[:swash_base], w)
    end
    # up the beach quickly, back slowly (a skewed wave), as a scale about the island's middle
    ph = Float32(mod(w.t / SWASH_T, 1.0))
    u = ph < 0.35f0 ? sin(0.5f0pi * ph / 0.35f0) : cos(0.5f0pi * (ph - 0.35f0) / 0.65f0)
    k = 1 + SWASH_M * (u - 0.5f0) / game.world.island.radius
    Makie.scale!(SHALLOWS[:swash], k, k, 1)
    twinkle!(game, w)
    return
end

"Each glint flashes for a moment now and then (10 updates a second); none at night, in the rain or while path tracing."
function twinkle!(game, w)
    abs(w.t - SHALLOWS[:glint_t]) < 0.1 && return
    SHALLOWS[:glint_t] = w.t
    on = NG.night_factor(w) < 0.3f0 && NG.SUN_DIM[] > 0.95f0 && !NG.path_traced(game)
    g = SHALLOWS[:glints]
    g.visible[] == on || (g.visible[] = on)
    on || return
    t = Float32(mod(w.t, 1000.0))
    ms = map(SHALLOWS[:glint_seeds]) do (ph, sp)
        f = mod(sp * t / 2.2f0 + ph, 1f0)                 # a flash in the first 20% of each cycle
        f < 0.2f0 ? (b = sin(pi * f / 0.2f0); Vec3f(0.2f0 * b, 0.06f0 * b, 0.004f0)) : Vec3f(0)
    end
    Makie.update!(g; markersize = ms)
end

register!(Shallows())
