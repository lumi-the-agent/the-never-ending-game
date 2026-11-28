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

# Magnet stone (s158): near-black iron oxide rock, a dull sheen where it is smooth, pitted and grainy (two noises).
function mo_stone()
    TN = NG.Hikari.TextureNodes
    big = TN.noise(TN.xyz(); scale = 60, detail = 4).fac
    fine = TN.noise(TN.xyz(); scale = 400, detail = 3).fac
    col = TN.color_ramp(big, 0.0 => (0.10, 0.10, 0.11), 0.5 => (0.20, 0.19, 0.19), 1.0 => (0.33, 0.30, 0.28))
    NG.Hikari.Principled(base_color = col, metallic = 0.35, roughness = 0.45 + 0.4 * fine,
                         normal = TN.bump(0.7 * big + 0.3 * fine; distance = 0.0015))
end

"The stones of `b` (s = 3 film size) as world-space meshes about axle centre `A`: [(mesh, sh)], the same triangles em.jl magnetises."
function mo_stones(b, A)
    y = maximum(m.pos[2] for m in b.magnets)          # the + stone's near face: gap / 2
    map(Motor.stator_shapes(; R = 0.036, H = 0.036, gap = 2y)) do sh
        P = [A + Point3f((collect(sh.pos) .+ sh.Rm * collect(p))...) for p in sh.v]
        (GeometryBasics.normal_mesh(GeometryBasics.Mesh(P, [GLTriangleFace(f...) for f in sh.f])), sh)
    end
end

"Red ochre round the north end of a stone (side faces within the last 22% of its length), lifted 0.6 mm off it."
function mo_paint(sh, A, north_at_H::Bool; frac = 0.22)
    H = maximum(p[3] for p in sh.v) - minimum(p[3] for p in sh.v); z0 = minimum(p[3] for p in sh.v)
    keep(i) = (z = (sh.v[i][3] - z0) / H; north_at_H ? z > 1 - frac : z < frac)
    fs = [f for f in sh.f if all(keep, f) && !(1 in f) && !(2 in f)]      # a band round the sides, not the end face
    c = sum(collect.(sh.v)) / length(sh.v)
    P = [A + Point3f((collect(sh.pos) .+ sh.Rm * (collect(p) .+ 0.0006 .* normalize(collect(p) .- c)))...) for p in sh.v]
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(P, [GLTriangleFace(f...) for f in fs]))
end

# Copper as wire made on the island is (s158): a thin cuprite skin over the metal, so a deeper orange than clean
# copper's salmon F0 (0.95, 0.64, 0.54), which the raster drew pink-silver; a little rougher where it was handled.
function mo_copper()
    TN = NG.Hikari.TextureNodes
    n = TN.noise(TN.xyz(); scale = 300, detail = 3).fac
    NG.Hikari.Principled(base_color = (0.86, 0.46, 0.24), metallic = 1.0, roughness = 0.2 + 0.15 * n)
end

"Chaikin corner cutting on a closed polyline (look only: wound wire bends round, it doesn't kink)."
function mo_round(pts; times = 2)
    P = [Point3f(p...) for p in pts]
    first(P) ≈ last(P) && (P = P[1:end-1])
    for _ in 1:times
        Q = Point3f[]
        for i in eachindex(P)
            a, b = P[i], P[mod1(i + 1, length(P))]
            push!(Q, 0.75f0 * a + 0.25f0 * b); push!(Q, 0.25f0 * a + 0.75f0 * b)
        end
        P = Q
    end
    push!(P, P[1]); P
end

