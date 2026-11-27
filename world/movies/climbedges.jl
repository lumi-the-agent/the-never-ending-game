using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame

Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "echo.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "climb.jl"))

"""
Climb anything, step 1 (s134, projects/climb-anything.md): Lumi stands at the east wall of the old camera obscura hut,
and every lip its claws could hold (physics/climb.jl `climb_edges`, rays against the real meshes) glows as a small
amber point. Path traced still, nothing placed by hand but Lumi and the lens.
"""
function climbedges_still(path; samples = 96, width = 960, height = 540, gap = 0.7f0, facing = (-1.0, 0.0), building = "obscura_hut_")
    size = (width, height)
    NG.with_scratch_game(NG.game_root(), size) do g, root_scene
        w = g.world
        scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
        cam3d!(scene)
        g.stage = NG.Stage(scene, w; show_names = false)
        for _ in 1:3     # the plugins make their plots (the hut among them) when the systems step
            Base.invokelatest(NG.step_systems!, g, 1 / 30)
            NG.sync!(g.stage, w); NG.sync_actors!(g)
        end
        # the hut in WORLD space (data_limits leaves out the plot's placement: s134's first try stood elsewhere)
        hut = Set{Any}()
        for p in scene.plots
            haskey(p.attributes, :name) && startswith(string(Makie.to_value(p.attributes[:name])), building) &&
                foreach(q -> push!(hut, q), Makie.collect_atomic_plots(p))
        end
        ht = stage_triangles(scene; keep = q -> q in hut)
        xs = Float32[v[1] for t in ht for v in t]; ys = Float32[v[2] for t in ht for v in t]
        isempty(xs) && error("no plot named $building* in this scratch game (plugins/obscura.jl skips them)")
        fx, fy = Float32(facing[1]), Float32(facing[2])
        cy = (minimum(ys) + maximum(ys)) / 2; cx = (minimum(xs) + maximum(xs)) / 2
        feet = fx < 0 ? (maximum(xs) + gap, cy) : fx > 0 ? (minimum(xs) - gap, cy) : fy < 0 ? (cx, maximum(ys) + gap) : (cx, minimum(ys) - gap)
        side = Vec2f(-fy, fx)
        eye = (feet[1] - 1.0f0 * fx + 3.4f0 * side[1], feet[2] - 1.0f0 * fy + 3.4f0 * side[2], 2.1f0 + NG.terrain_height(w.island, feet...))
        target = (feet[1] + 1.2f0 * fx, feet[2] + 1.2f0 * fy, 1.4f0 + NG.terrain_height(w.island, feet...))
        @info "hut" bbox = (extrema(xs), extrema(ys)) feet
        lumi = only(c for c in w.creatures if c.name == "Lumi")
        lumi.pos = NG.ground(w.island, Float32.(feet)); lumi.yaw = Float32(atan(facing[2], facing[1]))
        lumi.goal = NG.Goal(:idle, lumi.pos, :idle, 60.0, w.t + 60, true, 0, false); lumi.controlled = false
        for _ in 1:3
            Base.invokelatest(NG.step_systems!, g, 1 / 30)
            NG.sync!(g.stage, w); NG.sync_actors!(g)
        end
        lumi.pos = NG.ground(w.island, Float32.(feet)); lumi.yaw = Float32(atan(facing[2], facing[1]))
        NG.sync!(g.stage, w); NG.sync_actors!(g)
        tris = solid_triangles(scene)
        backend = KA.CPU()
        tlas = echo_tlas(tris, backend)
        f = Point3f(feet[1], feet[2], NG.terrain_height(w.island, feet[1], feet[2]))
        lips = climb_edges(tlas, backend, f, facing; width = 2.4, columns = 61, reach = 1.8)
        @info "climb edges" n = length(lips) heights = [round(l[1][3] - f[3]; digits = 2) for l in lips]
        pts = [l[1] + 0.03f0 * l[2] for l in lips]      # just off the wall's face, on its lip
        if !isempty(pts)      # frame the lip itself: close, low, from the side (s134 critic: the dots were 1% of the picture)
            m = sum(pts) / length(pts); nrm = normalize(sum(l[2] for l in lips))
            sd = Vec3f(-nrm[2], nrm[1], 0)
            eye = Tuple(m + 2.9f0 * nrm + 1.3f0 * sd + Vec3f(0, 0, 1.0))
            target = Tuple(m - 0.4f0 * sd + Vec3f(0, 0, 0.8))
            lumi.pos = NG.ground(w.island, (m[1] + 0.6f0 * nrm[1] - 1.3f0 * sd[1], m[2] + 0.6f0 * nrm[2] - 1.3f0 * sd[2]))
            lumi.yaw = Float32(atan(nrm[2], nrm[1]))     # s134: atan(facing) stood it with its back to the wall
            NG.sync!(g.stage, w); NG.sync_actors!(g)
        end
        isempty(pts) || meshscatter!(scene, pts; marker = NG.shape(:glowdot), markersize = 0.022f0, color = RGBf(1.0, 0.7, 0.3),
                                     shading = Makie.NoShading, material = NG.Hikari.Emission(color = (1.0, 0.7, 0.3), strength = 8.0),
                                     name = :climb_lips)
        foreach(p -> (p.visible[] = false), g.stage.overlay.plots)
        NG.sync_sun!(g.stage, w)
        rig = NG.CameraRig(; mode = :fixed); rig.eye = Point3f(eye...); rig.target = Point3f(target...)
        NG.update_camera!(rig, w, scene, 0.0; snap = true)
        img = NG.with_screen(screen -> Makie.colorbuffer(screen; samples), NG.traced_screen(root_scene; denoise = true, max_depth = 8)...)
        Makie.save(path, img)
        (path = path, lips = length(lips), hour = 24 * NG.daytime(w))
    end
end
