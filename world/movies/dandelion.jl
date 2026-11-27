# Dandelion clocks (s136): Lumi blows two clocks on the meadow; the film presses I like a player, so the seeds are
# plugins/dandelion.jl's own (drag to the breeze and eddies, nothing scripted). Camera low and side-on, downwind.
#   submit_job(:clip; path, script = "movies/dandelion.jl", call = "dandelion_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame

function dandelion_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 7.0,
                        hour = 17.2, spot = (-4f0, 18f0), blows = (0.6, 3.4))   # (-8,4) put a mushroom house and a tool rack in front
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        isdefined(Main, :JELLY) && (Main.JELLY[:active] = false; Main.JELLY[:last] = time() + 1e6)
        w = g.world; me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, spot); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        wd = isdefined(Main, :WIND) && haskey(Main.WIND, :now) ? Base.invokelatest(Main.WIND[:now], w.t)[1] : Vec2f(1, 0)
        S[:wind] = Vec3f(wd[1], wd[2], 0)
        me.yaw = Float32(atan(wd[2], wd[1])) - NG.species_of(me).heading     # blow downwind
        for c in w.creatures
            c === me && continue
            if hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 9
                c.pos = NG.ground(w.island, (spot[1] - 12f0, spot[2] - 10f0)); c.goal = NG.Goal()
            end
        end
        S[:next] = 1
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi"); me.controlled = true
        delete!(g.keys_down, Makie.Keyboard.i)
        if S[:next] <= length(blows) && t >= blows[S[:next]]
            push!(g.keys_down, Makie.Keyboard.i); S[:next] += 1
        end
        x, y, z = me.pos
        f = S[:wind]; l = Vec3f(-f[2], f[1], 0)
        rig.mode = :fixed
        rig.eye = Point3f(x, y, z) + 1.6f0 * f - 3.6f0 * l + Point3f(0, 0, 1.2f0)
        rig.target = Point3f(x, y, z) + 2.6f0 * f + Point3f(0, 0, 0.9f0)
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
