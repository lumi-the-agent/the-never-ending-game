# Putting over a magnet stone (s151, idea "Putting over buried magnet stones", physics/magnetgolf.jl).
# A sand tray with a lodestone sunk flush in it (its dark top shows). Three iron balls are putted down the tray one
# after another: one far from the stone rolls straight, one close and quick whips round it, one close and slow is
# caught and stops on it. Every path is MagnetGolf.putt: the stone's field (em.jl), the ball's induced moment, rolling
# resistance on sand. Nothing is keyframed.
#   submit_job(:clip; path, script = "movies/magnetgolf.jl", call = "golf_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "magnetgolf.jl"))

function golf_parts(; spot = (-4.6f0, 18.75f0), rb = 0.015, stone = (0.08, 0.0), Rs = 0.05,
                    putts = [((-0.33, -0.15), 0.7), ((-0.33, -0.05), 0.75), ((-0.33, -0.05), 0.6)],
                    starts = [0.6, 3.4, 6.2], cam = (0.05, -0.62, 0.36), target = (0.0, 0.0, 0.0))
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat, :autumn_fall, :magnetstone_block, :magnetstone_spikes, :crane_pegs, :crane_core, :crane_coil, :crane_cord) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot)
        # level on its highest corner (s151's first take sank its front edge into the slope)
        zt = maximum(Float64(NG.ground(w.island, (spot[1] + Float32(sx * 0.5), spot[2] + Float32(sy * 0.28)))[3]) for sx in (-1, 1), sy in (-1, 1)) + 0.05
        S[:zt] = zt
        ox, oy = Float64(spot[1]), Float64(spot[2])
        eye = (ox + cam[1], oy + cam[2])
        filter!(p -> hypot(p.pos[1] - eye[1], p.pos[2] - eye[2]) > 1.5 && hypot(p.pos[1] - ox, p.pos[2] - oy) > 1.2, w.props)
        for c in w.creatures
            hypot(c.pos[1] - ox, c.pos[2] - oy) < 4 && (c.pos = NG.ground(w.island, (spot[1] + 10f0, spot[2] - 12f0)); c.goal = NG.Goal())
        end
        # the physics, before anything is drawn: one stone flush with the sand, three putts
        st = [MagnetGolf.Stone(; x = stone[1], y = stone[2], depth = 0.0, R = Rs)]
        S[:runs] = [MagnetGolf.putt(st, p0, (v, 0.0); r = rb, half = 0.45) for (p0, v) in putts]
        S[:info] = [(stop = r.stop, t = round(r.t, digits = 2), last = r.path[end]) for r in S[:runs]]
        sc = gm.stage.scene
        wood = NG.Hikari.Diffuse(color = (0.45, 0.28, 0.15), roughness = 0.8f0)
        L = 0.48f0; Wd = 0.26f0; th = 0.025f0; ztf = Float32(zt)
        rims = [Rect3f(Point3f(ox - L - th, oy - Wd - th, ztf - 0.2f0), Vec3f(2L + 2th, th, 0.215f0)),
                Rect3f(Point3f(ox - L - th, oy + Wd, ztf - 0.2f0), Vec3f(2L + 2th, th, 0.215f0)),
                Rect3f(Point3f(ox - L - th, oy - Wd, ztf - 0.2f0), Vec3f(th, 2Wd, 0.215f0)),
                Rect3f(Point3f(ox + L, oy - Wd, ztf - 0.2f0), Vec3f(th, 2Wd, 0.215f0))]
        for (k, r) in enumerate(rims)
            mesh!(sc, GeometryBasics.normal_mesh(r); color = RGBf(0.45, 0.28, 0.15), material = wood, name = Symbol("golf_rim$k"))
        end
        sand = NG.Hikari.Diffuse(color = (0.86, 0.76, 0.56), roughness = 1f0)
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(ox - L, oy - Wd, ztf - 0.2f0), Vec3f(2L, 2Wd, 0.2f0))); color = RGBf(0.86, 0.76, 0.56), material = sand, name = :golf_sand)
        # the stone's top, flush with the sand (a dark rough disc)
        stoneM = NG.Hikari.Diffuse(color = (0.42, 0.37, 0.33), roughness = 0.9f0)
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(ox + stone[1], oy + stone[2], ztf - 0.02f0), Point3f(ox + stone[1], oy + stone[2], ztf + 0.006f0), Float32(Rs))); color = RGBf(0.42, 0.37, 0.33), material = stoneM, name = :golf_stone)
        # the balls: waiting in a row at the start end until their turn
        S[:wait] = [(ox - 0.42, oy + 0.08 + 0.04k) for k in 0:length(putts)-1]
        iron = NG.Hikari.Conductor(ior = (2.9f0, 2.9f0, 2.9f0), extinction = (3.0f0, 3.0f0, 3.0f0), roughness = 0.25f0)   # iron: n ~ 2.9, k ~ 3
        ball = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Sphere(Point3f(0), Float32(rb)), 32))
        S[:balls] = meshscatter!(sc, [Point3f(p[1], p[2], zt + rb) for p in S[:wait]]; marker = ball, markersize = 1f0,
                                 color = RGBf(0.35, 0.35, 0.37), material = iron, name = :golf_balls)
        S[:ox] = ox; S[:oy] = oy
    end
    "where ball k is at film time t"
    at = function (k, t)
        t0 = starts[k]
        t < t0 && return S[:wait][k]
        path = S[:runs][k].path
        tt = t - t0
        i = searchsortedlast([p[1] for p in path], tt)
        i = clamp(i, 1, length(path))
        if i < length(path)
            a = path[i]; b = path[i+1]; s = (tt - a[1]) / max(b[1] - a[1], 1e-9); s = clamp(s, 0.0, 1.0)
            return (S[:ox] + a[2] + s * (b[2] - a[2]), S[:oy] + a[3] + s * (b[3] - a[3]))
        end
        return (S[:ox] + path[end][2], S[:oy] + path[end][3])
    end
    shot = function (gm, rig, t)
        n = length(putts)
        Makie.update!(S[:balls]; arg1 = [Point3f(at(k, t)..., S[:zt] + rb) for k in 1:n])
        rig.mode = :fixed
        ox, oy, zt = S[:ox], S[:oy], S[:zt]
        rig.eye = Point3f(ox + cam[1], oy + cam[2], zt + cam[3])
        rig.target = Point3f(ox + target[1], oy + target[2], zt + target[3])
        return nothing
    end
    setup, shot, S
