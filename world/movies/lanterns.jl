# Lantern float (session 91, plugins/lanterns.jl): a traced still of the moment the lanterns float on the pond at
# dusk, each one a real light on the water and the faces round the bank. A short take at 2 fps that ends once every
# lantern floats; its last frame is the picture (the job path is the png, so it counts as traced).
#   submit_job(:clip; path = abs png, script = "movies/lanterns.jl", call = "lantern_still", kwargs = Dict("take" => abs mp4))
using NeverendingGame, Makie
const NG = NeverendingGame

"The cast round the pond, everyone else parked far off."
function lantern_setup(g, cast)
    w = g.world
    A = g.plugins["areas"].mod
    P = A.POND; R = A.POND_R
    Main.LANTERNS[:try_at] = Inf
    k = 0
    for x in w.creatures
        x.controlled = false; x.action = :idle
        i = findfirst(==(x.name), cast)
        if i === nothing
            k += 1
            for r in 22f0:2f0:40f0
                q = (P[1] - 6f0 + 1.4f0 * k, P[2] - r)
                if NG.on_land(w.island, q[1], q[2]; margin = 0.3)
                    x.pos = NG.ground(w.island, q); break
                end
            end
            x.controlled = true; x.goal = NG.Goal()
            continue
        end
        a = 2f0 * Float32(pi) * i / length(cast)
        x.pos = NG.ground(w.island, (P[1] + (R + 1.6f0) * cos(a), P[2] + (R + 1.6f0) * sin(a)))
        x.goal = NG.Goal(:idle, x.pos, :idle, 600.0, w.t + 600, true, 0, false)
    end
end

function lantern_still(path; take, samples = 96, width = 1280, height = 720, hour = 19.7, rasterize = false,
                       cast = ["Lumi", "Truffle", "Gloop", "Cumulus", "Pinchy", "Wibbles", "Pickles", "Marshmallow", "Hopscotch"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        L = Main.LANTERNS
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            L[:t_gather] = 5.0; L[:gap] = 0.5; L[:t_float] = 60.0
            lantern_setup(g, cast)
            S[:ok] = Base.invokelatest(L[:start])
        end
        s = L[:sys]
        e, tg = Base.invokelatest(g.plugins["lanterns"].mod.lantern_view, g)
        rig.mode = :fixed; rig.eye = e; rig.target = tg
        s.state === :float && !haskey(S, :fin) && (S[:fin] = t)
        return haskey(S, :fin) ? S[:fin] + 3.0 : nothing
    end
    NG.game_clip(take; size = (width, height), seconds = 16.0, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize, setup = g -> lantern_setup(g, cast), shot)
    L = Main.LANTERNS
    for k in (:t_gather, :gap, :t_float, :try_at)
        delete!(L, k)
    end
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)
    return (path = path, started = S[:ok])
end

"""
The whole float as a short: the lanterns set on the water one by one, a moment of wishing, and all of them lifting off
into the dusk (no sound yet).
  submit_job(:clip; path, script = "movies/lanterns.jl", call = "lantern_clip", kwargs = Dict("rasterize" => false))
"""
function lantern_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 18.0, hour = 19.7,
                      cast = ["Lumi", "Truffle", "Gloop", "Cumulus", "Pinchy", "Wibbles", "Pickles", "Marshmallow", "Hopscotch"])
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        L = Main.LANTERNS
        w = g.world
        if !haskey(S, :off)
            S[:off] = w.t - t
            L[:t_gather] = 3.0; L[:gap] = 0.45; L[:t_float] = 3.5
            lantern_setup(g, cast)
            S[:ok] = Base.invokelatest(L[:start])
        end
        s = L[:sys]
        e, tg = Base.invokelatest(g.plugins["lanterns"].mod.lantern_view, g)
        rig.mode = :fixed; rig.eye = e
        # tilt up with the lanterns as they rise
        rig.target = s.state === :rise ? tg + Point3f(0, 0, min(3.0f0, 0.35f0 * Float32(w.t - s.t0))) : tg
        s.state === :idle && haskey(S, :ok) && t > 3 && !haskey(S, :end) && (S[:end] = t)
        return haskey(S, :end) ? S[:end] : nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> lantern_setup(g, cast), shot)
    L = Main.LANTERNS
    for k in (:t_gather, :gap, :t_float, :try_at)
        delete!(L, k)
    end
    return (path = path, started = S[:ok])
end
