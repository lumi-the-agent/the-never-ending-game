# The cannonball contest at the lily pond (session 86, plugins/splash.jl): the friends leap into the pond one
# after another, the two crabs judge, and Lumi goes last with the run-up of its life. Three shots: wide on the
# pond and the line-up, closer for the friends' splashes, low at the water for Lumi's. The sound is this take's
# splashes (from the plugin's log) and Lumi's own "wheee" and laugh.
#   submit_job(:clip; path, script = "movies/splash.jl", call = "splash_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

lcg(s) = (s = (1103515245 * s + 12345) % 2147483648; (s, s / 2147483648))

function splash_sound(big)
    n = round(Int, (big ? 1.4 : 0.9) * SR); s = big ? 9 : 4; y = 0.0
    map(1:n) do j
        u = j / SR
        s, r = lcg(s)
        y = 0.75y + 0.25 * (2r - 1)
        (big ? 0.9 : 0.6) * y * exp(-u / (big ? 0.35 : 0.2)) + (big ? 0.4 : 0.25) * sin(2pi * (160 - 90u) * u) * exp(-u / 0.08)
    end
end

function splash_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, k) in log
        k in (:splash, :big) || continue
        a = splash_sound(k === :big); j0 = round(Int, t * SR)
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

"The divers and the crab judges round the pond, everyone else parked far off on land."
function splash_setup(g, divers, judges)
    w = g.world
    A = g.plugins["areas"].mod
    P = A.POND; R = A.POND_R
    k = 0
    cast = vcat(["Lumi"], divers, judges)
    for x in w.creatures
        i = findfirst(==(x.name), cast)
        x.controlled = false
        if i === nothing
            k += 1
            for r in 20f0:2f0:40f0
                q = (P[1] - 6f0 + 1.4f0 * k, P[2] - r)
                if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                    x.pos = NG.ground(w.island, q); break
                end
            end
            x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = 2f0 * Float32(pi) * (i - 1) / length(cast)
        x.pos = NG.ground(w.island, (P[1] + (R + 1.4f0) * cos(a), P[2] + (R + 1.4f0) * sin(a)))
        x.yaw = atan(P[2] - x.pos[2], P[1] - x.pos[1]) - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function splash_clip(path; rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 14.8,
                     divers = ["Wibbles", "Truffle", "Cumulus"], judges = ["Pinchy", "Hopscotch"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        SPd = Main.SPLASH
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            SPd[:t_gather] = 2.6
            splash_setup(g, divers, judges)
            S[:ok] = Base.invokelatest(SPd[:start])
        end
        s = SPd[:sys]
        v = get(SPd, :view, nothing)
        v === nothing && return nothing
        e, tg = v
        landed = count(x -> x[2] in (:splash, :big), get(SPd, :log, Tuple{Float64,Symbol}[]))
        lumi_jumping = any(x -> x[2] === :lumi, get(SPd, :log, Tuple{Float64,Symbol}[]))
        rig.mode = :fixed
        if landed == 0
            rig.eye = e; rig.target = tg                                  # the pond and the line-up
        elseif !lumi_jumping
            rig.eye = e + 0.35f0 * (tg - e); rig.target = tg               # closer for the friends' splashes
        else
            # low at the water's edge for Lumi's big one, the splash against the sky
            d = tg - e; d = Vec3f(d[1], d[2], 0) / hypot(d[1], d[2])
            rig.eye = tg - 3.6f0 * d + Point3f(0, 0, -0.3f0); rig.target = tg + Point3f(0, 0, 0.4f0)
        end
        s.state === :after && !haskey(S, :end) && (S[:end] = t)
        return haskey(S, :end) ? S[:end] + 2.0 : nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> splash_setup(g, divers, judges), shot)
    SPd = Main.SPLASH
    delete!(SPd, :t_gather)
    log = [(t - S[:off], k) for (t, k) in get(SPd, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = splash_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    voices = Tuple{Float64,String}[]
    for (t, k) in log
        k === :lumi && push!(voices, (t + 0.1, "wheee"))
        k === :big && push!(voices, (t + 1.2, "haha"))
    end
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
