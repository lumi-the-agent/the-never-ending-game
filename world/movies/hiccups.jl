# The Hiccup Epidemic (session 65): Lumi gets the hiccups, they jump friend to friend across the meadow,
# then BOO!, everyone leaps sky high... and Lumi goes "...hic." Raster preview:
#   include("world/movies/hiccups.jl"); hiccups_clip("world/media/s65/hic-preview.mp4"; rasterize = true, width = 480, height = 270, fps = 8)
using NeverendingGame, Makie
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "post_stills.jl"))    # open_meadow

function hiccups_clip(path; spot = nothing, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 15.0)
    size = (width, height)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        # the worker's setup runs before the plugins start, so open_meadow cannot see the Big Boing toadstool yet
        x, y = spot === nothing ? open_meadow(w) : Float32.(spot)
        hm = g.plugins["hiccups"].mod
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Hopscotch")
        # the friends stand about in a loose line across the meadow, so the hiccups travel from one to the next
        spots = ((2.0f0, 0.9f0), (3.6f0, -1.0f0), (-2.0f0, -1.2f0), (5.2f0, 0.4f0), (-3.6f0, 0.8f0), (6.4f0, -1.4f0))
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = -pi / 2f0; c.goal = NG.Goal(); c.controlled = false
                S[:lumi] = c
            elseif c.name in cast
                k += 1
                o = spots[k]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2])); c.yaw = Float32(-pi / 2 + 0.6randn())
                c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false); c.controlled = false
            else      # everyone else is out of the picture
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = Point3f(x + 1.2f0, y - 0.2f0, NG.ground(w.island, (x + 1.2f0, y))[3])
        S[:mod] = hm
    end
    shot = function (g, rig, t)
        hm = S[:mod]
        if !haskey(S, :sys)           # the plugins start with the first step, after setup
            S[:sys] = sys = only(g.plugins["hiccups"].systems)
            Base.invokelatest(hm.begin!, sys, g, S[:lumi])
        end
        sys = S[:sys]
        # the BOO comes once most of them have it (or at 10 s), so the film keeps its pace
        if sys.state === :spread && t > 7 && (length(sys.sick) >= 6 || t > 10)
            Base.invokelatest(hm.boo!, sys, g)
        end
        c = S[:c]
        drift = Float32(0.12 * t)
        rig.mode = :fixed
        rig.eye = c + Point3f(-1.2f0 + drift, -8.2f0, 2.4f0)
        rig.target = c + Point3f(drift, 0, 1.0f0)
        sys.state === :idle && t > 6 && return t + 1.0
        return nothing
    end
    NG.game_clip(path; size, seconds, fps, samples, hour = 10.5, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
