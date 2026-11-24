# The Great Paint Fight (session 68): Lumi wobbles under three paint pots, trips, SPLOOSH, and the
# friends around it break into a paint fight. Worker job:
#   submit_job(:clip; path, script = "movies/paintfight.jl", call = "paintfight_clip",
#              kwargs = Dict("spot" => [x, y], "rasterize" => false, "samples" => 24))
using NeverendingGame, Makie
const NG = NeverendingGame

function paintfight_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24,
                         seconds = 17.0, hour = 10.5)
    size = (width, height)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        # spots left from an earlier copy in this process (the worker keeps Main between jobs)
        isdefined(Main, :PAINT) && for k in (:spots, :until)
            haskey(Main.PAINT, k) && empty!(Main.PAINT[k])
        end
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Hopscotch", "Pickles", "Sir Sniffsalot")
        # the friends stand about Lumi in a loose ring, the open side towards the camera (south)
        ring = ((-2.6f0, 1.6f0), (0.2f0, 3.0f0), (2.8f0, 1.8f0), (3.4f0, -0.6f0), (-3.4f0, -0.4f0),
                (1.4f0, 4.6f0), (-1.6f0, 4.2f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = -pi / 2f0; c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast && k < length(ring)
                k += 1
                o = ring[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2]))
                c.yaw = atan(-o[2], -o[1])
                c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false); c.controlled = false
            else      # everyone else is out of the picture
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = Point3f(x, y + 1.4f0, NG.ground(w.island, (x, y + 1.4f0))[3])
    end
    shot = function (g, rig, t)
        if !haskey(S, :sys)           # the plugins start with the first step, after setup
            S[:mod] = m = g.plugins["paintfight"].mod
            S[:sys] = sys = only(g.plugins["paintfight"].systems)
            empty!(Main.PAINT[:spots]); empty!(Main.PAINT[:until]); empty!(Main.PAINT[:splat])
            Base.invokelatest(m.begin!, sys, g, S[:lumi]; least = 2)
        end
        sys = S[:sys]
        # the film keeps its pace: the fight ends after ~8 s of throwing
        sys.state === :fight && t > 14.0 && (sys.t0 = g.world.t - 100)
        c = S[:c]
        # close on Lumi wobbling, then a pull back as the paint flies
        pull = Float32(clamp((t - 2.0) / 3.0, 0, 1))
        pull = pull * pull * (3 - 2pull)
        rig.mode = :fixed
        rig.eye = c + Point3f(0.6f0 + 0.08f0 * Float32(t), -5.6f0 - 2.4f0 * pull, 1.7f0 + 1.3f0 * pull)
        rig.target = c + Point3f(0.08f0 * Float32(t), 0, 1.0f0 - 0.4f0 * (1 - pull))
        sys.state === :idle && t > 8 && return t + 0.5
        return nothing
    end
    NG.game_clip(path; size, seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
