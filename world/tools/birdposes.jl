# Lumi in a row of poses (side view, raster): checks the bird's own moves (bird.jl `Birdy`).
# `include("world/tools/birdposes.jl"); birdposes("media/x.png", [(:walk, 0.8f0, 0f0), ...])`
# each pose is (action, phase, fidget kind for :idle); seen from the south, facing east.
include(joinpath(@__DIR__, "lineup.jl"))

function birdposes(path, poses; size = (1600, 500), mood = 0f0, extra = 0.3f0)
    g = NG.Game(NG.game_root(); quiet = true)
    w = g.world
    NG.skip_to_hour!(w, 11)
    lumi = only(filter(c -> c.species == "Lumi", w.creatures))
    birds = [i == 1 ? lumi : (b = deepcopy(lumi); b.id = 10_000 + i; b) for i in eachindex(poses)]
    for i in 2:length(birds); push!(w.creatures, birds[i]); end
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
    cam3d!(scene)
    g.stage = NG.Stage(scene, w; show_names = false)
    bx, by = open_spot(w)
    for c in w.creatures
        c in birds || (c.pos = NG.ground(w.island, (bx + 30f0, by)))
    end
    for (i, (c, (a, ph, t))) in enumerate(zip(birds, poses))
        c.pos = NG.ground(w.island, (bx + (i - (length(birds) + 1) / 2) * 1.5f0, by))
        c.yaw = 0f0; c.action = a; c.phase = ph; c.mood = mood; c.extra = extra
    end
    for (c, (a, ph, f)) in zip(birds, poses)    # pose = (action, phase, fidget): a seed that fidgets f now
        f == 0 && continue
        T = Float32(w.t)
        c.seed = something(findfirst(s -> (r = NG.fidget(NG.PoseCtx(:idle, 0f0, 0f0, 0f0, s, T, 1f0)); r[1] == f && r[2] > 0.9f0),
                                     0f0:0.0005f0:1f0), 1) * 0.0005f0 - 0.0005f0
    end
    NG.sync!(g.stage, w); NG.sync_sun!(g.stage, w)
    gz = NG.ground(w.island, (bx, by))[3]
    rig = NG.CameraRig(; mode = :fixed); rig.eye = Point3f(bx, by - 6.5f0, gz + 1.0f0); rig.target = Point3f(bx, by, gz + 0.8f0)
    NG.update_camera!(rig, w, scene, 0.0; snap = true)
    screen = RayMakie.Screen(root_scene; visible = false, rasterize = true)
    img = Makie.colorbuffer(screen)
    close(screen)
    Makie.save(path, img)
    return path
end
