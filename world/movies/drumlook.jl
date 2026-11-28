# A look at the drum motor on its bench by day (s157): a check of the materials and that it turns, NOT a post.
# The bench plugin (plugins/motorbench.jl) draws and runs the motor; this only switches it on and points a camera.
using NeverendingGame, Makie
const NG = NeverendingGame

function drum_look(path; hour = 10.5, seconds = 3.0, samples = 32, rasterize = false, size = (960, 540))
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(5.96, -14.04, 1.34); rig.target = Point3f(5.6, -14.3, 1.16)
    shot = function (g, rig, t)
        MB = isdefined(Main, :MOTORBENCH) ? Main.MOTORBENCH : nothing
        if MB !== nothing && haskey(MB, :A) && haskey(MB, :st)
            MB[:st].on = true
            A = MB[:A]
            # s158: 0.36/0.26/0.16 was ~0.47 m off, the default eye: the motor came out ~1/4 of the frame. ~0.25 m now.
            rig.eye = A + Point3f(0.19, 0.15, 0.08); rig.target = A + Point3f(0.01, 0, -0.005)
        end
        nothing
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 4, rig, rasterize, shot)
end
