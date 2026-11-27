# Three logs in the sea (s145, project log-boat): each is put in upright with a 3 degree lean and rolls by the torque
# physics/hull.jl computes from its own mesh (buoyancy through the submerged volume's centre, weight through the log's
# centre, density 500, the waterline re-found each step so it always displaces its own weight). Wide and low stays
# upright; a square log turns onto its corner; a tall narrow one lies down.
#   submit_job(:clip; path, script = "movies/hulls.jl", call = "hulls_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "hull.jl"))

function box_vf(L, w, h)
    m = GeometryBasics.triangle_mesh(Rect3d(Point3d(-L/2, -w/2, -h/2), Vec3d(L, w, h)))
    v = [Tuple(Float64.(p)) for p in GeometryBasics.coordinates(m)]
    f = [Tuple(Int.(GeometryBasics.value.(t))) for t in GeometryBasics.faces(m)]
    return v, f
end
rotx(a) = [1 0 0; 0 cos(a) -sin(a); 0 sin(a) cos(a)]

"Roll angle and centre height (relative to the water) per frame for a log of section w x h."
function roll_track(L, w, h; density = 500.0, frames = 168, fps = 24, phi0 = deg2rad(3), damp = 1.2)
    v, f = box_vf(L, w, h)
    mass = density * L * w * h
    I = mass * (w^2 + h^2) / 12 * 1.3                        # +30% added mass of the water around it
    function float_at(phi)
        vr = [Tuple(rotx(phi) * collect(p)) for p in v]
        lo, hi = -(w + h), (w + h)
        for _ in 1:50
            mid = (lo + hi) / 2
            submerged(vr, f, mid)[1] * 1000 < mass ? (lo = mid) : (hi = mid)
        end
        hw = (lo + hi) / 2
        return hw, hydro_wrench(vr, f, hw, mass, (0.0, 0.0, 0.0))[2][1]
    end
    phi, om = phi0, 0.0
    out = Tuple{Float64,Float64}[]
    sub = 8; dt = 1 / (fps * sub)
    for k in 1:frames
        hw = 0.0
        for _ in 1:sub
            hw, T = float_at(phi)
            om += dt * (T / I - damp * om)                    # roll damping from the water (1/s)
            phi += dt * om
        end
        push!(out, (phi, -hw))                                 # the centre sits -hw above the water line
    end
    return out
end

function hulls_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24, seconds = 7.0,
                    hour = 16.5, spot = (-4f0, 18f0))
    nf = round(Int, seconds * fps)
    logs = [(1.2, 0.60, 0.25, RGBf(0.62, 0.45, 0.28)), (1.2, 0.36, 0.36, RGBf(0.55, 0.38, 0.22)), (1.2, 0.18, 0.60, RGBf(0.70, 0.55, 0.36))]
    tracks = [roll_track(L, w, h; frames = nf, fps) for (L, w, h, _) in logs]
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot)
        S[:beach] = g
        S[:plots] = map(enumerate(logs)) do (i, (L, wd, h, c))
            mesh!(gm.stage.scene, GeometryBasics.normal_mesh(Rect3f(Point3f(-L/2, -wd/2, -h/2), Vec3f(L, wd, h)));
                  color = c, name = Symbol("hull_log_", i),
                  material = NG.Hikari.Diffuse(color = (Float64(c.r), Float64(c.g), Float64(c.b)), roughness = 0.6f0))
        end
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 8 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 12f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        k = clamp(round(Int, t * fps) + 1, 1, nf)
        x, y = spot
        for (i, p) in enumerate(S[:plots])
            phi, zc = tracks[i][k]
            Makie.rotate!(p, Makie.qrotation(Vec3f(1, 0, 0), Float32(phi)))
            Makie.translate!(p, Vec3f(x + (i - 2) * 1.7f0, y + 4.5f0, Float32(zc)))
        end
        rig.mode = :fixed
        rig.eye = Point3f(x + 0.3f0, y + 0.6f0, S[:beach][3] + 1.1f0)
        rig.target = Point3f(x, y + 4.5f0, 0.0f0)
        return nothing
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(r, (; path, final_deg = [round(rad2deg(tr[end][1]), digits = 1) for tr in tracks]))
end
