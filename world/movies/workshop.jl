# My workshop, out at sea (session 102, plugins/workshopisle.jl): from our beach, the little island out at sea with
# the other game's friends moving on it, and a paper boat sailing across to us with something new; Lumi waits at the
# water's edge.
#   submit_job(:clip; path, script = "movies/workshop.jl", call = "workshop_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function workshop_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 16.6)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        WS = Main.WORKSHOPISLE
        wm = g.plugins["workshopisle"].mod
        if !haskey(S, :eye)
            C = Base.invokelatest(getfield, wm, :CENTRE)
            d = Point2f(C[1], C[2]) / hypot(C[1], C[2]); side = Point2f(-d[2], d[1])
            r = 40f0
            while r > 0 && !NG.on_land(w.island, r * d[1], r * d[2]; margin = 0.3f0); r -= 1f0; end
            shore = Point2f(r * d[1], r * d[2])
            for c in w.creatures
                c.controlled = true; c.goal = NG.Goal(); c.action = :idle
                if c.name == "Lumi"
                    q = shore - 0.8f0 * d
                    c.pos = NG.ground(w.island, (q[1], q[2])); c.yaw = atan(d[2], d[1]) - NG.species_of(c).heading
                    c.controlled = false
                    c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                elseif c.name == "Gloop"
                    q = shore - 1.2f0 * d + 1.4f0 * side
                    c.pos = NG.ground(w.island, (q[1], q[2])); c.yaw = atan(d[2], d[1]) + 0.3f0 - NG.species_of(c).heading
                end
            end
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)
            BT = Base.invokelatest(getfield, wm, :BOAT_T)
            Base.invokelatest(wm.send_boat!, g, "a new thing")
            WS[:sail] = merge(WS[:sail], (t0 = w.t - (BT - 8.5),))   # it lands about 8.5 s in
            e = shore - 1.5f0 * d + 4.5f0 * side
            S[:eye] = Point3f(e[1], e[2], NG.terrain_height(w.island, e[1], e[2]) + 1.6f0)
            tq = shore + 9f0 * d - 1.5f0 * side
            S[:tg] = Point3f(tq[1], tq[2], 1.0f0)
        end
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:tg]
        g.rig.mode = :fixed; g.rig.eye = S[:eye]; g.rig.target = S[:tg]
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