"""
A wound bundle along a closed path: a core plus `ns` strands of radius `rs` lying round it (frames carried along the
path by parallel transport, so the strands don't twist at the corners). Returns one mesh.
"""
function mo_bundle(path, R; ns = 11, rs = 0.0009f0)
    P = path; n = length(P)
    T = [normalize(P[mod1(i + 1, n)] - P[mod1(i - 1, n)]) for i in 1:n]
    a = abs(T[1][3]) < 0.9 ? Vec3f(0, 0, 1) : Vec3f(1, 0, 0)
    U = [normalize(cross(T[1], a))]
    for i in 2:n
        u = U[end] - dot(U[end], T[i]) * T[i]; push!(U, normalize(u))
    end
    meshes = [mtube(P, R - rs)]
    for k in 0:ns-1
        ph = 2pi * k / ns
        push!(meshes, mtube([P[i] + (R - rs) * (cos(ph) * U[i] + sin(ph) * cross(T[i], U[i])) for i in 1:n], rs; nring = 7))
    end
    merge(meshes)
end

"""
    motor_plots!(sc, b, P; prefix = "mo_") -> (; A, rot, stones)

Draws build `b` (three times bench size, movies/motor.jl `film_build`) on a board whose top centre is `P`. `rot`:
the rotor's plots (turn and move them with `Makie.rotate!`/`translate!` about the axle centre `A`).
"""
function motor_plots!(sc, b, P; prefix = "mo_")
    nm(s) = Symbol(prefix, s)
    copper = mo_copper()
    wood = mo_wood()
    h0 = 0.075f0
    A = P + Point3f(0, 0, h0)
    mesh!(sc, GeometryBasics.normal_mesh(Rect3f(P - Point3f(0.16f0, 0.12f0, 0.03f0), Vec3f(0.36f0, 0.24f0, 0.03f0)));
          color = RGBf(0.42, 0.27, 0.15), name = nm("board"), material = wood)
    stones = []
    for (k, (msh, sh)) in enumerate(mo_stones(b, A))
        push!(stones, mesh!(sc, msh; color = RGBf(0.2, 0.2, 0.2), name = nm("stone$k"), material = mo_stone()))
        y0 = Float32(sh.pos[2]); Hs = 0.036f0; Rs = 0.036f0
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(A[1] - 0.03f0, A[2] + y0, P[3]), Vec3f(0.06f0, Hs, h0 - 0.7f0 * Rs)));
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
        push!(rot, mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(-0.043f0, 0, 0), Point3f(0.043f0, 0, 0), 0.0225f0));
                         color = RGBf(0.5, 0.33, 0.18), name = nm("rotor_wood"), material = mo_wood(moving = true, base = (0.62, 0.42, 0.22))))
    else
        push!(rot, mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(-0.045f0, -0.008f0, -0.024f0), Vec3f(0.09f0, 0.016f0, 0.048f0)));
                         color = RGBf(0.5, 0.33, 0.18), name = nm("rotor_wood"), material = wood))
    end
    if drum      # each coil one wound bundle (N turns of rw wire, packed 75%), its end bends round the axle
        rb = Float32(sqrt(b.N * b.rw^2 / 0.75))
        for (k, t) in enumerate(turns)
            φ = 2pi * (k - 1) / length(turns)
            pts = map(t) do p
                q = Point3f(p...); r = sqrt(q[2]^2 + q[3]^2)
                r < 0.009f0 ? q + (0.009f0 - r) * Vec3f(0, cos(φ), sin(φ)) : q   # off the end's line, round the axle
            end
            push!(rot, mesh!(sc, mo_bundle(mo_round(pts), rb); color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("coil$k")))
        end
    else
        for (k, t) in enumerate(turns), j in 1:7
            nrm = Vec3f(0, 1, 0)
            out(p) = (r = Vec3f(0, p[2], p[3]); norm(r) > 1f-6 ? normalize(r) : Vec3f(0))
            pts = [Point3f(p[1] * 1.02f0, p[2], p[3]) + (j - 4) * 0.0024f0 * nrm + 0.0015f0 * out(p) for p in t]
            push!(rot, mesh!(sc, mtube(pts, 0.0016f0); color = RGBf(0.78, 0.42, 0.22), material = copper, name = nm("turn$(k)_$j")))
        end
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
