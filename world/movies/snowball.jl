# A snowball that grows as it rolls (s140, project snowball): a 12 cm layer of snow on an open slope,
# Lumi gives a small ball a push at (14,-6) and it rolls east and down
# into the sea (7 m, 1.4 m clear of every prop), filmed from the uphill side with the sea behind, peeling the snow to the grass and growing from what it took.
# The roll is physics/snowball.jl over the island's own ground (Bekker sinkage, mass and inertia from the snow).
#   submit_job(:clip; path, script = "movies/snowball.jl", call = "snowball_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics, LinearAlgebra
const NG = NeverendingGame
const SB = Module(:SnowballPhysics)
Base.include(SB, joinpath(@__DIR__, "..", "physics", "snowball.jl"))

function snowball_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24, seconds = 9.0,
                       hour = 10.0, start = (14.0, -6.0), dir = (1.0, 0.0), depth = 0.12, cell = 0.06,
                       area = (11.5, -11.5, 12.0, 10.5), push = 15.0, t0 = 1.0, side = -4.8, up = 2.2)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        H(x, y) = Float64(NG.ground(w.island, (Float32(x), Float32(y)))[3])
        x0, y0, wx, wy = area
        nx, ny = round(Int, wx / cell), round(Int, wy / cell)
        f = SB.Snowball.Field(x0, y0, cell, fill(depth, nx, ny))
        tr = SB.Snowball.roll(H, f; start, v0 = 0.3 .* dir, push, push_s = 1.5, seconds = seconds - t0 + 0.1)
        S[:f] = f; S[:tr] = tr; S[:H] = H
        # rotation per track sample: small turns about the horizontal axis across the motion
        q = Quaternionf(0, 0, 0, 1); Q = Quaternionf[]
        for k in eachindex(tr.t)
            k > 1 && (q = Makie.qrotation(Vec3f(tr.axis[k][1], tr.axis[k][2], 0), Float32(tr.angle[k] - tr.angle[k-1])) * q)
            push!(Q, q)
        end
        S[:Q] = Q
        # the snow sheet: one vertex per cell, at ground + depth, sunk below the ground where peeled
        S[:G] = [H(x0 + (i - 0.5) * cell, y0 + (j - 0.5) * cell) for i in 1:nx, j in 1:ny]
        F = TriangleFace{Int}[]
        L = LinearIndices((nx, ny))
        for i in 1:nx-1, j in 1:ny-1
            push!(F, TriangleFace(L[i, j], L[i+1, j], L[i+1, j+1]), TriangleFace(L[i, j], L[i+1, j+1], L[i, j+1]))
        end
        S[:F] = F
        S[:snow] = mesh!(g.stage.scene, snowmesh(S, 0.0); color = RGBf(0.95, 0.96, 1.0), name = :snowball_snow)
        ball = GeometryBasics.normal_mesh(GeometryBasics.Tesselation(GeometryBasics.Sphere(Point3f(0), 1f0), 48))
        S[:ball] = meshscatter!(g.stage.scene, [Point3f(start..., H(start...) + 0.13)]; marker = ball,
                                markersize = 0.13f0, rotation = Q[1], color = RGBf(0.93, 0.94, 0.98),
                                name = :snowball_ball)
        me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, (Float32(start[1] - 0.9dir[1]), Float32(start[2] - 0.9dir[2])))
        me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        # friends far off so nobody walks into the shot
        for c in w.creatures
            c.name == "Lumi" && continue
            c.pos = NG.ground(w.island, (Float32(c.pos[1] + 40), Float32(c.pos[2] - 40)))
            c.controlled = true; c.goal = NG.Goal(); c.action = :idle       # and they stay there
        end
        @info "snowball: r $(round(tr.r[1]; digits = 2)) -> $(round(tr.r[end]; digits = 2)) m, $(round(tr.m[end]; digits = 1)) kg"
    end
    shot = function (g, rig, t)
        tr = S[:tr]; f = S[:f]
        ts = max(t - t0, 0.0)
        k = clamp(searchsortedlast(tr.t, ts), 1, length(tr.t))
        x, y, r = tr.x[k], tr.y[k], tr.r[k]
        z = S[:H](x, y) + r - 0.5tr.sink[k]
        Makie.update!(S[:ball]; arg1 = [Point3f(x, y, z)], markersize = Float32(r), rotation = S[:Q][k])
        S[:snow][1][] = snowmesh(S, ts)
        me = NG.creature(g.world, "Lumi"); me.controlled = true
        me.action = t < t0 + 1.2 ? :wave : :idle
        rig.mode = :fixed
        cx, cy = start[1] + 3.5dir[1], start[2] + 3.5dir[2]       # the middle of the run
        nx, ny = dir[2], -dir[1]                                   # to the right of the run
        rig.eye = Point3f(cx + side * nx, cy + side * ny, S[:H](cx, cy) + up)
        rig.target = Point3f(0.6cx + 0.4x, 0.6cy + 0.4y, S[:H](x, y) + 0.3)
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end

function snowmesh(S, ts)
    f = S[:f]; Gd = S[:G]; nx, ny = size(f.depth)
    V = Vector{Point3f}(undef, nx * ny)
    L = LinearIndices((nx, ny))
    for i in 1:nx, j in 1:ny
        d = f.peeled[i, j] <= ts ? -0.03 : (isfinite(f.peeled[i, j]) ? 0.12 : f.depth[i, j])
        V[L[i, j]] = Point3f(f.x0 + (i - 0.5) * f.h, f.y0 + (j - 0.5) * f.h, Gd[i, j] + d)
    end
    return GeometryBasics.mesh(V, S[:F]; normal = GeometryBasics.normals(V, S[:F]))
end
