# Six clay-pot cells running the drum motor on its oak table (s159, project friends-battery). The bench plugin draws and
# runs everything (physics/potcell.jl sets the motor's emf and resistance each frame); this switches it on and films:
# 0-4.5 s the pots (blue copper salt, copper strips, iron bars, cords rising to the table), then the motor turning close.
using NeverendingGame, Makie
const NG = NeverendingGame

function clay_pots(path; hour = 11.0, seconds = 9.0, samples = 20, rasterize = false, size = (960, 540))
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(6.25, -13.12, 1.5); rig.target = Point3f(5.95, -13.85, 1.38)
    shot = function (g, rig, t)
        MB = isdefined(Main, :MOTORBENCH) ? Main.MOTORBENCH : nothing
        if MB !== nothing && haskey(MB, :A) && haskey(MB, :st)
            MB[:st].on = true
            A = MB[:A]
            if t < 4.5      # the pots, a slow drift along the row
                u = Float32(t / 4.5)
                rig.eye = Point3f(6.25 - 0.12u, -13.12, 1.5 + 0.04u); rig.target = Point3f(5.95 - 0.08u, -13.85, 1.38)
            else            # the motor close, turning
                rig.eye = A + Point3f(0.19, 0.15, 0.08); rig.target = A + Point3f(0.01, 0, -0.005)
            end
        end
        nothing
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 4, rig, rasterize, shot)
end
