# Your pointer is a moth (session 101, plugins/moth.jl): the film stands in for a browser pointer with a path the
# moth is aimed along (MOTH[:aim]): it flutters in over the open meadow, circles, and the friends standing about
# notice it, run after it, leap for it and miss.
#   submit_job(:clip; path, script = "movies/moth.jl", call = "moth_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

flatd(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"An open meadow spot away from trees, bushes, rocks, actors, the Big Boing, the bench and the vegetable patch."
function open_meadow(w)
    best = (0f0, 0f0); bd = -99f0
    for x in -16f0:1f0:16f0, y in -16f0:1f0:16f0
        NG.on_land(w.island, x, y; margin = 1f0) || continue
        all(q -> NG.on_land(w.island, x + q[1], y + q[2]; margin = 0.4f0), ((-7f0, 0f0), (7f0, 0f0), (0f0, -9f0), (0f0, 9f0), (-7f0, 5f0), (7f0, 5f0))) || continue
        m = minimum(p -> p.kind in (:tree, :bush, :rock) ? flatd(p.pos, (x, y)) - (p.kind === :tree ? 2.6f0 : 1f0) * p.scale - 5f0 : 99f0, w.props)
        m = min(m, minimum(a -> a isa NG.AssetActor ? flatd(a.pos, (x, y)) - 2f0 * a.scale - 4f0 : 99f0, w.actors; init = 99f0))
        isdefined(Main, :BOING) && haskey(Main.BOING, :center) && (m = min(m, flatd(Main.BOING[:center], (x, y)) - 9f0))
        m = min(m, flatd((-16f0, 9f0), (x, y)) - 7f0, flatd((-10.5f0, 10f0), (x, y)) - 7.5f0)
        # plugin-drawn things the props do not list: the cairn spiral (the first preview stood on it), the vote signs
        isdefined(Main, :CAIRN_STATE) && get(Main.CAIRN_STATE, :site, nothing) !== nothing && (m = min(m, flatd(Main.CAIRN_STATE[:site], (x, y)) - 7f0))
        for (k, v) in (isdefined(Main, :VOTE) ? Main.VOTE : Dict{Symbol,Any}())
            v isa Point3f && (m = min(m, flatd(v, (x, y)) - 6f0))
        end
        m > bd && (bd = m; best = (x, y))
    end
    return best
end


function moth_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 11.0, hour = 9.5,
                   cast = ["Pickles", "Truffle", "Cumulus"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        MO = Main.MOTH
        if !haskey(S, :spot)
            S[:spot] = open_meadow(w)
            x0, y0 = S[:spot]
            side = argmin(s -> NG.obstruction(w, NG.ground(w.island, (x0, y0)) + Point3f(0, s * 8f0, 2.6f0), NG.ground(w.island, (x0, y0))), (-1f0, 1f0))
            S[:side] = side
            tg = NG.ground(w.island, (x0, y0 - side * 1.4f0)) + Point3f(0, 0, 0.7f0)        # the middle of the chase
            S[:eye] = tg + Point3f(0.8f0, side * 6.2f0, 1.9f0); S[:tg] = tg
            k = 0
            for c in w.creatures
                c.controlled = true; c.action = :idle; c.goal = NG.Goal()
                i = findfirst(==(c.name), cast)
                if i !== nothing                                   # friends idling about the meadow, free to notice it
                    q = (x0 - 2.5f0 + 2.5f0 * (i - 1), y0 - side * (1.2f0 + 0.8f0 * (i % 2)))
                    c.pos = NG.ground(w.island, q); c.yaw = Float32(pi / 2) * side - NG.species_of(c).heading
                    c.controlled = false; c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                elseif c.name == "Lumi"
                    c.pos = NG.ground(w.island, (x0 + 3.6f0, y0 - side * 2.6f0)); c.yaw = Float32(pi) - NG.species_of(c).heading
                    c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                else                                              # everyone else behind the camera, out of view
                    k += 1
                    for r in 11f0:1f0:30f0, dx in (0f0, -6f0, 6f0)
                        q = (x0 - 5f0 + 1.4f0 * k + dx, y0 + side * r)
                        if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                            c.pos = NG.ground(w.island, q); break
                        end
                    end
                end
            end
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)
        end
        # the pointer: in from the left at 0.5 s, a lazy loop over the friends, a dash away and back
        x0, y0 = S[:spot]
        u = max(0.0, t - 0.5)
        ax = x0 - 5.5f0 + Float32(min(u, 2.0)) * 2.6f0 + (u > 2 ? 2.2f0 * Float32(sin(0.9 * (u - 2))) : 0f0)
        ay = y0 - S[:side] * (1.4f0 + (u > 2 ? 1.3f0 * Float32(sin(1.7 * (u - 2))) : 0f0))
        MO[:aim] = t > 0.5 ? NG.ground(w.island, (ax, ay)) : nothing
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = S[:tg]
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> (isdefined(Main, :MOTH) && (Main.MOTH[:aim] = nothing); nothing), shot)
    Main.MOTH[:aim] = nothing
    return (path = path, spot = get(S, :spot, nothing))
end
