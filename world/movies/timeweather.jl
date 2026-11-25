# Time weather (session 100, plugins/timeweather.jl): a patch of slow time settles on the open meadow. Two friends
# walk across side by side: Truffle's lane passes just outside the ring and it strolls on, Pickles' lane goes through
# the middle and Pickles crawls, legs paddling in slow motion, drawling. Gloop and Lumi watch from the edge.
#   submit_job(:clip; path, script = "movies/timeweather.jl", call = "timeweather_clip", kwargs = Dict(...))
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

function timeweather_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 11.0, hour = 9.5)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        TW = Main.TIMEWEATHER
        if !haskey(S, :spot)
            S[:spot] = open_meadow(w); S[:tl] = t
            x0, y0 = S[:spot]
            # the clearer of the two sides across the walk
            tg = NG.ground(w.island, (x0, y0 + 1f0)) + Point3f(0, 0, 0.5f0)
            side = argmin(s -> NG.obstruction(w, tg + Point3f(0, s * 7.5f0, 1.7f0), tg), (-1f0, 1f0))
            S[:eye] = tg + Point3f(0, side * 7.5f0, 1.7f0); S[:tg] = tg + Point3f(0, 0, 0.1f0)
            far = -side                                           # Truffle's lane on the far side, beyond the ring
            lanes = Dict("Pickles" => y0, "Truffle" => y0 + far * 5.2f0)
            S[:walkers] = String[]
            k = 0
            for c in w.creatures
                c.controlled = true; c.action = :idle; c.goal = NG.Goal()
                if haskey(lanes, c.name)
                    c.pos = NG.ground(w.island, (x0 - 5.6f0, lanes[c.name])); c.yaw = 0f0 - NG.species_of(c).heading
                    push!(S[:walkers], c.name)
                elseif c.name == "Gloop"                              # free to point and laugh (the plugin's watchers)
                    c.pos = NG.ground(w.island, (x0 + 2.6f0, y0 - side * 4.6f0)); c.yaw = atan(side, -0.5f0) - NG.species_of(c).heading
                    c.controlled = false; c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                elseif c.name == "Lumi"
                    c.pos = NG.ground(w.island, (x0 + 4.4f0, y0 - side * 2.0f0)); c.yaw = Float32(pi) - NG.species_of(c).heading
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
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)   # no other moment takes Lumi
            p = TW[:start](; at = Point3f(x0, y0, 0), kind = :slow)
            p[:c] = Point2f(x0, y0); p[:v] = Vec2f(0.04, 0); p[:walk_at] = Inf; p[:until] = w.t + 600
        end
        # the two walk east at a stroll from 0.8 s on; the patch's own time rate slows Pickles' steps inside it
        dt = Float32(t - S[:tl]); S[:tl] = t
        if t > 0.8
            for c in w.creatures
                c.name in S[:walkers] || continue
                q = c.pos + Point3f(1.25f0 * dt, 0, 0)
                c.pos = NG.ground(w.island, (q[1], q[2])); c.action = :walk
                c.phase += 7f0 * 1.25f0 * dt
                c.yaw = 0f0 - NG.species_of(c).heading
            end
        end
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = S[:tg]
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path, spot = get(S, :spot, nothing))
end
