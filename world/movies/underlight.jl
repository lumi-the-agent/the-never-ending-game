using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

"""
Lit from below (s116): the sun has sunk into the sea and shines up through the water. Friends stand at
the north shore looking down into the glow; the camera drifts low over the water towards them, the
tree crowns behind them lit from underneath.
"""
function underlight_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24,
                         seconds = 8.0, hour = 19.4, strength = 1.5)
    S = Dict{Any,Any}()
    isdefined(Main, :UNDERLIGHT) || Core.eval(Main, :(const UNDERLIGHT = Dict{Symbol,Any}()))
    Main.UNDERLIGHT[:force] = true
    Main.UNDERLIGHT[:strength] = strength
    lines = ("The sun fell in!", "It's shining UP!", "My chin is warm", "Is it coming back?", "Sun soup!", "Don't step on it!")
    shot = function (g, rig, t)
        w = g.world
        U = Main.UNDERLIGHT
        U[:force] = true
        dirv = Vec2f(-9.0f0, 19.5f0) / hypot(-9.0f0, 19.5f0)
        side = Vec2f(dirv[2], -dirv[1])
        if !haskey(S, :go)
            S[:go] = true
            d = 18.0f0
            while NG.ground(w.island, (dirv[1] * d, dirv[2] * d))[3] > 0.12f0
                d += 0.25f0
            end
            S[:d] = d
            names = ("Lumi", "Marshmallow", "Gloop", "Truffle", "Hopscotch")
            friends = [c for c in w.creatures if c.name in names || (c.species == "Lumi")]
            S[:friends] = friends
            face = atan(dirv[2], dirv[1])
            offs = (-2.4f0, -1.0f0, 0.3f0, 1.5f0, 2.8f0)
            for (k, c) in enumerate(friends[1:min(end, 5)])
                xy = dirv * (d - 0.9f0 - 0.4f0 * isodd(k)) + side * offs[k]
                c.pos = NG.ground(w.island, (xy[1], xy[2]))
                c.action = :idle
                c.yaw = Float32(face + 0.25 * (k - 3) * -1) - NG.species_of(c).heading
                c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
            S[:next] = 0.6; S[:k] = 0
        end
        for c in S[:friends]
            c.action = :idle
        end
        if t >= S[:next] && !isempty(S[:friends])
            S[:k] += 1
            c = S[:friends][mod1(S[:k] * 2, length(S[:friends]))]
            NG.say!(w, c, lines[mod1(S[:k], length(lines))]; duration = 1.6)
            S[:next] = t + 1.4
        end
        d = S[:d]
        u = Float32(smooth(t / seconds))
        c0 = dirv * (d - 1.0f0)
        eye_xy = dirv * (d + 7.0f0 - 2.5f0 * u) + side * (3.0f0 - 4.0f0 * u)
        eye = Point3f(eye_xy[1], eye_xy[2], 0.55f0 + 0.35f0 * u)
        tg = Point3f(c0[1] + side[1] * (0.6f0 - 1.2f0 * u), c0[2] + side[2] * (0.6f0 - 1.2f0 * u), 1.9f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.5, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, u = get(Main.UNDERLIGHT, :u, -1), dim = NG.SUN_DIM[])
end
