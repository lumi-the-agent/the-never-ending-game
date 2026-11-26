# The island on TV (session 112, plugins/tv.jl): three friends sit in front of the television on the meadow, I walk
# past, and the camera slowly pushes in towards the screen, which shows the film's own frame before: the television
# inside the television inside the television. Afterwards the last frame goes to the human's game (state/tv.png),
# so the television there shows the island as it was last filmed.
#   submit_job(:clip; path, script = "movies/tv.jl", call = "tv_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function tv_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 9.8,
                 cast = ["Gloop", "Truffle", "Pinchy"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        m = g.plugins["tv"].mod
        if !haskey(S, :go)
            S[:go] = true
            for c in w.creatures
                k = findfirst(==(c.name), cast)
                if k !== nothing
                    # s113 (review #546): off to the sides, so the camera's push-in passes between them, not through a head
                    off = ((-1.9f0, -3.2f0), (1.4f0, -3.3f0), (2.3f0, -2.5f0))[k]
                    tb = Base.invokelatest(m.base, w)
                    p = NG.ground(w.island, (tb[1] + off[1], tb[2] + off[2]))
                    c.pos = p; c.action = :sit
                    c.goal = NG.Goal(:tvwatch, p, :sit, 60.0, w.t + 60, true, 0, false)
                elseif c.species != "Lumi"        # everyone else far off
                    p = NG.ground(w.island, (Float32(-20), Float32(-30 + 2 * c.id)))
                    c.pos = p; c.goal = NG.Goal(:idle, p, :idle, 60.0, w.t + 60, true, 0, false)
                end
            end
        end
        tvp = Base.invokelatest(m.base, w)
        for c in w.creatures
            k = findfirst(==(c.name), cast)
            if k !== nothing
                c.action = :sit
                want = Float32(atan(tvp[2] - c.pos[2], tvp[1] - c.pos[1])) - NG.species_of(c).heading
                c.yaw = want
            elseif c.species == "Lumi"        # I stroll past between the friends and the television, early on
                u = Float32(clamp((t - 0.3) / 4.5, 0, 1))
                x = 15.2f0 + 6.0f0 * u
                c.pos = NG.ground(w.island, (x, Float32(tvp[2] - 2.1)))
                c.action = 0 < u < 1 ? :walk : :idle
                c.yaw = 0f0 - NG.species_of(c).heading
                c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
            end
        end
        # the camera pushes in towards the screen, slowly, all the way
        s = Float32(clamp(t / seconds, 0, 1)); s = s * s * (3 - 2s)
        scr = tvp + Point3f(-0.3, -0.43, 1.02)
        d = 7.0f0 - 4.8f0 * s
        eye = scr + Point3f(0.35f0 * (1 - s), -d, 0.55f0 * (1 - s) + 0.05f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = scr
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = scr
        return seconds - 0.1
    end
    # no soap bubbles drifting over the screen (the s112 take had them): their plugin starts on its own in a copy
    nobubbles = g -> (isdefined(Main, :BUBBLES) && (Main.BUBBLES[:film] = false; Main.BUBBLES[:try_at] = Inf); nothing)
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = nobubbles, shot)
    f = NG.LAST_FRAME[]
    if f !== nothing && !rasterize
        root = NG.game_root()
        for inst in (:live, :sandbox)
            Makie.save(joinpath(NG.GamePaths(root, inst).state, "tv.png"), f)
        end
    end
    return (path = path,)
end

"""
One broadcast for the television in the human's game: a short raster take from the camera the human looks through
(the latest saved world), whose last frame becomes `state/tv.png` in both games. The copy's own television shows the
broadcast before, so the pictures nest one inside the other over the day.
"""
function tv_still(path; eye, target, width = 480, height = 270, rasterize = true, samples = 16)
    e = Point3f(eye...); tg = Point3f(target...)
    shot = function (g, rig, t)
        rig.mode = :fixed; rig.eye = e; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = e; g.rig.target = tg
        return 0.5
    end
    NG.game_clip(path; size = (width, height), seconds = 0.5, fps = 8, samples, warmup = 0.5,
                 rig = NG.CameraRig(; mode = :fixed), rasterize, setup = g -> nothing, shot)
    f = NG.LAST_FRAME[]
    f === nothing && return (path = path, saved = false)
    root = NG.game_root()
    for inst in (:live, :sandbox)
        Makie.save(joinpath(NG.GamePaths(root, inst).state, "tv.png"), f)
    end
    return (path = path, saved = true)
end
