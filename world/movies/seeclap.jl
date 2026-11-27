# See by clapping (s130, project island-echo): at night Lumi claps by the pond and every place the sound touches
# lights up the moment the sound gets there, slowed 40 times. The points are the traced hits of real acoustic rays
# (physics/echo.jl `echo_hits`, Raycore BVH over the stage's 1.4M triangles): nothing is placed by hand, the
# ring runs over the ground, climbs the trees on the side facing the clap and comes back off what it hit.
#   submit_job(:clip; path, script = "movies/seeclap.jl", call = "seeclap_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame
const E = Module(:EchoPhysics)
Base.include(E, joinpath(@__DIR__, "..", "physics", "echo.jl"))

const SC_HIDE = Point3f(0, 0, -50)

function seeclap_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 6.0,
                      hour = 22.5, spot = (-4f0, 10f0), clap = 0.8, slow = 40.0, fade = 0.45, rays = 8000,
                      bounces = 3, size = 0.07f0, eye = (-6f0, -8f0, 5f0), slots = 700)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world; me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, spot); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        src = me.pos + Vec3f(0, 0, 1.2)                     # the clap: Lumi's hands
        tlas = E.echo_tlas(E.stage_triangles(g.stage.scene), E.KA.CPU())
        P, T, En = E.echo_hits(tlas, E.KA.CPU(), src; rays, bounces)
        S[:P] = P; S[:T] = T; S[:E] = En
        # a fixed pool of `slots` points (only the ones glowing now): every emissive instance is a light the
        # tracer rebuilds each frame, and 7643 of them took 135 s a frame at 480x270 (s130)
        ball = GeometryBasics.normal_mesh(GeometryBasics.Tesselation(GeometryBasics.Sphere(Point3f(0), 1f0), 6))
        S[:plot] = meshscatter!(g.stage.scene, fill(SC_HIDE, slots); marker = ball,
                                markersize = zeros(Float32, slots), color = RGBf(1.0, 0.8, 0.45),
                                shading = Makie.NoShading,
                                material = NG.Hikari.Emission(color = (1.0, 0.8, 0.45), strength = 4.0), name = :seeclap)
        @info "seeclap: $(length(P)) hits, arrivals $(round(1000minimum(T); digits = 1))-$(round(1000maximum(T); digits = 1)) ms"
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi")
        x, y = spot; z = me.pos[3]
        rig.mode = :fixed
        rig.eye = Point3f(x + eye[1], y + eye[2], z + eye[3])
        rig.target = Point3f(x, y + 2f0, z + 0.3f0)
        me.controlled = true
        me.action = abs(t - clap) < 0.3 ? :wave : :idle
        P = S[:P]; T = S[:T]; En = S[:E]
        pos = fill(SC_HIDE, slots); ms = zeros(Float32, slots); n = 0
        for k in eachindex(P)
            age = t - (clap + slow * T[k])
            (0 <= age < fade && n < slots) || continue
            n += 1
            pos[n] = P[k]
            ms[n] = size * sqrt(1 - age / fade) * (0.6f0 + 0.4f0 * sqrt(En[k]))
        end
        Makie.update!(S[:plot]; arg1 = pos, markersize = ms)      # both at once (setting [1][] alone: UndefRefError)
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
