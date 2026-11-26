using NeverendingGame, Makie
using LinearAlgebra: norm
const NG = NeverendingGame

"""
A notebook page falls (s127, plugins/paperpage.jl): a rigid A4 plate in simulated air (plate aerodynamics with the
centre of pressure toward the leading edge), landing by corner contacts. The camera follows the page down from the side.
"""
function paperpage_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 30,
                        seconds = 6.0, hour = 16.0, back = 2.6, side = 1.2, lift = 0.35)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        isdefined(Main, :PAPERPAGE) && haskey(Main.PAPERPAGE, :sys) && haskey(Main.PAPERPAGE, :plots) || return seconds - 0.1
        PP = Main.PAPERPAGE
        sys = PP[:sys]
        if !haskey(S, :go)
            S[:go] = true
            for (k, p) in enumerate(sys.pages)            # only the page this film drops
                p.on = false
                PP[:plots][k].visible = false
            end
            sys.next_at = g.world.t + 1e6
            PP[:force] = true
        end
        if !haskey(S, :k)
            k = findfirst(p -> p.on, sys.pages)
            k === nothing || (S[:k] = k)
        end
        if haskey(S, :k)
            p = sys.pages[S[:k]]
            x = Point3f(p.x)
            c = get(S, :c, x)
            c = c + 0.25f0 * (x - c)                      # the lens follows the page smoothly
            S[:c] = c
            ground = NG.terrain_height(g.world.island, c[1], c[2])
            tg = Point3f(c[1], c[2], max(c[3], ground + 0.25f0))
            eye = Point3f(c[1] - side, c[2] - back, max(c[3] + lift, ground + 0.6f0))
            rig.mode = :fixed; rig.eye = eye; rig.target = tg
            g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        end
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path,)
end
