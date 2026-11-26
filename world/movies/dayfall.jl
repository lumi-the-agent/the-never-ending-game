using NeverendingGame, Makie
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
nrm(v) = sqrt(sum(abs2, v))

"A wandering line in local coordinates (u along the meadow, v toward the camera): a meander, then a spiral in."
function day_path()
    pts = Vec2f[]
    for u in -10f0:0.05f0:3f0
        push!(pts, Vec2f(u, 2.0f0 * sin(0.62f0 * (u + 10f0))))
    end
    c = Vec2f(6.2f0, 0f0)        # spiral in round c
    p0 = pts[end]
    a0 = atan(p0[2] - c[2], p0[1] - c[1]); r0 = nrm(p0 - c)
    for k in 1:600
        f = k / 600
        a = a0 - 2.3f0 * pi * f            # clockwise
        r = r0 + (1.3f0 - r0) * f
        push!(pts, c + r * Vec2f(cos(a), sin(a)))
    end
    # resample every 0.5 m
    out = [pts[1]]; acc = 0f0
    for i in 2:length(pts)
        acc += nrm(pts[i] - pts[i - 1])
        if acc >= 0.5f0
            push!(out, pts[i]); acc = 0f0
        end
    end
    out
end

"""
My day falls over and sings (s119): a line of tiles laid across the meadow, a meander then a spiral, tipped at the
start; the fall is the plugin's simulated chain, the camera runs along the front at friend height.
"""
function dayfall_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24,
                      seconds = 14.0, hour = 18.1)
    S = Dict{Any,Any}()
    isdefined(Main, :DAYFALL) || Core.eval(Main, :(const DAYFALL = Dict{Symbol,Any}()))
    DF = Main.DAYFALL
    DF[:force] = true
    shot = function (g, rig, t)
        w = g.world
        DF[:force] = true
        if !haskey(S, :go)
            S[:go] = true
            if isdefined(Main, :SEESAW) && haskey(Main.SEESAW, :sys)
                for c in w.creatures
                    Main.SEESAW[:weights][c.id] = 0f0
                end
                Main.SEESAW[:sys].tilt = Vec2f(0); Main.SEESAW[:sys].spin = Vec2f(0)
            end
            if isdefined(Main, :WORDSAND) && haskey(Main.WORDSAND, :H)
                Main.WORDSAND[:H] .= 0; Main.WORDSAND[:dirty] = true; Main.WORDSAND[:gain] = 0f0
            end
            isdefined(Main, :TIED) && (Main.TIED[:force] = false)
            isdefined(Main, :JELLY) && (Main.JELLY[:force] = true)
            P = day_path()
            props = [(Vec2f(p.pos[1], p.pos[2]), p.kind) for p in w.props]
            best = (Vec2f(0), 0f0); bs = -Inf32
            for x in -24f0:1f0:24f0, y in -24f0:1f0:24f0, ang in 0f0:0.5236f0:6.2f0
                d = Vec2f(cos(ang), sin(ang)); n = Vec2f(-d[2], d[1])
                q = Vec2f(x, y)
                ok = true
                for p in P[1:4:end]
                    wp = q + p[1] * d + p[2] * n
                    NG.terrain_height(w.island, wp...) > 0.7f0 || (ok = false; break)
                    # the pond, the cottage and its garden are drawn by plugins, not props: keep well away
                    nrm(wp - Vec2f(-5.5f0, 10.5f0)) > 9f0 || (ok = false; break)
                    nrm(wp - Vec2f(18f0, -1.5f0)) > 7f0 || (ok = false; break)       # the old television
                    if isdefined(Main, :EXTRA_SOLIDS)                                  # easels, benches, huts...
                        for (_, sol) in Main.EXTRA_SOLIDS, (c, r) in sol
                            nrm(wp - Vec2f(c[1], c[2])) > r + 1.5f0 || (ok = false; break)
                        end
                        ok || break
                    end
                end
                ok || continue
                sc = 0f0
                for (pp, kind) in props, p in P[1:3:end]
                    nrm(pp - (q + p[1] * d + p[2] * n)) < (kind === :tree ? 2.2f0 : 1.0f0) && (sc -= 1f0)
                end
                # the camera side (v up to 6 m) clear of trees
                for (pp, kind) in props
                    kind === :tree || continue
                    for u in -10f0:2f0:8f0
                        nrm(pp - (q + u * d + 5f0 * n)) < 2.5f0 && (sc -= 0.5f0)
                    end
                end
                sc -= 0.01f0 * nrm(q)
                sc > bs && (bs = sc; best = (q, ang))
            end
            q, ang = best
            d = Vec2f(cos(ang), sin(ang)); n = Vec2f(-d[2], d[1])
            S[:q] = q; S[:d] = d; S[:n] = n
            DF[:reset]()
            for (k, p) in enumerate(P)
                DF[:lay](g, q + p[1] * d + p[2] * n, "")
            end
            l = first(c for c in w.creatures if c.species == "Lumi")
            st = DF[:base][1]
            l.pos = NG.ground(w.island, ((Vec2f(st[1], st[2]) - 0.9f0 * DF[:dir][1])...,))
            l.yaw = Float32(atan(DF[:dir][1][2], DF[:dir][1][1])) - NG.species_of(l).heading
            l.action = :idle; l.goal = NG.Goal(:film, l.pos, :idle, 600.0, w.t + 600, true, 0, false)
            # friends stand beside the line, waiting for it
            spots = (14, 24, 33, 44, 55, 63)
            others = [c for c in w.creatures if c !== l]
            for (j, c) in enumerate(others)
                if j <= length(spots) && spots[j] <= length(DF[:base])
                    b = DF[:base][spots[j]]; dd = DF[:dir][spots[j]]
                    side = (j % 2 == 0 ? 1f0 : -1f0) * Vec2f(-dd[2], dd[1])
                    xy = Vec2f(b[1], b[2]) + 0.75f0 * side
                    c.pos = NG.ground(w.island, (xy...,))
                    c.yaw = Float32(atan(-side[2], -side[1])) - NG.species_of(c).heading
                else
                    xy = q - 12f0 * n + Float32(j) * d
                    c.pos = NG.ground(w.island, (xy...,))
                end
                c.action = :idle; c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
            S[:l] = l
        end
        if t >= 0.2 && t < 0.9 && haskey(S, :l)
            st = DF[:base][1]; dd = DF[:dir][1]; u = Float32((t - 0.2) / 0.7)
            xy = Vec2f(st[1], st[2]) - (0.9f0 - 0.6f0 * u) * dd
            S[:l].pos = Point3f(xy[1], xy[2], NG.ground(w.island, (xy...,))[3] + 0.35f0 * sin(Float32(pi) * u))
        end
        if t >= 0.9 && !haskey(S, :tipped)
            S[:tipped] = true
            NG.say!(w, S[:l], "Goodnight, day."; duration = 1.6)
            DF[:tip](g)
        end
        # the camera: along the front at friend height, rising over the spiral at the end
        B = DF[:base]
        k = clamp(get(DF, :front, 1), 1, length(B))
        k2 = clamp(k + 5, 1, length(B))
        fr = Vec2f(B[k][1], B[k][2]); ah = Vec2f(B[k2][1], B[k2][2])
        n = S[:n]; d = S[:d]
        spiral = Vec2f(S[:q] + 6.2f0 * d)
        late = Float32(smooth((t - (seconds - 4.0)) / 3.0))
        tgt2 = fr * (1 - late) + spiral * late
        gz = NG.ground(w.island, (tgt2...,))[3]
        eye2 = tgt2 + n * (5.4f0 + 2.0f0 * late) - d * (3.0f0 * (1 - late))
        eye = Point3f(eye2[1], eye2[2], gz + 2.0f0 + 3.0f0 * late)
        tg = Point3f(tgt2[1] + 0.8f0 * d[1] * (1 - late), tgt2[2] + 0.8f0 * d[2] * (1 - late), gz + 0.45f0)
        if haskey(S, :eye)
            a = 0.06f0
            eye = Point3f(S[:eye] + a * (eye - S[:eye])); tg = Point3f(S[:tg] + a * (tg - S[:tg]))
        end
        S[:eye] = eye; S[:tg] = tg
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.5, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, q = S[:q])
end
