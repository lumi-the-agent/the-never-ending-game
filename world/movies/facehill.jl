# A hill with my face (session 104, plugins/facehill.jl): the camera rises from the meadow over the golden relief of
# me while three friends climb it, to my beak, my crest and my belly.
#   submit_job(:clip; path, script = "movies/facehill.jl", call = "facehill_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function facehill_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 16.8,
                       cast = ["Gloop", "Pinchy", "Truffle"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        fm = g.plugins["facehill"].mod
        C = Base.invokelatest(getfield, fm, :CENTRE)
        if !haskey(S, :go)
            S[:go] = true
            boxes = ((0.35, 0.65, 0.55, 0.75), (0.4, 0.75, 0.82, 1.0), (0.35, 0.65, 0.2, 0.45))
            k = 0
            for c in w.creatures
                i = findfirst(==(c.name), cast)
                if i === nothing
                    c.controlled = true; c.goal = NG.Goal(); c.action = :idle
                    if hypot(c.pos[1] - C[1], c.pos[2] - C[2]) < 12          # out of the shot
                        for r in 16f0:2f0:30f0
                            q = (C[1] + r, C[2] - 8f0 + 1.5f0 * (k += 1))
                            NG.on_land(w.island, q[1], q[2]; margin = 0.3) && (c.pos = NG.ground(w.island, q); break)
                        end
                    end
                    continue
                end
                p = Base.invokelatest(fm.peak_in, g, boxes[i]...)
                p === nothing && continue
                start = (C[1] + 7f0 * cos(1.1f0 * i), C[2] - 7f0 + 2f0 * i)
                c.pos = NG.ground(w.island, start); c.controlled = false
                c.goal = NG.Goal(:facehill, p, :sit, 600.0, w.t + 600, false, 0, false)
            end
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)
            me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
            me.controlled = true; me.pos = NG.ground(w.island, (C[1] - 2f0, C[2] - 7.5f0)); me.yaw = Float32(pi / 2) - NG.species_of(me).heading; me.action = :proud
        end
        u = Float32(clamp(t / seconds, 0, 1)); u = u * u * (3 - 2u)
        a = Float32(-pi / 2) + 0.9f0 * (u - 0.5f0)                      # a slow turn round the foot of the hill
        r = 13f0 - 2f0 * u; hgt = 3f0 + 9f0 * u                          # rising as it goes
        z0 = NG.terrain_height(w.island, C[1], C[2])
        eye = Point3f(C[1] + r * cos(a), C[2] + r * sin(a), z0 + hgt)
        tg = Point3f(C[1], C[2] + 0.5f0, z0 + 0.8f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
