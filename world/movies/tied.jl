# Tied together (s117): the friends stand in a ring round a tree, the rope appears (tied.jl ties them
# nearest to nearest, so it runs round the trunk), and everyone sets off outward, each its own way.
# The rope does the rest.
using NeverendingGame, Makie, LinearAlgebra
const NG = NeverendingGame

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

"A tree in open meadow: far from other trees, on dry ground, not too far from the middle."
function open_tree(w)
    trees = [p for p in w.props if p.kind === :tree]
    best = nothing; score = -Inf
    for p in trees
        hypot(p.pos[1], p.pos[2]) > 22 && continue
        NG.terrain_height(w.island, p.pos[1], p.pos[2]) < 0.6 && continue
        others = [hypot(q.pos[1] - p.pos[1], q.pos[2] - p.pos[2]) for q in trees if q !== p]
        d = isempty(others) ? 99.0 : minimum(others)
        d > score && (score = d; best = p)
    end
    return best
end

function tied_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 9.0)
    S = Dict{Any,Any}()
    shot = function (g, rig, t)
        w = g.world
        TD = Main.TIED
        if !haskey(S, :go)
            S[:go] = true
            # a level island and a green meadow for this shot: nobody weighs on the seesaw, the talk-sand is swept
            if isdefined(Main, :SEESAW) && haskey(Main.SEESAW, :sys)
                for c in w.creatures
                    Main.SEESAW[:weights][c.id] = 0f0
                end
                Main.SEESAW[:sys].tilt = Vec2f(0); Main.SEESAW[:sys].spin = Vec2f(0)
            end
            if isdefined(Main, :WORDSAND) && haskey(Main.WORDSAND, :H)
                Main.WORDSAND[:H] .= 0; Main.WORDSAND[:dirty] = true; Main.WORDSAND[:gain] = 0f0
            end
            tr = open_tree(w)
            d = Vec2f(cos(1.0f0), sin(1.0f0))            # toward the camera (the meadow side)
            side = Vec2f(-d[2], d[1])                     # along the row
            # open meadow: no tree within 5 m, the big toadstool and its fence 12 m away, dry ground
            trees = [Vec2f(p.pos[1], p.pos[2]) for p in w.props if p.kind === :tree]
            boing = isdefined(Main, :BOING) && haskey(Main.BOING, :center) ? Vec2f(Main.BOING[:center][1], Main.BOING[:center][2]) : Vec2f(999, 999)
            best = Vec2f(tr.pos[1], tr.pos[2]); bs = -Inf
            for x in -20f0:2f0:20f0, y in -20f0:2f0:20f0
                q = Vec2f(x, y)
                NG.terrain_height(w.island, x, y) < 0.8f0 && continue
                NG.terrain_height(w.island, x + 12d[1], y + 12d[2]) < 0.3f0 && continue
                dt_ = isempty(trees) ? 99f0 : minimum(norm(q - t) for t in trees)
                db = norm(q - boing)
                sc = min(dt_, 5f0) + min(db, 12f0) - 0.05f0 * norm(q)
                sc > bs && (bs = sc; best = q)
            end
            c0 = NG.ground(w.island, (best[1], best[2]))
            S[:c0] = c0; S[:d] = d
            cs = [c for c in w.creatures if c.species != "ghost"]
            n = length(cs)
            li = findfirst(c -> c.species == "Lumi", cs)
            if li !== nothing
                cs[li], cs[n ÷ 2] = cs[n ÷ 2], cs[li]
            end
            # one row across the meadow, 2.2 m apart: the rope (3 m a piece) hangs slack between them
            for (k, c) in enumerate(cs)
                o = (k - (n + 1) / 2) * 1.6f0
                c.pos = NG.ground(w.island, (c0[1] + o * side[1], c0[2] + o * side[2]))
                c.action = :idle
                c.yaw = Float32(atan(d[2], d[1])) - NG.species_of(c).heading
                c.goal = NG.Goal(:film, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            end
            S[:cs] = cs
            TD[:force] = true
        end
        # then everyone wants to be somewhere else: every other one toward the camera, the rest the other way
        if t > 0.8 && !haskey(S, :off)
            S[:off] = true
            d = S[:d]; side = Vec2f(-d[2], d[1]); n = length(S[:cs])
            for (k, c) in enumerate(S[:cs])
                o = (k - (n + 1) / 2) * 1.6f0 + 2.0f0 * sin(2.3f0 * k)
                f = isodd(k) ? 7.5f0 : -6.5f0
                far = NG.ground(w.island, (S[:c0][1] + o * side[1] + f * d[1], S[:c0][2] + o * side[2] + f * d[2]))
                c.goal = NG.Goal(:film_go, far, :idle, 600.0, w.t + 600, false, 0, k % 3 == 0)
                c.action = :walk
            end
        end
        c0 = S[:c0]; d = S[:d]
        u = Float32(smooth(t / seconds))
        r = 12.5f0 - 3.5f0 * u                           # a slow push in, no swing round
        eye = Point3f(c0[1] + r * d[1], c0[2] + r * d[2], c0[3] + 6.5f0 - 1.5f0 * u)
        tg = Point3f(c0[1], c0[2], c0[3] + 0.3f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    s = Main.TIED[:sys]
    return (path = path, wraps = s.wraps, tied = length(s.ids))
end
