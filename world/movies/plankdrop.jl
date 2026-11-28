# s181 (project planks): three oak planks let go over the cart road's sand, falling and coming to rest by PrintSim
# contact (physics/plankdrop.jl drop_planks, poses saved in physics/data/plankdrop-s181.jls every 1/48 s). Nothing here
# moves them: the film replays the solved poses (x = A X + t of each affine body) at half speed. The old berm road and
# the cart are hidden so the sand the planks met is the sand you see.
#   submit_job(:clip; path = ..., script = "movies/plankdrop.jl", call = "plank_drop")
using NeverendingGame, Makie, GeometryBasics, Serialization, LinearAlgebra
const NG = NeverendingGame

const PD_YAWS = (0.0, 0.0, 0.35)    # the drops' yaw, as in the run (planks (u, v, yaw, lift))

function pd_box(p, A, yaw, L, W, T)
    ax = (Vec3(cos(yaw), sin(yaw), 0.0), Vec3(-sin(yaw), cos(yaw), 0.0), Vec3(0.0, 0, 1))
    h = (L / 2, W / 2, T / 2)
    corner(s) = Point3f(p + A * (s[1] * h[1] * ax[1] + s[2] * h[2] * ax[2] + s[3] * h[3] * ax[3]))
    S = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
    v = corner.(S)
    quads = ((1, 4, 3, 2), (5, 6, 7, 8), (1, 2, 6, 5), (2, 3, 7, 6), (3, 4, 8, 7), (4, 1, 5, 8))
    pts = Point3f[]; fcs = GLTriangleFace[]
    for q in quads                      # flat-shaded: each face its own four corners
        o = length(pts); append!(pts, v[collect(q)])
        push!(fcs, GLTriangleFace(o + 1, o + 2, o + 3), GLTriangleFace(o + 1, o + 3, o + 4))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fcs))
end

function plank_drop(path; hour = 16.8, seconds = 7.0, samples = 24, rasterize = false, size = (960, 540), slow = 0.5,
                    t_fall = 0.6, file = joinpath(@__DIR__, "..", "physics", "data", "plankdrop-s181.jls"),
                    eye = (3.42, -15.72, 0.40), target = (3.42, -14.70, 0.10), t0 = 0.0, fade = 0.4)
    D = deserialize(file)
    off = [D.x0, D.y0, D.z0]
    pose(k, ts) = (ps = D.poses[k]; i = clamp(1 + floor(Int, ts * 48), 1, length(ps)); (ps[i][2] .+ off, ps[i][3]))
    obs = Observable{Any}[]; made = Ref(false); hidden = Ref(false)
    rig = NG.CameraRig(); rig.mode = :fixed
    shot = function (g, rig, t)
        sc = g.stage.scene
        if !made[]
            p = get(g.plugins, "cartcord", nothing)
            oak = p === nothing ? nothing : parentmodule(typeof(only(p.systems))).mo_wood(base = (0.56, 0.40, 0.24))
            for k in eachindex(D.poses)
                c, A = pose(k, 0.0)
                o = Observable(pd_box(c, A, PD_YAWS[k], D.L, D.W, D.T)); push!(obs, o)
                oak === nothing ? mesh!(sc, o; color = RGBf(0.56, 0.42, 0.27), name = Symbol("plankdrop_", k)) :
                                  mesh!(sc, o; color = RGBf(0.56, 0.42, 0.27), material = oak, name = Symbol("plankdrop_", k))
            end
            made[] = true
        end
        if !hidden[] || t < 1.0          # the cart, its cord and the old berm road (plots appear after the plugins start)
            for pl in sc.plots
                haskey(pl.attributes, :name) && startswith(string(pl.attributes[:name][]), "cartcord") && (pl.visible[] = false)
            end
            hidden[] = true
        end
        ts = max(0.0, (t + t0 - t_fall) * slow)
        for k in eachindex(obs)
            c, A = pose(k, ts)
            obs[k][] = pd_box(c, A, PD_YAWS[k], D.L, D.W, D.T)
        end
        z = NG.ground(g.world.island, (Float32(target[1]), Float32(target[2])))[3]
        rig.eye = Point3f(eye[1], eye[2], z + eye[3]); rig.target = Point3f(target[1], target[2], z + target[3])
        nothing
    end
    setup = function (g)
        isdefined(Main, :CARTCORD) && (Main.CARTCORD[:next_run] = g.world.t + 1e6)
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, setup, fade)
end
