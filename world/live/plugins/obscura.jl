# The camera obscura (s128): a dark hut on the south-west meadow with a glass lens in its front wall, looking
# north-east over the meadow. Inside it is black, but for a white back wall 1.7 m behind the lens: in the path
# tracer the island lands on that wall upside down, by light alone (movies/obscura.jl takes the picture from
# inside). In the raster game it is a little dark hut with a glinting lens. Films build their own hut
# (game.dash === nothing), so this one stays out of them.
const NG = NeverendingGame
const GeometryBasics = NG.Makie.GeometryBasics
using .GeometryBasics: GLTriangleFace
isdefined(Main, :OBSCURA) || Core.eval(Main, :(const OBSCURA = Dict{Symbol,Any}()))
const OB = Main.OBSCURA

const OB_AT = (-14.135f0, -10.458f0)                 # where the lens is (the still of s128 chose it from the afternoon sun)
const OB_LOOK = Vec3f(0.7635f0, 0.6458f0, 0)          # the lens looks this way
const OB_H = 1.0f0                                    # lens height over the floor

struct Obscura <: System end

ob_side(d) = Vec3f(-d[2], d[1], 0)
ob_world(p, P, d) = P + p[1] * d + p[2] * ob_side(d) + Vec3f(0, 0, p[3])

function ob_box(lo::Vec3f, hi::Vec3f, P, d)
    m = GeometryBasics.normal_mesh(Rect3f(Point3f(lo), hi - lo))
    pts = [ob_world(Point3f(p), P, d) for p in GeometryBasics.coordinates(m)]
    return GeometryBasics.normal_mesh(pts, GeometryBasics.faces(m))
end

"A biconvex lens, axis along x: two spherical caps of radius R over a disc of radius a."
function ob_lens(; R = 1.5f0, a = 0.4f0, nr = 16, nt = 48)
    sag(r) = sqrt(R^2 - r^2) - sqrt(R^2 - a^2)
    pts = Point3f[]; fs = GLTriangleFace[]
    for side in (1f0, -1f0)
        base = length(pts)
        push!(pts, Point3f(side * sag(0f0), 0, 0))
        for i in 1:nr, j in 0:nt-1
            r = a * i / nr; t = 2f0 * Float32(pi) * j / nt
            push!(pts, Point3f(side * sag(r), r * cos(t), r * sin(t)))
        end
        idx(i, j) = base + 1 + (i - 1) * nt + mod(j, nt) + 1
        flip(f) = side > 0 ? f : GLTriangleFace(f[1], f[3], f[2])
        for j in 0:nt-1
            push!(fs, flip(GLTriangleFace(base + 1, idx(1, j), idx(1, j + 1))))
        end
        for i in 1:nr-1, j in 0:nt-1
            push!(fs, flip(GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1))))
            push!(fs, flip(GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1))))
        end
    end
    return GeometryBasics.normal_mesh(pts, fs)
end

function ob_walls(; D = 1.7f0, W = 1.2f0, H = 2.1f0, h = OB_H, hole = 0.3f0, t = 0.08f0, below = 0.6f0)
    return [(Vec3f(-D - t, -W - t, -below), Vec3f(-D, W + t, H + t), :screen),
            (Vec3f(-D - t, -W - t, -below), Vec3f(t, -W, H + t), :dark),
            (Vec3f(-D - t, W, -below), Vec3f(t, W + t, H + t), :dark),
            (Vec3f(-D - t, -W - t, H), Vec3f(t, W + t, H + t), :roof),
            (Vec3f(-D - t, -W - t, -below), Vec3f(t, W + t, 0), :dark),
            (Vec3f(0, -W - t, -below), Vec3f(t, -hole, H + t), :outside),
            (Vec3f(0, hole, -below), Vec3f(t, W + t, H + t), :outside),
            (Vec3f(0, -hole, -below), Vec3f(t, hole, h - hole), :outside),
            (Vec3f(0, -hole, h + hole), Vec3f(t, hole, H + t), :outside)]
end

function ob_plots!(game)
    haskey(OB, :plots) && all(p -> p.parent !== nothing, OB[:plots]) && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "obscura_hut"), copy(sc.plots))
        delete!(sc, p)
    end
    w = game.world
    d = OB_LOOK
    P0 = Point3f(OB_AT[1], OB_AT[2], 0)
    zs = [NG.ground(w.island, (q[1], q[2]))[3] for q in
          (ob_world(Point3f(x, y, 0), P0, d) for x in -1.8f0:0.3f0:0.1f0, y in -1.3f0:0.3f0:1.3f0)]
    P = Point3f(P0[1], P0[2], maximum(zs) + 0.02f0)
    Hk = NG.Hikari
    look = Dict(:screen => (RGBf(0.85, 0.84, 0.80), Hk.Diffuse(color = (0.85, 0.84, 0.80))),
                :dark => (RGBf(0.05, 0.05, 0.06), Hk.Diffuse(color = (0.02, 0.02, 0.02))),
                :roof => (RGBf(0.32, 0.22, 0.16), Hk.Diffuse(color = (0.32, 0.22, 0.16))),
                :outside => (RGBf(0.42, 0.30, 0.20), Hk.Diffuse(color = (0.42, 0.30, 0.20))))
    plots = Any[]
    for (k, (lo, hi, kind)) in enumerate(ob_walls())
        c, m = look[kind]
        push!(plots, mesh!(sc, ob_box(lo, hi, P, d); color = c, material = m, name = Symbol(:obscura_hut_, k)))
    end
    lens = ob_lens()
    lp = [ob_world(Point3f(p[1] + 0.1f0, p[2], p[3] + OB_H), P, d) for p in GeometryBasics.coordinates(lens)]
    push!(plots, mesh!(sc, GeometryBasics.normal_mesh(lp, GeometryBasics.faces(lens)); color = RGBAf(0.8, 0.9, 1.0, 0.35),
                       transparency = true, material = Hk.Glass(ior = 1.5), name = :obscura_hut_lens))
    OB[:plots] = plots
    OB[:at] = P
    return nothing
end

function NG.step!(::Obscura, game, dt)
    game.stage === nothing && return
    game.dash === nothing && return            # films build their own hut (movies/obscura.jl)
    ob_plots!(game)
end

NG.start!(::Obscura, game) = (delete!(OB, :plots); nothing)

function NG.stop!(::Obscura, game)
    for p in get(OB, :plots, Any[])
        p.parent !== nothing && delete!(p.parent, p)
    end
    delete!(OB, :plots)
end

register!(Obscura())
