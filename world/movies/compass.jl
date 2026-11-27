# The compass bowl (s147, plugins/compassbowl.jl): the magnet stone (plugins/magnetstone.jl) is carried past the bowl
# and back away; the needle on the lily pad turns by m x B alone (the island's 25 uT plus the stone's own field).
# Staging only moves the stone; Lumi walks with it.
#   submit_job(:clip; path, script = "movies/compass.jl", call = "compass_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame

function compass_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 8.0, hour = 16.5)
    bx, by = -4.9, 17.8
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat, :autumn_fall) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        for c in gm.world.creatures
            hypot(c.pos[1] - bx, c.pos[2] - by) < 6 && c.name != "Lumi" && (c.pos = NG.ground(gm.world.island, (Float32(bx) + 12f0, Float32(by) - 14f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    # the stone comes from the east along the beach side of the bowl, passes 0.4 m from it, and goes on west
    path_x(t) = (u = clamp((t - 0.6) / (seconds - 1.2), 0.0, 1.0); bx + 2.2 - 4.4 * (u * u * (3 - 2u)))
    shot = function (gm, rig, t)
        w = gm.world
        x = path_x(t); y = by + 0.4
        if isdefined(Main, :MAGSTONE) && haskey(Main.MAGSTONE, :c)
            MS = Main.MAGSTONE
            MS[:carried] = false; MS[:psi] = pi
            MS[:c] = (x, y, Float64(NG.ground(w.island, (Float32(x), Float32(y)))[3]) + 0.075)
        end
        me = NG.creature(w, "Lumi")
        me !== nothing && (me.pos = NG.ground(w.island, (Float32(x + 0.45), Float32(y))); me.yaw = Float32(pi))
        g = NG.ground(w.island, (Float32(bx), Float32(by)))
        rig.mode = :fixed
        rig.eye = Point3f(bx - 0.15f0, by - 1.0f0, g[3] + 0.95f0)
        rig.target = Point3f(bx, by + 0.1f0, g[3] + 0.1f0)
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.5, rasterize,
                 rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
