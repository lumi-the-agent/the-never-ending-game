# The island weighs its words (session 115, plugins/wordsand.jl): everything said pours out as sand at the
# speaker's feet. Close on Gloop shouting "Higher!" as his heap lifts him, then the camera rises and the
# talk speeds up (a timelapse) until the meadow has three dunes: Gloop's, the argument's, the gossip's.
#   submit_job(:clip; path, script = "movies/wordsand.jl", call = "wordsand_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

function wordsand_clip(path; rasterize = true, samples = 20, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 17.6)
    S = Dict{Any,Any}()
    gloop_lines = ("Higher!", "HIGHER!", "Boing time for me!", "Higher!!", "HIGHER! HIGHER!", "Look at me!")
    fight = ("My hut!", "NO! MY hut!", "Total DRAMBLY!", "It is NOT!", "Is TOO!", "Hmph!")
    gossip = ("Did you hear?", "No way!", "Tell me more", "Ooh!", "And then?", "Shh, listen")
    shot = function (g, rig, t)
        w = g.world
        WS = Main.WORDSAND
        if !haskey(S, :go)
            S[:go] = true
            haskey(WS, :H) && (WS[:H] .= 0; WS[:dirty] = true)
            byname(n) = NG.creature(w, n)
            gl = byname("Gloop")
            rest = [c for c in w.creatures if c !== gl && c.species != "Lumi"]
            lumi = first(c for c in w.creatures if c.species == "Lumi")
            S[:gloop] = gl
            S[:fight] = rest[1:3]
            S[:gossip] = vcat(rest[4:min(end, 7)], [lumi])
            S[:sleep] = rest[8:end]
            place(c, x, y, face) = (c.pos = NG.ground(w.island, (Float32(x), Float32(y)));
                                    c.action = :idle; c.yaw = Float32(face) - NG.species_of(c).heading;
                                    c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false))
            place(gl, -16.0, 7.0, -0.7)
            for (k, c) in enumerate(S[:fight])
                a = 2.1 * k
                place(c, -13.5 + 1.3cos(a), 11.5 + 1.3sin(a), a + pi)
            end
            for (k, c) in enumerate(S[:gossip])
                a = 1.6 * k
                place(c, -16.5 + 1.5cos(a), 2.0 + 1.5sin(a), a + pi)
            end
            for (k, c) in enumerate(S[:sleep])
                place(c, 6.0 + 2k, -14.0, 0.0)
            end
            S[:next] = Dict{Any,Float64}(:g => 0.3, :f => 1.5, :s => 2.2)
            S[:k] = Dict{Any,Int}(:g => 0, :f => 0, :s => 0)
        end
        # the talk: slow at first, then a timelapse with heavier words
        WS[:speed] = t < 4.5 ? 1.5f0 : 4f0
        WS[:maxh] = 8f0
        WS[:gain] = t < 4.5 ? 4f0 : 4f0 + 10f0 * Float32(smooth((t - 4.5) / 4))
        gap = t < 4.5 ? 1.3 : 0.45
        nx = S[:next]
        if t >= nx[:g]
            S[:k][:g] += 1
            NG.say!(w, S[:gloop], gloop_lines[mod1(S[:k][:g], length(gloop_lines))]; duration = gap * 0.9)
            nx[:g] = t + gap
        end
        if t >= nx[:f]
            S[:k][:f] += 1
            NG.say!(w, S[:fight][mod1(S[:k][:f], length(S[:fight]))], fight[mod1(S[:k][:f], length(fight))]; duration = gap * 1.6)
            nx[:f] = t + gap * 0.7
        end
        if t >= nx[:s]
            S[:k][:s] += 1
            NG.say!(w, S[:gossip][mod1(S[:k][:s], length(S[:gossip]))], gossip[mod1(S[:k][:s], length(gossip))]; duration = gap * 1.6)
            nx[:s] = t + gap * 0.9
        end
        for c in vcat([S[:gloop]], S[:fight], S[:gossip])
            c.action = :idle
        end
        # the camera: close on Gloop, then up and back over the meadow
        gp = S[:gloop].pos
        u = smooth((t - 4.0) / 7.5)
        near_eye = Point3f(gp[1] + 3.6f0, gp[2] - 3.0f0, gp[3] + 1.2f0)
        near_tg = Point3f(gp[1], gp[2], gp[3] + 0.9f0)
        far_eye = Point3f(-3.5f0, -2.5f0, 10.5f0)
        far_tg = Point3f(-15.5f0, 7.0f0, 1.0f0)
        eye = near_eye + (far_eye - near_eye) * Float32(u)
        tg = near_tg + (far_tg - near_tg) * Float32(u)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, poured = get(Main.WORDSAND, :poured, -1), peak = maximum(get(Main.WORDSAND, :H, [0f0])))
end

# Sledding (s115): a dune by the workshop, four friends on top; one after another they throw themselves down it.
function sled_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 7.0, hour = 16.5)
    S = Dict{Any,Any}()
    shot = function (g, rig, t)
        w = g.world
        WS = Main.WORDSAND
        m = g.plugins["wordsand"].mod
        cx, cy = -4.0f0, 6.0f0
        if !haskey(S, :go)
            S[:go] = true
            WS[:maxh] = 8f0
            H = WS[:H]; H .= 0
            for _ in 1:6
                m.deposit!(H, cx, cy, 0.6f0)
            end
            WS[:box] = (1, m.N, 1, m.N); WS[:dirty] = true
            S[:who] = [c for c in w.creatures if c.species != "Lumi"][1:4]
            for (k, c) in enumerate(S[:who])
                a = 1.2f0 * k
                x, y = cx + 0.7f0 * cos(a), cy + 0.7f0 * sin(a)
                c.pos = Point3f(x, y, NG.terrain_height(w.island, x, y) + m.sand_at(H, x, y))
                c.action = :idle
                c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
            S[:sent] = 0
        end
        k = S[:sent] + 1
        if k <= length(S[:who]) && t > 0.6 + 1.4 * (k - 1)
            S[:sent] = k
            sleds = get!(() -> Dict{Int32,Any}(), WS, :sleds)
            m.start_sled!(w, WS[:H], S[:who][k], sleds)
        end
        eye = Point3f(cx + 9.5f0, cy - 7.5f0, 5.5f0)
        tg = Point3f(cx, cy, 2.2f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, slides = get(Main.WORDSAND, :sleds, nothing))
end
