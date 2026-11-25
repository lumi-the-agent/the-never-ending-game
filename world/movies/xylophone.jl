# The island plays itself (session 95b, plugins/xylophone.jl): friends about Lumi on the meadow, each doing its own
# thing, and every hop, bite, chat and wave strikes that friend's note. The plugin logs every note it plays
# (`Main.XYLO[:notes]`: island time, frequency, loudness); this script returns them with the film's start, and
# movies/xylophone_sound.py turns them into the sound outside Julia (lesson s92/s93: no mux in here).
#   submit_job(:clip; path, script = "movies/xylophone.jl", call = "xylophone_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame

const CAST = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Hopscotch", "Pickles")
const RING = ((-2.4f0, 1.4f0), (0.2f0, 2.8f0), (2.6f0, 1.6f0), (3.1f0, -0.7f0), (-3.1f0, -0.5f0), (1.4f0, 4.2f0), (-1.6f0, 3.9f0))
# who does what when (s): the island's tune comes out of this ordinary bustle
const CUES = ((1.0, "Pinchy", :jump), (1.6, "Gloop", :laugh), (2.3, "Truffle", :wave), (2.9, "Wibbles", :jump),
              (3.6, "Cumulus", :think), (4.2, "Hopscotch", :laugh), (4.8, "Pickles", :jump), (5.5, "Lumi", :sigh),
              (6.3, "Gloop", :jump), (6.9, "Pinchy", :wave), (7.4, "Lumi", :proud), (7.9, "Truffle", :jump),
              (8.4, "Wibbles", :laugh), (8.9, "Hopscotch", :jump), (9.4, "Cumulus", :wave), (9.9, "Lumi", :laugh),
              (10.4, "Pickles", :laugh), (10.9, "Gloop", :wave))

function xylophone_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24,
                        seconds = 12.0, hour = 9.6, brighten_at = 7.4)
    S = Dict{Symbol,Any}()
    x0, y0 = Float32.(spot)
    shot = function (g, rig, t)
        w = g.world
        X = Main.XYLO
        if !haskey(S, :off)
            S[:off] = w.t - t
            k = 0
            for c in w.creatures
                c.controlled = false
                if c.name == "Lumi"
                    c.pos = NG.ground(w.island, (x0, y0)); c.yaw = -Float32(pi) / 2 - NG.species_of(c).heading
                    c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.action = :idle
                elseif c.name in CAST && k < length(RING)
                    k += 1; o = RING[k]
                    c.pos = NG.ground(w.island, (x0 + o[1], y0 + o[2]))
                    c.yaw = atan(-o[2], -o[1]) - NG.species_of(c).heading
                    c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.action = :idle
                else                                        # everyone else well out of the picture
                    for r in 24f0:2f0:44f0
                        q = (x0 - 8f0 + 1.6f0 * (c.id % 6), y0 + r)
                        NG.on_land(w.island, q[1], q[2]; margin = 0.3) && (c.pos = NG.ground(w.island, q); break)
                    end
                    c.controlled = true; c.goal = NG.Goal()
                end
            end
            X[:notes] = NTuple{3,Float64}[]; X[:queue] = NTuple{3,Float64}[]; X[:film_feeling] = "bored"; delete!(X, :sent_at)
            tg = NG.ground(w.island, (x0, y0 + 1.2f0)) + Point3f(0, 0, 0.5f0)
            S[:tg] = tg
            S[:dir] = argmin(a -> NG.obstruction(w, tg + Point3f(6.5f0 * cos(a), 6.5f0 * sin(a), 2.2f0), tg),
                             Float32[-pi / 2, -pi / 2 + 0.4, -pi / 2 - 0.4, -pi / 2 + 0.8, -pi / 2 - 0.8])
            S[:cued] = 0
        end
        # the cues: each friend does its thing, and the island rings it
        while S[:cued] < length(CUES) && CUES[S[:cued] + 1][1] <= t
            S[:cued] += 1
            _, who, act = CUES[S[:cued]]
            i = findfirst(c -> c.name == who, w.creatures)
            i === nothing || NG.feel!(w, w.creatures[i], act; seconds = 1.4)
        end
        t >= brighten_at && (Main.XYLO[:film_feeling] = "proud")       # I cheer up, and the tune goes major
        a = S[:dir] - 0.02f0 * Float32(t)                                # a slow drift round the group
        eye = S[:tg] + Point3f(6.5f0 * cos(a), 6.5f0 * sin(a), 2.2f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = S[:tg]
        return seconds - 0.3
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    X = Main.XYLO
    notes = [[round(t - S[:off]; digits = 3), round(f; digits = 2), g] for (t, f, g) in get(X, :notes, NTuple{3,Float64}[])
             if t - S[:off] >= 0]
    delete!(X, :film_feeling)
    mv(silent, path; force = true)
    return (path = path, notes = notes)
end
