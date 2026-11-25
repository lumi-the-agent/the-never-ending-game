# A message in a bottle (session 80): Lumi walks down to the west shore at golden hour with a bottle, the friends
# gather behind it, it holds the bottle up and throws it out to sea, and it bobs away towards the low sun. The
# soundtrack is Lumi's own voice reading the letter (Kokoro am_puck, made in the session: media/s80/letter.f32,
# 24 kHz Float32) and a splash where the bottle lands (from the plugin's log).
#   submit_job(:clip; path, script = "movies/bottle.jl", call = "bottle_clip", kwargs = Dict("voice" => ...))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

function splash()
    s = 9; y = 0.0
    map(0:round(Int, 0.8SR)) do j
        u = j / SR
        s = (1103515245 * s + 12345) % 2147483648
        y = 0.8y + 0.2 * (s / 2147483648 * 2 - 1)
        0.5 * y * exp(-u / 0.18) + 0.25 * sin(2pi * (300 - 200u) * u) * exp(-u / 0.06)
    end
end

function bottle_wav(path, voice, log, seconds; voice_at = 0.8)
    buf = zeros(Float64, round(Int, seconds * SR))
    v = Float64.(reinterpret(Float32, read(voice)))
    i0 = round(Int, voice_at * SR)
    for (j, x) in enumerate(v)
        i0 + j <= length(buf) && (buf[i0 + j] += 0.9x)
    end
    for (t, k) in log
        k === :splash || continue
        a = splash(); j0 = round(Int, t * SR)
        for (j, x) in enumerate(a)
            1 <= j0 + j <= length(buf) && (buf[j0 + j] += x)
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

function bottle_clip(path; voice, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 15.0, hour = 17.8)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        # the shore by the sunset bench (bottle.jl `shore`), Lumi and the friends close to it already
        spot = Point3f(-17.2f0, 11.0f0, 0f0); out = Vec3f(-0.5f0, 0.87f0, 0f0)
        cast = ("Lumi", "Wibbles", "Truffle", "Gloop", "Cumulus", "Pickles")
        side = Vec3f(-out[2], out[1], 0)
        k = 0
        for c in w.creatures
            if c.name in cast
                k += 1
                p = c.name == "Lumi" ? spot - 1.4f0 * out : spot - 1.2f0 * out - (1.5f0 + 0.95f0 * k) * side
                c.pos = NG.ground(w.island, (p[1], p[2])); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        B = Main.BOTTLE
        s = B[:sys]
        if !haskey(S, :started)
            S[:started] = true
            S[:off] = g.world.t - t
            Base.invokelatest(B[:start])     # (not B[:film]: that would start a second bottle when this one ends)
        end
        rig.mode = :fixed
        if s.state !== :idle
            haskey(S, :view) || (S[:view] = s.view)
            e, tg = S[:view]
            u = Float32(min(t, seconds) / seconds)
            rig.eye = e + 0.15f0 * u * (tg - e); rig.target = tg
        end
        haskey(S, :view) && s.state === :idle && t > 6 && return t + 0.5
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    log = [(t - S[:off], k) for (t, k) in get(Main.BOTTLE, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = bottle_wav(replace(path, ".mp4" => ".wav"), voice, log, seconds + 1)
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return path
end

"""
A traced still of Lumi holding the bottle up against the evening sea (s80): a short 2 fps take of `bottle_clip`'s
scene that ends 1 s into the hold, a little closer than the film; its last frame is written to `path` (png).
"""
function bottle_still(path; take, samples = 64, width = 1280, height = 720, hour = 17.8)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        spot = Point3f(-17.2f0, 11.0f0, 0f0); out = Vec3f(-0.5f0, 0.87f0, 0f0)
        side = Vec3f(-out[2], out[1], 0)
        cast = ("Lumi", "Wibbles", "Gloop")
        k = 0
        for c in w.creatures
            if c.name in cast
                k += 1
                p = c.name == "Lumi" ? spot - 0.6f0 * out : spot - 1.2f0 * out - (1.5f0 + 0.95f0 * k) * side
                c.pos = NG.ground(w.island, (p[1], p[2])); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        B = Main.BOTTLE
        s = B[:sys]
        haskey(S, :started) || (S[:started] = true; Base.invokelatest(B[:start]))
        rig.mode = :fixed
        if s.state !== :idle
            e, tg = s.view
            rig.eye = e + 0.08f0 * (tg - e); rig.target = tg + Point3f(0, 0, 0.9f0)   # (0.35 in: Lumi and the bottle cut off)
        end
        s.state === :hold && !haskey(S, :hold) && (S[:hold] = t)
        haskey(S, :hold) && return S[:hold] + 1.0
        return nothing
    end
    NG.game_clip(take; size = (width, height), seconds = 20.0, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, setup, shot)
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)
    return path
end
