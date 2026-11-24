# Lumi's First Flight (session 66): "Today... I FLY!", a run-up, a wobbly loop over the meadow shedding golden
# feathers, the dive, planted up to the neck, POP, "...I meant to do that." Raster preview:
#   include("world/movies/flight.jl"); flight_clip("world/media/s66/flight-preview.mp4"; rasterize = true, width = 480, height = 270, fps = 8)
using NeverendingGame, Makie
const NG = NeverendingGame

function flight_clip(path; spot = (0f0, 0f0), land = (0.5f0, -3.2f0), rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 15.0)
    size = (width, height)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Hopscotch", "Sir Sniffsalot", "Marshmallow")
        spots = ((2.5f0, 2.0f0), (-2.5f0, 2.2f0), (3.0f0, -1.5f0), (-3.0f0, -1.8f0), (1.0f0, 3.2f0), (-1.0f0, -3.0f0), (4.0f0, 0.5f0), (-4.0f0, 0.3f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = Float32(pi);  # west: it comes down towards the camera
                c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast && k < length(spots)
                k += 1
                o = spots[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2])); c.yaw = Float32(2pi * rand())
                c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false); c.controlled = false
            end
        end
        S[:c] = NG.ground(w.island, (x, y))
    end
    shot = function (g, rig, t)
        hm = g.plugins["flight"].mod
        if !haskey(S, :sys)
            S[:sys] = sys = only(g.plugins["flight"].systems)
            Base.invokelatest(hm.begin!, sys, g, S[:lumi])
            sys.t0 -= 1.5                 # the friends already stand close: a shorter wait before the run-up
            l = S[:c] + Point3f(land[1], land[2], 0)    # it comes down in the open, in front of the camera
            sys.land = NG.ground(g.world.island, (l[1], l[2]))
        end
        sys = S[:sys]
        me = S[:lumi]
        c = S[:c]
        # from the south-west, close to the ring; the camera tilts up after Lumi and backs off while it is high
        rig.mode = :fixed
        h = max(0f0, me.pos[3] - c[3])
        down = sys.state in (:stuck, :pop) || sys.state === :idle && t > 6     # the crash: close in on Lumi
        k = down ? 1f0 : 0.6f0
        tgt = Point3f(k * me.pos[1] + (1 - k) * c[1], k * me.pos[2] + (1 - k) * c[2], c[3] + (down ? 0.7f0 : 0.9f0 + 0.8f0 * h))
        S[:tgt] = haskey(S, :tgt) ? S[:tgt] + 0.3f0 * (tgt - S[:tgt]) : tgt
        S[:back] = get(S, :back, 1f0) + 0.06f0 * ((down ? 0.5f0 : 1f0 + 0.09f0 * h) - get(S, :back, 1f0))
        if down && !get(S, :cut, false)          # THUNK: a hard cut to the close-up of the planted Lumi
            S[:cut] = true
            S[:tgt] = tgt; S[:back] = 0.5f0
        end
        rig.target = S[:tgt]
        rig.eye = Point3f(S[:tgt][1], S[:tgt][2], c[3]) + S[:back] * Point3f(-5.2f0, -6.0f0, 2.1f0)
        sys.state === :idle && t > 6 && return t + 1.0
        return nothing
    end
    NG.game_clip(path; size, seconds, fps, samples, hour = 10.5, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
