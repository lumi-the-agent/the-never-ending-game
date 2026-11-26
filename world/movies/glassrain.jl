using NeverendingGame, Makie
const NG = NeverendingGame

"""
Glass rain (s123): a shower of glass drops over the west meadow in the afternoon sun. Each drop is a little
lens (Hikari Glass) and throws a bright spot onto the grass; the friends chase the spots and pounce.
The lens stays low across the shower, side-lit by the sun, and drifts slowly round it.
"""
function glassrain_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24,
                        seconds = 10.0, hour = 15.2, strength = 10.0, spot = (-9.5, -0.5), dist = 3.8, up = 1.1)
    S = Dict{Any,Any}()
    for nm in (:GLASSRAIN, :SUNBALL)
        isdefined(Main, nm) || Core.eval(Main, :(const $nm = Dict{Symbol,Any}()))
    end
    Main.GLASSRAIN[:force] = true
    Main.GLASSRAIN[:spot] = (Float32(spot[1]), Float32(spot[2]))
    Main.GLASSRAIN[:strength] = strength
    Main.SUNBALL[:force] = false
    shot = function (g, rig, t)
        w = g.world
        Main.GLASSRAIN[:force] = true
        x, y = Float32(spot[1]), Float32(spot[2])
        gz = NG.ground(w.island, (x, y))[3]
        if !haskey(S, :go)
            S[:go] = true
            isdefined(Main, :TIED) && (Main.TIED[:force] = false)
            isdefined(Main, :UNDERLIGHT) && (Main.UNDERLIGHT[:force] = false; Main.UNDERLIGHT[:u] = 0.0)
            isdefined(Main, :JELLY) && (Main.JELLY[:force] = false)
            isdefined(Main, :ORBIT) && haskey(Main.ORBIT, :reset) && Main.ORBIT[:reset]()
            names = ("Pinchy", "Truffle", "Gloop", "Marshmallow", "Lumi")
            friends = [c for c in w.creatures if c.name in names]
            for (k, c) in enumerate(friends)
                a = 2pi * k / length(friends) + 0.4
                xy = (x + 1.8f0 * cos(a), y + 1.8f0 * sin(a))
                c.pos = NG.ground(w.island, xy)
                c.goal = NG.Goal(:glassrain, Point3f(x, y, 0), :play, 1.0, Inf, false, 0, true)
            end
            sd = NG.sun(w)[1]
            S[:a0] = atan(sd[2], sd[1]) + Float32(pi / 2)      # across the sun: the drops side-lit, the spots on the grass
        end
        a = S[:a0] + 0.45 * clamp(t / seconds, 0, 1)
        eye = Point3f(x + dist * cos(a), y + dist * sin(a), gz + up)
        tg = Point3f(x - 0.4f0 * cos(a), y - 0.4f0 * sin(a), gz + 0.35f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 2.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    Main.GLASSRAIN[:force] = false
    return (path = path, dots = length(get(Main.GLASSRAIN, :dots, [])))
end
