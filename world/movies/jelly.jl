using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
nrm(v) = sqrt(sum(abs2, v))

"""
I swallow what I hit (s118): on an open patch of meadow in the late sun, I hop at Pinchy, the jelly swells round
us both and Pinchy floats inside me, turning, seen through the green glass, until a hiccup throws it out.
"""
function jelly_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24,
                    seconds = 8.5, hour = 17.3, tscale = 1.6, victim = "Pinchy")
    S = Dict{Any,Any}()
    isdefined(Main, :JELLY) || Core.eval(Main, :(const JELLY = Dict{Symbol,Any}()))
    J = Main.JELLY
    J[:force] = true
    shot = function (g, rig, t)
        w = g.world
        J[:force] = true
        if !haskey(S, :go)
            S[:go] = true
            isdefined(Main, :TIED) && (Main.TIED[:force] = false)
            d = Vec2f(cos(0.4f0), sin(0.4f0))      # the way the action runs (left to right in the frame)
            n = Vec2f(-d[2], d[1])                 # from the action toward the camera
            props = [Vec2f(p.pos[1], p.pos[2]) for p in w.props]
            best = Vec2f(0, 0); bs = -Inf32
            for x in -22f0:1f0:22f0, y in -22f0:1f0:22f0
                q = Vec2f(x, y)
                ok = all(NG.terrain_height(w.island, (q + s * d + c * n)...) > 0.6f0 for s in (-4f0, 0f0, 5f0), c in (-2f0, 0f0, 7f0))
                ok || continue
                # nothing between the camera and the action, nothing on the stage
                sc = 0f0
                for p in props
                    for s in -5f0:1f0:7f0, c in -2.5f0:1f0:7.5f0
                        nrm(p - (q + s * d + c * n)) < 1.6f0 && (sc -= 1f0)
                    end
                end
                sc -= 0.02f0 * nrm(q)
                sc > bs && (bs = sc; best = q)
            end
            S[:c0] = best; S[:d] = d; S[:n] = n
            l = first(c for c in w.creatures if c.species == "Lumi")
            v = first(c for c in w.creatures if c.name == victim)
            l.pos = NG.ground(w.island, ((best - 2.6f0 * d)...,))
            v.pos = NG.ground(w.island, (best...,))
            v.yaw = Float32(atan(n[2], n[1])) - NG.species_of(v).heading    # looking at us, unaware
            for c in (l, v)
                c.action = :idle
                c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
            # everyone else off the stage
            for c in w.creatures
                (c === l || c === v) && continue
                nrm(Vec2f(c.pos[1], c.pos[2]) - best) < 7 || continue
                q = best - 9f0 * n + Float32(c.id % 5) * d
                c.pos = NG.ground(w.island, (q...,))
            end
            S[:l] = l; S[:v] = v
            J[:tscale] = Float32(tscale); J[:toward] = n
        end
        if t >= 0.3 && !haskey(S, :started)
            S[:started] = true
            J[:swallow](g, S[:v])
        end
        c0, d, n = S[:c0], S[:d], S[:n]
        u = Float32(smooth(t / seconds))
        mid = c0 - d * (0.7f0 - 0.3f0 * u)
        eye_xy = mid + n * (4.4f0 - 0.8f0 * u)
        gz = NG.ground(w.island, (mid...,))[3]
        eye = Point3f(eye_xy[1], eye_xy[2], gz + 2.7f0 - 0.3f0 * u)
        tg = Point3f(mid[1], mid[2], gz + 0.95f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.5, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, c0 = S[:c0])
end
