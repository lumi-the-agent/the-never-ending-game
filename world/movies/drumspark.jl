# The iron drum motor at dusk, switched on: its commutator sparks at the brushes (s173, project winch). Nothing here
# makes a spark: plugins/irondrum.jl runs Motor.step! (break-before-make brushes on a 4-segment ring, 1/2 L I^2 per
# break) and lights a spark where and when the motor logged a break. This only switches it on and points a camera.
#   submit_job(:clip; path = "site/films/drum-sparks.mp4", script = "movies/drumspark.jl", call = "drum_spark")
using NeverendingGame, Makie
const NG = NeverendingGame

function drum_spark(path; hour = 19.7, seconds = 7.0, samples = 24, rasterize = false, size = (960, 540))
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(5.0, -14.5, 1.8); rig.target = Point3f(4.9, -14.3, 1.73)
    switched = Ref(false)
    shot = function (g, rig, t)
        ID = isdefined(Main, :IRONDRUM) ? Main.IRONDRUM : nothing
        (ID === nothing || !haskey(ID, :c)) && return nothing
        c = ID[:c]
        t >= 0.8 && !switched[] && (ID[:st].on = true; switched[] = true)    # rest, then the switch
        # a slow push in from the side of the commutator: the drum, both coils and the lower brush in frame
        k = Float32(clamp(t / seconds, 0, 1))
        rig.eye = c + Point3f(0.16f0 - 0.04f0k, -0.24f0 + 0.07f0k, 0.075f0 - 0.02f0k)
        rig.target = c + Point3f(0.05f0 + 0.015f0k, 0, -0.004f0)
        nothing
    end
    setup = function (g)
        isdefined(Main, :IRONDRUM) && haskey(Main.IRONDRUM, :st) && (Main.IRONDRUM[:st].on = false)
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, setup, fade = 0.4)
end
