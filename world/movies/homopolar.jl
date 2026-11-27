# The bent wire that spins by itself (s146): three AA cells on disc magnets on the slate board at the tops board
# (5.6, -13), each with a copper wire bent differently. physics/homopolar.jl spins each from its own path in the magnet's
# field: a balanced heart whirs (~25 rev/s), a one-armed wire flies off its dimple, a heart bent tight against the
# magnet is held by its own squeeze and never starts. Shown 12x slowed so the spin does not strobe.
#   submit_job(:clip; path, script = "movies/homopolar.jl", call = "homopolar_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "homopolar.jl"))

"A tube mesh along a polyline (radius rad, nring sides)."
function tube(pts, rad; nring = 10)
    P = [Point3f(p...) for p in pts]
    n = length(P)
    verts = Point3f[]; fcs = GLTriangleFace[]
    for i in 1:n
        t = normalize(i == 1 ? P[2] - P[1] : i == n ? P[n] - P[n-1] : P[i+1] - P[i-1])
        a = abs(t[3]) < 0.9 ? Vec3f(0, 0, 1) : Vec3f(1, 0, 0)
        u = normalize(cross(t, a)); w = cross(t, u)
        for k in 0:nring-1
            ph = 2pi * k / nring
            push!(verts, P[i] + rad * (cos(ph) * u + sin(ph) * w))
        end
    end
    for i in 1:n-1, k in 0:nring-1
        a = (i - 1) * nring + k + 1; b = (i - 1) * nring + mod(k + 1, nring) + 1
        c = i * nring + k + 1; d = i * nring + mod(k + 1, nring) + 1
        push!(fcs, GLTriangleFace(a, c, b)); push!(fcs, GLTriangleFace(b, c, d))
    end
    return GeometryBasics.normal_mesh(GeometryBasics.Mesh(verts, fcs))
end

function homopolar_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24, seconds = 8.0,
                        hold = 1.2, slow = 12.0, hour = 16.6, spot = (5.6f0, -13.0f0))
    H = Homopolar; r = H.Rig()
    cases = [(H.onearm(r), 0.1e-3), (H.heart(r), 0.1e-3), (H.heart(r), 0.6e-3)]   # flies off, whirs, held tight
    real_s = (seconds - hold) / slow + 0.05
    runs = [H.spin(a, r; seconds = real_s, squeeze = s) for (a, s) in cases]
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot)
        P = Point3f(g[1], g[2], g[3] + 0.05f0)
        S[:P] = P
        sc = gm.stage.scene
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(P - Point3f(0.15f0, 0.07f0, 0.03f0), Vec3f(0.30f0, 0.14f0, 0.03f0)));
              color = RGBf(0.30, 0.34, 0.38), name = :hp_board, material = NG.Hikari.Diffuse(color = (0.30, 0.34, 0.38), roughness = 0.7f0))
        S[:wires] = []
        for (i, (arms, _)) in enumerate(cases)
            O = P + Vec3f((i - 2) * 0.075f0, 0, 0)
            mesh!(sc, GeometryBasics.normal_mesh(Cylinder(O, O + Point3f(0, 0, r.H), Float32(r.R))); color = RGBf(0.78, 0.78, 0.8),
                  name = Symbol("hp_magnet", i), material = NG.Hikari.Aluminum(roughness = 0.2f0))
            mesh!(sc, GeometryBasics.normal_mesh(Cylinder(O + Point3f(0, 0, r.H), O + Point3f(0, 0, r.H + r.Lb - 0.0015), 0.007f0));
                  color = RGBf(0.12, 0.18, 0.42), name = Symbol("hp_cell", i), material = NG.Hikari.Diffuse(color = (0.12, 0.18, 0.42), roughness = 0.35f0))
            mesh!(sc, GeometryBasics.normal_mesh(Cylinder(O + Point3f(0, 0, r.H + r.Lb - 0.0015), O + Point3f(0, 0, r.H + r.Lb), 0.0025f0));
                  color = RGBf(0.8, 0.8, 0.82), name = Symbol("hp_button", i), material = NG.Hikari.Aluminum(roughness = 0.25f0))
            wm = [mesh!(sc, tube(H.fine(arm; h = 0.002), Float32(r.d / 2)); color = RGBf(0.85, 0.45, 0.3),
                        material = NG.Hikari.Copper(roughness = 0.18f0), name = Symbol("hp_wire", i, "_", j)) for (j, arm) in enumerate(arms)]
            push!(S[:wires], (O, wm))
        end
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:tops_live_board, :tops_live_top)) && (p.visible[] = false)
        end
        treal = max(t - hold, 0.0) / slow
        for (i, (O, wm)) in enumerate(S[:wires])
            run = runs[i]
            k = clamp(round(Int, treal / run.dt) + 1, 1, length(run.ths))
            off = Vec3f(0, 0, 0); th = run.ths[k]
            if !isnan(run.off_t) && treal > run.off_t
                # off the dimple: its centre carries on at the speed it had (w e, tangential) and falls to the board
                k0 = round(Int, run.off_t / run.dt); th0 = run.ths[k0]; w0 = run.ws[k0]
                dtf = treal - run.off_t
                v = abs(w0) * run.e
                drop = min(4.9 * dtf^2, r.H + r.Lb - 0.004)
                off = Vec3f(v * min(dtf, 0.12) * -sin(th0), v * min(dtf, 0.12) * cos(th0), -drop)
                th = th0 + w0 * min(dtf, 0.08)
            end
            for m in wm
                Makie.rotate!(m, Makie.qrotation(Vec3f(0, 0, 1), Float32(th)))
                Makie.translate!(m, O + off)
            end
        end
        P = S[:P]
        rig.mode = :fixed
        T = P + Point3f(0.0f0, 0.0f0, 0.030f0)
        rig.target = T
        rig.eye = T + Point3f(0.0f0, -0.24f0, 0.07f0)
        return nothing
    end
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(res, (; path, rps = [round(x.ws[end] / 2pi, digits = 1) for x in runs], off_t = [x.off_t for x in runs]))
end
