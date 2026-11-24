# Steady films test (todo #402): three friends stand still in front of a fixed camera for a few seconds;
# tools/steady_measure.py tracks how far the sheep moves between frames (the human saw it jump several px).
using NeverendingGame, Makie
const NG = NeverendingGame

function steady_clip(path; spot, rasterize = true, samples = 16, width = 480, height = 270, fps = 24, seconds = 2.5, hour = 10.5,
                     walk_into = nothing)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Cumulus", "Truffle", "Gloop")
        offs = ((0f0, 0f0), (-1.6f0, 0.8f0), (1.6f0, 0.8f0))
        k = 0
        for c in w.creatures
            if c.name in cast
                k += 1
                c.pos = NG.ground(w.island, (x + offs[k][1], y + offs[k][2])); c.yaw = Float32(-pi / 2)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = NG.ground(w.island, (x, y))
        # `walk_into = [x, y]`: the sheep is sent at a spot inside a solid (a rock's centre) and must come to rest at its edge
        if walk_into !== nothing
            sheep = first(filter(c -> c.name == "Cumulus", w.creatures))
            sheep.goal = NG.Goal(:wander, NG.ground(w.island, (Float32(walk_into[1]), Float32(walk_into[2]))), :idle, 600.0, w.t + 600, false, 0, false)
        end
    end
    shot = function (g, rig, t)
        c = S[:c]
        rig.mode = :fixed
        rig.eye = c + Point3f(0, -5.5f0, 1.6f0)
        rig.target = c + Point3f(0, 0, 0.6f0)
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
