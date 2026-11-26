# Keep the island level (session 114, plugins/balance.jl): the mini game seen from behind Lumi. The friends
# crowd to one shore, the island tips under a level horizon, heavy Lumi runs to the other side and it comes
# back; they crowd somewhere else, Lumi is too slow, the low shore floods (SPLASH, wet feet), Lumi runs again.
#   submit_job(:clip; path, script = "movies/balance.jl", call = "balance_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function balance_clip(path; rasterize = true, samples = 20, width = 960, height = 540, fps = 24, seconds = 12.0,
                      hour = 15.8, φ = 2.2f0, cam_h = 8.5f0, cam_back = 11.0f0)
    S = Dict{Any,Any}()
    shot = function (g, rig, t)
        w = g.world
        m = g.plugins["seesaw"].mod
        lumi = something(findfirst(c -> c.species == "Lumi", w.creatures), 1)
        me = w.creatures[lumi]
        if !haskey(S, :go)
            S[:go] = true
            m.WEIGHTS[me.id] = 5.0f0
            S[:A] = m.rim_spot(w, φ)                       # where they crowd first
            S[:B] = m.rim_spot(w, φ + Float32(pi))         # where Lumi runs to
            S[:C] = m.rim_spot(w, φ + 1.9f0)               # where they crowd next
            S[:D] = m.rim_spot(w, φ + 1.9f0 + Float32(pi)) # and Lumi again
            S[:jit] = [Point3f(randn() * 1.6f0, randn() * 1.6f0, 0) for _ in w.creatures]
            S[:said] = Set{Int}()
            for (i, c) in enumerate(w.creatures)
                p = NG.ground(w.island, (Float32(3 * cos(1.7i)), Float32(3 * sin(1.7i))))
                c.pos = p; c.action = :idle
                c.goal = NG.Goal(:seesaw, p, :idle, 600.0, w.t + 600, true, 0, false)
            end
            me.pos = NG.ground(w.island, (0.0f0, 0.0f0))
        end
        # (start, end, where) of each run: friends A at 0.3-2.6, Lumi B at 2.8-5.4, friends C at 6.0-8.0,
        # Lumi late (the splash at ~8.6) to D at 8.8-11.2
        mv = function (c, key, t0, t1, goal)
            from = get!(S, (key, c.id), c.pos)
            u = Float32(clamp((t - t0) / (t1 - t0), 0, 1))
            t < t0 && return false
            p = from + (goal - from) * u
            c.pos = NG.ground(w.island, (p[1], p[2]))
            moving = 0 < u < 1
            if moving
                d = goal - from
                c.yaw = Float32(atan(d[2], d[1])) - NG.species_of(c).heading
            end
            c.action = moving ? :run : :idle
            return moving
        end
        for (i, c) in enumerate(w.creatures)
            c === me && continue
            lag = 0.2 * ((i * 7) % 5)
            if t < 5.8
                mv(c, :a, 0.3 + lag, 2.6 + lag, S[:A] + S[:jit][i])
            else
                mv(c, :c, 6.0 + lag, 8.0 + lag, S[:C] + S[:jit][i])
            end
        end
        t < 8.8 ? mv(me, :b, 2.8, 5.4, S[:B]) : mv(me, :d, 8.8, 11.2, S[:D])
        say = function (k, c, text)
            k in S[:said] && return
            push!(S[:said], k)
            NG.say!(w, c, text; duration = 2.2)
        end
        others = [c for c in w.creatures if c !== me]
        t > 0.2 && say(1, others[1], "Ooh! What's that by the shore?")
        t > 2.6 && say(2, me, "Hold on, I'm coming!")
        t > 5.9 && say(3, others[3], "A shiny thing! Come see!")
        if t > 8.4 && !(4 in S[:said])
            for (k, c) in enumerate(others)
                k <= 4 && NG.feel!(w, c, :scared; seconds = 1.4)
            end
            say(4, others[4], "SPLASH! Lumi!")
        end
        t > 8.9 && say(5, me, "Sorry! Sorry!")
        # the camera: behind Lumi and up a little, following where Lumi is DRAWN (on the tipped island),
        # the horizon level: the ground tips under it
        p = m.drawn(me.pos)
        dir = haskey(S, :camdir) ? S[:camdir] : (S[:camdir] = Vec3f(cos(φ), sin(φ), 0))
        # high over Lumi's shoulder (8.5 m up, 11 m back): at 3.6 m the trees filled the first five seconds (s114 preview)
        eye = Point3f(p + Vec3f(0, 0, cam_h) - cam_back * dir)
        tg = Point3f(p + Vec3f(0, 0, 0.5) + 3.0f0 * dir)
        k = haskey(S, :eye) ? 0.12f0 : 1.0f0
        S[:eye] = haskey(S, :eye) ? S[:eye] + k * (eye - S[:eye]) : eye
        S[:tg] = haskey(S, :tg) ? S[:tg] + k * (tg - S[:tg]) : tg
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = S[:tg]
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, angle = get(Main.SEESAW, :angle, -1.0))
end
