# Giant Lumi (session 69): a golden mushroom, *munch*, Lumi grows five times taller than the trees,
# friends scatter, three ride on its back, POP. Worker job:
#   submit_job(:clip; path, script = "movies/giant.jl", call = "giant_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function giant_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24,
                    seconds = 17.0, hour = 10.5)
    size = (width, height)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Hopscotch", "Pickles")
        # friends about Lumi, most of them between Lumi and the camera (south) and at the sides
        ring = ((-2.4f0, -1.6f0), (1.8f0, -2.4f0), (3.2f0, 0.4f0), (-3.2f0, 0.6f0), (0.4f0, -3.4f0),
                (2.2f0, 2.2f0), (-2.0f0, 2.4f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = 0f0; c.goal = NG.Goal(); c.controlled = false
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
        S[:c] = NG.ground(w.island, (x, y))
    end
    shot = function (g, rig, t)
        if !haskey(S, :sys)
            S[:mod] = m = g.plugins["giant"].mod
            S[:sys] = sys = only(g.plugins["giant"].systems)
            S[:lumi].yaw = 0f0          # facing east: the camera in the south sees its side and the riders
            Base.invokelatest(m.begin!, sys, g, S[:lumi]; least = 2)
        end
        sys = S[:sys]
        sys.state === :giant && t > 13.0 && (sys.t0 = g.world.t - 100)
        c = S[:c]
        s = sys.s
        # from the side (Lumi faces east): the riders on its back in view; back off as it grows
        rig.mode = :fixed
        rig.eye = c + Point3f(-1.0f0 + 0.6f0 * s, -(5.5f0 + 3.1f0 * s), 1.4f0 + 0.8f0 * s)
        rig.target = c + Point3f(0.3f0 * s, 0, 0.7f0 + 0.8f0 * s)
        sys.state === :idle && t > 8 && return t + 0.4
        return nothing
    end
    NG.game_clip(path; size, seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
