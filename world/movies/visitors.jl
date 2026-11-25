# Someone's watching (session 93, plugins/visitors.jl): the camera is the visitor. Lumi is asleep on the meadow,
# the friends potter about, and then someone opens the page: Lumi jumps up, runs right up to the lens and waves at
# you, and the friends turn round one by one and wave too.
#   submit_job(:clip; path, script = "movies/visitors.jl", call = "visitor_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame

function visitor_setup(g, spot, cast, eye)
    w = g.world
    x0, y0 = Float32.(spot)
    k = 0
    for x in w.creatures
        x.controlled = false; x.action = :idle
        if x.name == "Lumi"                                   # asleep across the meadow, facing away
            x.pos = NG.ground(w.island, (x0, y0 + 1.5f0)); x.yaw = Float32(pi / 2) - NG.species_of(x).heading
            x.goal = NG.Goal(:sleep, x.pos, :sleep, 600.0, w.t + 600, true, 0, false); x.action = :sleep
            continue
        end
        i = findfirst(==(x.name), cast)
        if i === nothing
            k += 1
            for r in 22f0:2f0:40f0
                q = (x0 - 6f0 + 1.4f0 * k, y0 + r)
                if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                    x.pos = NG.ground(w.island, q); break
                end
            end
            x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = 2f0 * Float32(pi) * i / length(cast)
        x.pos = NG.ground(w.island, (x0 + 3.2f0 * cos(a), y0 + 1f0 + 2.4f0 * sin(a)))
        x.yaw = a + Float32(pi) / 2 - NG.species_of(x).heading           # about their own business, side on
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function visitor_clip(path; spot, rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 8.0,
                      cast = ["Truffle", "Gloop", "Cumulus", "Pinchy", "Wibbles", "Pickles"])
    S = Dict{Symbol,Any}()
    x0, y0 = Float32.(spot)
    shot = function (g, rig, t)
        V = Main.VISITORS
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            tg = NG.ground(w.island, (x0, y0 + 1f0)) + Point3f(0, 0, 0.7f0)
            S[:tg] = tg
            S[:eye] = argmin(e -> NG.obstruction(w, e, tg), [tg + Point3f(0.4f0, d, 1.5f0) for d in (-7.5f0, 7.5f0, -6f0, 6f0)])
            visitor_setup(g, spot, cast, S[:eye])
            V[:fake] = 0; V[:t_greet] = 9.0; V[:log] = Tuple{Float64,Symbol}[]
        end
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = S[:tg]     # the visitor looks from the lens
        t >= 2.0 && get(V, :fake, 0) == 0 && (V[:fake] = 1)                 # someone opens the page
        return 11.5
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    V = Main.VISITORS
    log = [(t - S[:off], k) for (t, k) in get(V, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    delete!(V, :fake); delete!(V, :t_greet)
    a = isempty(log) ? 2.0 : log[1][1]
    # (the sound is mixed afterwards outside Julia: an ffmpeg here ran forever twice, s92/s93)
    mv(silent, path; force = true)
    return (path = path, log = log)
end
