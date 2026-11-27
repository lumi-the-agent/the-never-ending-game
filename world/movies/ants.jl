# Ants on a honey road (s137, project ant-road). The ants and the biscuit are physics/ants.jl (pheromone fields,
# antennae steering, pullers summed against friction), stepped while the film runs; nothing is keyed by hand.
# A drawn honey line runs in a loop from the nest to a biscuit; the film is 3x time-lapse from a low camera.
#   submit_job(:clip; path, script = "movies/ants.jl", call = "ants_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics, LinearAlgebra
const NG = NeverendingGame
const ANTS = Module(:ANTS)
Base.include(ANTS, joinpath(@__DIR__, "..", "physics", "ants.jl"))

const AN_HIDE = Point3f(0, 0, -50)

"An ant: head, thorax, gaster as three squashed balls along +x, about 2.2 cm long."
function ant_mesh()
    ball(c, r) = GeometryBasics.normal_mesh(GeometryBasics.Tesselation(Sphere(Point3f(c...), Float32(r)), 10))
    ms = [ball((0.008, 0, 0.004), 0.0032), ball((0.0015, 0, 0.004), 0.0028), ball((-0.0065, 0, 0.0045), 0.0048)]
    GeometryBasics.merge(ms)
end

function ants_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 10.0,
                   hour = 16.0, origin = (4f0, -14f0), nants = 500, warm = 38.0, lapse = 3.0, cut = 4.0)
    S = Dict{Symbol,Any}()
    ox, oy = origin
    road = [(0.3, 1.5), (0.8, 2.2), (1.5, 2.5), (2.1, 2.2), (2.5, 1.5)]
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) || continue
            nm = string(p.attributes[:name][])
            (nm in ("rain", "rainrings", "raincloud") ||
             occursin("grass", nm)) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world
        cx, cy = ox + 1.5f0, oy + 1.5f0
        for c in w.creatures     # friends stay off the road (Lumi watches from the nest end)
            if hypot(c.pos[1] - cx, c.pos[2] - cy) < 6
                a = atan(c.pos[2] - cy, c.pos[1] - cx)
                c.pos = NG.ground(w.island, (cx + 7f0 * cos(a), cy + 7f0 * sin(a))); c.goal = NG.Goal()
                c.controlled = true   # take 1: Pinchy wandered back and stood over the biscuit for the whole close shot
            end
        end
        me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, (ox - 1.2f0, oy + 2.6f0)); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        me.yaw = 0f0 - NG.species_of(me).heading
        W = ANTS.AntWorld(); ANTS.ants!(W, nants); ANTS.honey!(W, road)
        nsteps = round(Int, warm / 0.05)
        for _ in 1:nsteps
            ANTS.step!(W, 0.05)
        end
        S[:W] = W
        gz(x, y) = NG.ground(w.island, (ox + Float32(x), oy + Float32(y)))[3]
        S[:gz] = gz
        # the honey: amber drops along the drawn line
        hp = Point3f[]
        for k in 1:length(road)-1
            (x0, y0), (x1, y1) = road[k], road[k+1]
            m = ceil(Int, hypot(x1 - x0, y1 - y0) / 0.02)
            for s in 0:m-1
                u = s / m; x = x0 + u * (x1 - x0); y = y0 + u * (y1 - y0)
                push!(hp, Point3f(ox + x, oy + y, gz(x, y) + 0.001f0))
            end
        end
        S[:honey] = meshscatter!(g.stage.scene, hp; marker = GeometryBasics.Tesselation(Sphere(Point3f(0), 1f0), 10),
            markersize = Vec3f(0.011, 0.011, 0.0025), color = RGBf(0.85, 0.5, 0.08),
            material = NG.Hikari.Plastic(color = (0.85, 0.5, 0.08), roughness = 0.08), name = :antfilm_honey)
        S[:ants] = meshscatter!(g.stage.scene, fill(AN_HIDE, nants); marker = ant_mesh(), markersize = 1f0,
            rotation = fill(Makie.Quaternionf(0, 0, 0, 1), nants), color = RGBf(0.16, 0.07, 0.04),
            material = NG.Hikari.Plastic(color = (0.16, 0.07, 0.04), roughness = 0.3), name = :antfilm_ants)
        S[:crumbs] = meshscatter!(g.stage.scene, fill(AN_HIDE, nants); marker = GeometryBasics.Tesselation(Sphere(Point3f(0), 1f0), 8),
            markersize = 0f0, color = RGBf(0.93, 0.8, 0.55), name = :antfilm_crumbs)
        S[:biscuit] = mesh!(g.stage.scene, GeometryBasics.normal_mesh(GeometryBasics.Tesselation(
                Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 0.022), Float32(W.br)), 48));
            color = RGBf(0.82, 0.58, 0.28), material = NG.Hikari.Diffuse(color = (0.82, 0.58, 0.28)), name = :antfilm_biscuit)
        S[:t] = 0.0
    end
    draw! = function ()
        W = S[:W]; gz = S[:gz]; n = length(W.x)
        P = Vector{Point3f}(undef, n); R = Vector{Makie.Quaternionf}(undef, n); C = fill(AN_HIDE, n)
        for k in 1:n
            z = gz(W.x[k], W.y[k])
            P[k] = Point3f(ox + W.x[k], oy + W.y[k], z)
            R[k] = Makie.qrotation(Vec3f(0, 0, 1), Float32(W.th[k]))
            W.state[k] == 1 && (C[k] = P[k] + Point3f(0.013f0 * cos(W.th[k]), 0.013f0 * sin(W.th[k]), 0.006f0))
        end
        Makie.update!(S[:ants]; arg1 = P, rotation = R)
        Makie.update!(S[:crumbs]; arg1 = C, markersize = [c === AN_HIDE ? 0f0 : 0.0042f0 for c in C])
        Makie.translate!(S[:biscuit], Vec3f(ox + W.bx, oy + W.by, gz(W.bx, W.by) - 0.002f0))
        Makie.rotate!(S[:biscuit], Makie.qrotation(Vec3f(0, 0, 1), Float32(W.ba)))
    end
    shot = function (g, rig, t)
        W = S[:W]
        target = warm + lapse * max(t, 0.0)
        while W.t < target
            ANTS.step!(W, 0.05)
        end
        draw!()
        me = NG.creature(g.world, "Lumi"); me.controlled = true
        rig.mode = :fixed
        if t < cut   # the whole road from the south: the nest left, the honey loop, the biscuit right
            rig.eye = Point3f(ox + 1.4f0, oy - 0.7f0, S[:gz](1.4, -0.7) + 1.25f0)
            rig.target = Point3f(ox + 1.4f0, oy + 1.8f0, S[:gz](1.4, 1.8))
        else         # close on the biscuit and its pullers, from the nest side, low
            bx, by = W.bx, W.by
            rig.eye = Point3f(ox + bx - 0.45f0, oy + by - 0.42f0, S[:gz](bx - 0.45, by - 0.42) + 0.3f0)
            rig.target = Point3f(ox + bx, oy + by, S[:gz](bx, by) + 0.01f0)
        end
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
