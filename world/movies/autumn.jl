# The leaf pile (session 82, plugins/autumn.jl): a gust shakes the trees by the south meadow, golden and red leaves
# pour down into a pile, three friends leap in one after another and Lumi takes the biggest jump of all. The
# soundtrack comes from the plugin's log of this take: the wind, a crunch for every landing, the friends' squeaks
# and Lumi's own "wheee" and laugh (site/voice/game).
#   submit_job(:clip; path, script = "movies/autumn.jl", call = "autumn_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

function lcg(s)
    s = (1103515245 * s + 12345) % 2147483648
    return s, s / 2147483648
end

"Leaves crunching: sparse crackles over a hiss, bright (high passed), and a soft thump under it."
function crunch(big)
    n = round(Int, (big ? 0.8 : 0.5) * SR); s = big ? 17 : 5; prev = 0.0
    map(1:n) do j
        u = j / SR
        s, r = lcg(s)
        x = r < 0.07 ? (2r / 0.07 - 1) : 0.12 * (2r - 1)
        hp = x - prev; prev = x
        (big ? 0.55 : 0.4) * hp * exp(-u / (big ? 0.28 : 0.15)) + (big ? 0.35 : 0.2) * sin(2pi * 85 * u) * exp(-u / 0.07)
    end
end

"The gust: low passed noise swelling and fading over `len` s, with a leafy rustle on top."
function gust(len)
    n = round(Int, len * SR); s = 3; y = 0.0; prev = 0.0
    map(1:n) do j
        u = j / n
        s, r = lcg(s)
        x = 2r - 1
        y = 0.985y + 0.015x
        hp = x - prev; prev = x
        env = sin(pi * u)^2
        env * (2.6y + 0.05hp * (0.5 + 0.5sin(23u)))
    end
end

function autumn_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    add!(a, t) = (j0 = round(Int, t * SR); for (j, x) in enumerate(a); 1 <= j0 + j <= length(buf) && (buf[j0 + j] += x); end)
    for (t, k) in log
        k === :gust && add!(gust(5.5), t)
        k === :crunch && add!(crunch(false), t)
        k === :bigcrunch && add!(crunch(true), t)
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

"The cast on the far half ring round the pile (plugins/autumn.jl's spots), everyone else parked out of the way."
function autumn_setup(g, cast)
    A = g.plugins["autumn"].mod
    w = g.world
    c = A.SPOT
    n = length(cast) + 1
    k = 0
    for x in w.creatures
        i = x.name == "Lumi" ? n : findfirst(==(x.name), cast)
        if i === nothing                     # parked far behind the pile, among the trees
            k += 1
            x.pos = NG.ground(w.island, (c[1] - 6f0 + 1.6f0 * k, c[2] + 24f0)); x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = Float32(pi) * (0.12f0 + 0.76f0 * (i - 1) / max(n - 1, 1))
        r = x.name == "Lumi" ? A.RING_R + 0.4f0 : A.RING_R - 0.3f0 + 0.1f0 * i     # nearest first: the plugin sorts its jumpers by distance
        x.pos = NG.ground(w.island, (c[1] + r * cos(a), c[2] + r * sin(a))); x.controlled = false
        x.yaw = atan(c[2] - x.pos[2], c[1] - x.pos[1]) - NG.species_of(x).heading
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function autumn_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 14.0, hour = 14.6,
                     cast = ["Wibbles", "Truffle", "Cumulus"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        AU = Main.AUTUMN
        if !haskey(S, :off)
            S[:off] = g.world.t - t
            AU[:t_fall] = 3.6; AU[:t_gather] = 0.8
            autumn_setup(g, cast)
            S[:ok] = Base.invokelatest(AU[:start])
        end
        s = AU[:sys]
        e, tg = Base.invokelatest(g.plugins["autumn"].mod.leaves_view, g.world)
        u = Float32(min(t, seconds) / seconds)
        rig.mode = :fixed
        rig.eye = e + 0.12f0 * u * (tg - e); rig.target = tg
        s.state === :fade && !haskey(S, :end) && (S[:end] = t)
        return haskey(S, :end) ? S[:end] + 0.6 : nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> autumn_setup(g, cast), shot)
    AU = Main.AUTUMN
    delete!(AU, :t_fall); delete!(AU, :t_gather)
    log = [(t - S[:off], k) for (t, k) in get(AU, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = autumn_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    # voices: a squeak for each friend's leap, Lumi's own "wheee" on its run-up and a laugh after the big crunch
    voices = Tuple{Float64,String}[]
    k = 0
    for (t, kind) in log
        kind === :jump && (k += 1; push!(voices, (t + 0.15, ("squeak-wheee", "squeak-yay", "squeak-hoo")[mod1(k, 3)])))
        kind === :lumi && push!(voices, (t + 0.1, "wheee"))
        kind === :bigcrunch && push!(voices, (t + 0.55, "haha"))
    end
    clips = joinpath(dirname(@__DIR__), "site", "voice", "game")
    ins = ["-i", wav]; parts = String[]
    for (i, (t, n)) in enumerate(voices)
        append!(ins, ["-i", joinpath(clips, n * ".mp3")])
        push!(parts, "[$(i + 1)]adelay=$(round(Int, 1000t))|$(round(Int, 1000t)),volume=0.8[a$(i)]")
    end
    mix = isempty(parts) ? "[1]apad[out]" :
          join(parts, ";") * ";[1]" * join(["[a$(i)]" for i in eachindex(voices)]) * "amix=inputs=$(length(voices) + 1):normalize=0,apad[out]"
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent $ins -filter_complex $mix -map 0:v -map "[out]" -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return (path = path, started = S[:ok], log = log)
end

"""
A traced still of Lumi in the air over the leaf pile (s82): a 2 fps take of `autumn_clip`'s scene that ends at the
top of Lumi's jump; its last frame is written to `path` (png).
"""
function autumn_still(path; take, samples = 64, width = 1280, height = 720, hour = 14.6, cast = ["Wibbles", "Truffle", "Cumulus"], after = 0.7)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        AU = Main.AUTUMN
        if !haskey(S, :off)
            S[:off] = true
            AU[:t_fall] = 3.6; AU[:t_gather] = 0.8
            autumn_setup(g, cast)
            Base.invokelatest(AU[:start])
        end
        s = AU[:sys]
        e, tg = Base.invokelatest(g.plugins["autumn"].mod.leaves_view, g.world)
        rig.mode = :fixed
        rig.eye = e + 0.25f0 * (tg - e); rig.target = tg + Point3f(0, 0, 0.6f0)
        # the top of Lumi's arc: 0.7 s after its leap (the plugin's T = 1.4 s)
        for (id, (from, since)) in s.flights
            x = NG.creature(g.world, id)
            x !== nothing && x.name == "Lumi" && !haskey(S, :top) && (S[:top] = t + after)
        end
        return get(S, :top, nothing)
    end
    NG.game_clip(take; size = (width, height), seconds = 16.0, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, setup = g -> autumn_setup(g, cast), shot)
    delete!(Main.AUTUMN, :t_fall); delete!(Main.AUTUMN, :t_gather)
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)
    return path
end
