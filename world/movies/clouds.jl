# Cloud watching (session 101-102, plugins/cloudshapes.jl): from low behind us, three friends and I sitting in the
# grass while the cloud above turns from a heart into a fish.
#   submit_job(:clip; path, script = "movies/clouds.jl", call = "clouds_clip", kwargs = Dict(...))
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


function clouds_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 16.4,
                     cast = ["Truffle", "Wibbles", "Sir Sniffsalot"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        cm = g.plugins["cloudshapes"].mod
        if !haskey(S, :start)
            S[:start] = true
            x0, y0 = open_meadow(w)
            me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
            k = 0
            for c in w.creatures
                c.controlled = true; c.goal = NG.Goal(); c.action = :idle
                if c.name == "Lumi"
                    c.pos = NG.ground(w.island, (x0, y0)); c.controlled = false
                    c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                elseif c.name in cast                                # close by, free to flop down beside me
                    k += 1
                    c.pos = NG.ground(w.island, (x0 + 2.5f0 * cos(1.5f0 * k), y0 + 2.5f0 * sin(1.5f0 * k)))
                    c.controlled = false; c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                else
                    for r in 22f0:2f0:44f0
                        q = (x0 + r, y0 - 6f0 + 1.3f0 * c.id)
                        if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                            c.pos = NG.ground(w.island, q); break
                        end
                    end
                end
            end
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = -Inf)
            Base.invokelatest(cm.begin_watch!, g, me)
            Main.CLOUDSHAPES[:watch][:t0] = w.t - 7.0        # the heart is up; it turns into a fish half way through
        end
        v = Base.invokelatest(cm.watch_view, w)
        if v !== nothing
            rig.mode = :fixed; rig.eye = v[3][1]; rig.target = v[3][2]
            g.rig.mode = :fixed; g.rig.eye = v[3][1]; g.rig.target = v[3][2]
        end
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
