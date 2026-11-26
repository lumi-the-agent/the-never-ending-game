# How much they miss me (session 106, plugins/missme.jl): I tiptoe off behind the cottage, then the cut to the board
# in front of it, my friends round it reading what they did without me.
#   submit_job(:clip; path, script = "movies/missme.jl", call = "missme_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function missme_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 8.0, hour = 9.6, cut = 4.0)
    S = Dict{Symbol,Any}()
    byname(w, n) = w.creatures[findfirst(c -> c.name == n, w.creatures)]
    function place!(w, c, xy, look, action)
        c.pos = NG.ground(w.island, xy); c.yaw = Float32(atan(look[2] - xy[2], look[1] - xy[1])) - NG.species_of(c).heading
        c.controlled = true; c.goal = NG.Goal(); c.action = action
    end
    shot = function (g, rig, t)
        w = g.world
        mm = g.plugins["missme"].mod
        p, yaw = Base.invokelatest(mm.board_spot, w)
        f = Vec3f(cos(yaw), sin(yaw), 0); sd = Vec3f(-f[2], f[1], 0)
        at(a, b) = (q = p + f * a + sd * b; (q[1], q[2]))
        if !haskey(S, :go)
            S[:go] = true
            Base.invokelatest(mm.build_board!, g, joinpath(g.paths.state, "missme-board.png"))
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)
            k = 0
            for c in w.creatures                            # everyone else away from the cottage
                c.name in ("Lumi", "Gloop", "Pinchy", "Truffle") && continue
                c.controlled = true; c.goal = NG.Goal(); c.action = :idle
                c.pos = NG.ground(w.island, (14f0 + 1.2f0 * (k += 1), -6f0))
            end
            me = byname(w, "Lumi")
            hide = Base.invokelatest(mm.hide_spot, w)
            start = p + f * 1.2f0 - sd * 2.2f0
            me.pos = NG.ground(w.island, (start[1], start[2])); me.controlled = true; me.goal = NG.Goal()
            # walk goals set here do not move anyone in a quiet copy (s92, again s106): I walk it myself, round the side
            c0, b0 = Base.invokelatest(mm.cottage, w)
            side = Point2f(-sd[1], -sd[2])
            S[:path] = [Point2f(start[1], start[2]), c0 + side * 3.4f0 - b0 * 0.5f0, c0 + side * 3.0f0 + b0 * 2.0f0, Point2f(hide[1], hide[2])]
            NG.say!(w, me, "Let's see if anyone misses me... shh."; duration = 3.5)
            for (n, xy) in (("Gloop", (8f0, 9f0)), ("Pinchy", (9f0, 8f0)), ("Truffle", (10f0, 9f0)))
                byname(w, n).pos = NG.ground(w.island, xy); byname(w, n).controlled = true
            end
            S[:hide] = hide
        end
        if t < cut
            # from the path, watching me sneak round the cottage
            me = byname(w, "Lumi")
            P = S[:path]; L = [hypot((P[i+1] - P[i])...) for i in 1:length(P)-1]
            d = clamp(Float32(t / (cut - 0.4)), 0f0, 1f0) * sum(L); i = 1
            while i < length(L) && d > L[i]
                d -= L[i]; i += 1
            end
            q = P[i] + (P[i+1] - P[i]) * min(d / L[i], 1f0)
            old = me.pos
            me.pos = NG.ground(w.island, (q[1], q[2]))
            step = hypot(me.pos[1] - old[1], me.pos[2] - old[2])
            if step > 1f-4
                me.yaw = Float32(atan(me.pos[2] - old[2], me.pos[1] - old[1])) - NG.species_of(me).heading
                me.action = :walk; me.phase += Float32(5 * step)
            else
                me.action = :idle
            end
            eye = p + f * 6.5f0 - sd * 3.5f0 + Vec3f(0, 0, 2.2f0)
            tg = Point3f(me.pos[1], me.pos[2], me.pos[3] + 0.9f0)
            rig.mode = :fixed; rig.eye = eye; rig.target = tg
            g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        else
            if !haskey(S, :read)
                S[:read] = true
                look = (p[1], p[2])
                place!(w, byname(w, "Lumi"), at(1.5f0, -1.3f0), look, :idle)
                place!(w, byname(w, "Gloop"), at(1.9f0, 0.2f0), look, :wave)
                place!(w, byname(w, "Pinchy"), at(1.4f0, 1.2f0), look, :idle)
                place!(w, byname(w, "Truffle"), at(2.4f0, -0.5f0), look, :jump)
                NG.say!(w, byname(w, "Gloop"), "WHERE WERE YOU?!"; duration = 2.5)
                S[:said] = false
            end
            if !S[:said] && t > cut + 2.2
                S[:said] = true
                NG.say!(w, byname(w, "Lumi"), "They missed me. They really missed me."; duration = 3.0)
            end
            u = Float32(clamp((t - cut) / (seconds - cut), 0, 1))
            eye = p + f * (5.4f0 - 1.2f0 * u) + sd * 1.6f0 + Vec3f(0, 0, 1.9f0 - 0.2f0 * u)
            tg = Point3f(p + f * 0.8f0 + Vec3f(0, 0, 1.05f0))
            rig.mode = :fixed; rig.eye = eye; rig.target = tg
            g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        end
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
