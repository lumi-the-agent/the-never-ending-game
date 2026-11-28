# The winch's first haul (s176, project winch): the iron drum motor on six clay pots winds a hemp rope on the oak
# spindle on its axle and drags a driftwood log across the grass to its block. Nothing here moves the log:
# plugins/irondrum.jl runs Motor.step! with the rope's pull as the load and Rope.step! (particles + springs that only
# pull, reel = turn x spindle radius). This only lays the log out, switches the motor on and points a camera.
#   submit_job(:clip; path = "site/films/winch-first-haul.mp4", script = "movies/winch.jl", call = "winch_haul")
using NeverendingGame, Makie
const NG = NeverendingGame

function winch_haul(path; hour = 17.6, seconds = 10.0, samples = 24, rasterize = false, size = (960, 540))
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(5.55, -11.15, 1.65); rig.target = Point3f(4.74, -12.6, 1.2)
    switched = Ref(false)
    shot = function (g, rig, t)
        ID = isdefined(Main, :IRONDRUM) ? Main.IRONDRUM : nothing
        (ID === nothing || !haskey(ID, :load)) && return nothing
        t >= 1.0 && !switched[] && (ID[:st].on = true; ID[:haul_from] = ID[:load].x[1]; ID[:haul_told] = false; switched[] = true)
        # low beside the log, the rope running off to the motor on its block; a slow drift after the log
        k = Float32(clamp(t / seconds, 0, 1)); k = k * k * (3 - 2k)
        # (s176 retake: the camera holds still, so the log visibly comes in, and sits closer to the rope)
        rig.eye = Point3f(5.30f0, -11.55f0, 1.55f0) + k * Point3f(-0.03f0, -0.05f0, 0)
        rig.target = Point3f(4.74f0, -12.9f0, 1.22f0)
        nothing
    end
    setup = function (g)
        ID = isdefined(Main, :IRONDRUM) ? Main.IRONDRUM : nothing
        ID === nothing && return
        haskey(ID, :st) && (ID[:st].on = false)
        p = get(g.plugins, "irondrum", nothing)
        # (before the plugin's first step there is no drum yet: its first step lays the log out at the start anyway)
        p === nothing || !haskey(ID, :c) || parentmodule(typeof(only(p.systems))).id_winch_reset!()
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, setup, fade = 0.4)
end
