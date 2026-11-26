using NeverendingGame, Makie, GeometryBasics
using LinearAlgebra: norm, normalize
const NG = NeverendingGame

"""
The camera obscura (s128). A dark hut on the meadow, black inside, with a glass lens in its front wall and a white
back wall 1.7 m behind it. No projection, no texture: the picture on the back wall is sunlight from the island that
comes in through the lens (Hikari Glass, a biconvex lens R 1.5 m, aperture radius 0.4 m (0.25 in the first test), n 1.5, f ~ 1.5 m) and lands
upside down. The still is taken from inside the hut. Only ~2% of the wall's light paths find the lens, so it needs
many samples, and the picture is ~50x dimmer than the island outside: `exposure` makes up for that, like a long
exposure would.
"""

"A biconvex lens with its axis along x, centred at the origin: two spherical caps (radius R) over a disc of radius a."
function lens_mesh(; R = 1.5f0, a = 0.25f0, nr = 24, nt = 64)
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
        for j in 0:nt-1
            f = GLTriangleFace(base + 1, idx(1, j), idx(1, j + 1))
            push!(fs, side > 0 ? f : GLTriangleFace(f[1], f[3], f[2]))
        end
        for i in 1:nr-1, j in 0:nt-1
            f1 = GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1))
            f2 = GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1))
            push!(fs, side > 0 ? f1 : GLTriangleFace(f1[1], f1[3], f1[2]))
            push!(fs, side > 0 ? f2 : GLTriangleFace(f2[1], f2[3], f2[2]))
        end
    end
    return GeometryBasics.normal_mesh(pts, fs)
end

"Hut frame: lens at `P` (height h above the floor), looking along unit `d` (horizontal); local (x along d, y left, z up)."
function hut_boxes(; D = 1.7f0, W = 1.2f0, H = 2.1f0, h = 1.0f0, hole = 0.18f0, t = 0.08f0, below = 0.6f0)
    walls = Tuple{Vec3f,Vec3f,Symbol}[]
    push!(walls, (Vec3f(-D - t, -W - t, -below), Vec3f(-D, W + t, H + t), :screen))          # back wall: the screen
    push!(walls, (Vec3f(-D - t, -W - t, -below), Vec3f(t, -W, H + t), :dark))               # side walls
    push!(walls, (Vec3f(-D - t, W, -below), Vec3f(t, W + t, H + t), :dark))
    push!(walls, (Vec3f(-D - t, -W - t, H), Vec3f(t, W + t, H + t), :dark))                  # roof
    push!(walls, (Vec3f(-D - t, -W - t, -below), Vec3f(t, W + t, 0), :dark))                 # floor
    # front wall with a square hole round the lens axis (y = 0, z = h)
    push!(walls, (Vec3f(0, -W - t, -below), Vec3f(t, -hole, H + t), :outside))
    push!(walls, (Vec3f(0, hole, -below), Vec3f(t, W + t, H + t), :outside))
    push!(walls, (Vec3f(0, -hole, -below), Vec3f(t, hole, h - hole), :outside))
    push!(walls, (Vec3f(0, -hole, h + hole), Vec3f(t, hole, H + t), :outside))
    return walls
end

function to_world(p::Point3f, P::Point3f, d::Vec3f)
    side = Vec3f(-d[2], d[1], 0)
    return P + p[1] * d + p[2] * side + Vec3f(0, 0, p[3])
end

function box_world(lo::Vec3f, hi::Vec3f, P, d)
    m = GeometryBasics.normal_mesh(Rect3f(Point3f(lo), hi - lo))
    pts = [to_world(Point3f(p), P, d) for p in GeometryBasics.coordinates(m)]
    return GeometryBasics.normal_mesh(pts, GeometryBasics.faces(m))
end

"Pick the hut place: the lens looks away from the sun (the island it sees is front-lit), toward `look_at`."
function hut_place(w; look_at = (-6.5f0, -4.0f0), dist = 10f0)
    sd = NG.sun(w)[1]
    d = normalize(Vec3f(-sd[1], -sd[2], 0))
    C = Point2f(look_at...)
    for r in dist:-0.5f0:4f0
        xy = C - r * Point2f(d[1], d[2])
        g = NG.ground(w.island, (xy[1], xy[2]))[3]
        g > 0.3f0 && return (Point3f(xy[1], xy[2], g), d, r)
    end
    error("no land for the hut behind $(look_at)")
end

