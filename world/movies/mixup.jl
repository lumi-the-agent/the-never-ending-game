# The Big Mix-Up (session 88, plugins/mixup.jl): Lumi reads a spell to the friends round it, SWAPSIE, and every
# friend comes out of a sparkle cloud in somebody else's body. Two shots: the ring round Lumi for the spell and
# the poof, then closer on the mixed-up friends. Sound: a whoosh at each poof and Lumi's "hm" and "haha".
#   submit_job(:clip; path, script = "movies/mixup.jl", call = "mixup_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

lcg(s) = (s = (1103515245 * s + 12345) % 2147483648; (s, s / 2147483648))

"A sparkly whoosh: noise swelling and falling with a rising shimmer on top."
function poof(len = 1.2)
    n = round(Int, len * SR); s = 13; y = 0.0
    map(1:n) do j
        u = j / n
        s, r = lcg(s)
        y = 0.8y + 0.2 * (2r - 1)
        env = sin(pi * u)^2
        0.7 * env * y + 0.18 * env * sin(2pi * (900 + 1400u) * j / SR) * sin(2pi * 7 * j / SR)
    end
end

function mixup_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, k) in log
        k === :poof || continue
        a = poof(); j0 = round(Int, t * SR)
        for (j, x) in enumerate(a)
            1 <= j0 + j <= length(buf) && (buf[j0 + j] += x)
        end
    end
    buf ./= max(1.0, maximum(abs, buf) / 0.85)
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

"Lumi on `spot`, the friends of every kind in a ring round it, nobody else near."
function mixup_setup(g, spot, cast)
    w = g.world
    x0, y0 = Float32.(spot)
    k = 0
    for x in w.creatures
        x.controlled = false
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
        a = 2f0 * Float32(pi) * (i - 1) / length(cast)
        x.pos = NG.ground(w.island, (x0 + 2.4f0 * cos(a), y0 + 2.4f0 * sin(a)))
        x.yaw = atan(y0 - x.pos[2], x0 - x.pos[1]) - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function mixup_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 16.0, hour = 9.6,
                    cast = ["Truffle", "Pinchy", "Cumulus", "Gloop", "Pickles", "Hopscotch", "Marshmallow", "Wibbles", "Sir Sniffsalot"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        M = Main.MIXUP
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            M[:t_gather] = 1.5; M[:t_mixed] = 8.5
            mixup_setup(g, spot, cast)
            S[:ok] = Base.invokelatest(M[:start])
        end
        e, tg = Base.invokelatest(g.plugins["mixup"].mod.mixup_view, w)
        s = M[:sys]
        rig.mode = :fixed
        if s.state in (:gather, :spell) || (s.state === :mixed && w.t - s.t0 < 2.5)
            rig.eye = e; rig.target = tg                       # the ring, the spell, the poof
        elseif s.state === :mixed
            rig.eye = e + 0.3f0 * (tg - e); rig.target = tg    # closer on the mixed-up friends
        else
            rig.eye = e + 0.2f0 * (tg - e); rig.target = tg    # the poof back
        end
        s.state === :after && !haskey(S, :end) && (S[:end] = t)
        return haskey(S, :end) ? S[:end] + 2.0 : nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> mixup_setup(g, spot, cast), shot)
    M = Main.MIXUP
    delete!(M, :t_gather); delete!(M, :t_mixed)
    log = [(t - S[:off], k) for (t, k) in get(M, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = mixup_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    voices = Tuple{Float64,String}[]
    poofs = [t for (t, k) in log if k === :poof]
    isempty(poofs) || push!(voices, (poofs[1] + 0.6, "oh"))
    length(poofs) >= 2 && push!(voices, (poofs[2] + 0.8, "haha"))
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
