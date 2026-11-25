# Makeover day (session 74): the Snootles vanish in a puff of sparkles and come out as plush piglets.
#   submit_job(:clip; path, script = "movies/makeover.jl", call = "makeover_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function makeover_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 13.5, hour = 10.5)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        # one row facing the camera: three pigs, then the two blobs; Lumi watches from behind
        row = Dict{String,Tuple{Float32,Float32}}()
        pigs = [c.name for c in w.creatures if c.species == "Snootle"]
        blobs = [c.name for c in w.creatures if c.species == "Blorbo"]
        xs = (-2.3f0, -1.15f0, 0.0f0, 1.15f0, 2.3f0)
        for (k, n) in enumerate(vcat(pigs[1:min(end, 3)], blobs[1:min(end, 2)]))
            row[n] = (xs[k], 1.0f0)
        end
        row["Lumi"] = (0.2f0, 3.0f0)
        S[:pos] = Dict{Int32,Point3f}()
        for c in w.creatures
            if haskey(row, c.name)
                o = row[c.name]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2])); c.yaw = Float32(-pi / 2)
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
                S[:pos][c.id] = c.pos
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = NG.ground(w.island, (x, y + 1.2f0))
    end
    shot = function (g, rig, t)
        if !haskey(S, :started)
            S[:started] = true
            m = g.plugins["makeover"].mod
            # back to the old bodies for the film, then the makeover happens on camera
            Base.invokelatest(m.dress!, g, NG.snootle())
            Base.invokelatest(m.dress!, g, NG.blorbo())
            Main.MAKEOVER[:todo] = ["Snootle", "Blorbo"]
            Main.MAKEOVER[:at] = g.world.t + 3.0
        end
        # everyone stays in the row (the gasp ends in a new goal, and they wandered off in the preview)
        for (id, p) in S[:pos]
            cr = NG.creature(g.world, id)
            cr === nothing && continue
            cr.pos = p; cr.yaw = Float32(-pi / 2)
            cr.action in (:walk, :run) && (cr.action = :idle)
        end
        c = S[:c]
        rig.mode = :fixed
        rig.eye = c + Point3f(0.0f0, -5.4f0, 1.5f0)
        rig.target = c + Point3f(0, 0, 0.55f0)
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
