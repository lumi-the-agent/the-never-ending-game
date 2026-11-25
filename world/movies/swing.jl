# The swing (session 79): a friend swings higher and higher while the others shout "Higher!", goes right over the
# top bar and flies off in a great arc. Sound from the plugin's log: a creak at every swing, a rising "wheee" for
# the loop, a whoosh as the rider lets go, a thump and a burst of giggles at the landing.
#   submit_job(:clip; path, script = "movies/swing.jl", call = "swing_clip", kwargs = Dict())
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
creak() = [0.16 * sin(2pi * (180 + 60sin(2pi * 9u)) * u) * exp(-u / 0.25) * (0.6 + 0.4sin(2pi * 37u)) for u in (0:round(Int, 0.45SR)) ./ SR]
function wheee(d)
    ph = 0.0
    map(0:round(Int, d * SR)) do j
        u = j / SR
        f = 380 + 520 * (u / d) + 25sin(2pi * 6u)
        ph += 2pi * f / SR
        0.22 * (sin(ph) + 0.3sin(2ph)) * min(1, u / 0.1) * min(1, (d - u) / 0.3)
    end
end
function noise(d, a, tau; seed = 5, smooth = 0.9)
    s = seed; y = 0.0
    map(0:round(Int, d * SR)) do j
        s = (1103515245 * s + 12345) % 2147483648
        y = smooth * y + (1 - smooth) * (s / 2147483648 * 2 - 1)
        a * y * exp(-j / (tau * SR))
    end
end
thump() = [0.7 * sin(2pi * (90 - 40u) * u) * exp(-u / 0.12) for u in (0:round(Int, 0.4SR)) ./ SR]
giggles() = vcat([[0.12 * sin(2pi * f * u) * exp(-u / 0.08) for u in (0:round(Int, 0.13SR)) ./ SR] for f in (880, 990, 830, 1046, 932, 1108, 880)]...)

function swing_wav(path, log, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    for (t, k) in log
        k === :creak && add!(buf, t, creak())
        k === :loop && add!(buf, t, wheee(2.6))
        k === :fly && add!(buf, t, 6 .* noise(1.0, 0.5, 0.5; smooth = 0.97))
        k === :land && (add!(buf, t, thump()); add!(buf, t + 0.25, giggles()))
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

function swing_clip(path; rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 15.0, hour = 16.0)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        # the cast close by, everyone else busy elsewhere
        x, y = 6f0, -15f0
        cast = ("Cumulus", "Pickles", "Gloop", "Hopscotch", "Wibbles")
        k = 0
        for c in w.creatures
            if c.name in cast
                k += 1
                a = Float32(2pi * k / length(cast))
                c.pos = NG.ground(w.island, (x + 3.4f0 * cos(a), y + 3.4f0 * sin(a))); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                c.controlled = true; c.goal = NG.Goal()
            end
        end
        # the rider: Cumulus nearest
        first_c = w.creatures[findfirst(c -> c.name == "Cumulus", w.creatures)]
        first_c.pos = NG.ground(w.island, (x - 0.8f0, y - 1.6f0))
    end
    shot = function (g, rig, t)
        W = Main.SWING
        s = W[:sys]
        if !haskey(S, :started)
            S[:started] = true
            S[:off] = g.world.t - t
            W[:t_swing] = 6.0
            Base.invokelatest(W[:start])
        end
        v = Base.invokelatest(g.plugins["swing"].mod.swing_group, g.world)
        rig.mode = :fixed
        if v !== nothing
            haskey(S, :view) || (S[:view] = v[3])
            rig.eye = S[:view][1]; rig.target = S[:view][2]
        end
        s.state === :idle && t > 5 && return t + 0.8
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    log = [(t - S[:off], k) for (t, k) in get(Main.SWING, :log, Tuple{Float64,Symbol}[]) if t - S[:off] >= 0]
    wav = swing_wav(replace(path, ".mp4" => ".wav"), log, seconds + 1)
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return path
end

"""
A traced still of the rider shooting off the swing (s79): a short take at 2 frames a second that ends 0.5 s after
the rider lets go; its last frame is written to `path` (png). The take goes to `take` (outside site/).
"""
function swing_still(path; take, samples = 64, width = 1280, height = 720, hour = 16.0)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = 6f0, -15f0
        cast = ("Cumulus", "Pickles", "Gloop", "Hopscotch", "Wibbles")
        k = 0
        for c in w.creatures
            if c.name in cast
                k += 1
                a = Float32(2pi * k / length(cast))
                c.pos = NG.ground(w.island, (x + 3.4f0 * cos(a), y + 3.4f0 * sin(a))); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                c.controlled = true; c.goal = NG.Goal()
            end
        end
        rider = w.creatures[findfirst(c -> c.name == "Pickles", w.creatures)]
        rider.pos = NG.ground(w.island, (x - 0.6f0, y - 1.2f0))
    end
    shot = function (g, rig, t)
        W = Main.SWING
        s = W[:sys]
        if !haskey(S, :started)
            S[:started] = true
            W[:t_swing] = 6.0
            Base.invokelatest(W[:start])
        end
        v = Base.invokelatest(g.plugins["swing"].mod.swing_group, g.world)
        rig.mode = :fixed
        if v !== nothing
            haskey(S, :view) || (S[:view] = v[3])
            # a little closer than the film's framing: the rider fills more of the picture
            e, tg = S[:view]
            rig.eye = e + 0.3f0 * (tg - e); rig.target = tg + Point3f(0, 0, 0.6f0)
        end
        s.state === :fly && !haskey(S, :fly) && (S[:fly] = t)
        haskey(S, :fly) && return S[:fly] + 0.5
        return nothing
    end
    NG.game_clip(take; size = (width, height), seconds = 30.0, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, setup, shot)
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)
    return path
end
