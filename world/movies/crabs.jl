# The crabs' makeover (session 85): Pinchy and Hopscotch, still pink balls on sticks, vanish in a puff of sparkles
# and come out as sculpted clay crabs with bunny ears, in front of their plush friends.
#   submit_job(:clip; path, script = "movies/crabs.jl", call = "crabs_clip", kwargs = Dict("spot" => [x, y], ...))
using NeverendingGame, Makie
const NG = NeverendingGame

function crabs_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 9.5)
    S = Dict{Symbol,Any}()
    setup = function (g)
        w = g.world
        x, y = Float32.(spot)
        crabs = [c.name for c in w.creatures if c.species == "Crabbit"]
        row = Dict{String,Tuple{Float32,Float32,Float32}}()       # (x, y, facing the camera's yaw)
        for (k, n) in enumerate(crabs[1:min(end, 2)])
            row[n] = ((k == 1 ? -0.75f0 : 0.75f0), 0f0, Float32(-pi))   # heading pi/2: yaw -pi looks at the camera
        end
        watchers = ["Lumi", "Truffle", "Cumulus", "Gloop", "Marshmallow"]
        for (k, n) in enumerate(watchers)
            a = Float32(pi) * (0.18f0 + 0.64f0 * (k - 1) / (length(watchers) - 1))
            row[n] = (2.3f0 * cos(a), 0.6f0 + 1.9f0 * sin(a), Float32(-pi / 2))
        end
        S[:pos] = Dict{Int32,Tuple{Point3f,Float32}}()
        for c in w.creatures
            if haskey(row, c.name)
                o = row[c.name]
                c.pos = NG.ground(w.island, (x + o[1], y + o[2]))
                yaw = c.species == "Crabbit" ? o[3] : atan(-o[2], -o[1]) - NG.species_of(c).heading
                c.yaw = yaw
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false); c.controlled = false
                S[:pos][c.id] = (c.pos, yaw)
            else
                far = argmax(q -> NG.on_land(w.island, q[1], q[2]; margin = 0.5f0) ? hypot(q[1] - x, q[2] - y) : -1f0,
                             [(Float32(a), Float32(b)) for a in -20:2:20 for b in -20:2:20])
                c.pos = NG.ground(w.island, far .+ (0.8f0 * (c.id % 4), 0f0)); c.controlled = true; c.goal = NG.Goal()
            end
        end
        S[:c] = NG.ground(w.island, (x, y))
    end
    shot = function (g, rig, t)
        if !haskey(S, :started)
            S[:started] = true
            m = g.plugins["makeover"].mod
            # the old crab first, then the makeover on camera
            Base.invokelatest(m.dress!, g, NG.crabbit())
            Main.MAKEOVER[:todo] = ["Crabbit"]
            Main.MAKEOVER[:at] = g.world.t + 2.8
        end
        for (id, (p, yaw)) in S[:pos]
            cr = NG.creature(g.world, id)
            cr === nothing && continue
            cr.pos = p; cr.yaw = yaw
            cr.action in (:walk, :run) && (cr.action = :idle)
        end
        c = S[:c]
        u = Float32(min(t, seconds) / seconds)
        rig.mode = :fixed
        rig.eye = c + Point3f(0.3f0, -(3.6f0 - 0.6f0 * u), 1.25f0)
        rig.target = c + Point3f(0, 0.4f0, 0.55f0)
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
end
