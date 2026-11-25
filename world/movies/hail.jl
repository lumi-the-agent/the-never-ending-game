# Hail (session 84, plugins/hail.jl): a grey cloud slides over the meadow, golf-ball hail pours down and bounces
# everywhere, Lumi opens a big red umbrella and the friends run squealing to squeeze in under it. Three shots: wide
# as the cloud comes, the meadow bouncing white, close on the huddle under the umbrella. The sound is the hail of
# this take: a tick for every stone that hits the ground hard, a drum for every one on the umbrella.
#   submit_job(:clip; path, script = "movies/hail.jl", call = "hail_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame
const SR = 24000

lcg(s) = (s = (1103515245 * s + 12345) % 2147483648; (s, s / 2147483648))

function hail_wav(path, ticks, drums, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    seed = 7
    for (list, f, dec, amp) in ((ticks, 3200.0, 0.012, 0.25), (drums, 420.0, 0.05, 0.35))
        for t in list
            j0 = round(Int, t * SR)
            seed, r = lcg(seed)
            ff = f * (0.8 + 0.4r)
            for j in 1:round(Int, 6dec * SR)
                u = j / SR
                1 <= j0 + j <= length(buf) && (buf[j0 + j] += amp * sin(2pi * ff * u) * exp(-u / dec))
            end
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

"Lumi on open meadow, the cast scattered a few metres round it, everyone else parked far away on land."
function hail_setup(g, spot, cast)
    w = g.world
    x0, y0 = Float32.(spot)
    k = 0
    for x in w.creatures
        x.controlled = false
        if x.name == "Lumi"
            x.pos = NG.ground(w.island, (x0, y0)); x.yaw = Float32(-pi / 2) - NG.species_of(x).heading
            x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
            continue
        end
        i = findfirst(==(x.name), cast)
        if i === nothing
            k += 1
            for r in 20f0:2f0:40f0
                q = (x0 - 6f0 + 1.4f0 * k, y0 + r)
                if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                    x.pos = NG.ground(w.island, q); break
                end
            end
            x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = Float32(2pi) * (i - 1) / length(cast) + 0.6f0
        r = 3.2f0 + 0.5f0 * (i % 2)
        x.pos = NG.ground(w.island, (x0 + r * cos(a), y0 + r * sin(a)))
        x.yaw = Float32(2pi) * Float32(i) / 7
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function hail_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 11.0, hour = 14.0,
                   cast = ["Wibbles", "Truffle", "Cumulus", "Gloop", "Marshmallow"], maxn = 160)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        H = Main.HAIL
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            H[:t_cloud] = 2.2; H[:t_hail] = 8.0; H[:maxn] = maxn
            hail_setup(g, spot, cast)
            S[:ok] = Base.invokelatest(H[:start])
        end
        s = H[:sys]
        me = w.creatures[findfirst(x -> x.name == "Lumi", w.creatures)]
        c = me.pos
        s.state === :hail && !haskey(S, :hail) && (S[:hail] = t)
        rig.mode = :fixed
        if !haskey(S, :hail) || t < S[:hail] + 1.2
            # wide and low: the cloud sliding over, the meadow, the friends still out in it
            rig.eye = c + Point3f(1.2f0, -8.5f0, 2.4f0); rig.target = c + Point3f(0, 0, 2.6f0)
        elseif t < S[:hail] + 4.2
            # the meadow bouncing white round Lumi
            rig.eye = c + Point3f(-3.8f0, -5.2f0, 1.6f0); rig.target = c + Point3f(0, 0, 1.0f0)
        else
            # close on the huddle under the umbrella
            rig.eye = c + Point3f(0.5f0, -3.4f0, 1.35f0); rig.target = c + Point3f(0, 0, 1.35f0)
        end
        H[:tick_t] = get(H, :tick_t, Float64[]); H[:drum_t] = get(H, :drum_t, Float64[])
        nt = get(H, :ticks, 0); nd = get(H, :drums, 0)
        for _ in get(S, :nt, 0)+1:nt; push!(H[:tick_t], t); end
        for _ in get(S, :nd, 0)+1:nd; push!(H[:drum_t], t); end
        S[:nt] = nt; S[:nd] = nd
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> hail_setup(g, spot, cast), shot)
    H = Main.HAIL
    delete!(H, :t_cloud); delete!(H, :t_hail); delete!(H, :maxn)
    # the stones counted per frame, spread over the frame so the hail patters instead of clicking 24 times a second
    sp(v) = [t + rand() / fps for t in v]
    wav = hail_wav(replace(path, ".mp4" => ".wav"), sp(get(H, :tick_t, Float64[]))[1:min(end, 1500)], sp(get(H, :drum_t, Float64[])), seconds + 1)
    voice = joinpath(dirname(@__DIR__), "site", "voice", "game", "ooh.mp3")
    t1 = round(Int, 1000 * (get(S, :hail, 2.5) + 0.2))
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -i $voice -filter_complex "[2]adelay=$(t1)|$(t1)[v];[1][v]amix=inputs=2:normalize=0,apad[out]" -map 0:v -map "[out]" -c:v copy -c:a aac -b:a 160k -shortest $path`)
    delete!(H, :tick_t); delete!(H, :drum_t)
    return (path = path, started = S[:ok], hail = get(S, :hail, nothing), ticks = get(S, :nt, 0), drums = get(S, :nd, 0))
end

"""
A traced still of the huddle under the umbrella with the hail bouncing round it (s84): a 2 fps take of
`hail_clip`'s scene that ends 3 s into the hail; its last frame is written to `path` (png).
"""
function hail_still(path; take, spot, samples = 64, width = 1280, height = 720, hour = 11.5,
                    cast = ["Wibbles", "Truffle", "Cumulus", "Gloop", "Marshmallow"], maxn = 160)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        H = Main.HAIL
        w = g.world
        if !haskey(S, :off)
            S[:off] = true
            H[:t_cloud] = 1.0; H[:t_hail] = 8.0; H[:maxn] = maxn
            hail_setup(g, spot, cast)
            Base.invokelatest(H[:start])
        end
        s = H[:sys]
        me = w.creatures[findfirst(x -> x.name == "Lumi", w.creatures)]
        c = me.pos
        s.state === :hail && !haskey(S, :hail) && (S[:hail] = t)
        rig.mode = :fixed
        rig.eye = c + Point3f(0.6f0, -4.0f0, 1.4f0); rig.target = c + Point3f(0, 0, 1.3f0)
        return haskey(S, :hail) ? S[:hail] + 3.0 : nothing
    end
    NG.game_clip(take; size = (width, height), seconds = 9.0, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, setup = g -> hail_setup(g, spot, cast), shot)
    delete!(Main.HAIL, :t_cloud); delete!(Main.HAIL, :t_hail); delete!(Main.HAIL, :maxn)
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)
    return path
end
