# Fireflies that learn my rhythm (s131): at night 300 fireflies twinkle over the pond meadow, each on its own
# clock (pulse-coupled oscillators, physics/fireflies.jl). At `start` Lumi begins to flash a lantern on a steady
# beat; the flies near it shift their phase at every flash they see, their neighbours follow them, and the field
# falls into one flash. Nothing is timed by hand: who flashes when comes from the simulation, stepped with the film.
#   submit_job(:clip; path, script = "movies/fireflysync.jl", call = "fireflysync_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame
const FS = Module(:FireflyPhysics)
Base.include(FS, joinpath(@__DIR__, "..", "physics", "fireflies.jl"))

const FS_HIDE = Point3f(0, 0, -50)

ff_glow(age) = age < 0.16f0 ? exp(-age / 0.05f0) : 0f0   # a real flash lasts ~0.1-0.2 s: short flashes make the field go dark between beats once in step

function fireflysync_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 10.0,
                          hour = 22.0, spot = (-4f0, 10f0), start = 3.0, beat = 0.55, n = 300, seed = 3,
                          eye = (2.5f0, -9.5f0, 2.6f0), size = 0.05f0, strength = 6.0)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        isdefined(Main, :NIGHTCLAP) && haskey(Main.NIGHTCLAP, :plot) && (Main.NIGHTCLAP[:plot].visible[] = false)
        if isdefined(Main, :FIREFLYSYNC)            # the live plugin's own swarm stands at the same spot: off
            Main.FIREFLYSYNC[:off] = true
            for k in (:plot, :lamp)
                haskey(Main.FIREFLYSYNC, k) && (Main.FIREFLYSYNC[k].visible[] = false)
            end
        end
        w = g.world; me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, spot); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        gr = (x, y) -> Float32(max(NG.ground(w.island, (x, y))[3], -0.05f0))
        S[:sw] = FS.ff_swarm((spot[1], spot[2] + 3f0), n; spread = (8f0, 5f0), seed, ground = gr)
        S[:lantern] = Point3f(me.pos) + Point3f(0.35f0, 0.1f0, 1.0f0)
        S[:t] = 0.0; S[:lph] = 0.0
        ball = GeometryBasics.normal_mesh(GeometryBasics.Tesselation(GeometryBasics.Sphere(Point3f(0), 1f0), 6))
        S[:plot] = meshscatter!(g.stage.scene, fill(FS_HIDE, n); marker = ball, markersize = zeros(Float32, n),
                                color = RGBf(0.8, 1.0, 0.35), shading = Makie.NoShading,
                                material = NG.Hikari.Emission(color = (0.8, 1.0, 0.35), strength = strength), name = :fireflyfilm)
        S[:lamp] = meshscatter!(g.stage.scene, [FS_HIDE]; marker = ball, markersize = [0f0],
                                color = RGBf(1.0, 0.72, 0.35), shading = Makie.NoShading,
                                material = NG.Hikari.Emission(color = (1.0, 0.72, 0.35), strength = 2strength),
                                name = :fireflyfilmlamp)
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi")
        x, y = spot; z = me.pos[3]
        rig.mode = :fixed
        rig.eye = Point3f(x + eye[1], y + eye[2], z + eye[3])
        rig.target = Point3f(x, y + 2.5f0, z + 1.0f0)
        me.controlled = true
        sw = S[:sw]
        dt = t - S[:t]
        lf = false
        if dt > 0
            if t >= start
                S[:lph] += dt / beat
                lf = S[:lph] >= 1
                lf && (S[:lph] -= 1)
                lf && (S[:lastlamp] = t)
            end
            FS.ff_step!(sw, dt; lantern = S[:lantern], lantern_fired = lf)
            S[:t] = t
        end
        me.action = t >= start ? :wave : :idle
        pos = fill(FS_HIDE, length(sw.pos)); ms = zeros(Float32, length(sw.pos))
        for i in eachindex(sw.pos)
            b = ff_glow(sw.age[i])
            b > 0.02f0 || continue
            pos[i] = sw.pos[i]; ms[i] = size * sqrt(b)
        end
        Makie.update!(S[:plot]; arg1 = pos, markersize = ms)
        la = haskey(S, :lastlamp) ? ff_glow(Float32(t - S[:lastlamp]) / 1.5f0) : 0f0
        Makie.update!(S[:lamp]; arg1 = [la > 0.02f0 ? S[:lantern] : FS_HIDE], markersize = [0.09f0 * sqrt(la)])
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
