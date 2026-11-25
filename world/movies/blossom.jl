# Spring comes to the island (session 78): the friends gather on the bare meadow north of the vegetable patch,
# little cherry trees spring up one after another, burst into pink and shower petals over everyone dancing.
# Sound from the moments the plugin went through: a soft rising hum while something pokes up, a bright chime as
# each tree springs, a breath of wind with a shimmer when the petals fly, and a little music box tune.
#   submit_job(:clip; path, script = "movies/blossom.jl", call = "blossom_clip", kwargs = Dict())
using NeverendingGame, Makie
const NG = NeverendingGame

const SR = 44100

function add!(buf, t, f)
    i0 = round(Int, t * SR)
    for (j, x) in enumerate(f)
        i = i0 + j
        1 <= i <= length(buf) && (buf[i] += x)
    end
end

tone(f, d; a = 0.2, decay = 0.4) = [a * sin(2pi * f * u) * exp(-u / decay) * min(1, u / 0.005) for u in (0:round(Int, d * SR)) ./ SR]
hum(d) = [0.08 * sin(2pi * (220 + 60u / d) * u) * min(1, u / 0.5) * min(1, (d - u) / 0.3) for u in (0:round(Int, d * SR)) ./ SR]

"A breath of wind: filtered noise that swells and fades, with a high shimmer."
function wind(d)
    s = 11; y = 0.0
    map(0:round(Int, d * SR)) do j
        u = j / SR
        s = (1103515245 * s + 12345) % 2147483648
        y = 0.985y + 0.015 * (s / 2147483648 * 2 - 1)
        env = sin(pi * u / d)^2
        2.2 * y * env + 0.04 * sin(2pi * 2637 * u) * env * (0.5 + 0.5sin(2pi * 6u))
    end
end

"A music box tune: a little rising phrase in C major."
function tune()
    notes = (523.3, 659.3, 784.0, 1046.5, 880.0, 784.0, 1046.5)
    out = zeros(round(Int, 3.2SR))
    for (k, f) in enumerate(notes)
        t = tone(f, 1.0; a = 0.14, decay = 0.35) .+ tone(2f, 1.0; a = 0.03, decay = 0.2)
        i0 = round(Int, (k - 1) * 0.32 * SR)
        for (j, x) in enumerate(t)
            i0 + j <= length(out) && (out[i0 + j] += x)
        end
    end
    out
end

function sound_wav(path, marks, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, kind) in marks
        kind === :look && add!(buf, t + 0.2, hum(2.8))
        if kind === :grow
            for i in 0:4
                add!(buf, t + 0.7i + 0.1, tone((1046.5, 1174.7, 1318.5, 1568.0, 1760.0)[i + 1], 1.2; a = 0.18, decay = 0.5))
            end
        end
        kind === :bloom && (add!(buf, t - 0.6, wind(4.5)); add!(buf, t, tune()))
    end
    buf ./= max(1.0, maximum(abs, buf) / 0.9)
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

function blossom_clip(path; rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 15.5,
                      eye = [-4.0, 20.0, 2.4], target = [-12.5, 13.5, 1.6])
    S = Dict{Symbol,Any}(:marks => Tuple{Float64,Symbol}[], :last => :none)
    c = (-12.5f0, 13.5f0)
    setup = function (g)
        w = g.world
        cast = ("Lumi", "Wibbles", "Truffle", "Gloop", "Cumulus", "Pickles", "Hopscotch", "Marshmallow", "Pinchy")
        k = 0
        for x in w.creatures
            if x.name in cast
                k += 1
                a = Float32(0.3 + 2pi * (k - 1) / length(cast))
                r = 7.5f0
                p = (c[1] + r * cos(a), c[2] + r * sin(a))
                NG.on_land(w.island, p[1], p[2]; margin = 0.3f0) || (p = (c[1] + 3.5f0 * cos(a + 1), c[2] + 3.5f0 * sin(a + 1)))
                x.pos = NG.ground(w.island, p); x.yaw = Float32(a + pi); x.controlled = false
                x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                x.controlled = true; x.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        B = Main.BLOSSOM
        s = B[:sys]
        if !haskey(S, :started)
            S[:started] = true
            B[:film] = true; B[:said] = 0; B[:shown] = true
            s.state = :old
        end
        st = s.state
        if st !== S[:last]
            st in (:look, :grow, :bloom) && push!(S[:marks], (t, st))
            S[:last] = st
        end
        # a slow push in towards the grove over the whole film (one framing, no swings)
        e = Point3f(eye...); tg = Point3f(target...)
        u = Float32(min(t, seconds) / seconds)
        rig.mode = :fixed
        rig.eye = e + 0.2f0 * u * (tg - e)
        rig.target = tg
        st === :new && t > 6 && return t + 1.2
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    wav = sound_wav(replace(path, ".mp4" => ".wav"), S[:marks], seconds + 1)
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return path
end
