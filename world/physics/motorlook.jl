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

# Wood with grain (s157): Blender-style wave bands along the board's length, distorted by noise, a little bump in the
# grain; `moving` uses the mesh's own coordinates so the grain turns with the part.
function mo_wood(; moving = false, base = (0.50, 0.32, 0.17))
    TN = NG.Hikari.TextureNodes
    p = moving ? TN.texture_coordinate().object : TN.xyz()
    q = TN.mapping(p; scale = (1, 1, 1))
    g = TN.wave(q; type = :bands, direction = :y, scale = 45, distortion = 9, detail = 4).fac
    col = TN.color_ramp(g, 0.0 => base, 0.55 => base .* 0.8, 1.0 => base .* 0.45)
    NG.Hikari.Principled(base_color = col, roughness = 0.55 + 0.25 * g,
                         normal = TN.bump(g; distance = 0.0006), coat_weight = 0.25, coat_roughness = 0.35)
end

# Iron-grey stone magnets (ferrite is a sintered iron oxide): dark, a dull metallic sheen, a grainy cast surface.
function mo_iron()
    TN = NG.Hikari.TextureNodes
    n = TN.noise(TN.xyz(); scale = 220, detail = 6).fac
    NG.Hikari.Principled(base_color = (0.30, 0.30, 0.31), metallic = 0.75, roughness = 0.42 + 0.25 * n,
                         normal = TN.bump(n; distance = 0.0004))
end

"""
    motor_plots!(sc, b, P; prefix = "mo_") -> (; A, rot, stones)

Draws build `b` (three times bench size, movies/motor.jl `film_build`) on a board whose top centre is `P`. `rot`:
the rotor's plots (turn and move them with `Makie.rotate!`/`translate!` about the axle centre `A`).
"""
function motor_plots!(sc, b, P; prefix = "mo_")
    nm(s) = Symbol(prefix, s)
    copper = NG.Hikari.Copper(roughness = 0.18f0)
    wood = mo_wood()
    h0 = 0.075f0
    A = P + Point3f(0, 0, h0)
    mesh!(sc, GeometryBasics.normal_mesh(Rect3f(P - Point3f(0.16f0, 0.12f0, 0.03f0), Vec3f(0.36f0, 0.24f0, 0.03f0)));
          color = RGBf(0.42, 0.27, 0.15), name = nm("board"), material = wood)
    stones = []
    for (k, m) in enumerate(b.magnets)
        y0 = Float32(m.pos[2]); Hs = 0.036f0; Rs = 0.036f0
        c0 = A + Point3f(0, y0, 0); c1 = c0 + Point3f(0, Hs, 0)
        push!(stones, mesh!(sc, GeometryBasics.normal_mesh(Cylinder(c0, c1, Rs)); color = RGBf(0.30, 0.30, 0.32), name = nm("stone$k"),
              material = mo_iron()))
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
    drum = b isa Motor.Drum
    turns = drum ? b.turns : [b.turn]
    if drum      # a wooden drum the coils are wound across (their ends cross just outside it)
        push!(rot, mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(-0.04f0, 0, 0), Point3f(0.04f0, 0, 0), 0.018f0));
                         color = RGBf(0.5, 0.33, 0.18), name = nm("rotor_wood"), material = mo_wood(moving = true, base = (0.62, 0.42, 0.22))))
    else
        push!(rot, mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(-0.045f0, -0.008f0, -0.024f0), Vec3f(0.09f0, 0.016f0, 0.048f0)));
                         color = RGBf(0.5, 0.33, 0.18), name = nm("rotor_wood"), material = wood))
    end
    nlay = drum ? 3 : 7
    for (k, t) in enumerate(turns), j in 1:nlay
        φ = drum ? 2pi * (k - 1) / length(turns) : 0.0
        nrm = Vec3f(0, cos(φ), sin(φ))                  # the coil's normal: its layers stack along it
        out(p) = (r = Vec3f(0, p[2], p[3]); norm(r) > 1f-6 ? normalize(r) : Vec3f(0))
        pts = [Point3f(p[1] * 1.02f0, p[2], p[3]) + (j - (nlay + 1) / 2) * 0.0024f0 * nrm + 0.0015f0 * out(p) for p in t]
        push!(rot, mesh!(sc, mtube(pts, 0.0016f0); color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("turn$(k)_$j")))
    end
    xr = xa + 0.018f0; rr = Float32(b.ring_r); half = (2pi / length(b.seg_c) - b.gap) / 2
    for (k, c) in enumerate(b.seg_c)
        arc = [Point3f(xr, rr * cos(c + u), rr * sin(c + u)) for u in range(-half, half; length = 16)]
        push!(rot, mesh!(sc, mtube(arc, 0.0035f0); color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("seg$k")))
    end
    if drum      # junction k (where coil k-1 ends and coil k starts) soldered to segment k
        for (k, c) in enumerate(b.seg_c)
            t = turns[k]; p = t[length(t) ÷ 4 + 1]
            push!(rot, mesh!(sc, mtube([Point3f(p[1] * 1.02f0, p[2], p[3]), Point3f(xr, rr * cos(c), rr * sin(c))], 0.0012f0);
                             color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("lead$k")))
        end
    else
        push!(rot, mesh!(sc, mtube([Point3f(0.045f0, 0, -0.028f0), Point3f(xr, rr, 0.0f0)], 0.0012f0);
                         color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("lead1")))
        push!(rot, mesh!(sc, mtube([Point3f(0.045f0, 0, 0.028f0), Point3f(xr, -rr, 0.0f0)], 0.0012f0);
                         color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("lead2")))
    end
    for (k, β) in enumerate(b.brushes)
        tip = A + Point3f(xr, rr * cos(β) * 1.25f0, rr * sin(β) * 1.25f0)
        base = Point3f(A[1] + xr + 0.05f0, A[2] + (k == 1 ? 0.03f0 : -0.03f0), P[3])
        mesh!(sc, mtube([base, Point3f(base[1], base[2], tip[3]), tip], 0.0016f0); color = RGBf(0.78, 0.42, 0.22),
              material = copper, name = nm("brush$k"))
        mesh!(sc, mtube([base, base + Point3f(0.04f0, (k == 1 ? 0.28f0 : 0.22f0), -0.02f0)], 0.0018f0); color = RGBf(0.78, 0.42, 0.22),
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
