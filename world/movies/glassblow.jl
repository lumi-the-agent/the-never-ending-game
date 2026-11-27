# The first glass bubble (s142, project glassblowing): physics/glassblow.jl blows a gather of soda-lime glass at
# 1000 C on a steel pipe: 600 Pa of breath for 5 s, the pipe turning half a turn a second for 3 s, then dipped 57
# degrees so gravity pulls it long. Each triangle cools by its own thickness (thin walls freeze first) and is drawn
# in one of four heat bands: three glowing (glass plus blackbody-ish emission), the coolest clear glass.
#   submit_job(:clip; path, script = "movies/glassblow.jl", call = "glassblow_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "glassblow.jl"))

gb_plan(t) = (t < 5.0 ? 600.0 : 0.0, clamp(t - 3.0, 0.0, 1.0) * 1.0, t < 3.0 ? 0.5 : 0.0)

const GB_BANDS = ((1223.0, Inf, (1.0, 0.55, 0.16), 3.0), (1123.0, 1223.0, (1.0, 0.40, 0.08), 1.6),
                  (1023.0, 1123.0, (1.0, 0.24, 0.04), 0.7), (-Inf, 1023.0, (0.0, 0.0, 0.0), 0.0))

function gb_world(fr, P)
    p, s = fr.pitch, fr.spin
    Rp = [cos(p) 0 sin(p); 0 1 0; -sin(p) 0 cos(p)]
    Rs = [1 0 0; 0 cos(s) -sin(s); 0 sin(s) cos(s)]
    W = Rp * Rs * fr.X
    [Point3f(P[1] + W[1, i], P[2] + W[2, i], P[3] + W[3, i]) for i in 1:size(W, 2)]
end

function gb_band_mesh(pts, F, T, lo, hi, P)
    fs = [TriangleFace(a, b, c) for (k, (a, b, c)) in enumerate(F) if lo <= T[k] < hi]
    isempty(fs) && return GeometryBasics.normal_mesh(GeometryBasics.Mesh([P, P + Point3f(0, 1f-5, 0), P + Point3f(0, 0, 1f-5)], [TriangleFace(1, 2, 3)]))
    return GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

function glassblow_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 8.0,
                        hour = 18.4, spot = (5.0f0, -17.4f0), level = 3)
    frames, g = blow(gb_plan; seconds, dt = 4e-3, T = 1273.0, r = 0.025, h = 0.008, level)
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        base = NG.ground(w.island, spot)
        P = Point3f(base[1], base[2], base[3] + 1.0f0)
        S[:P] = P
        pts = gb_world(frames[1], P)
        S[:bands] = map(enumerate(GB_BANDS)) do (bi, (lo, hi, col, st))
            mat = st > 0 ? NG.Hikari.Add(NG.Hikari.Glass(), NG.Hikari.Emission(color = col, strength = st)) : NG.Hikari.Glass()
            mesh!(gm.stage.scene, gb_band_mesh(pts, g.F, frames[1].T, lo, hi, P); color = st > 0 ? RGBf(col...) : RGBf(0.85, 0.92, 0.9),
                  material = mat, name = Symbol("glassblow_", bi))
        end
        pipe = GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Cylinder(P - Point3f(1.1f0, 0, 0), P + Point3f(0.004f0, 0, 0), 0.008f0)))
        S[:pipe] = mesh!(gm.stage.scene, pipe; color = RGBf(0.35, 0.35, 0.37), name = :glassblow_pipe,
                         material = NG.Hikari.Metallic(base_color = (0.55, 0.55, 0.57), roughness = 0.35))
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile) || startswith(string(p.attributes[:name][]), "paperpage_")) && (p.visible[] = false)
        end
        P = S[:P]
        fr = frames[clamp(round(Int, t / frames[1].t), 1, length(frames))]
        pts = gb_world(fr, P)
        for (b, (lo, hi, _, _)) in zip(S[:bands], GB_BANDS)
            b[1][] = gb_band_mesh(pts, g.F, fr.T, lo, hi, P)
        end
        p = fr.pitch      # the pipe dips with the bubble
        S[:pipe][1][] = GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Cylinder(P - Point3f(1.1f0 * cos(p), 0, -1.1f0 * sin(p)), P, 0.008f0)))
        c = sum(pts) / length(pts)
        rig.mode = :fixed
        rig.eye = Point3f(P[1] + 0.06f0, P[2] - 0.32f0, P[3] + 0.03f0)
        rig.target = Point3f(P[1] + 0.05f0, P[2], P[3] - 0.03f0)
        return nothing
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    last = frames[end]
    return merge(r, (; path, burst = g.burst, len_cm = 100 * (maximum(last.X[1, :]) - minimum(last.X[1, :])),
                     wall_mm = extrema(last.h) .* 1e3, T_C = extrema(last.T) .- 273.15))
end
