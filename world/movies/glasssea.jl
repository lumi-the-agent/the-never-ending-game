using NeverendingGame, Makie
using LinearAlgebra: norm
const NG = NeverendingGame

"""
The sea freezes into glass (s126, plugins/glasssea.jl): five friends slide out on the ice off the east shore,
converge, bump and spin; fish hang frozen under the clear ice. The lens stands low on the ice, out at sea,
looking back at the island, so the skaters are in front and the island behind them.
Take 2 (s126 critic): the friends start on the shore, the sea freezes at `freeze_at`, they trot out and skate.
"""
function glasssea_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24,
                       seconds = 9.0, hour = 7.5, center = (25.6, 6.9), dist = 9.0, up = 1.8, side = 2.0, freeze_at = 1.2,
                       thinice = false)
    isdefined(Main, :GLASSSEA) || Core.eval(Main, :(const GLASSSEA = Dict{Symbol,Any}()))
    Main.GLASSSEA[:thinice] = thinice      # s133: the ice as a floating plate that bends and cracks (physics/ice.jl)
    S = Dict{Any,Any}()
    cx, cy = Float32(center[1]), Float32(center[2])
    out = Vec2f(cx, cy) / hypot(cx, cy)
    ring = Vec2f(-out[2], out[1])
    shot = function (g, rig, t)
        w = g.world
        is = w.island
        if !haskey(S, :go)
            S[:go] = true
            for k in (:TIED, :UNDERLIGHT, :JELLY, :GLASSRAIN, :SUNBALL, :GROUNDWHALE)
                isdefined(Main, k) && (getfield(Main, k)[:force] = false)
            end
            isdefined(Main, :UNDERLIGHT) && (Main.UNDERLIGHT[:u] = 0.0)
            friends = [c for c in w.creatures if c.name != "Lumi"]
            for (k, c) in enumerate(first(friends, 5))
                o = (k - 3) * 1.4f0                # side by side along the shore
                r = 0f0
                while r < 20 && NG.terrain_height(is, cx - r * out[1] + o * ring[1], cy - r * out[2] + o * ring[2]) < 0.2f0
                    r += 0.5f0
                end
                c.pos = NG.ground(is, (cx - (r + 0.8f0) * out[1] + o * ring[1], cy - (r + 0.8f0) * out[2] + o * ring[2]))
                c.yaw = atan(out[2], out[1])
                c.action = :idle
                c.goal = NG.Goal(:idle, c.pos, :idle, 30.0, w.t + 30, true, 0, false)
            end
            Main.GLASSSEA[:at] = (cx, cy)
        end
        if t >= freeze_at && !haskey(S, :frozen)
            S[:frozen] = true
            Main.GLASSSEA[:force] = true
        end
        eye = Point3f(cx + dist * out[1] + side * ring[1], cy + dist * out[2] + side * ring[2], up)
        tg = Point3f(cx - 3f0 * out[1], cy - 3f0 * out[2], 0.6f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 2.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, skaters = haskey(Main.GLASSSEA, :sys) ? length(Main.GLASSSEA[:sys].sk) : -1)
end
