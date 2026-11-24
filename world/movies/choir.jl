# The Island Choir (session 67): Lumi conducts, five friends sing do-re-mi-fa-so, one big chord... and one
# BWAAARP. The plugin logs every note it sings (Main.CHOIR[:notes]); after the take this script synthesizes
# the song from that log (little "aah" voices, the chord, the sour rasp, the giggles) and muxes it under the film.
# Raster preview:
#   include("world/movies/choir.jl"); choir_clip("world/media/s67/choir-preview.mp4"; rasterize = true, width = 480, height = 270, fps = 8)
using NeverendingGame, Makie
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "post_stills.jl"))    # open_meadow

# ---------------------------------------------------------------- the sound

const SR = 44100

"A sung vowel: harmonics of `f` weighted by two 'aah' formants, vibrato, soft attack and release."
function voice!(buf, t0, dur, f; amp = 0.18, bright = 1.0, slide = 0.0)
    i0 = round(Int, t0 * SR) + 1
    n = round(Int, dur * SR)
    ph = 0.0
    for j in 0:n-1
        i = i0 + j
        i > length(buf) && break
        i < 1 && continue
        t = j / SR
        fv = f * 2^(slide * t / 12) * (1 + 0.012 * sin(2pi * 5.6 * t) * min(1, t / 0.25))
        ph += 2pi * fv / SR
        s = 0.0
        for h in 1:14
            fh = h * fv
            fh > 8000 && break
            g = exp(-((fh - 750) / 260)^2) + 0.6 * exp(-((fh - 1150) / 300)^2) + 0.25 * exp(-((fh - 2600) / 500)^2) * bright
            s += g / h^0.3 * sin(h * ph)
        end
        env = min(1, t / 0.05) * min(1, (dur - t) / 0.12)
        buf[i] += amp * env * s
    end
end

"The sour note: a buzzing sawtooth that sags and rasps."
function bwaarp!(buf, t0, dur, f)
    i0 = round(Int, t0 * SR) + 1
    ph = 0.0
    for j in 0:round(Int, dur * SR)-1
        i = i0 + j
        (i < 1 || i > length(buf)) && continue
        t = j / SR
        fv = f * (1 - 0.18 * t / dur) * (1 + 0.04 * sin(2pi * 11 * t)) + 6 * randn() * 0.1
        ph += fv / SR
        saw = 2 * (ph - floor(ph + 0.5))
        env = min(1, t / 0.03) * min(1, (dur - t) / 0.25)
        buf[i] += 0.32 * env * (saw + 0.3 * sign(sin(2pi * ph * 0.5)))
    end
end

function giggles!(buf, t0, rng = 1)
    for k in 0:9
        voice!(buf, t0 + 0.13k + 0.05 * sin(7k), 0.09, 520 * 2^((8 - k % 5 - (k ÷ 5) * 3) / 12); amp = 0.12)
        voice!(buf, t0 + 0.07 + 0.15k, 0.08, 780 * 2^(-(k % 4) / 12); amp = 0.08)
    end
end

hz(m) = 440 * 2.0^((m - 69) / 12)

"Synthesize the choir's song from (clip second, kind, midi) and write a 16-bit mono WAV."
function choir_wav(path, notes, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, kind, m) in notes
        if kind === :solo
            voice!(buf, t, 0.7, hz(m + 12); amp = 0.2)
        elseif kind === :chord
            for (k, mm) in enumerate((60, 64, 67, 72, 76))
                voice!(buf, t + 0.01k, 2.0, hz(mm + 12) * (1 + 0.003k); amp = 0.09)
            end
            voice!(buf, t, 2.0, hz(48); amp = 0.07)
        elseif kind === :sour
            bwaarp!(buf, t, 1.3, hz(m))
        elseif kind === :laugh
            giggles!(buf, t)
        end
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

# ---------------------------------------------------------------- the film

function choir_clip(path; spot = nothing, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 16.0)
    size = (width, height)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = spot === nothing ? open_meadow(w) : Float32.(spot)
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus")
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = 0f0; c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
                c.controlled = false
                S[:lumi] = c
            elseif c.name in cast
                c.pos = NG.ground(w.island, (x + 3.4f0, y + 0.5f0 * (c.id % 5))); c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
                c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = Point3f(x, y, NG.ground(w.island, (x, y))[3])
    end
    shot = function (g, rig, t)
        w = g.world
        if !haskey(S, :sys)
            m = g.plugins["choir"].mod
            S[:sys] = sys = only(g.plugins["choir"].systems)
            S[:off] = w.t - t
            Base.invokelatest(m.begin!, sys, g, S[:lumi])
            # the film skips the walk over: everyone is already standing in the half circle
            for (k, id) in enumerate(sys.singers)
                c = NG.creature(w, id); c.pos = sys.spots[k]
            end
        end
        sys = S[:sys]
        c = S[:c]
        rig.mode = :fixed
        if sys.state === :sing && sys.stage in (3, 4) && (sc = NG.creature(w, sys.sour); sc !== nothing)
            # cut in on the culprit, everyone else staring
            e = c + Point3f(-4.5f0, 2.0f0, 0f0) - sc.pos
            d = Point3f(e[1], e[2], 0f0) / hypot(e[1], e[2])
            rig.eye = sc.pos + 3.4f0 * d + Point3f(0, 0, 1.3f0)
            rig.target = sc.pos + Point3f(0, 0, 0.8f0)
        else
            # over the conductor's shoulder: the choir faces us
            push = Float32(0.07 * t)
            rig.eye = c + Point3f(-4.5f0 + push, 2.0f0 - 0.3f0 * push, 2.1f0)
            rig.target = c + Point3f(2.6f0, 0f0, 0.8f0)
        end
        sys.state === :idle && t > 4 && return t + 0.5
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size, seconds, fps, samples, hour = 10.5, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    notes = [(t - S[:off], k, m) for (t, k, m, _) in Main.CHOIR[:notes] if t - S[:off] >= 0]
    wav = choir_wav(replace(path, ".mp4" => ".wav"), notes, seconds + 1)
    run(`ffmpeg -y -loglevel error -i $silent -i $wav -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return path
end
