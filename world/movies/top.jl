# Two turned tops on a board (s143, project tops): physics/top.jl spins a classic pointed top and a round tippe
# top; each frame draws them where the simulation put them, painted in sectors so the spin shows. 3/4 speed.
# The tippe top needs a hard spin: at 180 rad/s it rolls onto its rim and stalls at ~120 deg, at 300 it stands on its stem.
#   submit_job(:clip; path, script = "movies/top.jl", call = "tops_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "top.jl"))

"""Surface of revolution around the centre of mass: vertices, faces and sector colours."""
function top_mesh(S::TopShape; nphi = 48, cols = (RGBf(0.75, 0.12, 0.08), RGBf(0.93, 0.85, 0.66)))
    V = Point3f[]; C = RGBf[]
    nz = length(S.z)
    for i in 1:nz, j in 0:nphi-1
        phi = 2pi * j / nphi
        push!(V, Point3f(S.r[i] * cos(phi), S.r[i] * sin(phi), S.z[i] - S.zc))
        push!(C, cols[1 + (div(j, 6) % 2)])
    end
    push!(V, Point3f(0, 0, S.z[1] - S.zc)); push!(C, cols[1])
    push!(V, Point3f(0, 0, S.z[end] - S.zc)); push!(C, cols[2])
    idx(i, j) = (i - 1) * nphi + mod(j, nphi) + 1
    F = TriangleFace{Int}[]
    for i in 1:nz-1, j in 0:nphi-1
        push!(F, TriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(F, TriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    b, t = length(V) - 1, length(V)
    for j in 0:nphi-1
        push!(F, TriangleFace(b, idx(1, j + 1), idx(1, j)))
        push!(F, TriangleFace(t, idx(nz, j), idx(nz, j + 1)))
    end
    return V, F, C
end

top_world(V, fr, base) = [Point3f(base .+ fr.pos .+ qrot(fr.q) * v) for v in V]

function tops_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 8.0,
                   speed = 0.75, hour = 16.6, spot = (6.5f0, -15.0f0))
    zt, rt = tippe_profile(; cut = 1.6, stem_len = 1.0, stem_r = 0.22)
    rin = [z <= 1.6 * 0.02 ? min(x, 0.9 * r) : 0.0 for (z, x, r) in zip(zt, tippe_hollow(zt; wall = 0.15), rt)]
    tippe = TopShape(zt, rt, rin)
    cone = TopShape(cone_profile()...)
    simlen = seconds * speed + 0.1
    ft = spin_top(tippe; omega = 300.0, tilt = 0.15, seconds = simlen, air = 1e-10, mu = 0.35)
    fc = spin_top(cone; omega = 120.0, tilt = 0.25, seconds = simlen, air = 1e-10, mu = 0.35)
    Vt, Ftp, Ct = top_mesh(tippe; cols = (RGBf(0.10, 0.25, 0.65), RGBf(0.93, 0.85, 0.66)))
    Vc, Fcn, Cc = top_mesh(cone)
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot)
        P = Point3f(g[1], g[2], g[3] + 0.05f0)          # the board's top
        S[:P] = P
        board = GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Cylinder(P - Point3f(0, 0, 0.05f0), P, 0.3f0)))
        mesh!(gm.stage.scene, board; color = RGBf(0.55, 0.38, 0.22), name = :tops_board,
              material = NG.Hikari.Diffuse(color = (0.55, 0.38, 0.22), roughness = 0.4f0))
        S[:bt] = P + Point3f(0.05f0, 0, 0); S[:bc] = P - Point3f(0.05f0, 0, 0)
        wood(c) = NG.Hikari.Diffuse(color = (0.8, 0.6, 0.4), roughness = 0.3f0)
        S[:mt] = mesh!(gm.stage.scene, GeometryBasics.normal_mesh(GeometryBasics.Mesh(top_world(Vt, ft[1], S[:bt]), Ftp));
                       color = Ct, material = wood(1), name = :tops_tippe)
        S[:mc] = mesh!(gm.stage.scene, GeometryBasics.normal_mesh(GeometryBasics.Mesh(top_world(Vc, fc[1], S[:bc]), Fcn));
                       color = Cc, material = wood(2), name = :tops_cone)
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile) || startswith(string(p.attributes[:name][]), "paperpage_")) && (p.visible[] = false)
        end
        st = t * speed
        k(fr) = clamp(round(Int, st / (fr[2].t - fr[1].t)) + 1, 1, length(fr))
        S[:mt][1][] = GeometryBasics.normal_mesh(GeometryBasics.Mesh(top_world(Vt, ft[k(ft)], S[:bt]), Ftp))
        S[:mc][1][] = GeometryBasics.normal_mesh(GeometryBasics.Mesh(top_world(Vc, fc[k(fc)], S[:bc]), Fcn))
        P = S[:P]
        rig.mode = :fixed
        rig.eye = Point3f(P[1] + 0.03f0, P[2] - 0.26f0, P[3] + 0.07f0)
        rig.target = Point3f(P[1], P[2], P[3] + 0.02f0)
        return nothing
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(r, (; path, tippe_tilt_end = rad2deg(ft[end].tilt), cone_tilt_end = rad2deg(fc[end].tilt),
                     tippe_alpha = (0.02 - tippe.zc) / 0.02))
end
