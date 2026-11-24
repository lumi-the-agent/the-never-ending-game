# The little one's first flying lesson (session 71). Worker job:
#   submit_job(:clip; path, script = "movies/flylesson.jl", call = "lesson_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function lesson_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24,
                     seconds = 14.0, hour = 10.5)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Wibbles", "Truffle", "Pinchy")
        spots = ((-1.2f0, 2.6f0), (1.6f0, 2.8f0), (3.4f0, 2.0f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = 0f0; c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast && k < length(spots)
                k += 1
                o = spots[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2])); c.yaw = Float32(-pi / 2)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = NG.ground(w.island, (x + 0.6f0, y))
    end
    shot = function (g, rig, t)
        if !haskey(S, :sys)
            m = g.plugins["flylesson"].mod
            S[:sys] = sys = only(g.plugins["flylesson"].systems)
            ch = Main.EGG[:chick]
            ch[:hatched] = true                    # a quiet copy never loads the saved chick
            S[:lumi].yaw = 0f0
            ok = Base.invokelatest(m.begin!, sys, g, S[:lumi])
            ok || error("the lesson did not start")
        end
        sys = S[:sys]
        c = S[:c]
        rig.mode = :fixed
        rig.eye = c + Point3f(0.2f0, -3.8f0, 1.45f0)
        rig.target = c + Point3f(0, 0, 1.0f0)
        sys.state === :ride && t > 10 && return t + 3.0
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
