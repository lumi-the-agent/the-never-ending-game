# The magnet stone on the north beach (s147, plugins/magnetstone.jl, big goal "Sparks from stones" step 1).
# Lumi carries the stone along the sand past iron spikes laid at different distances from its path; what each spike
# does is the plugin's physics (the stone's real field from em.jl, the spike magnetised by it, friction on the sand):
# the close ones leap to it, the next slide and turn, the far ones lie still. Staging only places the spikes.
#   submit_job(:clip; path, script = "movies/magnetstone.jl", call = "magnet_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame

function magnet_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 9.0,
                     hour = 16.5, y0 = 18.9, xa = -5.1, xb = -2.7)
    # spikes: (x, distance from the path, yaw in degrees); the path runs along +x at y0, the camera looks from the sea side
    lay = [(-4.6, 0.10, 20), (-4.2, -0.17, 75), (-3.9, 0.24, 130), (-3.55, -0.09, 100), (-3.3, 0.33, 10),
           (-3.05, -0.21, 160), (-2.95, 0.15, 60), (-4.4, 0.45, 45)]
    S = Dict{Symbol,Any}(:laid => false)
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat, :autumn_fall) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        for c in gm.world.creatures
            hypot(c.pos[1] - xa, c.pos[2] - y0) < 6 && c.name != "Lumi" && (c.pos = NG.ground(gm.world.island, (Float32(xa) + 12f0, Float32(y0) - 14f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    walk = function (t)
        u = clamp((t - 0.8) / (seconds - 1.8), 0.0, 1.0)
        xa + (xb - xa) * (u * u * (3 - 2u))            # eases in and out like a careful walk
    end
    shot = function (gm, rig, t)
        MS = Main.MAGSTONE
        w = gm.world
        if !S[:laid] && haskey(MS, :spikes)
            for (s, (x, d, yaw)) in zip(MS[:spikes], lay)
                gz = Float64(NG.ground(w.island, (Float32(x), Float32(y0 + d)))[3])
                s.p = (x, y0 + d, gz + 0.003); s.v = (0.0, 0.0, 0.0); s.u = (cosd(yaw), sind(yaw), 0.0); s.w = 0.0; s.stuck = false
            end
            for s in MS[:spikes][length(lay)+1:end]           # the rest wait far down the beach
                gz = Float64(NG.ground(w.island, (Float32(xa - 3), Float32(y0)))[3])
                s.p = (xa - 3.0, y0 - 0.5, gz + 0.003); s.v = (0.0, 0.0, 0.0); s.stuck = false
            end
            S[:laid] = true
        end
        x = walk(t)
        if haskey(MS, :c)
            gz = Float64(NG.ground(w.island, (Float32(x), Float32(y0)))[3])
            MS[:carried] = false; MS[:psi] = 0.0
            MS[:c] = (x, y0, gz + 0.045 + 0.03)
        end
        me = NG.creature(w, "Lumi")
        if me !== nothing
            me.pos = NG.ground(w.island, (Float32(x - 0.45), Float32(y0)))
            me.yaw = 0f0
        end
        cx = Float32(xa + 0.15 + 0.8 * (x - xa))         # the camera drifts after the stone
        gzc = NG.ground(w.island, (cx, Float32(y0)))[3]
        rig.mode = :fixed
        # from the water side looking up the beach (inland the ground rises above any low eye: s147's first try was inside the hill)
        rig.eye = Point3f(cx - 0.1f0, Float32(y0) + 1.1f0, max(gzc, 0f0) + 0.45f0)
        rig.target = Point3f(cx + 0.25f0, Float32(y0), gzc + 0.05f0)
        return nothing
    end
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.5, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    MS = Main.MAGSTONE
    return merge(res, (; path, stuck = count(s -> s.stuck, MS[:spikes])))
end
