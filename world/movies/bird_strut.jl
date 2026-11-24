# Lumi's new moves (session 59): a strut, three fidgets, a run, a happy hop . Raster preview:
#   include("world/movies/bird_strut.jl"); bird_strut("media/s59/strut.mp4"; rasterize = true)
using NeverendingGame, Makie
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "tools", "lineup.jl"))    # open_spot (the worker runs scripts in a module without `include`)

function bird_strut(path; rasterize = true, samples = 48, width = 960, height = 540, fps = 24, seconds = 14.5)
    size = (width, height)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        bx, by = open_spot(w)
        b = only(filter(c -> c.species == "Lumi", w.creatures))
        b.controlled = true
        S[:b] = b; S[:start] = (bx - 2.2f0, by); S[:t0] = nothing
    end
    "A seed that starts fidget `f` at time T (u just past 0)."
    seedfor(f, T) = something(findfirst(s -> (r = NG.fidget(NG.PoseCtx(:idle, 0f0, 0f0, 0f0, s, T, 1f0)); r[1] == f && r[2] < 0.02f0),
                                        0f0:0.0001f0:1f0), 1) * 0.0001f0
    # (until, action, fidget): strut in, preen, peek at the sky, tap a foot, a short run, a happy hop
    plan = [(3.0, :walk, 0), (5.6, :idle, 1), (8.2, :idle, 2), (10.8, :idle, 3), (12.0, :run, 0), (14.5, :proud, 0)]
    shot = function (g, rig, t)
        w = g.world; b = S[:b]
        x0, y = S[:start]
        k = something(findfirst(p -> t < p[1], plan), length(plan))
        _, a, f = plan[k]
        if get(S, :seg, 0) != k                         # a new segment starts now
            S[:seg] = k
            f > 0 && (b.seed = seedfor(f, Float32(w.t) + 0.3f0))
            S[:x] = get(S, :x, 0f0)
        end
        if a === :walk || a === :run
            v = a === :walk ? 1.0f0 : 1.6f0
            S[:x] += v / Float32(fps)
            b.phase = 8f0 * S[:x]
        end
        b.pos = NG.ground(w.island, (x0 + 0.94f0 * S[:x], y - 0.34f0 * S[:x]))   # walking where it faces (yaw -0.35)
        b.action = a; b.mood = a === :idle ? 0.3f0 : 0.9f0
        b.yaw = -0.35f0
        NG.sync!(g.stage, w)
        p = NG.ground(w.island, (x0 + 0.9f0 + 0.7f0 * S[:x], y - 0.25f0 * S[:x]))   # the camera drifts along a little
        rig.mode = :fixed; rig.eye = p + Point3f(0.4f0, -4.4f0, 0.95f0); rig.target = p + Point3f(0, 0, 0.85f0)
        return nothing
    end
    NG.game_clip(path; size, seconds, fps, samples, hour = 10.5, warmup = 2, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
