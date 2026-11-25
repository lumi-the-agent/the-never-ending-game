# Lumi's first real flight (session 73): a circle high over the island with the little one riding on its back.
#   submit_job(:clip; path, script = "movies/soar.jl", call = "soar_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function soar_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 15.0, hour = 11.0)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Wibbles", "Truffle", "Pinchy", "Cumulus")
        ring = ((-2.6f0, 1.6f0), (2.6f0, 1.8f0), (-1.0f0, 3.2f0), (1.4f0, 3.4f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = Float32(pi / 2); c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast && k < length(ring)
                k += 1
                o = ring[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2])); c.yaw = Float32(-pi / 2)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = NG.ground(w.island, (x, y))
    end
    shot = function (g, rig, t)
        if !haskey(S, :sys)
            Main.EGG[:chick][:hatched] = true          # a quiet copy never loads the saved chick
            S[:mod] = m = g.plugins["soar"].mod
            S[:sys] = sys = only(g.plugins["soar"].systems)
            Main.SOAR[:loop_t] = 9.0
            Base.invokelatest(m.takeoff!, sys, g, S[:lumi])
            # a shorter circle for the film
            S[:sys].radius = 7.5f0
            d = Vec2f(-S[:c][1], -S[:c][2]); d = d / max(hypot(d[1], d[2]), 1f-3)
            S[:sys].centre = Point2f(S[:c][1] + 7.5f0 * d[1], S[:c][2] + 7.5f0 * d[2])
            S[:sys].a0 = atan(S[:c][2] - S[:sys].centre[2], S[:c][1] - S[:sys].centre[1])
        end
        sys = S[:sys]
        me = S[:lumi]
        c = S[:c]
        rig.mode = :fixed
        # the plugin's own view: beside Lumi on the way up, then flying alongside, a little behind and outside
        v = sys.state === :idle ? nothing : Base.invokelatest(S[:mod].soar_group, g.world)
        eye, look = v === nothing ? (c + Point3f(0, -6f0, 2f0), c + Point3f(0, 0, 1f0)) : v[3]
        # landed (s75): a slow pull back beside Lumi and a tilt up to the ring of cloud it left (eased over ~2 s:
        # a quick turn reads as a whip, the human, s74)
        slow = sys.state === :idle || sys.state === :after
        if slow
            o = Vec3f(sys.centre[1] - c[1], sys.centre[2] - c[2], 0); o = o / max(hypot(o[1], o[2]), 1f-3)
            eye = c - 5.5f0 * o + Point3f(0, 0, 1.4f0) + 2.5f0 * Vec3f(-o[2], o[1], 0)
            look = Point3f(sys.centre[1], sys.centre[2], c[3] + 6.5f0)
        end
        if haskey(S, :eye)
            a = slow ? 0.025f0 : 0.2f0
            S[:eye] += a * (eye - S[:eye]); S[:look] += (slow ? 0.025f0 : 0.3f0) * (look - S[:look])
        else
            S[:eye] = eye; S[:look] = look
        end
        rig.eye = S[:eye]; rig.target = S[:look]
        sys.state === :idle && t > 10 && return t + 2.5
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
