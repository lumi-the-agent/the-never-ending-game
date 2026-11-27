# The first fired jug (s141, project pottery): a jug whose body has lines cut into it, dipped in glaze and fired.
# The glaze is not painted: physics/glaze.jl flows the molten film over the cut body for 60 s at peak heat
# (surface tension fills the cuts, gravity drains it down, it breaks thin off the raised ring and the lip),
# and each point's colour is Beer-Lambert through the thickness it ended with, under a clear glossy coat
# (Hikari CoatedDiffuse: the glaze's glass surface, its base the colour seen through the glaze).
#   submit_job(:clip; path, script = "movies/kiln.jl", call = "kiln_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "jug.jl"))

function kiln_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 9.0,
                   hour = 16.6, spot = (4f0, -16.5f0), radius = 0.36f0, steps = 12000)
    b, h = fire_jug(; steps)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world
        base = NG.ground(w.island, spot)
        m, cols = jug_mesh(b, h, Point3f(base[1], base[2], base[3] - 0.002f0))
        mesh!(g.stage.scene, m; color = cols, name = :kiln_jug,
              material = NG.Hikari.CoatedDiffuse(roughness = 0.03, ior = 1.52, thickness = 0.0004))
        S[:base] = base
        for c in w.creatures                     # nobody walks through the shot
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (g, rig, t)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile) || startswith(string(p.attributes[:name][]), "paperpage_")) && (p.visible[] = false)
        end
        bb = S[:base]
        a = Float32(-0.9 + 0.55 * t / seconds * 2π / 2)      # half a turn round the jug
        rig.mode = :fixed
        rig.eye = Point3f(bb[1] + radius * cos(a), bb[2] + radius * sin(a), bb[3] + 0.30f0)   # looking down: sand behind, not the grass
        rig.target = Point3f(bb[1], bb[2], bb[3] + 0.060f0)
        return nothing
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(r, (; path, glaze_mm = (minimum(h[:, 13:end]) * 1e3, maximum(h) * 1e3)))
end
