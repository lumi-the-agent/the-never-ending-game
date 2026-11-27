# A top floating over a ring of lodestone (s148, project levitron). physics/levitron.jl moves the top: a full rigid
# body under gravity, the ring's field force mu0 G m and torque m x B. It spins on a glass plate held where the field
# balances its weight; the plate sinks away and nothing else holds it. 5.75 g of copper washers: inside the window
# the simulation found (5.5 to 6.0 g floats at 25 rev/s; 6.25 g has no balance point; 5 g drifts off).
#   submit_job(:clip; path, script = "movies/levitron.jl", call = "levitron_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "levitron.jl"))

"Closed annulus (outer Ro, inner Ri, z from z0 to z1), with per-vertex colours from `col(phi, which)`."
function annulus(Ro, Ri, z0, z1; n = 72, col = (phi, k) -> RGBf(0.2, 0.2, 0.2))
    V = Point3f[]; C = RGBf[]; F = TriangleFace{Int}[]
    for (k, (r, z)) in enumerate(((Ro, z0), (Ro, z1), (Ri, z1), (Ri, z0))), j in 0:n-1
        phi = 2pi * j / n
        push!(V, Point3f(r * cos(phi), r * sin(phi), z)); push!(C, col(phi, k))
    end
    id(k, j) = (k - 1) * n + mod(j, n) + 1
    for k in 1:4, j in 0:n-1
        k2 = k % 4 + 1
        push!(F, TriangleFace(id(k, j), id(k, j + 1), id(k2, j + 1))); push!(F, TriangleFace(id(k, j), id(k2, j + 1), id(k2, j)))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(V, F)), C
end

function quat(R)
    t = R[1, 1] + R[2, 2] + R[3, 3]
    if t > 0
        s = sqrt(t + 1) * 2
        Quaternionf((R[3, 2] - R[2, 3]) / s, (R[1, 3] - R[3, 1]) / s, (R[2, 1] - R[1, 2]) / s, s / 4)
    elseif R[1, 1] > R[2, 2] && R[1, 1] > R[3, 3]
        s = sqrt(1 + R[1, 1] - R[2, 2] - R[3, 3]) * 2
        Quaternionf(s / 4, (R[1, 2] + R[2, 1]) / s, (R[1, 3] + R[3, 1]) / s, (R[3, 2] - R[2, 3]) / s)
    elseif R[2, 2] > R[3, 3]
        s = sqrt(1 + R[2, 2] - R[1, 1] - R[3, 3]) * 2
        Quaternionf((R[1, 2] + R[2, 1]) / s, s / 4, (R[2, 3] + R[3, 2]) / s, (R[1, 3] - R[3, 1]) / s)
    else
        s = sqrt(1 + R[3, 3] - R[1, 1] - R[2, 2]) * 2
        Quaternionf((R[1, 3] + R[3, 1]) / s, (R[2, 3] + R[3, 2]) / s, s / 4, (R[2, 1] - R[1, 2]) / s)
    end
end

function levitron_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0,
                       hour = 16.4, spot = (5.6f0, -13.0f0), washers = 0.00575, spin = 25.0, hold = 2.0)
    L = Levitron
    run = L.launch(; washers, spin, secs = seconds + 0.2, fps, hold)
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world; sc = gm.stage.scene
        g = NG.ground(w.island, spot)
        P = Point3f(g[1], g[2], g[3] + 0.04f0)                # the slate's top
        S[:P] = P
        slate = GeometryBasics.normal_mesh(Cylinder(P - Point3f(0, 0, 0.04f0), P, 0.22f0))
        mesh!(sc, slate; color = RGBf(0.30, 0.32, 0.34), name = :lev_slate,
              material = NG.Hikari.Diffuse(color = (0.30, 0.32, 0.34), roughness = 0.6f0))
        S[:zr] = P[3] + 0.025f0                                # the ring's top face = the simulation's z = 0
        rm, rc = annulus(0.075, 0.025, -0.025, 0.0; col = (phi, k) -> RGBf(0.12, 0.11, 0.12))
        r = mesh!(sc, rm; color = RGBf(0.12, 0.11, 0.12), name = :lev_ring,
                  material = NG.Hikari.Diffuse(color = (0.12, 0.11, 0.12), roughness = 0.45f0))
        translate!(r, Vec3f(P[1], P[2], S[:zr]))
        # the top: ferrite disc painted in sectors (so the spin shows), copper washers on a wooden spindle
        dm, dc = annulus(0.015, 0.003, -0.003, 0.003; col = (phi, k) -> k == 2 && iseven(floor(Int, phi / (pi / 3))) ? RGBf(0.80, 0.15, 0.10) : RGBf(0.93, 0.88, 0.75))
        wm, _ = annulus(0.006, 0.003, 0.003, 0.0105)
        sp = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -0.012), Point3f(0, 0, 0.022), 0.003f0))
        S[:top] = [mesh!(sc, dm; color = dc, name = :lev_disc, material = NG.Hikari.Diffuse(color = (0.9, 0.9, 0.9), roughness = 0.5f0)),
                   mesh!(sc, wm; color = RGBf(0.85, 0.45, 0.25), name = :lev_washers, material = NG.Hikari.Copper(roughness = 0.2f0)),
                   mesh!(sc, sp; color = RGBf(0.7, 0.5, 0.3), name = :lev_spindle, material = NG.Hikari.Diffuse(color = (0.7, 0.5, 0.3), roughness = 0.4f0))]
        pm = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -0.003), Point3f(0, 0, 0), 0.05f0))
        S[:plate] = mesh!(sc, pm; color = RGBAf(0.9, 0.95, 1.0, 0.3), name = :lev_plate, material = NG.Hikari.Glass())
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile, :tops_live_board, :tops_live_top, :tops_board, :wire_bench) || startswith(string(p.attributes[:name][]), "paperpage_") || startswith(string(p.attributes[:name][]), "floattop_")) && (p.visible[] = false)   # s148: the plugin's own ring stands 1 m behind; s149: this && sat inside the comment, so nothing was hidden and the board's top filled the film
        end
        P = S[:P]; zr = S[:zr]
        k = clamp(round(Int, t * fps) + 1, 1, length(run.frames))
        tt, x, Rm, zp, phi = run.frames[k]
        if tt < hold                                       # on the plate it spins in place: turn the picture by the spin
            c, s = cos(phi), sin(phi); Rm = Rm * [c -s 0; s c 0; 0 0 1]
        end
        q = quat(Rm); o = Vec3f(P[1] + x[1], P[2] + x[2], zr + x[3])
        for p in S[:top]
            Makie.rotate!(p, q); translate!(p, o)
        end
        translate!(S[:plate], Vec3f(P[1], P[2], zr + zp))
        rig.mode = :fixed
        rig.eye = Point3f(P[1] + 0.05f0, P[2] - 0.34f0, zr + 0.15f0)
        rig.target = Point3f(P[1], P[2], zr + 0.045f0)
        return nothing
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(r, (; path, fell = run.fell, hover_cm = 100run.z0, mass_g = 1000run.mass))
end
