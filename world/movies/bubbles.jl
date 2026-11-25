# Bubble trouble (session 90, plugins/bubbles.jl): Lumi blows a giant soap bubble at each friend in the ring, each
# one floats off with a friend inside, they pop one by one, and Lumi's biggest one swallows Lumi itself.
# Sound: a soft plip at every pop and Lumi's and the friends' voices.
#   submit_job(:clip; path, script = "movies/bubbles.jl", call = "bubbles_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

"A pop: a short bright click with a falling ring."
function plip(len = 0.25)
    n = round(Int, len * SR)
    [exp(-j / (0.02SR)) * sin(2pi * (1800 - 900 * j / n) * j / SR) * 0.8 + (j < 60 ? 0.6 * (rand() - 0.5) : 0.0) for j in 1:n]
end

function bubbles_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, k) in log
        k === :pop || continue
        a = plip(); j0 = round(Int, t * SR)
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

"Lumi on `spot`, the cast in a ring round it, everyone else parked far off."
function bubbles_setup(g, spot, cast)
    w = g.world
    x0, y0 = Float32.(spot)
    Main.BUBBLES[:try_at] = Inf                # the film starts it, not the morning clock
    k = 0
    for x in w.creatures
        x.controlled = false; x.action = :idle
        if x.name == "Lumi"
            x.pos = NG.ground(w.island, (x0, y0)); x.yaw = Float32(-pi / 2)
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
        a = 2f0 * Float32(pi) * (i - 0.5f0) / length(cast)
        x.pos = NG.ground(w.island, (x0 + 3.6f0 * cos(a), y0 + 3.6f0 * sin(a)))
        x.yaw = atan(y0 - x.pos[2], x0 - x.pos[1]) - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function bubbles_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 16.0, hour = 8.6,
                      cast = ["Truffle", "Gloop", "Cumulus", "Pinchy", "Wibbles", "Pickles", "Marshmallow"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        B = Main.BUBBLES                       # (made when the plugins load, inside game_clip)
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            B[:at] = Point2f(spot...); B[:t_gather] = 1.8; B[:gap] = 0.6; B[:big_gap] = 1.6; B[:lumi_pop] = 4.2; B[:pop_min] = 3.6
            bubbles_setup(g, spot, cast)
            S[:ok] = Base.invokelatest(B[:start])
        end
        s = B[:sys]
        e, tg = Base.invokelatest(g.plugins["bubbles"].mod.bubble_view, w, s)
        rig.mode = :fixed; rig.eye = e; rig.target = tg
        s.state === :after && !haskey(S, :end) && (S[:end] = t)
        return haskey(S, :end) ? S[:end] + 1.2 : nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> bubbles_setup(g, spot, cast), shot)
    B = Main.BUBBLES
    for k in (:at, :t_gather, :gap, :big_gap, :lumi_pop, :pop_min, :try_at)
        delete!(B, k)
    end
    log = [(t - S[:off], k) for (t, k) in get(B, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = bubbles_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    voices = Tuple{Float64,String}[]
    caught = [t for (t, k) in log if k === :caught]
    length(caught) >= 1 && push!(voices, (caught[1] + 0.1, "squeak-wheee"))
    length(caught) >= 3 && push!(voices, (caught[3] + 0.1, "squeak-yay"))
    big = [t for (t, k) in log if k === :blow_big]
    isempty(big) || push!(voices, (big[1] + 1.5, "oh"))
    bumps = [t for (t, k) in log if k === :bump]
    isempty(bumps) || push!(voices, (bumps[end] + 0.2, "tadaa"))
    clips = joinpath(dirname(@__DIR__), "site", "voice", "game")
    ins = ["-i", wav]; parts = String[]
    for (i, (t, n)) in enumerate(voices)
        append!(ins, ["-i", joinpath(clips, n * ".mp3")])
        push!(parts, "[$(i + 1)]adelay=$(round(Int, 1000t))|$(round(Int, 1000t)),volume=0.8[a$(i)]")
    end
    mix = isempty(parts) ? "[1]apad[out]" :
          join(parts, ";") * ";[1]" * join(["[a$(i)]" for i in eachindex(voices)]) * "amix=inputs=$(length(voices) + 1):normalize=0,apad[out]"
    run(`ffmpeg -y -loglevel error -i $silent $ins -filter_complex $mix -map 0:v -map "[out]" -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return (path = path, started = S[:ok], log = log)
end
