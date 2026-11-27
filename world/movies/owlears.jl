# The owl that hunts by ear (s132, projects/owl-ears.md): at night Lumi walks behind the cottage, then round its
# north corner into the open. The owl in the tree west of the cottage hears every footstep through the island
# (plugins/owlears.jl runs in the film's game: physics/echo.jl `hear`, first wavefront) and turns to where the sound
# comes from; its faint moonlit spot on the ground shows where it is looking. Nothing here moves the owl.
#   submit_job(:clip; path, script = "movies/owlears.jl", call = "owlears_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame

# Lumi's walk: east side of the cottage going north, then west along its north side into the owl's view
const OE_PATH = (Point2f(-3.4, 1.5), Point2f(-3.4, 8.6), Point2f(-9.5, 9.4))

function oe_along(path, s)
    for k in 1:length(path) - 1
        a, b = path[k], path[k + 1]; L = hypot((b - a)...)
        s <= L && return a + (b - a) * (s / L), atan(b[2] - a[2], b[1] - a[1])
        s -= L
    end
    a, b = path[end - 1], path[end]
    return b, atan(b[2] - a[2], b[1] - a[1])
end

function owlears_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 9.0,
                      hour = 22.4, speed = 1.6f0, start = 0.6, eye = (-15.5f0, -0.5f0, 3.6f0), target = (-7.5f0, 6.5f0, 2.6f0),
                      night_dark = 0.6f0)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        NG.NIGHT_DARK[] = Float32(night_dark)
        w = g.world; me = NG.creature(w, "Lumi")
        p0, yaw = oe_along(OE_PATH, 0f0)
        me.pos = NG.ground(w.island, (p0[1], p0[2])); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        me.yaw = Float32(yaw) - NG.species_of(me).heading
        S[:t] = 0.0
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi")
        rig.mode = :fixed
        rig.eye = Point3f(eye...); rig.target = Point3f(target...)
        me.controlled = true
        s = Float32(max(0.0, t - start)) * speed
        p, yaw = oe_along(OE_PATH, s)
        me.pos = NG.ground(w.island, (p[1], p[2]))
        me.yaw = Float32(yaw) - NG.species_of(me).heading
        me.action = t > start && s < 13.5f0 ? :walk : :idle
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