function obscura_still(path; samples = 1536, width = 960, height = 540, exposure = 60f0, hour = 15.5,
                       look_at = (-6.5, -4.0), dist = 10.0, h = 1.0, preview = false, max_depth = 8,
                       aperture = 0.4, lensR = 1.5, hole = 0.18, denoise = true, eye = (-0.15, 0.45, 1.75), target = (-1.8, 0.0, 0.95))
    return NG.with_scratch_game(NG.game_root(), (width, height)) do g, root_scene
        w = g.world
        NG.skip_to_hour!(w, hour)
        scene = Scene(root_scene; viewport = Rect2i(0, 0, width, height), lights = NG.stage_lights(w))
        cam3d!(scene)
        g.stage = NG.Stage(scene, w; show_names = false)
        P0, d, r = hut_place(w; look_at = Float32.(look_at), dist = Float32(dist))
        # the floor sits on the highest ground under the hut, so no grass pokes in
        zs = [NG.ground(w.island, (q[1], q[2]))[3] for q in
              (to_world(Point3f(x, y, 0), P0, d) for x in -1.8f0:0.3f0:0.1f0, y in -1.3f0:0.3f0:1.3f0)]
        P = Point3f(P0[1], P0[2], maximum(zs) + 0.02f0)
        # friends out in the sun in front of the lens, 7-12 m away
        names = ("Lumi", "Truffle", "Pickles", "Gloop", "Hopscotch", "Marshmallow")
        friends = [c for c in w.creatures if c.name in names]
        side = Vec3f(-d[2], d[1], 0)
        for (k, c) in enumerate(friends)
            off = (k - (length(friends) + 1) / 2) * 1.3f0
            q = P + (7.5f0 + 1.2f0 * mod(k, 3)) * d + off * side
            c.pos = NG.ground(w.island, (q[1], q[2]))
            c.goal = NG.Goal(:obscura, Point3f(q[1], q[2], 0), :play, 1.0, Inf, false, 0, true)
        end
        for _ in 1:4
            Base.invokelatest(NG.step_systems!, g, 1 / 30)
            NG.sync!(g.stage, w)
            NG.sync_actors!(g)
        end
        foreach(p -> (p.visible[] = false), g.stage.overlay.plots)
        # a shower in the snapshot: its glowing rain meshscatter fails in the tracer (s128 job 20261126-233551-075),
        # and the hut's picture wants sun, so the rain stops for this still
        for p in scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        Hk = NG.Hikari
        mats = Dict(:screen => Hk.Diffuse(color = (0.85, 0.84, 0.80)),
                    :dark => Hk.Diffuse(color = (0.02, 0.02, 0.02)),
                    :outside => Hk.Diffuse(color = (0.30, 0.20, 0.13)))
        colors = Dict(:screen => RGBf(0.85, 0.84, 0.8), :dark => RGBf(0.02, 0.02, 0.02), :outside => RGBf(0.3, 0.2, 0.13))
        for (lo, hi, kind) in hut_boxes(; h = Float32(h), hole = Float32(hole))
            mesh!(scene, box_world(lo, hi, P, d); color = colors[kind], material = mats[kind])
        end
        lens = lens_mesh(; R = Float32(lensR), a = Float32(aperture))
        lpts = [to_world(Point3f(p[1] + 0.1f0, p[2], p[3] + Float32(h)), P, d) for p in GeometryBasics.coordinates(lens)]
        mesh!(scene, GeometryBasics.normal_mesh(lpts, GeometryBasics.faces(lens)); color = RGBAf(0.9, 0.95, 1, 0.3),
              material = Hk.Glass(ior = 1.5))
        NG.sync_sun!(g.stage, w)
        # the eye: inside, by the front wall, off to one side, looking at the back wall
        eyew = to_world(Point3f(eye...), P, d)
        tg = to_world(Point3f(target...), P, d)
        rig = NG.CameraRig(; mode = :fixed); rig.eye = eyew; rig.target = tg
        NG.update_camera!(rig, w, scene, 0.0; snap = true)
        if preview
            img = Makie.colorbuffer(root_scene)
        else
            oidn = denoise ? NG.GPUOIDN(NG.OIDNRunner.OIDNDenoiser()) : nothing
            screens = (NG.RayMakie.Screen(root_scene; visible = false, rasterize = false, exposure = Float32(exposure),
                                          max_depth, denoise, denoise_config = oidn), oidn)
            img = NG.with_screen(screen -> Makie.colorbuffer(screen; samples), screens...)
        end
        Makie.save(path, img)
        (path = path, hut = P, look = d, dist = r, friends = [c.name for c in friends])
    end
end
