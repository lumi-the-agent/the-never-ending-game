# One creature of each species in a row on open meadow at 11:00, raster picture, without touching
# the live game: `include("world/tools/lineup.jl"); lineup("media/x.png")` in the agent session.
using NeverendingGame, Makie, RayMakie
const NG = NeverendingGame

"The land spot (and the camera spot 5 m south of it) furthest from trees, bushes and rocks."
function open_spot(w)
    best = nothing; bd = -99f0
    for x in -18f0:1f0:18f0, y in -18f0:1f0:18f0
        NG.on_land(w.island, x, y; margin = 1f0) || continue
        NG.on_land(w.island, x, y - 5; margin = 0.5f0) || continue
        m = minimum(w.props) do p
            p.kind in (:tree, :bush, :rock) || return 99f0
            r = p.kind === :tree ? 2.6f0 * p.scale : 1f0 * p.scale
            min(hypot(p.pos[1] - x, p.pos[2] - y) - r - 3.5f0, hypot(p.pos[1] - x, p.pos[2] - (y - 5)) - r)
        end
        m > bd && (bd = m; best = (x, y))
    end
    return best
end

function lineup(path; size = (1400, 500), traced = false, samples = 32)   # traced: path traced still (check materials)
    g = NG.Game(NG.game_root(); quiet = true)
    w = g.world
    NG.skip_to_hour!(w, 11)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
    cam3d!(scene)
    g.stage = NG.Stage(scene, w; show_names = false)
    bx, by = open_spot(w)
    seen = Set{String}(); row = NG.Creature[]
    for c in w.creatures
        c.species in seen && continue
        push!(seen, c.species); push!(row, c)
    end
    for c in w.creatures
        c in row || (c.pos = NG.ground(w.island, (bx + 30f0, by)))      # out of the picture
    end
    for (i, c) in enumerate(row)
        c.pos = NG.ground(w.island, (bx + (i - (length(row) + 1) / 2) * 1.4f0, by))
        c.yaw = Float32(-pi / 2) - NG.species_of(c).heading
        c.action = :idle; c.phase = 0.3f0
    end
    NG.sync!(g.stage, w); NG.sync_sun!(g.stage, w)
    gz = NG.ground(w.island, (bx, by))[3]
    rig = NG.CameraRig(; mode = :fixed); rig.eye = Point3f(bx, by - 5f0, gz + 1.2f0); rig.target = Point3f(bx, by, gz + 0.5f0)
    NG.update_camera!(rig, w, scene, 0.0; snap = true)
    screen = traced ? RayMakie.Screen(root_scene; visible = false, rasterize = false, exposure = NG.FILM_EXPOSURE) :
                      RayMakie.Screen(root_scene; visible = false, rasterize = true)
    img = traced ? Makie.colorbuffer(screen; samples) : Makie.colorbuffer(screen)
    close(screen)
    Makie.save(path, img)
    return [c.species for c in row]
end
