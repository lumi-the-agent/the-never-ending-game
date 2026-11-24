# Lumi's egg (session 70): a golden egg, the friends gather, it wobbles, CRACK, a tiny Lumi hops out. Worker job:
#   submit_job(:clip; path, script = "movies/egg.jl", call = "egg_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function egg_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24,
                  seconds = 13.5, hour = 10.5)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Hopscotch")
        ring = ((-2.2f0, 0.8f0), (2.2f0, 0.8f0), (-2.8f0, 1.8f0), (2.8f0, 1.8f0), (-1.4f0, 2.4f0), (1.4f0, 2.4f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = Float32(-pi / 2); c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast && k < length(ring)
                k += 1
                o = ring[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2]))
                c.yaw = atan(-o[2], -o[1])
                c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:egg] = NG.ground(w.island, (x, y - 1.3f0))
    end
    shot = function (g, rig, t)
        if !haskey(S, :sys)
            m = g.plugins["egg"].mod
            S[:sys] = sys = only(g.plugins["egg"].systems)
            S[:lumi].yaw = Float32(-pi / 2)
            Base.invokelatest(m.begin!, sys, g, S[:lumi]; least = 2)
            w = g.world
            # the watchers start at their places by the egg (walking there, two crossed the foreground in take 1)
            for id in sys.friends
                c = NG.creature(w, id)
                c.pos = c.goal.target; c.goal.arrived = true; c.goal.until = w.t + 60
                c.yaw = atan(S[:egg][2] - c.pos[2], S[:egg][1] - c.pos[1])
            end
            # friends busy with something else wandered through the foreground (s70 preview): out of the picture
            for c in w.creatures
                (c.name == "Lumi" || c.id in sys.friends || c.controlled) && continue
                c.pos = NG.ground(w.island, (S[:egg][1] + 14f0, S[:egg][2] + 12f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        sys = S[:sys]
        e = S[:egg]
        # a slow push in on the egg while it wobbles, held through the hatch
        k = Float32(clamp((t - 2.5) / 6.0, 0, 1))
        k = k * k * (3 - 2k)
        rig.mode = :fixed
        rig.eye = e + Point3f(0.4f0, -(4.6f0 - 1.6f0 * k), 1.6f0 - 0.5f0 * k)
        rig.target = e + Point3f(0, 0.55f0, 0.55f0)
        sys.state === :idle && t > 6 && return t + 1.0
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
