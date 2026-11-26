# Breeding a new friend (session 113, plugins/nursery.jl): the pen on the meadow with four mixed-up little ones
# toddling about; four friends come to the fence one after another and hug the one they like (hearts), then the
# generation turns over and the next four, children of the two most hugged, appear.
#   submit_job(:clip; path, script = "movies/nursery.jl", call = "nursery_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function nursery_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 9.6,
                      cast = ["Truffle", "Gloop", "Pinchy", "Marshmallow"], turn = 8.5)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        N = Main.NURSERY
        m = g.plugins["nursery"].mod
        pen = m.PEN
        if !haskey(S, :go)
            S[:go] = true
            N[:film] = true; N[:film_gen] = 1e9; N[:next_visit] = Inf
            for c in w.creatures
                c.name in cast && continue
                c.species == "Lumi" && continue
                p = NG.ground(w.island, (Float32(-20), Float32(-30 + 2 * c.id)))     # everyone else far off
                c.pos = p; c.goal = NG.Goal(:idle, p, :idle, 60.0, w.t + 60, true, 0, false)
            end
            S[:t0] = w.t - t
        end
        # Lumi stands by the pen, watching
        for c in w.creatures
            c.species == "Lumi" || continue
            p = NG.ground(w.island, (Float32(pen[1] - 1.2), Float32(pen[2] + 2.9)))     # behind the pen, facing us
            c.pos = p; c.action = :idle
            c.yaw = Float32(atan(pen[2] - p[2], pen[1] - p[1])) - NG.species_of(c).heading
            c.goal = NG.Goal(:idle, p, :idle, 60.0, w.t + 60, true, 0, false)
        end
        # the friends come to the fence one after another and hug their favourite
        for (k, name) in enumerate(cast)
            c = w.creatures[findfirst(x -> x.name == name, w.creatures)]
            a = Float32(pi * (0.35 + 0.33 * (k - 1)))
            spot = NG.ground(w.island, (Float32(pen[1] + 2.6 * cos(a)), Float32(pen[2] + 2.6 * sin(a))))
            if !haskey(S, Symbol(:placed, k))
                S[Symbol(:placed, k)] = true
                c.pos = NG.ground(w.island, (Float32(pen[1] + 6 * cos(a)), Float32(pen[2] + 6 * sin(a))))
                c.goal = NG.Goal(:idle, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
            end
            # walk in from 6 m out, arriving at 1.0 + 1.8 k s
            u = Float32(clamp((t - (k - 1) * 1.8) / 1.0, 0, 1))
            if u < 1 || !haskey(S, Symbol(:hug, k))
                c.pos = NG.ground(w.island, (Float32(pen[1] + (6 - 3.4 * u) * cos(a)), Float32(pen[2] + (6 - 3.4 * u) * sin(a))))
                c.action = 0 < u < 1 ? :walk : :idle
                c.yaw = Float32(a + pi) - NG.species_of(c).heading
                if u >= 1
                    S[Symbol(:hug, k)] = true
                    get!(N, :hugged_by, Dict{Int32,Bool}())[c.id] = false
                    c.goal = NG.Goal(:nursery, c.pos, :idle, 30.0, w.t + 30, true, 0, false)
                end
            end
        end
        # the generation turns over
        if t >= turn && !haskey(S, :turned)
            S[:turned] = true
            Base.invokelatest(m.next_generation!, g)
        end
        c0 = NG.ground(w.island, (Float32(pen[1]), Float32(pen[2])))
        eye = Point3f(pen[1] + 3.0, pen[2] - 3.7, c0[3] + 2.0)
        tg = Point3f(pen[1] - 0.25, pen[2] + 0.35, c0[3] + 0.4)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> (isdefined(Main, :NURSERY) && empty!(Main.NURSERY); nothing), shot)
    N = Main.NURSERY
    return (path = path, gen = get(N, :gen, 0), hist = string(get(N, :history, Any[])))
end
