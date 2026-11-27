# A Piranesi view (s138, free time; "La Connocchia" on the workbench): a tall thing seen from the grass, portrait,
# with friends small at its foot, then etched by tools/etch.jl.
#   include("movies/piranesi.jl"); piranesi_still("media/x.mp4"; rasterize = true)
using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame

function piranesi_still(path; rasterize = true, samples = 16, width = 720, height = 1080, fps = 24, seconds = 0.5,
                        hour = 16.5, tree = (-10.2f0, 16.9f0), from = (1f0, -0.35f0), dist = 9f0, look_up = 4.5f0, eye_h = 0.35f0)
    d = Vec2f(from...) / hypot(from...)
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world
        # three friends small at the foot, between the camera and the trunk, a little to the side
        spots = ((2.2f0, 1.6f0), (2.8f0, -1.9f0), (3.6f0, 0.4f0))
        n = 0
        for c in w.creatures
            c.name == "Lumi" && continue
            n += 1; n > length(spots) && break
            a, b = spots[n]
            q = Vec2f(tree...) + a * d + b * Vec2f(-d[2], d[1])
            c.pos = NG.ground(w.island, (q[1], q[2])); c.goal = NG.Goal(); c.action = :idle
            c.yaw = Float32(atan(-d[2], -d[1])) - NG.species_of(c).heading
        end
        me = NG.creature(w, "Lumi"); me.pos = NG.ground(w.island, (tree[1] + 30f0, tree[2] - 25f0)); me.goal = NG.Goal()
    end
    shot = function (g, rig, t)
        w = g.world
        e = Vec2f(tree...) + dist * d
        gz = NG.ground(w.island, (e[1], e[2]))[3]
        tz = NG.ground(w.island, tree)[3]
        rig.mode = :fixed
        rig.eye = Point3f(e[1], e[2], gz + eye_h)
        rig.target = Point3f(tree[1], tree[2], tz + look_up)
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.0)
end

"A traced still of the view for the page: a few frames, the last one kept as a png at `path`."
function piranesi_png(path; samples = 64, tree = (-10.2f0, 16.9f0), from = (1f0, -0.35f0), dist = 9f0, look_up = 4.5f0, eye_h = 0.35f0)
    mp4 = path * ".mp4"
    r = piranesi_still(mp4; rasterize = false, samples, seconds = 0.25, tree = Tuple(Float32.(tree)), from = Tuple(Float32.(from)),
                       dist = Float32(dist), look_up = Float32(look_up), eye_h = Float32(eye_h))
    run(`ffmpeg -loglevel error -y -sseof -0.05 -i $mp4 -frames:v 1 -update 1 $path`)
    rm(mp4)
    return merge(r, (; path))
end
