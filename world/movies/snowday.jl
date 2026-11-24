# Snow day (session 72): out of a sunny sky it snows, the meadow turns white, the friends hop about and Lumi
# rolls a little snow-Lumi. Worker job:
#   submit_job(:clip; path, script = "movies/snowday.jl", call = "snow_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function snow_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 14.0, hour = 11.0)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Wibbles", "Truffle", "Pinchy", "Cumulus", "Hopscotch")
        ring = ((-1.6f0, 2.4f0), (1.0f0, 3.0f0), (3.4f0, 2.4f0), (-2.6f0, 0.6f0), (4.4f0, 0.8f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = 0f0; c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast && k < length(ring)
                k += 1
                o = ring[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2])); c.yaw = Float32(-pi / 2)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = NG.ground(w.island, (x + 0.75f0, y))
    end
    shot = function (g, rig, t)
        if !haskey(S, :sys)
            m = g.plugins["snowday"].mod
            S[:sys] = sys = only(g.plugins["snowday"].systems)
            Main.SNOWDAY[:speed] = 2.5
            S[:lumi].yaw = 0f0
            S[:lumi].goal = NG.Goal(:idle, S[:lumi].pos, :idle, 600.0, g.world.t + 600, true, 0, false)
            Base.invokelatest(m.begin!, sys, g)
        end
        # Lumi stays at its spot until it starts the snowman (the first gasp let it wander off, preview 1)
        sys = S[:sys]
        if sys.built < 0
            haskey(S, :at) || (S[:at] = S[:lumi].pos)
            S[:lumi].pos = S[:at]; S[:lumi].yaw = 0f0
        end
        c = S[:c]
        rig.mode = :fixed
        rig.eye = c + Point3f(0.6f0, -4.6f0, 1.7f0)
        rig.target = c + Point3f(0, 0.3f0, 0.75f0)
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
