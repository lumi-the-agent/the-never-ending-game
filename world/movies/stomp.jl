using NeverendingGame, Makie
const NG = NeverendingGame

"""
One stomp bounces the whole island (s125): I stomp in the middle of the friends, a ring runs out through the
ground and throws them, and every landing rings again (plugins/stomp.jl, a wave equation under the meadow).
The lens stands high and to the side of the sun so the rings are lit from the side, and pushes in slowly.
"""
function stomp_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24,
                    seconds = 10.0, hour = 16.6, spot = (-6.0, -4.0), dist = 12.0, up = 7.5, turn = 0.5, at = 0.8)
    isdefined(Main, :STOMP) || Core.eval(Main, :(const STOMP = Dict{Symbol,Any}()))
    S = Dict{Any,Any}()
    shot = function (g, rig, t)
        w = g.world
        x, y = Float32(spot[1]), Float32(spot[2])
        gz = NG.ground(w.island, (x, y))[3]
        if !haskey(S, :go)
            S[:go] = true
            isdefined(Main, :TIED) && (Main.TIED[:force] = false)
            isdefined(Main, :UNDERLIGHT) && (Main.UNDERLIGHT[:force] = false; Main.UNDERLIGHT[:u] = 0.0)
            isdefined(Main, :JELLY) && (Main.JELLY[:force] = false)
            isdefined(Main, :GLASSRAIN) && (Main.GLASSRAIN[:force] = false)
            isdefined(Main, :SUNBALL) && (Main.SUNBALL[:force] = false)
            isdefined(Main, :GROUNDWHALE) && (Main.GROUNDWHALE[:force] = false)
            isdefined(Main, :ORBIT) && haskey(Main.ORBIT, :reset) && Main.ORBIT[:reset]()
            friends = [c for c in w.creatures if c.name != "Lumi"]
            for (k, c) in enumerate(friends)
                a = 2pi * k / length(friends); d = 2.5f0 + 1.2f0 * (k % 3)
                c.pos = NG.ground(w.island, (x + d * cos(a), y + d * sin(a)))
                c.goal = NG.Goal(:stomp, c.pos, :idle, 30.0, w.t + 30, true, 0, false)
            end
            me = findfirst(c -> c.name == "Lumi", w.creatures)
            me === nothing || (w.creatures[me].pos = NG.ground(w.island, (x, y)))
            sd = NG.sun(w)[1]
            S[:a0] = atan(sd[2], sd[1]) + Float32(turn * pi)
        end
        if t >= at && !haskey(S, :stomped)
            S[:stomped] = true
            Main.STOMP[:at] = (x, y)
            Main.STOMP[:force] = true
        end
        k = clamp(t / seconds, 0, 1)
        a = S[:a0] + 0.25 * k
        d = dist * (1 - 0.18 * k)
        eye = Point3f(x + d * cos(a), y + d * sin(a), gz + up * (1 - 0.15 * k))
        tg = Point3f(x, y, gz + 0.8f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 2.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, thumps = haskey(Main.STOMP, :sys) ? Main.STOMP[:sys].sources : -1)
end
