using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

"""
The island has a ring (s120): a long day's junk already up (seeded on settled orbits, then integrated by the
plugin), a low afternoon sun, the camera on the shore looking up through the ring as it sweeps over; Pinchy
is thrown up next to the camera and goes off to join it.
"""
function ring_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24,
                   seconds = 10.0, hour = 16.8, n = 1300, CUT = 3.6)
    S = Dict{Any,Any}()
    isdefined(Main, :ORBIT) || Core.eval(Main, :(const ORBIT = Dict{Symbol,Any}()))
    O = Main.ORBIT
    O[:force] = true
    O[:size] = 2.2f0            # bigger junk, so it reads from far out
    isdefined(Main, :UNDERLIGHT) && (Main.UNDERLIGHT[:force] = false)   # a worker that just filmed the sun under the sea
    shot = function (g, rig, t)
        w = g.world
        O[:force] = true
        if !haskey(S, :go)
            S[:go] = true
            isdefined(Main, :TIED) && (Main.TIED[:force] = false)
            isdefined(Main, :JELLY) && (Main.JELLY[:force] = true)
            isdefined(Main, :DAYFALL) && haskey(Main.DAYFALL, :reset) && Main.DAYFALL[:reset]()
            O[:reset]()
            O[:seed](n)
            # Pinchy on the south shore, the camera behind it looking north and up
            p = first(c for c in w.creatures if c.name == "Pinchy")
            xy = Vec2f(2f0, -13f0)
            p.pos = NG.ground(w.island, (xy...,))
            p.action = :idle; p.goal = NG.Goal(:film, p.pos, :idle, 600.0, w.t + 600, true, 0, false)
            S[:p] = p
            # friends nearby, looking up
            k = 0
            for c in w.creatures
                c === p && continue
                k += 1
                k > 4 && break
                q = xy + Vec2f(-4f0 + 2.2f0 * k, 2.5f0 + 0.8f0 * (k % 2))
                c.pos = NG.ground(w.island, (q...,))
                c.yaw = Float32(pi / 2) - NG.species_of(c).heading
                c.action = :idle; c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
        end
        if t >= 1.0 && !haskey(S, :thrown)
            S[:thrown] = true
            O[:ride](g, S[:p]; laps = 99)
        end
        if t < CUT
            # shot 1: low on the meadow behind Pinchy, the ring's high side arching behind; follow it up
            O[:tscale] = 1f0
            pp = S[:p].pos
            eye = Point3f(-1.5f0, -19.5f0, NG.ground(w.island, (-1.5f0, -19.5f0))[3] + 1.2f0)
            tg = Point3f(pp[1], pp[2], pp[3] + 0.3f0)
            if haskey(S, :tg)
                tg = Point3f(S[:tg] + 0.35f0 * (tg - S[:tg]))
            end
        else
            # shot 2: far out, the whole tilted ring round the island, the sky running faster
            O[:tscale] = 4f0
            u = Float32(smooth((t - CUT) / (seconds - CUT)))
            a = -1.75f0 + 0.45f0 * u
            eye = Point3f(0.1f0 + 80f0 * cos(a), 0.5f0 + 80f0 * sin(a), 26f0 - 3f0 * u)
            tg = Point3f(0.1f0, 0.5f0, 3f0)
        end
        S[:eye] = eye; S[:tg] = tg
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return path
end
