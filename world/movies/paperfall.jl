using NeverendingGame, Makie, Serialization
using GeometryBasics
using LinearAlgebra: norm, cross, normalize
const NG = NeverendingGame

"""
A sheet of paper falls on the island (s127). The fall is not animated: it is PrintSim's sheet solver on the GPU
(stretching, bending, friction, contact) with the air drag I added to PrintSim, run in physics/paperfall.jl and saved
as vertex positions (physics/paperfall-s127.jls). This film plays that recording back at the spot `at` on the island,
with the pitched plank the paper hit in the simulation drawn as a wooden board on two posts.
"""
function paperfall_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 30,
                        seconds = 6.0, hour = 16.5, at = (-6.0, 6.0), dist = 3.3, up = 1.25, slow = 1.0, look = 1.05,
                        rec = joinpath(NG.game_root(), "world", "physics", "paperfall-s127.jls"))
    R = deserialize(rec)
    frames, tris = R.frames, R.tris
    faces = [GLTriangleFace(t...) for t in tris]
    S = Dict{Symbol,Any}()
    function sheet_mesh(k, o)
        pts = [Point3f(p[1] + o[1], p[2] + o[2], p[3] + o[3]) for p in frames[clamp(k, 1, length(frames))]]
        nrm = zeros(Vec3f, length(pts))
        for f in faces
            a, b, c = pts[f[1]], pts[f[2]], pts[f[3]]
            n = cross(b - a, c - a)
            nrm[f[1]] += n; nrm[f[2]] += n; nrm[f[3]] += n
        end
        return GeometryBasics.Mesh(pts, faces; normal = [norm(n) > 0 ? normalize(n) : Vec3f(0, 0, 1) for n in nrm])
    end
    shot = function (g, rig, t)
        is = g.world.island
        if !haskey(S, :o)
            h = NG.terrain_height(is, at[1], at[2])
            S[:o] = Point3f(at[1], at[2], h)
            sc = g.stage.scene
            o = S[:o]
            rc, rp, rh = R.roof
            u, n = Vec3f(cos(rp), 0, sin(rp)), Vec3f(-sin(rp), 0, cos(rp))
            # the plank exactly where the simulation had it, and two posts under its low and high ends
            corners = [Point3f(o + Vec3f(rc...) + su * rh[1] * u + sv * rh[2] * Vec3f(0, 1, 0) + sn * rh[3] * n)
                       for sn in (-1, 1) for sv in (-1, 1) for su in (-1, 1)]
            plank = GeometryBasics.mesh(Rect3f(Point3f(-1), Vec3f(2)); pointtype = Point3f, facetype = GLTriangleFace)
            P = [Point3f(o + Vec3f(rc...) + q[1] * rh[1] * u + q[2] * rh[2] * Vec3f(0, 1, 0) + q[3] * rh[3] * n)
                 for q in GeometryBasics.coordinates(plank)]
            wood = NG.Hikari.CoatedDiffuse(reflectance = (0.55, 0.35, 0.18), roughness = 0.35)
            mesh!(sc, GeometryBasics.Mesh(P, GeometryBasics.faces(plank)); color = RGBf(0.55, 0.35, 0.18), material = wood)
            for su in (-0.8f0, 0.8f0)
                top = o + Vec3f(rc...) + su * rh[1] * u - rh[3] * n
                mesh!(sc, Rect3f(Point3f(top[1] - 0.03, -0.03 + o[2], o[3] - 0.05), Vec3f(0.06, 0.06, top[3] - o[3] + 0.05));
                      color = RGBf(0.45, 0.28, 0.14), material = wood)
            end
            paper = NG.Hikari.DiffuseTransmission(reflectance = (0.82, 0.8, 0.74), transmittance = (0.45, 0.43, 0.38))
            S[:paper] = mesh!(sc, sheet_mesh(1, o); color = RGBf(0.95, 0.94, 0.9), material = paper)
            # friends off the set, so nobody walks through the lens or the plank
            for c in g.world.creatures
                hypot(c.pos[1] - at[1], c.pos[2] - at[2]) < 5 || continue
                c.pos = NG.ground(is, (at[1] + 6f0, at[2] + 6f0))
            end
        end
        o = S[:o]
        Makie.update!(S[:paper]; arg1 = sheet_mesh(floor(Int, t * R.fps / slow) + 1, o))   # `slow` x slow motion; holds the last frame
        eye = Point3f(o[1] - 0.2f0, o[2] - dist, o[3] + up)
        tg = Point3f(o[1] - 0.15f0, o[2], o[3] + Float32(look))
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.1
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, shot)
    return (path = path, frames = length(frames))
end
