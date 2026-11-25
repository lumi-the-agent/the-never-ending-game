# Shell washes ashore (session 98, todo #509; plugins/stranger.jl): on the south beach, at the water's edge, the
# little shell creature bobs in on the surf, lies tipped over on the wet sand, rights itself and looks about; a
# friend nearby jumps back, and I come down the beach to meet it. A low camera on the sand, close enough that Shell
# fills a good part of the frame.
#   submit_job(:clip; path, script = "movies/stranger.jl", call = "stranger_clip", kwargs = Dict("rasterize" => false))
using NeverendingGame, Makie
const NG = NeverendingGame

function stranger_clip(path; rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 9.2)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        X = Main.STRANGER
        sm = g.plugins["stranger"].mod
        if !haskey(S, :p)
            p, inland = Base.invokelatest(sm.landing, w)
            side = Point2f(-inland[2], inland[1])
            S[:p] = p; S[:inland] = inland; S[:side] = side
            # Wibbles a little way up the beach, me further off; everyone else out of the picture
            for c in w.creatures
                c.controlled = false
                if c.name == "Wibbles"
                    q = p + 2.2f0 * inland - 0.6f0 * side
                    c.pos = NG.ground(w.island, (q[1], q[2])); c.yaw = atan(-inland[2], -inland[1]) - NG.species_of(c).heading
                    c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.action = :idle
                elseif c.name == "Lumi"
                    q = p + 9f0 * inland - 3f0 * side
                    c.pos = NG.ground(w.island, (q[1], q[2])); c.action = :idle
                    c.goal = NG.Goal(:idle, c.pos, :idle, 5.0, w.t + 5, true, 0, false)
                else
                    for r in 24f0:2f0:44f0
                        q = (p[1] + r * inland[1] + 1.6f0 * (c.id % 6), p[2] + r * inland[2])
                        NG.on_land(w.island, q[1], q[2]; margin = 0.3) && (c.pos = NG.ground(w.island, q); break)
                    end
                    c.controlled = true; c.goal = NG.Goal()
                end
            end
            X[:trust] = Dict{String,Float64}(); X[:met] = Dict{Int32,Float64}(); X[:visits] = 0
            X[:sys].state = :away; X[:film] = true
            g0 = NG.ground(w.island, (p[1], p[2]))
            # low on the sand, looking along the waterline at the landing spot
            S[:eye] = g0 + Point3f(1.9f0 * side[1] + 0.7f0 * inland[1], 1.9f0 * side[2] + 0.7f0 * inland[2], 0.6f0)
            S[:tg] = g0 + Point3f(0.1f0 * inland[1], 0.1f0 * inland[2], 0.18f0)
        end
        # the camera drifts a little after Shell once it gets up
        st = X[:sys]
        tg = st.state in (:roam, :backoff) ? S[:tg] + 0.35f0 * (Point3f(st.pos[1], st.pos[2], S[:tg][3]) - S[:tg]) : S[:tg]
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = tg
        return seconds - 0.3
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
