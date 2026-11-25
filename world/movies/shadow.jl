# My shadow ran off (session 95, plugins/shadow.jl): a sunny morning on the meadow, Lumi standing about, and then its
# shadow peels away from its feet and runs off across the grass. Lumi chases it, it skips aside, friends jump, and in
# the end Lumi pounces and it slides back under its feet. One wide view from the sun's side, so the shadows fall away
# from the lens and the runaway one reads on the grass.
#   submit_job(:clip; path, script = "movies/shadow.jl", call = "shadow_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame
const DIST = 7.5f0
const HIGH = 3.4f0

function shadow_setup(g, spot, cast)
    w = g.world
    x0, y0 = Float32.(spot)
    k = 0
    for x in w.creatures
        x.controlled = false; x.action = :idle
        if x.name == "Lumi"
            x.pos = NG.ground(w.island, (x0, y0)); x.yaw = -Float32(pi) / 2 - NG.species_of(x).heading   # facing the lens
            x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
            continue
        end
        i = findfirst(==(x.name), cast)
        if i === nothing                                       # everyone else well out of the way
            k += 1
            for r in 24f0:2f0:44f0
                q = (x0 - 8f0 + 1.6f0 * k, y0 + r)
                if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                    x.pos = NG.ground(w.island, q); break
                end
            end
            x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = 2f0 * Float32(pi) * (i - 0.5f0) / length(cast)          # a few friends about the meadow, in its way
        x.pos = NG.ground(w.island, (x0 + 3.8f0 * cos(a), y0 + 3.2f0 * sin(a)))
        x.yaw = a + Float32(pi) / 2 - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function shadow_clip(path; spot, rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 17.0, hour = 9.2,
                     cast = ["Gloop", "Pinchy", "Pickles"], loose_at = 2.0, arena = 3.5)
    S = Dict{Symbol,Any}()
    x0, y0 = Float32.(spot)
    shot = function (g, rig, t)
        SH = Main.SHADOW
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            shadow_setup(g, spot, cast)
            SH[:log] = Tuple{Float64,Symbol}[]; SH[:next] = Inf; SH[:arena] = (Point2f(x0, y0), Float32(arena))
            haskey(SH, :sys) && (SH[:sys].state = :home)
            Main.LUMI_PARTY[:until] = -Inf
            tg = NG.ground(w.island, (x0, y0)) + Point3f(0, 0, 0.4f0)
            sd = NG.sun(w)[1]; sa = atan(sd[2], sd[1])
            # one side for the whole film (lesson s74), from the sun's half (lesson s35) and the clearest of eight
            dirs = [sa + da for da in (0.5f0, -0.5f0, 0.9f0, -0.9f0, 1.3f0, -1.3f0, 0.15f0, -0.15f0)]
            S[:dir] = argmin(a -> NG.obstruction(w, tg + Point3f(DIST * cos(a), DIST * sin(a), HIGH), tg), dirs)
            S[:mid] = tg; S[:tl] = t
        end
        # the camera keeps Lumi and its shadow in view, gliding after them (time-based, so the preview and the take agree)
        me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
        sh = SH[:sys]
        m = sh.state === :home ? me.pos : (me.pos + NG.ground(w.island, (sh.pos[1], sh.pos[2]))) / 2
        m = Point3f(m[1], m[2], m[3] + 0.4f0)
        S[:mid] = S[:mid] + (m - S[:mid]) * Float32(1 - exp(-1.6 * (t - S[:tl]))); S[:tl] = t
        a = S[:dir]; tg = S[:mid]
        eye = tg + Point3f(DIST * cos(a), DIST * sin(a), HIGH)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        if t >= loose_at && !get(S, :started, false)
            S[:started] = true
            S[:ok] = SH[:start]()
        end
        return seconds - 0.5
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    SH = Main.SHADOW
    log = [(round(t - S[:off]; digits = 2), k) for (t, k) in get(SH, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    delete!(SH, :arena)
    # (the sound is mixed afterwards outside Julia: an ffmpeg here ran forever twice, s92/s93)
    mv(silent, path; force = true)
    return (path = path, log = log, started = get(S, :ok, false))
end
