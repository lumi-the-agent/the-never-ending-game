# Which lead material reads as real cast lead on the beach (s171 free time): slabs + spheres of each candidate on a
# sand-coloured board in a quiet copy at 11:00, one path traced still. `include("world/tools/leadlook.jl"); leadlook(path)`
using NeverendingGame, Makie, RayMakie, GeometryBasics
const NG = NeverendingGame
include(joinpath(@__DIR__, "lineup.jl"))   # open_spot

const LEAD_CANDIDATES = [
    "now: metal 1, base .58, rough .5" => NG.Hikari.Principled(base_color = (0.58f0, 0.59f0, 0.61f0), metallic = 1f0, roughness = 0.5f0),
    "metal 1, rough .8" => NG.Hikari.Principled(base_color = (0.58f0, 0.59f0, 0.61f0), metallic = 1f0, roughness = 0.8f0),
    "oxide skin: metal .5, rough .7" => NG.Hikari.Principled(base_color = (0.52f0, 0.53f0, 0.55f0), metallic = 0.5f0, roughness = 0.7f0),
    "dull oxide: metal .25, rough .75" => NG.Hikari.Principled(base_color = (0.50f0, 0.51f0, 0.53f0), metallic = 0.25f0, roughness = 0.75f0),
    "grey card .5 (reference)" => NG.Hikari.Diffuse(color = (0.5, 0.5, 0.5)),
]

function leadlook(path; size = (1400, 500), samples = 96, hour = 11)
    g = NG.Game(NG.game_root(); quiet = true)
    w = g.world
    NG.skip_to_hour!(w, hour)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
    cam3d!(scene)
    g.stage = NG.Stage(scene, w; show_names = false)
    bx, by = open_spot(w)
    for c in w.creatures
        c.pos = NG.ground(w.island, (bx + 30f0, by))
    end
    NG.sync!(g.stage, w); NG.sync_sun!(g.stage, w)
    gz = NG.ground(w.island, (bx, by))[3] + 0.05f0
    n = length(LEAD_CANDIDATES)
    # a sand-coloured board under the row (the cove sand's colour, as the casting patch draws it)
    mesh!(scene, Rect3f(Vec3f(bx - 0.25f0 * n - 0.3f0, by - 0.5f0, gz - 0.02f0), Vec3f(0.5f0 * n + 0.6f0, 1.2f0, 0.02f0));
          color = RGBf(0.87, 0.77, 0.58), material = NG.Hikari.Diffuse(color = (0.87, 0.77, 0.58), roughness = 1f0))
    for (i, (name, m)) in enumerate(LEAD_CANDIDATES)
        x = bx + (i - (n + 1) / 2) * 0.5f0
        mesh!(scene, Rect3f(Vec3f(x - 0.12f0, by - 0.25f0, gz), Vec3f(0.24f0, 0.14f0, 0.012f0)); color = :grey, material = m)
        mesh!(scene, Sphere(Point3f(x, by + 0.15f0, gz + 0.08f0), 0.08f0); color = :grey, material = m)
        @info "slot $i" name
    end
    s = NG.sun(w)
    rig = NG.CameraRig(; mode = :fixed)
    rig.eye = Point3f(bx, by - 2.2f0, gz + 1.3f0); rig.target = Point3f(bx, by, gz)
    NG.update_camera!(rig, w, scene, 0.0; snap = true)
    screen = RayMakie.Screen(root_scene; visible = false, rasterize = false, exposure = NG.FILM_EXPOSURE)
    img = Makie.colorbuffer(screen; samples)
    close(screen)
    Makie.save(path, img)
    return (; sun = s, spot = (bx, by))
end
