# A copper rod on the south shore, waiting for a storm (s153, project lightning, physics/estatic.jl): a 2 m rod,
# 2 cm thick, real copper (Hikari Metallic), Lumi beside it looking up. 5 s, fixed camera.
#   submit_job(:clip; path, script = "movies/rod.jl", call = "rod_clip")
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame

const ROD_SPOT = (-3.0f0, -16.0f0)     # the clearest place on the island (NOTES 'Fire'), beside the campfire ring

function rod_parts()
    S = Dict{Symbol,Any}()
    setup = function (gm)
        w = gm.world
        g = NG.ground(w.island, ROD_SPOT)
        o = Point3f(g[1] + 0.9f0, g[2] + 0.6f0, g[3] - 0.15f0)   # planted 15 cm deep
        S[:o] = o
        rod = GeometryBasics.normal_mesh(Cylinder(o, o + Vec3f(0, 0, 2.15f0), 0.02f0))
        cap = GeometryBasics.normal_mesh(Sphere(o + Vec3f(0, 0, 2.15f0), 0.02f0))
        for m in (rod, cap)
            mesh!(gm.stage.scene, m; color = RGBf(0.85, 0.5, 0.35), name = :rod_copper,
                  material = NG.Hikari.Metallic(base_color = (0.95, 0.64, 0.54), roughness = 0.25))
        end
        for c in w.creatures
            hypot(c.pos[1] - ROD_SPOT[1], c.pos[2] - ROD_SPOT[2]) < 7 && c.name != "Lumi" && (c.pos = NG.ground(w.island, (ROD_SPOT[1] + 14f0, ROD_SPOT[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        o = S[:o]
        me = NG.creature(gm.world, "Lumi")
        if me !== nothing        # Lumi beside the rod, turned to it
            me.pos = NG.ground(gm.world.island, (o[1] - 0.9f0, o[2] + 0.1f0)); me.yaw = 0f0
        end
        rig.mode = :fixed
        rig.eye = Point3f(o[1] - 0.6f0, o[2] - 3.4f0, o[3] + 1.2f0)
        rig.target = Point3f(o[1] - 0.4f0, o[2], o[3] + 1.1f0)
        return nothing
    end
    setup, shot, S
end

function rod_clip(path; samples = 20, width = 540, height = 960, fps = 24, seconds = 5.0, hour = 18.3)
    setup, shot, S = rod_parts()
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize = false,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0)
    return merge(res, (; path))
end
