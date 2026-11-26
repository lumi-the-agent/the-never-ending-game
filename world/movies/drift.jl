# The island drifts (session 109, plugins/drift.jl): from high behind the stern, the whole island sailing on, its
# wake of foam peeling off the shore below, islets sliding by on both sides, the crew small at the bow.
#   submit_job(:clip; path, script = "movies/drift.jl", call = "drift_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function drift_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 14.0)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        D = Main.DRIFT
        if !haskey(S, :go)
            S[:go] = true
            Base.invokelatest(g.plugins["drift"].mod.start_drift!, g)
        end
        if !haskey(S, :run)
            S[:run] = true
            D[:t0] = w.t - 20.0        # already under way: no ease-in in the film
        end
        d = D[:dir]::Point2f; sd = Point2f(-d[2], d[1])
        # s110 (review #534): the camera swings slowly round from behind the stern to the beam, so the wake's V, the
        # passing palm islets and the island all move in the picture
        u = Float32(clamp(t / seconds, 0, 1)); u = u * u * (3 - 2u)
        th = 0.35f0 + 0.85f0 * u
        e = -d * (38f0 * cos(th)) + sd * (38f0 * sin(th))
        eye = Point3f(e[1], e[2], 15f0 - 3f0 * u)
        tg = Point3f(6f0 * d[1], 6f0 * d[2], 0f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
