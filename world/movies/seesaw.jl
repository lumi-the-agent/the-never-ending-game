# The island is a seesaw (session 114, plugins/seesaw.jl): seen from the side, everyone crowds to one shore,
# the island tips (the sea stays flat), they run uphill, overshoot, it tips the other way, then they freeze
# and it wobbles back. The plugin's own spring does the tilt from where the creatures stand; the film only
# moves them (walk goals do not move anyone in a quiet copy, s92).
#   submit_job(:clip; path, script = "movies/seesaw.jl", call = "seesaw_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function seesaw_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 16.8,
                     φ = -0.539f0, legs = ((0.3, 2.6), (4.2, 6.6), (8.0, 10.2)))
    S = Dict{Any,Any}()
    shot = function (g, rig, t)
        w = g.world
        m = g.plugins["seesaw"].mod
        if !haskey(S, :go)
            S[:go] = true
            S[:who] = [c for c in w.creatures]
            sides = (m.rim_spot(w, φ), m.rim_spot(w, φ + Float32(pi)))
            S[:ends] = sides
            S[:jit] = [Point3f(randn() * 1.8f0, randn() * 1.8f0, 0) for _ in w.creatures]
            S[:said] = Set{Int}()
            for (i, c) in enumerate(S[:who])        # start in a loose crowd around the middle
                p = NG.ground(w.island, (Float32(4 * cos(1.7i)), Float32(4 * sin(1.7i))))
                c.pos = p; c.action = :idle
                c.goal = NG.Goal(:seesaw, p, :idle, 600.0, w.t + 600, true, 0, false)
            end
        end
        A, B = S[:ends]
        # where each leg goes: 1 to A, 2 to B (uphill after the tip), 3 back toward A (the overshoot), then freeze
        for (i, c) in enumerate(S[:who])
            from = haskey(S, (:at, i)) ? S[(:at, i)] : c.pos
            leg = findlast(l -> t >= l[1], legs)
            leg === nothing && (S[(:at, i)] = c.pos; continue)
            t0, t1 = legs[leg]
            goal = (leg == 2 ? B : A) + S[:jit][i]
            start = get!(S, (:from, i, leg), c.pos)
            lag = 0.25 * ((i * 7) % 5)              # not all at once
            u = Float32(clamp((t - t0 - lag) / (t1 - t0), 0, 1))
            u = leg == 3 ? 0.45f0 * u : u           # the overshoot run stops halfway: "STOP!"
            p = start + (goal - start) * u
            q = NG.ground(w.island, (p[1], p[2]))
            moving = 0 < u < (leg == 3 ? 0.45f0 : 1)
            if moving
                d = goal - start
                c.yaw = Float32(atan(d[2], d[1])) - NG.species_of(c).heading
            end
            c.pos = q
            c.action = moving ? :run : :idle
        end
        say = function (k, idx, text)
            k in S[:said] && return
            push!(S[:said], k)
            c = S[:who][idx]
            NG.say!(w, c, text; duration = 2.4)
        end
        lumi = findfirst(c -> c.species == "Lumi", S[:who])
        lumi === nothing && (lumi = 1)
        t > 0.2 && say(1, lumi, "Everybody! Come and look at this!")
        t > 3.4 && say(2, mod1(lumi + 3, length(S[:who])), "Whoa! We're tipping!")
        t > 4.4 && say(3, mod1(lumi + 5, length(S[:who])), "Uphill! Everyone uphill!")
        t > 7.6 && say(4, mod1(lumi + 1, length(S[:who])), "Too far! Too far!")
        t > 9.6 && say(5, lumi, "Everybody... stand... very... still.")
        side = Vec3f(-sin(φ), cos(φ), 0)
        eye = Point3f(side * 38f0 + Vec3f(0, 0, 6.5))
        tg = Point3f(0, 0, 0.3)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, angle = get(Main.SEESAW, :angle, -1.0))
end
