# A check for todo #498 (s114): the horizon at dusk, traced, looking out to sea from the south shore.
# The sky map below the horizon now fades into the ground colour (Hikari sun_sky.jl HORIZON_FADE).
using NeverendingGame, Makie
const NG = NeverendingGame

function horizon_clip(path; samples = 48, width = 1280, height = 720, hour = 18.5)
    shot = function (g, rig, t)
        eye = Point3f(0, -22, 4.0); tg = Point3f(10, -80, 3.0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return 0.9
    end
    NG.game_clip(path; size = (width, height), seconds = 1.0, fps = 2, samples, hour, warmup = 0.5,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, shot)
    return (path = path,)
end
