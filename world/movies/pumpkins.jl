# Pumpkin bowling (session 83, plugins/pumpkins.jl): thirty pumpkins stacked on the flower meadow, the friends
# behind them, Lumi's run-up and the STRIKE, then the pumpkins tumbling where the physics takes them. Three shots:
# wide on the stack, close behind Lumi for the run and the crash, wide again for the tumble. The sound is the
# plugin's log of this take: a thump at the strike, knocks where pumpkins bonk a friend, Lumi's "wheee" and laugh.
#   submit_job(:clip; path, script = "movies/pumpkins.jl", call = "pumpkins_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

lcg(s) = (s = (1103515245 * s + 12345) % 2147483648; (s, s / 2147483648))

"A big hollow thump (the strike) or a small knock (a pumpkin on someone's head)."
function thump(big)
    n = round(Int, (big ? 0.9 : 0.35) * SR); s = big ? 11 : 3; y = 0.0
    map(1:n) do j
        u = j / SR
        s, r = lcg(s)
        y = 0.9y + 0.1 * (2r - 1)
        f = big ? 70 - 25u : 190
        (big ? 0.8 : 0.5) * sin(2pi * f * u) * exp(-u / (big ? 0.16 : 0.05)) + (big ? 1.2 : 0.6) * y * exp(-u / (big ? 0.12 : 0.03))
    end
end

function pumpkins_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, k) in log
        k in (:strike, :bonk) || continue
        a = thump(k === :strike); j0 = round(Int, t * SR)
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

"Lumi at its start south of the stack, the cast on the far side, everyone else parked out of the way (on land)."
function pumpkins_setup(g, cast)
    P = g.plugins["pumpkins"].mod
    w = g.world
    c = P.SPOT
    n = length(cast)
    k = 0
    for x in w.creatures
        x.controlled = false
        if x.name == "Lumi"
            x.pos = NG.ground(w.island, (c[1], c[2] - 6f0)); x.yaw = Float32(pi / 2) - NG.species_of(x).heading
            x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
            continue
        end
        i = findfirst(==(x.name), cast)
        if i === nothing
            k += 1
            for r in 22f0:2f0:40f0                # far east along the meadow, wherever there is land
                q = (c[1] - 4f0 + 1.4f0 * k, c[2] + r)
                if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                    x.pos = NG.ground(w.island, q); break
                end
            end
            x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = Float32(pi / 2) + Float32(pi) * (-0.35f0 + 0.7f0 * (i - 1) / max(n - 1, 1))
        r = 4.2f0 + 0.08f0 * i
        x.pos = NG.ground(w.island, (c[1] + r * cos(a), c[2] + r * sin(a)))
        x.yaw = atan(c[2] - x.pos[2], c[1] - x.pos[1]) - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function pumpkins_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 14.8,
                       cast = ["Wibbles", "Truffle", "Cumulus", "Gloop", "Marshmallow"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        P = Main.PUMPKINS
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            P[:t_gather] = 1.6
            pumpkins_setup(g, cast)
            S[:ok] = Base.invokelatest(P[:start])
        end
        s = P[:sys]
        m = g.plugins["pumpkins"].mod
        me = w.creatures[findfirst(x -> x.name == "Lumi", w.creatures)]
        e, tg = Base.invokelatest(m.pumpkin_view, w)
        d = get(P, :dir, Vec2f(0, 1)); side = Vec3f(-d[2], d[1], 0); dir = Vec3f(d[1], d[2], 0)
        s.state === :run && !haskey(S, :run) && (S[:run] = t)
        s.state === :tumble && !haskey(S, :hit) && (S[:hit] = t)
        rig.mode = :fixed
        if haskey(S, :run) && t < get(S, :hit, Inf) + 0.6
            # close behind Lumi's shoulder as it charges in (held still once it stops)
            haskey(S, :hit) || (S[:me] = me.pos)
            p = S[:me]
            rig.eye = p - 2.6f0 * dir + 1.1f0 * side + Point3f(0, 0, 1.35f0)
            rig.target = p + 2.2f0 * dir + Point3f(0, 0, 0.7f0)
        elseif haskey(S, :hit)
            u = Float32(min(t - S[:hit], 8) / 8)
            rig.eye = e + (0.35f0 - 0.1f0 * u) * (tg - e); rig.target = tg
        else
            rig.eye = e + 0.3f0 * (tg - e); rig.target = tg
        end
        haskey(S, :hit) && t > S[:hit] + 8.0 && return t
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> pumpkins_setup(g, cast), shot)
    P = Main.PUMPKINS
    delete!(P, :t_gather)
    log = [(t - S[:off], k) for (t, k) in get(P, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = pumpkins_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    voices = Tuple{Float64,String}[]
    for (t, k) in log
        k === :run && push!(voices, (t + 0.1, "wheee"))
        k === :strike && push!(voices, (t + 1.0, "haha"))
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
    return (path = path, started = S[:ok], log = log, run = get(S, :run, nothing), hit = get(S, :hit, nothing))
end
