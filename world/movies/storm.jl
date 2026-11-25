# The first thunderstorm (session 76): the black cloud, the bolts, the huddle under the Big Boing toadstool and
# the last bolt on Lumi's crest, with thunder synthesized from the strikes the storm plugin logged.
#   submit_job(:clip; path, script = "movies/storm.jl", call = "storm_clip", kwargs = Dict("centre" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

const SR = 44100

"Brown noise, low passed: the body of a rumble."
function rumble(n, rng_state)
    x = 0.0; y = 0.0; out = zeros(n); s = rng_state
    for i in 1:n
        s = (1103515245 * s + 12345) % 2147483648
        r = s / 2147483648 * 2 - 1
        x = 0.985 * x + 0.05 * r
        y = 0.93 * y + 0.07 * x
        out[i] = y
    end
    return out ./ max(maximum(abs, out), 1e-9)
end

function thunder!(buf, t, k; zap = false)
    i0 = round(Int, t * SR) + 1
    # the crack: a sharp noise burst
    s = 12345 + 977k
    for j in 0:round(Int, 0.3SR)
        i = i0 + j; i > length(buf) && break
        s = (1103515245 * s + 12345) % 2147483648
        buf[i] += 0.8 * (s / 2147483648 * 2 - 1) * exp(-j / (0.045SR))
    end
    # the rumble, rolling on with a flutter
    n = round(Int, 3.4SR)
    r = rumble(n, 999 + 31k)
    for j in 1:n
        i = i0 + round(Int, 0.06SR) + j; i > length(buf) && break
        u = j / SR
        env = min(1, u / 0.12) * exp(-u / 1.1) * (0.65 + 0.35 * sin(2pi * (2.3 + 0.4k) * u + k))
        buf[i] += 0.9 * env * r[j]
    end
    if zap   # a cartoon bzzzt, then a little pop
        for j in 0:round(Int, 0.45SR)
            i = i0 + j; i > length(buf) && break
            u = j / SR
            buf[i] += 0.25 * sign(sin(2pi * 92 * u)) * (0.6 + 0.4 * sin(2pi * 31 * u)) * exp(-u / 0.3)
        end
        ip = i0 + round(Int, 0.55SR)
        for j in 0:round(Int, 0.06SR)
            i = ip + j; i > length(buf) && break
            buf[i] += 0.5 * sin(2pi * 420 * j / SR) * exp(-j / (0.012SR))
        end
    end
end

function storm_wav(path, strikes, seconds)
    buf = zeros(Float64, round(Int, seconds * SR))
    # distant thunder while the cloud rolls in
    thunder!(buf, 1.2, 0)
    buf .*= 0.35
    for (k, (t, kind)) in enumerate(strikes)
        thunder!(buf, t, k; zap = kind === :zap)
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

