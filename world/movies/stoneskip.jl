# Skipping stones (s131): Lumi on the north beach throws flat stones out over the sea. The same skip rule as
# plugins/stoneskip.jl (a skip only when the path meets the water under 35° and fast enough; each skip keeps ~82% of
# the speed and 55% of the vertical speed), stepped with the film; a ring spreads from every touch.
#   submit_job(:clip; path, script = "movies/stoneskip.jl", call = "stoneskip_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics, Random
const NG = NeverendingGame

const SS_HIDE = Point3f(0, 0, -50)

function ss_ring_mesh(n = 40)
    pts = Point3f[]; fs = GLTriangleFace[]
    for k in 0:n-1
        a = 2f0 * Float32(pi) * k / n
        push!(pts, Point3f(0.88f0 * cos(a), 0.88f0 * sin(a), 0f0), Point3f(cos(a), sin(a), 0f0))
    end
    for k in 0:n-1
        i = 2k + 1; j = 2mod(k + 1, n) + 1
        push!(fs, GLTriangleFace(i, i + 1, j + 1), GLTriangleFace(i, j + 1, j))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

function stoneskip_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 8.0,
                        hour = 16.5, spot = (-4f0, 18f0), throws = (0.8, 4.2), eye = (1.6f0, -3.2f0, 1.6f0), seed = 4)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world; me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, spot); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        me.yaw = Float32(pi / 2) - NG.species_of(me).heading
        S[:rng] = Random.Xoshiro(seed); S[:t] = 0.0; S[:fly] = nothing; S[:rings] = Tuple{Point3f,Float64}[]; S[:next] = 1
        S[:stone] = meshscatter!(g.stage.scene, [SS_HIDE]; marker = GeometryBasics.Sphere(Point3f(0), 1f0),
            markersize = [Vec3f(0)], color = RGBf(0.5, 0.5, 0.53),
            material = NG.Hikari.Plastic(color = (0.5, 0.5, 0.53), roughness = 0.35), name = :ssfilm_stone)
        S[:ringp] = meshscatter!(g.stage.scene, fill(SS_HIDE, 24); marker = ss_ring_mesh(), markersize = fill(Vec3f(0), 24),
            color = RGBf(0.93, 0.97, 1.0), material = NG.Hikari.Diffuse(color = (0.93, 0.97, 1.0)), name = :ssfilm_rings)
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi")
        x, y = spot; z = me.pos[3]
        rig.mode = :fixed
        rig.eye = Point3f(x + eye[1], y + eye[2], z + eye[3])
        rig.target = Point3f(x, y + 9f0, 0.2f0)
        me.controlled = true
        dt = t - S[:t]; S[:t] = t
        rng = S[:rng]
        if S[:next] <= length(throws) && t >= throws[S[:next]]
            S[:next] += 1
            yaw = Float32(pi / 2) + 0.12f0 * (2rand(rng, Float32) - 1)
            f = Vec3f(cos(yaw), sin(yaw), 0f0)
            v = 10f0 + 2.5f0 * rand(rng, Float32); up = deg2rad(2f0 + 4f0 * rand(rng, Float32))
            S[:fly] = (pos = Point3f(me.pos) + 0.4f0 * f + Point3f(0, 0, 0.5f0), vel = v * (cos(up) * f + Vec3f(0, 0, sin(up))))
            S[:wave] = t
        end
        me.action = haskey(S, :wave) && t - S[:wave] < 0.4 ? :wave : :idle
        if dt > 0 && S[:fly] !== nothing
            h = Float32(dt) / 8
            for _ in 1:8
                S[:fly] === nothing && break
                pos, vel = S[:fly].pos, S[:fly].vel + Vec3f(0, 0, -9.81f0 * h)
                pos = pos + h * vel
                if pos[3] <= 0f0
                    vh = hypot(vel[1], vel[2])
                    push!(S[:rings], (Point3f(pos[1], pos[2], 0.012f0), t))
                    if atan(-vel[3], vh) < deg2rad(35f0) && vh > 3f0
                        keep = 0.82f0 + 0.08f0 * (2rand(rng, Float32) - 1)
                        vel = Vec3f(keep * vel[1], keep * vel[2], 0.55f0 * abs(vel[3])); pos = Point3f(pos[1], pos[2], 0.001f0)
                    else
                        S[:fly] = nothing; break
                    end
                end
                S[:fly] = (pos = pos, vel = vel)
            end
        end
        sp = S[:fly] === nothing ? SS_HIDE : S[:fly].pos
        Makie.update!(S[:stone]; arg1 = [sp], markersize = [sp === SS_HIDE ? Vec3f(0) : Vec3f(0.08, 0.08, 0.03)])
        filter!(r -> t - r[2] < 2.2, S[:rings])
        pos = fill(SS_HIDE, 24); ms = fill(Vec3f(0), 24)
        for (k, (p, t0)) in enumerate(Iterators.take(Iterators.reverse(S[:rings]), 24))
            a = Float32((t - t0) / 2.2); r = 0.15f0 + 1.3f0 * sqrt(a)
            pos[k] = p; ms[k] = Vec3f(r, r, 1f0) * (a < 0.85f0 ? 1f0 : (1f0 - a) / 0.15f0)
        end
        Makie.update!(S[:ringp]; arg1 = pos, markersize = ms)
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
