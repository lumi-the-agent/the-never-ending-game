# Clouds: a few soft puffy clouds drift slowly around the island, above the sea horizon,
# so the sky is not one flat colour (review s29). Each cloud is a cluster of puffs in one
# instanced meshscatter; unlit (NoShading) with painted shading: creamy tops, blue-grey bellies,
# golden at sunrise and sunset, dim blue at night. Emission material: no shadow blobs on the island.
isdefined(Main, :CLOUDS) || Core.eval(Main, :(const CLOUDS = Dict{Symbol,Any}()))
import Random
const NG = NeverendingGame
const CL = Main.CLOUDS
const CLOUD_VERSION = 7
const FRINGE = (1.07f0, 1.15f0, 1.24f0)   # rim shells per puff (one 1.22 shell at alpha 0.3 drew a ring)
const FRINGE_ALPHA = 0.11f0
const DRIFT = 0.004f0          # radians per sim second around the island

"Puffs of all clouds: (azimuth, distance, height) of the cloud, then per puff an offset and radius."
function cloud_puffs(radius)
    rng = Random.Xoshiro(7)
    puffs = Tuple{Float32,Float32,Float32,Vec3f,Float32}[]      # (az, dist, height, offset, r)
    # 11 clouds lower over the sea (7-16° above the horizon): at 15-25° an eye-level view held one or
    # two (perfectionist-0043: "one opaque white cloud", wants at least three soft shapes)
    n = 11
    for i in 1:n
        az = Float32(2pi * (i - 1) / n + 0.5 * rand(rng))
        dist = Float32(radius * (2.6 + 0.9 * rand(rng)))
        h = Float32(radius * (0.4 + 0.35 * rand(rng)))
        len = Float32(5 + 5 * rand(rng))                           # metres along the cloud
        m = 6 + rand(rng, 0:3)
        for k in 1:m
            x = len * ((k - 1) / (m - 1) - 0.5f0)
            r = Float32((2.2 + 1.8 * rand(rng)) * (1 - 0.6 * abs(x) / len))   # biggest in the middle
            push!(puffs, (az, dist, h, Vec3f(x, 1.5f0 * (rand(rng, Float32) - 0.5f0), 0.45f0 * r), r))
        end
    end
    return puffs
end

function build_clouds!(game)
    haskey(CL, :plot) && delete!(CL[:plot].parent, CL[:plot])
    w = game.world
    CL[:puffs] = cloud_puffs(w.island.radius)
    n = length(CL[:puffs])
    CL[:plot] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -100), n); marker = NG.shape(:sphere),
        markersize = [Vec3f(p[5]) for p in CL[:puffs]],
        color = fill(RGBf(1, 1, 1), n), shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (1.0, 1.0, 1.0), strength = 1.0), name = :clouds)
    # a soft rim (perfectionist-0055: "flat beige blobs with hard rims" at 19:25): every puff again, a
    # little bigger and faint, so the edge fades out; raster and browser only (traced alpha shells are discs)
    haskey(CL, :fringe) && delete!(CL[:fringe].parent, CL[:fringe])
    CL[:fringe] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -100), 3n); marker = NG.shape(:sphere),
        markersize = fill(Vec3f(1), 3n), color = fill(RGBAf(1, 1, 1, FRINGE_ALPHA), 3n),
        shading = Makie.NoShading, transparency = true, name = :cloud_fringe)
    CL[:key] = (CLOUD_VERSION, game.stage.scene)
    CL[:tint] = (-1f0, RGBf(0, 0, 0))
end

"World positions and sizes of the puffs at sim time `t`: the clouds turn slowly around the island."
function puff_layout(puffs, t)
    pos = Point3f[]; sz = Vec3f[]
    for (az, dist, h, o, r) in puffs
        a = az + DRIFT * Float32(mod(t, 2pi / DRIFT))
        c, s = cos(a), sin(a)
        # the cloud's long side faces the island (tangent direction)
        tx, ty = -s, c
        push!(pos, Point3f(dist * c + o[1] * tx + o[2] * c, dist * s + o[1] * ty + o[2] * s, h + o[3]))
        push!(sz, Vec3f(r, r, 0.8f0 * r))      # puffs a bit squat
    end
    return pos, sz
end