end

function golf_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 9.5,
                   hour = 11.0, kw...)
    setup, shot, S = golf_parts(; kw...)
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(res, (; path, putts = string(S[:info])))
end

"""A path traced still of the tray after the three putts: each ball where it stopped, and the groove it pressed into
the sand behind it, so the bend at the stone reads without motion (s151: the film's curve was too small to see)."""
function golf_still(path; size = (1280, 720), samples = 96, hour = 11.0, cam = (-0.02, -0.5, 0.62), kw...)
    g = NG.Game(NG.game_root(); quiet = true)
    w = g.world
    NG.skip_to_hour!(w, hour)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
    cam3d!(scene)
    g.stage = NG.Stage(scene, w; show_names = false)
    for _ in 1:3
        Base.invokelatest(NG.step_systems!, g, 1 / 30)
    end
    setup, shot, S = golf_parts(; kw...)
    setup(g)
    rig = NG.CameraRig(; mode = :fixed)
    shot(g, rig, 30.0)                                   # every ball has stopped
    ox, oy, zt = S[:ox], S[:oy], S[:zt]
    dents = Point3f[]
    for r in S[:runs]
        last = nothing
        for p in r.path
            q = Point3f(ox + p[2], oy + p[3], zt)
            (last === nothing || norm(q - last) > 0.006f0) && (push!(dents, q); last = q)
        end
    end
    dent = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 0.0012f0), 0.007f0))
    meshscatter!(g.stage.scene, dents; marker = dent, markersize = 1f0, color = RGBf(0.62, 0.52, 0.35),
                 material = NG.Hikari.Diffuse(color = (0.62, 0.52, 0.35), roughness = 1f0), name = :golf_grooves)
    NG.sync!(g.stage, w); NG.sync_actors!(g)
    foreach(p -> (p.visible[] = false), g.stage.overlay.plots)
    NG.sync_sun!(g.stage, w)
    rig.eye = Point3f(ox + cam[1], oy + cam[2], zt + cam[3]); rig.target = Point3f(ox + 0.0, oy + 0.0, zt)
    NG.update_camera!(rig, w, scene, 0.0; snap = true)
    screen, oidn = NG.traced_screen(root_scene; denoise = true, max_depth = 8)
    img = Makie.colorbuffer(screen; samples)
    close(screen)
    NG.release_denoiser!(oidn)
    Makie.save(path, img)
    return (; path, putts = string(S[:info]))
end
