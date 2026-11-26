# The island remembers being drawn (session 110, plugins/drafts.jl): a patch of the island's first drafts drifts over
# me and my friends on the meadow; inside it we are pale blobs again on grey-box ground, the trees grey balls on sticks.
#   submit_job(:clip; path, script = "movies/drafts.jl", call = "drafts_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function drafts_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 10.2,
                     spot = (-1.3, -3.1))
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        C = NG.ground(w.island, Float32.(spot))
        if !haskey(S, :go)
            S[:go] = true
            names = ("Lumi", "Gloop", "Pinchy", "Truffle", "Wibbles")
            k = 0
            for c in w.creatures
                c.name in names || continue
                k += 1
                a = 2f0 * Float32(pi) * k / length(names)
                c.pos = NG.ground(w.island, (C[1] + 2.2f0 * cos(a), C[2] + 2.2f0 * sin(a)))
                c.controlled = false; c.goal = NG.Goal(:wander, c.pos, :idle, 30.0, 0.0, false, 0, false)
            end
            dm = g.plugins["drafts"].mod
            Base.invokelatest(dm.begin_patch!, g; at = (C[1] - 5f0, C[2]))
            p = Main.DRAFTS[:patch]
            p[:d] = Point2f(1, 0); p[:c] = Point2f(C[1] - 7f0, C[2]); p[:t0] = w.t - 5; p[:until] = w.t + 120
        end
        eye = Point3f(C[1] + 1f0, C[2] - 9.5f0, C[3] + 6.5f0); tg = Point3f(C[1], C[2] + 0.5f0, C[3] + 0.3f0)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.5, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> nothing, shot)
    return (path = path,)
end
