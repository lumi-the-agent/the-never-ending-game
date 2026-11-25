# The Big Boing toadstool grows up (session 77): the friends gather, the old cap shivers and leaks spores, POP,
# and a real clay toadstool springs up in its place. Sound from the moments the plugin went through: a wobbly
# hum while it shivers, the POP, a springy BOIOING as the new one shoots up, and a little fanfare of cheers.
#   submit_job(:clip; path, script = "movies/toadstool.jl", call = "toadstool_clip", kwargs = Dict("centre" => [x, y]))
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

"A rising, wobbling hum while the cap shivers (`d` seconds)."
hum(d) = [0.18 * sin(2pi * (110 + 40u / d) * u + 3sin(2pi * 7u)) * min(1, u / 0.3) * min(1, (d - u) / 0.2) for u in (0:round(Int, d * SR)) ./ SR]

"POP: a burst of noise and a falling pitch."
function pop()
    s = 77
    map(0:round(Int, 0.35SR)) do j
        u = j / SR
        s = (1103515245 * s + 12345) % 2147483648
        n = s / 2147483648 * 2 - 1
        0.9 * n * exp(-u / 0.025) + 0.6 * sin(2pi * (420 - 600u) * u) * exp(-u / 0.08)
    end
end

"BOIOING: a pitch that springs up, overshoots and wobbles down, like the growing cap."
function boing(d = 1.6)
    ph = 0.0
    map(0:round(Int, d * SR)) do j
        u = j / SR
        f = 180 + 260 * (1 - exp(-3u) * cos(7.5u))
        ph += 2pi * f / SR
        0.35 * sin(ph) * exp(-u / 0.9) * min(1, u / 0.02)
    end
end

"Little cheers: a bright arpeggio."
cheer() = vcat([[0.16 * sin(2pi * f * u) * exp(-u / 0.25) for u in (0:round(Int, 0.22SR)) ./ SR] for f in (523.3, 659.3, 784.0, 1046.5)]...)

function sound_wav(path, marks, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, kind) in marks
        kind === :look && add!(buf, t + 0.3, hum(3.6))
        kind === :pop && add!(buf, t, pop())
        kind === :pop && add!(buf, t + 0.45, boing())
        kind === :cheer && add!(buf, t, cheer())
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

function toadstool_clip(path; centre, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 15.0)
    S = Dict{Symbol,Any}(:marks => Tuple{Float64,Symbol}[], :last => :none)
    cx, cy = Float32.(centre)
    setup = function (g)
        w = g.world
        cast = ("Lumi", "Wibbles", "Truffle", "Gloop", "Cumulus", "Pickles", "Hopscotch", "Marshmallow")
        k = 0
        for c in w.creatures
            if c.name in cast
                k += 1
                # round the toadstool, a step further out than where they will stand
                a = Float32(-0.6 + 2pi * (k - 1) / length(cast))
                r = c.name == "Lumi" ? 4.6f0 : 5.6f0
                p = (cx + r * cos(a), cy + r * sin(a))
                NG.on_land(g.world.island, p[1], p[2]; margin = 0.3f0) || (p = (cx + 2.5f0 * cos(a), cy + 2.5f0 * sin(a)))
                c.pos = NG.ground(w.island, p); c.yaw = Float32(a + pi); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - cx, q[2] - cy) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        T = Main.TOADSTOOL
        s = T[:sys]
        if !haskey(S, :started)
            # a quiet copy starts with the grown one: show the old one and let it happen
            S[:started] = true
            T[:film] = true; T[:said] = 0
            s.state = :old
        end
        st = s.state
        if st !== S[:last]
            st === :look && push!(S[:marks], (t, :look))
            st === :grow && push!(S[:marks], (t, :pop))
            st === :after && push!(S[:marks], (t, :cheer))
            S[:last] = st
        end
        c = Point3f(cx, cy, NG.ground(g.world.island, (cx, cy))[3])
        # from the side of the ring, a slow push in over the whole film (one framing, no swings)
        u = Vec3f(cos(-0.6f0), sin(-0.6f0), 0); v = Vec3f(-u[2], u[1], 0)
        push = Float32(min(t, seconds) / seconds)
        rig.mode = :fixed
        rig.eye = c + (8.6f0 - 1.4f0 * push) * v + 2.2f0 * u + Point3f(0, 0, 2.1f0 - 0.2f0 * push)
        rig.target = c + Point3f(0, 0, 1.45f0) + 0.8f0 * u
        st === :new && t > 6 && return t + 1.0
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    wav = sound_wav(replace(path, ".mp4" => ".wav"), S[:marks], seconds + 1)
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return path
end
