using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

"""
Football with the sun (s122): the sun drops out of the sky onto the meadow as a glowing ball, the only light
on a dusky island, and the friends kick it about; every kick swings every shadow. The lens stays low, a few
metres behind the ball, and follows it.
"""
function sunball_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24,
                      seconds = 10.0, hour = 12.4, strength = 30.0, spot = (2.0, 3.0), drop = 9.0)
    S = Dict{Any,Any}()
    isdefined(Main, :SUNBALL) || Core.eval(Main, :(const SUNBALL = Dict{Symbol,Any}()))
    Main.SUNBALL[:force] = true
    Main.SUNBALL[:strength] = strength
    shot = function (g, rig, t)
        w = g.world
        SB = Main.SUNBALL
        SB[:force] = true
        s = get(SB, :sys, nothing)
        if !haskey(S, :go) && s !== nothing && s.on
            S[:go] = true
            x, y = Float32(spot[1]), Float32(spot[2])
            s.pos = Point3f(x, y, NG.ground(w.island, (x, y))[3] + Float32(drop)); s.vel = Vec3f(0.6, -0.3, 0)
            names = ("Lumi", "Pinchy", "Truffle", "Gloop", "Marshmallow")
            friends = [c for c in w.creatures if c.name in names]
            for (k, c) in enumerate(friends)
                a = 2pi * k / length(friends)
                xy = (x + 3.2f0 * cos(a), y + 3.2f0 * sin(a))
                c.pos = NG.ground(w.island, xy)
                c.yaw = Float32(atan(y - xy[2], x - xy[1])) - NG.species_of(c).heading
                c.goal = NG.Goal(:sunball, Point3f(x, y, 0), :play, 1.0, Inf, false, 0, true)
            end
            S[:eye] = Point3f(x - 5.5f0, y - 3.5f0, NG.ground(w.island, (x, y))[3] + 1.6f0)
            S[:tg] = Point3f(x, y, NG.ground(w.island, (x, y))[3] + 0.8f0)
        end
        haskey(S, :go) || return seconds - 0.1
        b = s.pos
        gz = NG.ground(w.island, (b[1], b[2]))[3]
        want_tg = Point3f(b[1], b[2], max(gz + 0.7f0, min(b[3], gz + 3f0)))
        want_eye = Point3f(b[1] - 5.0f0, b[2] - 3.2f0, gz + 1.5f0)
        k = 1f0 - exp(-2.5f0 / 24f0)
        S[:tg] = S[:tg] + (want_tg - S[:tg]) * k
        S[:eye] = S[:eye] + (want_eye - S[:eye]) * (k * 0.6f0)
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = S[:tg]
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    Main.SUNBALL[:force] = false
    return (path = path, pos = get(Main.SUNBALL, :pos, nothing), dim = NG.SUN_DIM[])
end
