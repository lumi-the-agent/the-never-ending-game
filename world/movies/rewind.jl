# The pocket watch (session 92, plugins/rewind.jl): the friends run across the meadow, Lumi hops, and then Lumi winds
# the island back: everyone moonwalks back the way they came at speed, a ◀◀ in the corner and a tape-rewind whirr,
# and then time runs forward again. A side view of the ring, fixed.
#   submit_job(:clip; path, script = "movies/rewind.jl", call = "rewind_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

"A tape winding back: a falling-then-rising whirr with a bit of hiss."
function whirr(len)
    n = round(Int, len * SR); ph = 0.0; s = 7
    map(1:n) do j
        u = j / n
        f = 380 + 900 * u^1.5 + 60 * sin(2pi * 9 * j / SR)
        ph += 2pi * f / SR
        s = (1103515245 * s + 12345) % 2147483648
        env = min(1.0, 8u) * min(1.0, 6(1 - u))
        env * (0.35 * sin(ph) + 0.15 * sin(2ph) + 0.12 * (2 * s / 2147483648 - 1))
    end
end

function rewind_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    starts = [t for (t, k) in log if k === :rewind]; ends = [t for (t, k) in log if k === :forward]
    for (i, t0) in enumerate(starts)
        t1 = i <= length(ends) ? ends[i] : t0 + 2.4
        a = whirr(t1 - t0); j0 = round(Int, t0 * SR)
        for (j, x) in enumerate(a)
            1 <= j0 + j <= length(buf) && (buf[j0 + j] += x)
        end
    end
    buf ./= max(1.0, maximum(abs, buf) / 0.8)
    open(path, "w") do io
        n = length(buf)
        write(io, "RIFF", UInt32(36 + 2n), "WAVE", "fmt ", UInt32(16), UInt16(1), UInt16(1), UInt32(SR), UInt32(2SR), UInt16(2), UInt16(16),
              "data", UInt32(2n))
        for x in buf
            write(io, round(Int16, clamp(x, -1, 1) * 32000))
        end
    end
    return path
end

"Lumi in the middle of `spot`, the cast on the west side of a 7 m ring, everyone else parked far off."
function rewind_setup(g, spot, cast)
    w = g.world
    x0, y0 = Float32.(spot)
    Main.REWIND[:next] = Inf
    k = 0
    for x in w.creatures
        x.controlled = false; x.action = :idle
        if x.name == "Lumi"
            x.pos = NG.ground(w.island, (x0, y0 - 1f0)); x.yaw = 0f0
            x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
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
        x.pos = NG.ground(w.island, (x0 - 3.5f0, y0 - 3f0 + 6f0 * (i - 1) / max(length(cast) - 1, 1)))
        x.yaw = 0f0 - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function rewind_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 8.0,
                     cast = ["Truffle", "Gloop", "Cumulus", "Pinchy", "Wibbles", "Pickles"])
    S = Dict{Symbol,Any}()
    x0, y0 = Float32.(spot)
    shot = function (g, rig, t)
        R = Main.REWIND
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            rewind_setup(g, spot, cast)
            R[:log] = Tuple{Float64,Symbol}[]
            # off they go: everyone races across to the east side, Lumi hops about in the middle (moved by the
            # film itself: in a quiet copy the walk goals did not get them going, s92)
            S[:paths] = Tuple{Int32,Point3f,Point3f,Float32}[]
            for (i, n) in enumerate(cast)
                x = w.creatures[findfirst(c -> c.name == n, w.creatures)]
                q = NG.ground(w.island, (x0 + 3.5f0, y0 + 3f0 - 6f0 * (i - 1) / max(length(cast) - 1, 1)))
                push!(S[:paths], (x.id, x.pos, q, 0.8f0 + 0.4f0 * rand(w.rng, Float32)))
                x.goal = NG.Goal(:dash, x.pos, :idle, 60.0, w.t + 60, true, 0, false)
            end
            S[:lt] = t
        end
        dt = Float32(t - S[:lt]); S[:lt] = t
        if t < 4.4 && Main.REWIND[:sys].state === :rec
            for (id, a, b, v) in S[:paths]
                x = NG.creature(w, id)
                u = clamp(v * Float32(t - 0.3) / 3.6f0, 0f0, 1f0)
                if 0 < u < 1
                    x.pos = NG.ground(w.island, Tuple(a + (b - a) * u)[1:2])
                    x.yaw = atan(b[2] - a[2], b[1] - a[1]) - NG.species_of(x).heading
                    x.action = :run; x.goal.action = :run; x.phase += 14f0 * dt
                elseif u >= 1
                    x.action = :jump; x.goal.action = :jump
                end
            end
        end
        me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
        s = R[:sys]
        t < 4.2 && s.state === :rec && (me.action = :jump; me.goal.action = :jump)
        if t >= 4.4 && !haskey(S, :wound)
            S[:wound] = t
            S[:ok] = Base.invokelatest(R[:start]; back = 4.2)
        end
        # a side view across the race, a little above
        rig.mode = :fixed
        tg = NG.ground(w.island, (x0, y0)) + Point3f(0, 0, 0.7f0)
        if !haskey(S, :eye)                 # the clearer of the two sides across the race (s92: a bush filled the south one)
            S[:eye] = argmin(e -> NG.obstruction(w, e, tg), [tg + Point3f(0.5f0, d, 2.2f0) for d in (-8.5f0, 8.5f0, -7f0, 7f0)])
        end
        rig.eye = S[:eye]; rig.target = tg
        haskey(S, :wound) && s.state === :rec && !haskey(S, :end) && t > S[:wound] + 1 && (S[:end] = t)
        return haskey(S, :end) ? S[:end] + 3.0 : nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> rewind_setup(g, spot, cast), shot)
    R = Main.REWIND
    delete!(R, :next)
    log = [(t - S[:off], k) for (t, k) in get(R, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = rewind_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    st = [t for (t, k) in log if k === :rewind]; en = [t for (t, k) in log if k === :forward]
    a = isempty(st) ? 4.4 : st[1]; b = isempty(en) ? a + 2.4 : en[1]
    # ◀◀ in the corner while time runs back (this ffmpeg has no drawtext: ImageMagick draws it)
    png = replace(path, ".mp4" => "-rw.png")
    run(`magick -size $(width)x$(height) xc:none -font /usr/share/fonts/truetype/DejaVuSans-Bold.ttf -pointsize $(height ÷ 9) -gravity northwest -fill "#00000080" -annotate +34+30 "◀◀" -fill "#FFF6E0" -annotate +30+26 "◀◀" PNG32:$png`)
    voice = joinpath(dirname(@__DIR__), "site", "voice", "game", "hm.mp3")
    d1 = round(Int, 1000 * (b + 0.3))
    # (an explicit length: with a looped picture and padded sound -shortest never ends, s92 wrote 100s of MB)
    dur = parse(Float64, readchomp(`ffprobe -v error -show_entries format=duration -of csv=p=0 $silent`))
    run(`ffmpeg -y -loglevel error -i $silent -loop 1 -t $(dur) -i $png -i $wav -i $voice -filter_complex "[1:v]format=rgba[o];[0:v][o]overlay=0:0:shortest=1:enable='between(t,$(a),$(b))'[v];[3]adelay=$(d1)|$(d1),volume=0.8[h];[2][h]amix=inputs=2:normalize=0,apad[out]" -map "[v]" -map "[out]" -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 160k -t $(dur) $path`)
    rm(png); rm(silent)
    return (path = path, started = S[:ok], log = log)
end
