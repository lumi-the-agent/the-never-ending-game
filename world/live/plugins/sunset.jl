# Sunset: the sky model's sun never goes lower than ~20° (scenery.jl `sun`), so evenings had no sun to
# watch. This draws a big warm sun low over the western sea from late afternoon to dusk, sinking into
# the water, with a soft orange glow round it (many thin shells: few thick ones show rings). It is
# where the lookout bench faces (plugins/lookout.jl). Unlit (NoShading) so the raster and the browser
# show it; in quiet copies (traced clips and stills) the halo is left out (alpha shells are solid
# discs in path tracing). Moves only when it moved visibly (moving emissive plots leak in tracing).
isdefined(Main, :SUNSET) || Core.eval(Main, :(const SUNSET = Dict{Symbol,Any}()))

const NG = NeverendingGame
const S = Main.SUNSET
const SUNSET_VERSION = 6
const HOURS = (16.6, 20.2)                          # shown between these hours
const SETS_AT = 19.9                                # the disc's centre touches the sea
const SUNWARD = Vec2f(-1, -0.45) / norm(Vec2f(-1, -0.45))
const LAYERS = [(0.034f0, RGBAf(1.0, 0.78, 0.45, 1.0));
                [(0.036f0 + 0.0028f0 * k, RGBAf(1.0, 0.58, 0.32, 0.045)) for k in 1:16]]   # out to 2.3x the disc (bigger shells hit the far clip: a pale box)
const KEYS = [Symbol(:sun, k) for k in eachindex(LAYERS)]

struct Sunset <: System end

# the pink evening sky: a band round the western horizon, warm at the sun, rose higher up, fading out
# to the sides and the top (per-vertex alpha, unlit), strongest around 19:00
const BAND_AZ = 75.0          # degrees either side of the sunset direction
const BAND_TOP = 17.0         # degrees above the horizon
const BAND_NA, BAND_NE = 40, 8

"How strong the evening glow is at this hour (0..1)."
glow(h) = (s(a, b, x) = (t = clamp((x - a) / (b - a), 0, 1); t * t * (3 - 2t)); s(16.6, 18.6, h) * (1 - s(19.5, 20.2, h)))

function band_mesh(R)
    pts = Point3f[]; faces = GLTriangleFace[]
    a0 = atan(SUNWARD[2], SUNWARD[1])
    for i in 0:BAND_NA, j in 0:BAND_NE
        az = a0 + deg2rad(BAND_AZ * (2i / BAND_NA - 1)); el = deg2rad(-1.0 + (BAND_TOP + 1) * j / BAND_NE)
        push!(pts, Point3f(R * cos(el) * cos(az), R * cos(el) * sin(az), R * sin(el)))
    end
    idx(i, j) = i * (BAND_NE + 1) + j + 1
    for i in 0:(BAND_NA - 1), j in 0:(BAND_NE - 1)
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.Mesh(pts, faces)
end

# the golden path: a strip on the water from the west shore out towards the sun, glittering in bands
# a sun glitter path runs from the viewer to the sun: built along +x from the origin, then moved under the
# camera and turned towards the sun whenever the camera moved (the land hides the part under the island)
const PATH_NL, PATH_NW = 60, 6

function path_mesh(R)
    pts = Point3f[]; faces = GLTriangleFace[]
    for i in 0:PATH_NL, j in 0:PATH_NW
        t = (i / PATH_NL)^1.6f0
        d = t * (3.4f0 * R)
        half = 0.8f0 + 0.05f0 * d
        p = Vec2f(d, (2j / PATH_NW - 1) * half)
        push!(pts, Point3f(p[1], p[2], 0.03f0))
    end
    idx(i, j) = i * (PATH_NW + 1) + j + 1
    for i in 0:(PATH_NL - 1), j in 0:(PATH_NW - 1)
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.Mesh(pts, faces)
end

"Gold with glittering bands, clear at the sides and the near end."
function path_colors(g)
    cols = RGBAf[]
    for i in 0:PATH_NL, j in 0:PATH_NW
        u = abs(2j / PATH_NW - 1); t = i / PATH_NL
        sparkle = 0.55f0 + 0.45f0 * sin(37f0 * t + 3f0 * j)^2
        a = g * 0.42f0 * (1 - u^2) * min(1f0, 8t) * sparkle
        push!(cols, RGBAf(1.0, 0.72, 0.36, a))
    end
    return cols
end

