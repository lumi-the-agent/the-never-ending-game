# Three paper darts that differ only in their folds (s147, todo #693): the back edges bent down 4 degrees, up 4, up 20.
# Each is thrown at 4 m/s from 2.5 m over the bay and flies by physics/glider.jl (a vortex lattice over its own folded
# panels, the mass and balance of its own sheet): dive, glide, loop. Slowed down twice.
# s147 retake: the first take watched all three from 4.5 m and the 27 cm darts were ~30 px slivers. Now one shot per
# dart, side-on from ~1.7 m, the camera trailing the dart's smoothed path (it keeps the dart big, the sea and horizon
# show the motion, and the slow vertical follow lets the dive and the climb read).
#   submit_job(:clip; path, script = "movies/glider.jl", call = "glider_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "glider.jl"))

function dart_mesh(Q, cg)
    pts = Point3f[]; fs = GLTriangleFace[]
    for (a, b, c, d) in Q
        o = length(pts)
        append!(pts, Point3f.((a - cg, b - cg, c - cg, d - cg)))
        push!(fs, GLTriangleFace(o + 1, o + 2, o + 3), GLTriangleFace(o + 1, o + 3, o + 4))
        push!(fs, GLTriangleFace(o + 1, o + 3, o + 2), GLTriangleFace(o + 1, o + 4, o + 3))   # both sides
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

# exponential follow of a sampled path (time constant tau, seconds of flight): what a camera operator's pan does
function trail(ts, xs, tau)
    out = similar(xs); out[1] = xs[1]
    for k in 2:length(xs)
        a = 1 - exp(-(ts[k] - ts[k-1]) / tau)
        out[k] = out[k-1] + a * (xs[k] - out[k-1])
    end
    out
end

function glider_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, segment = 3.6, hold = 0.4,
                     slow = 2.0, hour = 11.0, spot = (-4f0, 18f0), bends = (-4, 4, 20), side = 1.7f0)
    flights = map(bends) do d
        P, M, Q = Glider.dart(delta = deg2rad(d), keel_mass = 0.004, keel_x = (-0.01, -0.07))
        r = Glider.fly(P, M; dt = 1e-4, every = 10, seconds = (segment - hold) / slow + 0.1)
        ext = collect(0.01:0.01:2.0)                          # the camera keeps settling after the dart has landed
        camt = vcat(r.t, r.t[end] .+ ext)
        px = vcat([Float64(p[1]) for p in r.pos], fill(Float64(r.pos[end][1]), length(ext)))
        pz = vcat([Float64(p[3]) for p in r.pos], fill(Float64(r.pos[end][3]), length(ext)))
        # tau z 0.06 s keeps the dive's last plunge inside the frame (checked: within 20 deg of 22.5)
        (; r, mesh = dart_mesh(Q, r.cg), camt, camx = trail(camt, px, 0.18), camz = trail(camt, pz, 0.06))
    end
    S = Dict{Symbol,Any}()
    x0 = spot[1] - 1.0f0
    lane = spot[2] + 5.0f0
    away = Vec3f(spot[1], spot[2], -60f0)                       # the darts not in this shot wait under the island
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        # s147 critic: each flight started from nothing. A launch rail on a post in the bay: the dart sits on it
        # through the hold and leaves it at 4 m/s (the throw speed of the simulation)
        wood = NG.Hikari.Diffuse(color = (0.50, 0.34, 0.20), roughness = 0.6f0)
        post = GeometryBasics.normal_mesh(Cylinder(Point3f(x0 - 0.2f0, lane, -0.4f0), Point3f(x0 - 0.2f0, lane, 2.44f0), 0.035f0))
        mesh!(gm.stage.scene, post; color = RGBf(0.50, 0.34, 0.20), name = :dart_rail_post, material = wood)
        rail = GeometryBasics.normal_mesh(Rect3f(Point3f(x0 - 0.45f0, lane - 0.025f0, 2.44f0), Vec3f(0.47f0, 0.05f0, 0.025f0)))
        mesh!(gm.stage.scene, rail; color = RGBf(0.50, 0.34, 0.20), name = :dart_rail, material = wood)
        S[:plots] = map(enumerate(flights)) do (i, f)
            mesh!(gm.stage.scene, f.mesh; color = RGBf(0.95, 0.93, 0.88), name = Symbol("paper_dart_", i),
                  material = NG.Hikari.Diffuse(color = (0.95, 0.93, 0.88), roughness = 0.8f0))
        end
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 8 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 12f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        seg = clamp(floor(Int, t / segment) + 1, 1, length(flights))
        treal = max(t - (seg - 1) * segment - hold, 0.0) / slow
        for (i, p) in enumerate(S[:plots])
            if i != seg
                Makie.translate!(p, away); continue
            end
            r = flights[i].r
            k = clamp(searchsortedlast(r.t, treal), 1, length(r.t))
            q = r.q[k]; pos = r.pos[k]
            Makie.rotate!(p, Makie.Quaternionf(q[2], q[3], q[4], q[1]))
            Makie.translate!(p, Vec3f(x0 + Float32(pos[1]), lane + Float32(pos[2]), Float32(pos[3])))
        end
        f = flights[seg]
        k = clamp(searchsortedlast(f.camt, treal), 1, length(f.camt))
        cx = x0 + Float32(f.camx[k]); cz = Float32(0.85 * f.camz[k] + 0.15 * 1.6)   # mostly follows the height
        rig.mode = :fixed
        # s147 critic: from the beach side the frame was open sea and cloud reflections, and the eye dipped to the water
        # on the dive. Now from the sea side looking at the island (the shore behind shows the motion), eye >= 1.2 m.
        rig.eye = Point3f(cx - 0.35f0, lane + side, max(cz + 0.5f0, 1.2f0))
        rig.target = Point3f(cx + 0.25f0, lane, cz + 0.15f0)
        return nothing
    end
    seconds = segment * length(flights)
    tmp = path * ".part.mp4"                # the posted film stays whole while the new one renders
    res = NG.game_clip(tmp; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    mv(tmp, path; force = true)
    return merge(res, (; path, bends = collect(bends), land_x = [round(f.r.pos[end][1], digits = 2) for f in flights],
                       airborne_s = [round(f.r.t[end], digits = 2) for f in flights]))
end
