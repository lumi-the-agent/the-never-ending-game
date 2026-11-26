using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
nrm(v) = sqrt(sum(abs2, v))

"""
My shadow quits (s121, the real-light sequel to s95's "My shadow ran off"): a long shadow of me walks across the
evening meadow with nobody casting it. It is my real shadow: my body walks the same path, but drawn high up the sun's
ray behind the camera, where no lens sees it, so the sun throws a true shadow that bends over grass and friends.
A friend it walks over jumps. `D` = how far up the sun ray my body is hung.
"""
function quits_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24,
                    seconds = 11.0, hour = 17.6, D = 15f0, back = 7.5f0, friend = "Pinchy", friend2 = "Truffle", spot = nothing,
                    track = false, cam_back = 4.5f0, cam_up = 2.4f0)
    S = Dict{Any,Any}()
    shot = function (g, rig, t)
        w = g.world
        if !haskey(S, :go)
            S[:go] = true
            if isdefined(Main, :SEESAW) && haskey(Main.SEESAW, :sys)
                for c in w.creatures
                    Main.SEESAW[:weights][c.id] = 0f0
                end
                Main.SEESAW[:sys].tilt = Vec2f(0); Main.SEESAW[:sys].spin = Vec2f(0)
            end
            if isdefined(Main, :WORDSAND) && haskey(Main.WORDSAND, :H)
                Main.WORDSAND[:H] .= 0; Main.WORDSAND[:dirty] = true; Main.WORDSAND[:gain] = 0f0
            end
            isdefined(Main, :TIED) && (Main.TIED[:force] = false)
            isdefined(Main, :UNDERLIGHT) && (Main.UNDERLIGHT[:force] = false; Main.UNDERLIGHT[:u] = 0.0)   # a still before may have left the sun under the sea
            isdefined(Main, :ORBIT) && haskey(Main.ORBIT, :reset) && Main.ORBIT[:reset]()
            isdefined(Main, :JELLY) && (Main.JELLY[:force] = false)
            sd = NG.sun(w)[1]
            s = Vec3f(sd ./ nrm(sd))                          # toward the sun
            sh = Vec2f(s[1], s[2]); sh = sh / nrm(sh)         # toward the sun, flat
            side = Vec2f(-sh[2], sh[1])                       # the way I walk: across the frame
            props = [Vec2f(p.pos[1], p.pos[2]) for p in w.props]
            best = Vec2f(0, 0); bs = -Inf32
            for x in (spot === nothing ? (-24f0:1f0:24f0) : (Float32(spot[1]):1f0:Float32(spot[1]))), y in (spot === nothing ? (-24f0:1f0:24f0) : (Float32(spot[2]):1f0:Float32(spot[2])))
                q = Vec2f(x, y)
                # the stage (walk line +-6 m, 5 m deep away from the sun) and the camera spot on land
                # the stage is dry open sand (a beach: bright, flat, nothing on it), the lens on land behind it
                ok = spot !== nothing || all(0.08f0 < NG.terrain_height(w.island, (q + a * side - b * sh)...) < 0.7f0 for a in (-5f0, 0f0, 5f0), b in (0f0, 2.5f0))
                ok = ok && NG.terrain_height(w.island, (q + back * sh)...) > 0.1f0
                ok || continue
                sc = 0f0
                for p in props
                    for a in -5f0:1f0:5f0
                        for b in -1f0:1f0:4f0              # nothing on the stage
                            nrm(p - (q + a * side - b * sh)) < 1.2f0 && (sc -= 1f0)
                        end
                        for k in 1f0:1f0:back + 1          # nor between it and the lens
                            nrm(p - (q + a * 0.4f0 * side + k * sh)) < 2.5f0 && (sc -= 3f0)
                        end
                        for k in back + 1:2f0:D + 3f0      # and little shading my hidden body
                            nrm(p - (q + a * side + k * sh)) < 2.5f0 && (sc -= 0.3f0)
                        end
                    end
                end
                h = NG.terrain_height(w.island, q...)
                for a in -5f0:2.5f0:5f0, b in 0f0:1.5f0:3f0   # flat ground, so the shadow is not torn
                    sc -= abs(NG.terrain_height(w.island, (q + a * side - b * sh)...) - h)
                end
                sc -= 0.01f0 * nrm(q)
                sc > bs && (bs = sc; best = q)
            end
            S[:c0] = best; S[:s] = s; S[:sh] = sh; S[:side] = side; S[:score] = bs
            l = first(c for c in w.creatures if c.species == "Lumi")
            S[:l] = l
            l.action = :walk
            l.goal = NG.Goal(:film, l.pos, :idle, 600.0, w.t + 600, true, 0, false)
            # friends sit just beyond the walk line, where my shadow will cover them
            f1 = first(c for c in w.creatures if c.name == friend)
            f2 = first(c for c in w.creatures if c.name == friend2)
            for (c, a) in ((f1, -0.2f0), (f2, 3.2f0))
                q = best + a * side - 1.6f0 * sh
                c.pos = NG.ground(w.island, (q...,))
                c.yaw = Float32(atan(sh[2], sh[1])) - NG.species_of(c).heading   # facing the lens, unaware
                c.action = :idle
                c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
            S[:f] = [(f1, -0.2f0), (f2, 3.2f0)]; S[:jumped] = Set{String}()
            S[:pin] = [(c, c.pos, c.yaw) for c in (f1, f2)]
            for c in w.creatures
                (c === l || c === f1 || c === f2) && continue
                p2 = Vec2f(c.pos[1], c.pos[2])
                (nrm(p2 - best) < 12 || nrm(p2 - (best + 10f0 * sh)) < 9) || continue
                q = best - 14f0 * sh + Float32(c.id % 7 - 3) * 2f0 * side
                NG.on_land(w.island, q[1], q[2]; margin = 0.3) || (q = best - 9f0 * sh + Float32(c.id % 7 - 3) * 2.5f0 * side)
                c.pos = NG.ground(w.island, (q...,))
            end
            S[:a] = -7.5f0
            S[:t] = t
        end
        c0, s, sh, side, l = S[:c0], S[:s], S[:sh], S[:side], S[:l]
        dt = Float32(t - S[:t]); S[:t] = t
        # the walk: in from the left, a stop over Pinchy, a look round, then on and out on the right
        v = t < 4.2 ? 1.25f0 : t < 6.2 ? 0f0 : 1.35f0
        S[:a] += v * dt
        a = S[:a]
        G = NG.ground(w.island, ((c0 + a * side)...,))
        hop = 6.2 < t < 7.4 ? Float32(0.55 * abs(sin(pi * (t - 6.2) / 0.6))) : 0f0
        l.pos = Point3f(G[1] + D * s[1], G[2] + D * s[2], G[3] + D * s[3] + hop)
        dir = 4.4 < t < 6.0 ? Vec2f(-side[1] * 0.2f0 - sh[1], -side[2] * 0.2f0 - sh[2]) : side   # turns toward the lens
        l.yaw = Float32(atan(dir[2], dir[1])) - NG.species_of(l).heading
        sp = NG.species_of(l)
        if v > 0
            l.phase += min(sp.stride * v * dt, NG.GAIT_MAX * dt); l.action = :walk
        else
            l.action = hop > 0 ? :jump : :idle
        end
        l.goal = NG.Goal(:film, l.pos, :idle, 600.0, w.t + 600, true, 0, false)
        # the friends stay where they sit (other plugins send them off otherwise), until my shadow scares them
        for (c, p0, y0) in S[:pin]
            c.name in S[:jumped] && continue
            c.pos = p0; c.yaw = y0; c.action = :idle
            c.goal = NG.Goal(:film, p0, :idle, 600.0, w.t + 600, true, 0, false)
        end
        for (c, fa) in S[:f]
            if abs(a - fa) < 0.6f0 && !(c.name in S[:jumped])
                push!(S[:jumped], c.name)
                c.action = :jump; c.goal.action = :jump
                NG.say!(w, c, "EEK! A shadow with nobody on it!"; duration = 2.0)
            end
        end
        NG.sync!(g.stage, w)                                 # draw me where I am now, not one frame late
        if track
            # close behind my shadow: the lens trails where my feet would be, looking down the shadow's length
            ca = get(S, :ca, a); ca += (a - ca) * min(1f0, 2f0 * dt); S[:ca] = ca
            mid = c0 + ca * side - 1.4f0 * sh
            gz = NG.ground(w.island, (mid...,))[3]
            eye_xy = mid + sh * (1.4f0 + cam_back)
            eye = Point3f(eye_xy[1], eye_xy[2], gz + cam_up)
            tg = Point3f(mid[1], mid[2], gz + 0.1f0)
        else
            u = Float32(smooth(t / seconds))
            mid = c0 + (-1.2f0 + 2.4f0 * u) * side - 1.2f0 * sh
            eye_xy = mid + sh * back
            gz = NG.ground(w.island, (mid...,))[3]
            eye = Point3f(eye_xy[1], eye_xy[2], gz + 3.0f0)
            tg = Point3f(mid[1], mid[2], gz + 0.2f0)
        end
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.5,
                     rig = NG.CameraRig(; mode = :fixed), rasterize, shot)
    return (path = path, c0 = S[:c0], score = S[:score], sun = S[:s], r...)
end