"Painted shading: top puffs light, low puffs darker; colours follow the time of day."
function puff_colors(puffs, w)
    nf = NG.night_factor(w)
    sun = NG.sun_color(w)
    top = RGBf(0.99, 0.98, 0.96); low = RGBf(0.78, 0.83, 0.92)
    # golden hour: warm tops, pinkish bellies
    gold = 1f0 - min(1f0, sun.g / max(sun.r, 1f-3))
    gold = clamp(4f0 * gold, 0f0, 1f0) * (1 - nf)
    # the evening the player sees: sunset.jl's sun sets at 19.9, while the engine's night factor is
    # near 1 from ~18:00 (s53: slate-dark clouds beside a sun still over the sea)
    h = 24f0 * Float32(NG.daytime(w))
    if 15f0 < h < 20.6f0
        nf = min(nf, clamp((h - 19.7f0) / 0.9f0, 0f0, 1f0))
        gold = max(gold, clamp((h - 16.3f0) / 2f0, 0f0, 1f0) * (1 - nf))
    end
    top = RGBf(top.r, top.g - 0.12f0gold, top.b - 0.3f0gold); low = RGBf(low.r + 0.1f0gold, low.g - 0.08f0gold, low.b - 0.12f0gold)
    # night: dim blue-grey, still a little lighter than the sky
    dim(c, k) = RGBf(c.r * (1 - 0.68f0nf * k), c.g * (1 - 0.64f0nf * k), c.b * (1 - 0.5f0nf * k))
    top = dim(top, 1f0); low = dim(low, 1.05f0)
    # a smooth ramp by height in the cloud (a hard top/low split showed as a dark band)
    lerp(f) = RGBf(low.r + f * (top.r - low.r), low.g + f * (top.g - low.g), low.b + f * (top.b - low.b))
    base = [lerp(clamp(0.35f0 + 0.4f0 * o[3], 0f0, 1f0)) for (_, _, _, o, _) in puffs]
    # a lit side and a shade side (perfectionist-0052: "flat lavender blobs with no light side"): puffs on
    # the cloud's sun side warm and bright, the far ones cooler and greyer; strongest with a low sun
    sa = Float32(2pi * (NG.daytime(w) - 0.25))     # the sun's path as NG.sun has it (its elevation there is clamped)
    hx, hy = cos(sa), -0.45f0; hl = hypot(hx, hy)
    hx /= hl; hy /= hl
    low_sun = clamp(1f0 - 1.4f0 * max(sin(sa), 0f0), 0.25f0, 1f0) * (1 - 0.7f0nf)
    warm = RGBf(1.0, 0.86 - 0.12f0gold, 0.62 - 0.2f0gold)
    shade = RGBf(0.62 - 0.1f0nf, 0.64 - 0.1f0nf, 0.78 - 0.05f0nf)
    out = similar(base)
    for (i, (az, _, _, o, _)) in enumerate(puffs)
        a = az + DRIFT * Float32(mod(w.t, 2pi / DRIFT))
        c, s = cos(a), sin(a)
        # the puff's offset in the world (as puff_layout), towards the sun along the cloud and across it
        ox = o[1] * -s + o[2] * c; oy = o[1] * c + o[2] * s
        side = clamp((ox * hx + oy * hy) / 4f0 - 0.35f0 * (c * hx + s * hy), -1f0, 1f0)
        k = low_sun * 0.55f0 * abs(side)
        t = side > 0 ? warm : shade
        b = base[i]
        out[i] = RGBf(b.r + k * (t.r - b.r), b.g + k * (t.g - b.g), b.b + k * (t.b - b.b))
    end
    return out
end

struct Clouds <: System end

function NG.start!(::Clouds, game)
    game.stage === nothing && return
    get(CL, :key, nothing) == (CLOUD_VERSION, game.stage.scene) || build_clouds!(game)
    CL[:plot].visible[] = true
end

NG.stop!(::Clouds, game) = (haskey(CL, :plot) && (CL[:plot].visible[] = false); haskey(CL, :fringe) && (CL[:fringe].visible[] = false))

function NG.step!(::Clouds, game, dt)
    game.stage === nothing && return
    get(CL, :key, nothing) == (CLOUD_VERSION, game.stage.scene) || build_clouds!(game)
    w = game.world
    traced = NG.path_traced(game)
    CL[:fringe].visible[] == !traced || (CL[:fringe].visible[] = !traced)
    traced && return     # glowing puffs held still while tracing (NG.path_traced)
    puffs = CL[:puffs]
    pos, sz = puff_layout(puffs, w.t)
    Makie.update!(CL[:plot]; arg1 = pos, markersize = sz)
    Makie.update!(CL[:fringe]; arg1 = repeat(pos, 3), markersize = vcat((sz .* k for k in FRINGE)...))
    # colours only when the light changed visibly
    nf = NG.night_factor(w); sun = NG.sun_color(w)
    old = CL[:tint]
    # and every 5 s as the clouds drift round the island (their sun side turns)
    if abs(old[1] - nf) > 0.01f0 || abs(old[2].g - sun.g) + abs(old[2].b - sun.b) > 0.01f0 || w.t > get(CL, :tinted, -Inf) + 5
        cs = puff_colors(puffs, w)
        CL[:plot].color[] = cs
        # the rim a touch lighter than its puff: a sunlit edge on the bright side
        CL[:fringe].color[] = repeat([RGBAf(min(1f0, c.r + 0.06f0), min(1f0, c.g + 0.05f0), min(1f0, c.b + 0.03f0), FRINGE_ALPHA) for c in cs], 3)
        CL[:tint] = (nf, sun); CL[:tinted] = w.t
    end
end

register!(Clouds())