function storm_clip(path; centre, spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 17.0, hour = 15.5)
    S = Dict{Symbol,Any}()
    cx, cy = Float32.(centre)
    sx, sy = Float32.(spot)
    setup = function (g)
        w = g.world
        u = Vec2f(sx - cx, sy - cy); u = u / hypot(u[1], u[2])
        v = Vec2f(-u[2], u[1])
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Pickles", "Hopscotch")
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (sx, sy)); c.yaw = atan(v[2], v[1]); c.goal = NG.Goal(); c.controlled = false
            elseif c.name in cast
                k += 1
                # out in the meadow on the far side of the toadstool and along it, so they run in
                a = atan(-u[2], -u[1]) + 0.55f0 * (k - 4)
                r = 6.5f0 + 1.2f0 * (k % 3)
                p = (cx + r * cos(a), cy + r * sin(a))
                NG.on_land(w.island, p[1], p[2]; margin = 0.3f0) || (p = (cx + 3f0 * cos(a), cy + 3f0 * sin(a)))
                c.pos = NG.ground(w.island, p); c.yaw = Float32(a + pi)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - cx, q[2] - cy) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        w = g.world
        if !haskey(S, :sys)
            S[:sys] = Main.STORM[:sys]
            Base.invokelatest(Main.STORM[:start])
            S[:off] = w.t - t
            # the storm's own view, from whichever side has less in the way
            s = S[:sys]
            eye, look = s.view
            mid = (s.centre + s.spot) / 2
            alt = Point3f(2mid[1] - eye[1], 2mid[2] - eye[2], eye[3])
            look = Point3f(look[1], look[2], look[3])
            ob(e) = Base.invokelatest(NG.obstruction, w, e, s.spot + Point3f(0, 0, 0.8f0)) +
                    Base.invokelatest(NG.obstruction, w, e, s.centre + Point3f(0, 0, 1f0))
            S[:eye] = ob(alt) < ob(eye) ? alt : eye
            S[:look] = look
        end
        s = S[:sys]
        rig.mode = :fixed
        # a slow push in over the whole storm (no cuts, no swings)
        push = Float32(min(t, 16.0) / 16.0)
        rig.eye = S[:eye] + 0.18f0 * push * (S[:look] - S[:eye])
        rig.target = S[:look]
        s.state === :idle && t > 6 && return t + 0.5
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    strikes = [(t - S[:off], k) for (t, k) in Main.STORM[:strikes] if t - S[:off] >= 0]
    wav = storm_wav(replace(path, ".mp4" => ".wav"), strikes, seconds + 1)
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return path
end

"""
A traced still of the moment the last bolt hits Lumi: a short take (2 frames a second, so only ~27 frames are traced)
that ends ~0.8 s after the zap, close on Lumi with the toadstool huddle behind; its last frame is written to `path` (png).
"""
function storm_still(path; centre, spot, samples = 64, width = 1280, height = 720, hour = 15.5)
    S = Dict{Symbol,Any}()
    cx, cy = Float32.(centre)
    sx, sy = Float32.(spot)
    take = replace(path, ".png" => "-take.mp4")
    clip_setup = function (g)
        w = g.world
        u = Vec2f(sx - cx, sy - cy); u = u / hypot(u[1], u[2])
        cast = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus", "Pickles", "Hopscotch")
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (sx, sy)); c.goal = NG.Goal(); c.controlled = false
            elseif c.name in cast
                k += 1
                a = atan(-u[2], -u[1]) + 0.55f0 * (k - 4)
                r = 6.5f0 + 1.2f0 * (k % 3)
                p = (cx + r * cos(a), cy + r * sin(a))
                NG.on_land(w.island, p[1], p[2]; margin = 0.3f0) || (p = (cx + 3f0 * cos(a), cy + 3f0 * sin(a)))
                c.pos = NG.ground(w.island, p); c.yaw = Float32(a + pi)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - cx, q[2] - cy) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        w = g.world
        if !haskey(S, :sys)
            S[:sys] = Main.STORM[:sys]
            Base.invokelatest(Main.STORM[:start])
        end
        s = S[:sys]
        me = NG.creature(w, s.lumi)
        # close on Lumi from the storm's own side, a little past it, looking back at the huddle under the toadstool
        u = Vec3f(me.pos[1] - s.centre[1], me.pos[2] - s.centre[2], 0); u = u / max(hypot(u[1], u[2]), 1f-3)
        side = Vec3f(s.view[1][1] - s.spot[1], s.view[1][2] - s.spot[2], 0); side = side / max(hypot(side[1], side[2]), 1f-3)
        rig.mode = :fixed
        rig.eye = me.pos + 4.4f0 * side + 1.6f0 * u + Point3f(0, 0, 0.9f0)
        rig.target = me.pos + Point3f(0, 0, 2.1f0) - 1.2f0 * u
        return nothing
    end
    NG.game_clip(take; size = (width, height), seconds = 13.8, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, setup = clip_setup, shot)
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)     # every frame over the same image: the last one stays
    return path
end
