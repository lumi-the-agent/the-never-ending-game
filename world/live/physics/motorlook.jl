# How a Motor.Build looks (s154): board, stones on blocks, axle in forked sticks, the wound rotor, the split ring and
# the brushes. Shared by movies/motor.jl and plugins/motorbench.jl. Needs Makie, GeometryBasics, NG and Motor loaded.

"A tube mesh along a polyline (radius rad, nring sides)."
function mtube(pts, rad; nring = 10)
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

"""
    motor_plots!(sc, b, P; prefix = "mo_") -> (; A, rot, stones)

Draws build `b` (three times bench size, movies/motor.jl `film_build`) on a board whose top centre is `P`. `rot`:
the rotor's plots (turn and move them with `Makie.rotate!`/`translate!` about the axle centre `A`).
"""
function motor_plots!(sc, b, P; prefix = "mo_")
    nm(s) = Symbol(prefix, s)
    copper = NG.Hikari.Copper(roughness = 0.18f0)
    wood = NG.Hikari.Diffuse(color = (0.42, 0.27, 0.15), roughness = 0.8f0)
    h0 = 0.075f0
    A = P + Point3f(0, 0, h0)
    mesh!(sc, GeometryBasics.normal_mesh(Rect3f(P - Point3f(0.16f0, 0.12f0, 0.03f0), Vec3f(0.36f0, 0.24f0, 0.03f0)));
          color = RGBf(0.42, 0.27, 0.15), name = nm("board"), material = wood)
    stones = []
    for (k, m) in enumerate(b.magnets)
        y0 = Float32(m.pos[2]); Hs = 0.036f0; Rs = 0.036f0
        c0 = A + Point3f(0, y0, 0); c1 = c0 + Point3f(0, Hs, 0)
        push!(stones, mesh!(sc, GeometryBasics.normal_mesh(Cylinder(c0, c1, Rs)); color = RGBf(0.16, 0.16, 0.17), name = nm("stone$k"),
              material = NG.Hikari.Diffuse(color = (0.16, 0.16, 0.17), roughness = 0.55f0)))
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(A[1] - 0.03f0, c0[2], P[3]), Vec3f(0.06f0, Hs, h0 - Rs)));
              color = RGBf(0.42, 0.27, 0.15), name = nm("block$k"), material = wood)
    end
    xa = 0.075f0
    mesh!(sc, GeometryBasics.normal_mesh(Cylinder(A - Point3f(xa + 0.01f0, 0, 0), A + Point3f(xa + 0.04f0, 0, 0), 0.0045f0));
          color = RGBf(0.6, 0.6, 0.62), name = nm("axle"), material = NG.Hikari.Aluminum(roughness = 0.3f0))
    for (k, x) in enumerate((-xa, xa + 0.03f0))
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(A[1] + x, A[2], P[3]), Point3f(A[1] + x, A[2], A[3] + 0.006f0), 0.007f0));
              color = RGBf(0.42, 0.27, 0.15), name = nm("fork$k"), material = wood)
    end
    rot = []
    push!(rot, mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(-0.045f0, -0.008f0, -0.024f0), Vec3f(0.09f0, 0.016f0, 0.048f0)));
                     color = RGBf(0.5, 0.33, 0.18), name = nm("rotor_wood"), material = wood))
    for j in 1:7
        dy = (j - 4) * 0.0022f0
        pts = [Point3f(p[1] * 1.02f0, p[2] + dy, p[3] + sign(p[3]) * 0.0015f0) for p in b.turn]
        push!(rot, mesh!(sc, mtube(pts, 0.0016f0); color = RGBf(0.85, 0.45, 0.3), material = copper, name = nm("turn$j")))
    end
    xr = xa + 0.018f0; rr = Float32(b.ring_r); half = (pi - b.gap) / 2
    for (k, c) in enumerate(b.seg_c)
        arc = [Point3f(xr, rr * cos(c + u), rr * sin(c + u)) for u in range(-half, half; length = 16)]
        push!(rot, mesh!(sc, mtube(arc, 0.0035f0); color = RGBf(0.85, 0.45, 0.3), material = copper, name = nm("seg$k")))
    end
    push!(rot, mesh!(sc, mtube([Point3f(0.045f0, 0, -0.028f0), Point3f(xr, rr, 0.0f0)], 0.0012f0);
                     color = RGBf(0.85, 0.45, 0.3), material = copper, name = nm("lead1")))
    push!(rot, mesh!(sc, mtube([Point3f(0.045f0, 0, 0.028f0), Point3f(xr, -rr, 0.0f0)], 0.0012f0);
                     color = RGBf(0.85, 0.45, 0.3), material = copper, name = nm("lead2")))
    for (k, β) in enumerate(b.brushes)
        tip = A + Point3f(xr, rr * cos(β) * 1.25f0, rr * sin(β) * 1.25f0)
        base = Point3f(A[1] + xr + 0.05f0, A[2] + (k == 1 ? 0.03f0 : -0.03f0), P[3])
        mesh!(sc, mtube([base, Point3f(base[1], base[2], tip[3]), tip], 0.0016f0); color = RGBf(0.85, 0.45, 0.3),
              material = copper, name = nm("brush$k"))
        mesh!(sc, mtube([base, base + Point3f(0.04f0, (k == 1 ? 0.28f0 : 0.22f0), -0.02f0)], 0.0018f0); color = RGBf(0.85, 0.45, 0.3),
              material = copper, name = nm("wire$k"))
    end
    for m in rot
        Makie.translate!(m, A)
    end
    return (; A, rot, stones)
end

"Turn the rotor's plots to angle θ about the axle centre A."
function motor_pose!(rot, A, θ)
    q = Makie.qrotation(Vec3f(1, 0, 0), Float32(θ))
    for m in rot
        Makie.rotate!(m, q); Makie.translate!(m, A)
    end
end