"Vertex colours of the band for glow strength g: orange-pink low at the sun, rose above, clear at the edges."
function band_colors(g)
    cols = RGBAf[]
    for i in 0:BAND_NA, j in 0:BAND_NE
        u = abs(2i / BAND_NA - 1)               # 0 at the sun, 1 at the band's ends
        v = j / BAND_NE                         # 0 at the horizon, 1 at the top
        warm = RGBf(1.0, 0.56, 0.38); rose = RGBf(0.93, 0.5, 0.62)
        c = RGBf((warm.r * (1 - v) + rose.r * v), (warm.g * (1 - v) + rose.g * v), (warm.b * (1 - v) + rose.b * v))
        a = g * 0.5f0 * (1 - u^1.5f0) * (1 - v)^1.3f0 * (j == 0 ? 0.6f0 : 1f0)
        push!(cols, RGBAf(c.r, c.g, c.b, a))
    end
    return cols
end

hour(w) = 24 * NG.daytime(w)

"From the island to the low sun: elevation sinks from ~6° at 16:36 to 0 at SETS_AT."
function sunset_dir(w)
    e = deg2rad(6.0 * clamp((SETS_AT - hour(w)) / (SETS_AT - HOURS[1]), -0.15, 1.0))
    return normalize(Vec3f(SUNWARD[1] * cos(e), SUNWARD[2] * cos(e), sin(e)))
end

function build_sunset!(game)
    for k in collect(keys(S))
        S[k] isa Makie.AbstractPlot || continue
        delete!(S[k].parent, S[k]); delete!(S, k)
    end
    sc = game.stage.scene
    layers = game.dash === nothing ? LAYERS[1:1] : LAYERS
    for (k, (r, col)) in zip(KEYS, layers)
        # no Emission in the live raster: it makes every glowing mesh a flat rectangular area light, and the
        # glossy sea mirrored it as a pale grey box under the sun (s51). Quiet copies trace it: there it glows.
        kw = game.dash === nothing ? (; material = NG.Hikari.Emission(color = (col.r, col.g, col.b), strength = 8.0)) : (;)
        S[k] = mesh!(sc, Sphere(Point3f(0), 1.0f0); color = col, shading = Makie.NoShading,
            transparency = col.alpha < 1, visible = false, name = k, kw...)
        S[Symbol(k, :_r)] = r
    end
    if game.dash !== nothing                   # live only (alpha meshes are solid in tracing)
        S[:band] = mesh!(sc, band_mesh(3.45f0 * game.world.island.radius); color = band_colors(0f0), shading = Makie.NoShading,
                         transparency = true, visible = false, name = :sunset_sky)
    end
    if game.dash !== nothing
        S[:path] = mesh!(sc, path_mesh(game.world.island.radius); color = path_colors(0f0), shading = Makie.NoShading,
                         transparency = true, visible = false, name = :sunset_path)
    end
    S[:g] = -1.0
    S[:keys] = KEYS[1:length(layers)]
    S[:key] = SUNSET_VERSION
    S[:dir] = Vec3f(0)
end

function NG.start!(::Sunset, game)
    game.stage === nothing && return
    get(S, :key, nothing) == SUNSET_VERSION && S[:sun1].parent === game.stage.scene || build_sunset!(game)
    return
end

function NG.step!(::Sunset, game, dt)
    game.stage === nothing && return
    w = game.world
    h = hour(w)
    on = HOURS[1] <= h <= HOURS[2]
    if S[:sun1].visible[] != on
        for k in S[:keys]
            S[k].visible[] = on
        end
    end
    for k in (:band, :path)
        haskey(S, k) && S[k].visible[] != on && (S[k].visible[] = on)
    end
    on || return
    g = glow(h)
    if haskey(S, :band) && abs(g - S[:g]) > 0.03
        S[:band].color = band_colors(Float32(g))
        S[:path].color = path_colors(Float32(g))
        S[:g] = g
    end
    haskey(S, :path) && aim_path!(game, w)
    dir = sunset_dir(w)
    dot(dir, S[:dir]) > cosd(0.2f0) && return
    D = 3.6f0 * w.island.radius
    for k in S[:keys]
        p = S[k]
        translate!(p, Vec3f(D * dir))
        scale!(p, Vec3f(D * S[Symbol(k, :_r)]))
    end
    S[:dir] = dir
    return
end

"Put the glitter path under the camera, pointing at the sun (only when the camera moved)."
function aim_path!(game, w)
    eye = game.stage.scene.camera.eyeposition[]
    sun = 3.6f0 * w.island.radius * sunset_dir(w)
    e2 = Vec2f(eye[1], eye[2])
    v = Vec2f(sun[1], sun[2]) - e2
    key = (round.(e2; digits = 0), round(atan(v[2], v[1]); digits = 2))
    key == get(S, :aim, nothing) && return
    S[:aim] = key
    translate!(S[:path], Vec3f(e2[1], e2[2], 0))
    Makie.rotate!(S[:path], Vec3f(0, 0, 1), atan(v[2], v[1]))
end

function NG.stop!(::Sunset, game)
    for k in get(S, :keys, Symbol[])
        haskey(S, k) && (S[k].visible[] = false)
    end
    for k in (:band, :path)
        haskey(S, k) && (S[k].visible[] = false)
    end
end

register!(Sunset())
