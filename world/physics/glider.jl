# A paper glider that flies by its own folds (s147). The folded sheet is a set of flat panels; each step a vortex
# lattice (one horseshoe vortex per panel, bound leg on the quarter chord, control point on the three-quarter chord,
# trailing legs along the local air flow) gives the circulation that leaves no flow through any panel, and
# Kutta-Joukowski the force on each bound leg. The air velocity at each point includes the body's rotation, so pitch
# damping and the moment from bent back edges come out of the geometry. A rigid body with the mass and inertia of the
# folded sheet (layers counted) flies under that and gravity. Linear lift: no stall model yet.
# Looked at: VortexLattice.jl (byuflowlab, 453 users) does this and more; this is ~60 lines for a per-step solve in a
# game loop. TODO next session: check these forces against VortexLattice.jl on the same panels.
module Glider
using LinearAlgebra, StaticArrays
const V3 = SVector{3,Float64}
const RHO = 1.2
const RC = 0.01    # vortex core radius (m), ~ a third of a panel chord

struct Panel
    a::V3; b::V3        # bound leg (quarter chord), body frame
    c::V3               # control point (three-quarter chord)
    n::V3               # unit normal
    area::Float64
end

"Panel from its four corners: leading edge le1 -> le2, trailing edge te1 -> te2 (body frame, x forward, z up)."
function panel(le1, le2, te1, te2)
    a = le1 + 0.25 * (te1 - le1); b = le2 + 0.25 * (te2 - le2)
    c = 0.5 * ((le1 + 0.75 * (te1 - le1)) + (le2 + 0.75 * (te2 - le2)))
    n = cross(te2 - le1, le2 - te1); area = norm(n) / 2
    n = normalize(n); n[3] < 0 && (n = -n)
    Panel(a, b, c, n, area)
end

"Velocity at p from a straight vortex segment x1 -> x2 of unit strength (with a small core)."
@inline function seg(p, x1, x2)
    r1 = p - x1; r2 = p - x2; r0 = x2 - x1
    cr = cross(r1, r2)
    n1 = norm(r1); n2 = norm(r2)
    (n1 < 1e-9 || n2 < 1e-9) && return zero(V3)
    d = dot(cr, cr) + (RC^2) * dot(r0, r0)                  # smooth core (s147: a bare core let a trailing leg that
    cr * (dot(r0, r1 / n1 - r2 / n2) / (4pi * d))           # crossed a rear control point make energy from nothing)
end
"Unit horseshoe: from far downstream to a, a to b, b to far downstream (dir = the air's direction)."
@inline horseshoe(p, a, b, dir) = seg(p, a + 50dir, a) + seg(p, a, b) + seg(p, b, b + 50dir)

"""
    dart(; delta, ...) -> (panels, masses, quads)

A dart folded from one sheet: two swept wings with `dihedral`, their back `elevon` fraction bent by `delta` radians
(up positive). Masses: each wing panel one layer of paper; the keel (the folded layers under the root) as point masses.
"""
function dart(; delta = 0.0, span = 0.28, root = 0.26, tip = 0.10, ns = 5, nc = 4, dihedral = deg2rad(6),
              elevon = 0.25, gsm = 0.080, keel_mass = 0.0022, keel_x = (-0.03, -0.15))
    P = Panel[]; M = Tuple{V3,Float64}[]; Q = NTuple{4,V3}[]   # Q: the panels' corners, for drawing
    for side in (-1, 1)
        for i in 1:ns
            y1 = (i - 1) / ns * span / 2; y2 = i / ns * span / 2
            le(y) = -(root - tip) * (y / (span / 2)) * 0.9       # swept leading edge, nose at x = 0
            ch(y) = root - (root - tip) * (y / (span / 2))
            for j in 1:nc
                f1 = (j - 1) / nc; f2 = j / nc
                pt(y, f) = begin
                    x = le(y) - f * ch(y)
                    if f > 1 - elevon                            # behind the crease: bent by delta about it
                        xh = le(y) - (1 - elevon) * ch(y); d = x - xh
                        V3(xh + d * cos(delta), side * y * cos(dihedral), y * sin(dihedral) + (-d) * sin(delta))
                    else
                        V3(x, side * y * cos(dihedral), y * sin(dihedral))
                    end
                end
                p = side > 0 ? panel(pt(y1, f1), pt(y2, f1), pt(y1, f2), pt(y2, f2)) :
                               panel(pt(y2, f1), pt(y1, f1), pt(y2, f2), pt(y1, f2))
                push!(P, p); push!(M, ((p.a + p.b) / 2 * 0.5 + p.c * 0.5, p.area * gsm))
                push!(Q, (pt(y1, f1), pt(y2, f1), pt(y2, f2), pt(y1, f2)))
            end
        end
    end
    for x in range(keel_x..., length = 6)
        push!(M, (V3(x, 0, -0.008), keel_mass / 6))
    end
    P, M, Q
end

"Force and moment (about the origin of the panel frame) in body frame, for body velocity v and rate w (body frame)."
function aero(P, v, w; local_rot = false, induced = false)
    N = length(P)
    air(p) = -(v + cross(w, p))
    u = air(V3(0, 0, 0)); dir = normalize(u)
    A = zeros(N, N); rhs = zeros(N)
    for i in 1:N
        ci = P[i].c
        for j in 1:N
            A[i, j] = dot(horseshoe(ci, P[j].a, P[j].b, dir), P[i].n)
        end
        rhs[i] = -dot(air(ci), P[i].n)
    end
    G = A \ rhs
    F = zero(V3); Mo = zero(V3)
    for i in 1:N
        m = (P[i].a + P[i].b) / 2
        vl = local_rot ? air(m) : u                         # local_rot = false: the force leans with the CG's air only
        if induced                                          # s147: OFF by default, it tilted lift forward (steady
            for j in 1:N                                    # thrust at 8 deg AoA); induced drag is missing without it
                j == i && continue
                vl += G[j] * horseshoe(m, P[j].a, P[j].b, dir)
            end
        end
        f = RHO * G[i] * cross(vl, P[i].b - P[i].a)
        ua = air(P[i].c)
        f += 0.5 * RHO * 0.02 * P[i].area * norm(ua) * ua      # skin friction of paper
        F += f; Mo += cross(m, f)
    end
    F, Mo
end

quat_rot(q) = (w = q[1]; x = q[2]; y = q[3]; z = q[4];
    SMatrix{3,3}(1 - 2(y^2 + z^2), 2(x*y + w*z), 2(x*z - w*y), 2(x*y - w*z), 1 - 2(x^2 + z^2), 2(y*z + w*x),
                 2(x*z + w*y), 2(y*z - w*x), 1 - 2(x^2 + y^2)))
qmul(a, b) = SVector(a[1]*b[1] - a[2]*b[2] - a[3]*b[3] - a[4]*b[4], a[1]*b[2] + a[2]*b[1] + a[3]*b[4] - a[4]*b[3],
                     a[1]*b[3] - a[2]*b[4] + a[3]*b[1] + a[4]*b[2], a[1]*b[4] + a[2]*b[3] - a[3]*b[2] + a[4]*b[1])

"""
    fly(P, M; v0, pitch0, h0, seconds, dt) -> NamedTuple (t, pos, q) sampled every `every` steps

Rigid-body flight of the folded glider: thrown along +x at `v0` m/s, nose `pitch0` up, from height `h0`, until it
touches z = 0. World frame: x along the throw, z up.
"""
function fly(P, M; v0 = 4.0, pitch0 = deg2rad(2), h0 = 2.5, seconds = 6.0, dt = 5e-4, every = 20)
    mass = sum(last, M); cg = sum(p * m for (p, m) in M) / mass
    P = [Panel(p.a - cg, p.b - cg, p.c - cg, p.n, p.area) for p in P]
    J = zeros(3, 3)
    for (p, m) in M
        r = p - cg; J .+= m .* (dot(r, r) * Matrix(1.0LinearAlgebra.I, 3, 3) .- r * r')
    end
    J .+= 1e-7 * Matrix(1.0LinearAlgebra.I, 3, 3); Ji = inv(J)
    x = V3(0, 0, h0); q = SVector(cos(-pitch0 / 2), 0.0, sin(-pitch0 / 2), 0.0)   # nose up = negative rotation about y
    R = quat_rot(q); v = R * V3(v0, 0, 0); w = zero(V3)
    ts = Float64[]; xs = V3[]; qs = SVector{4,Float64}[]
    k = 0
    while k * dt < seconds
        R = quat_rot(q)
        Fb, Mb = aero(P, R' * v, w)
        v += dt * (R * Fb / mass + V3(0, 0, -9.81))
        w += dt * (Ji * (Mb - cross(w, J * w)))
        x += dt * v
        q = normalize(qmul(q, SVector(1.0, 0.5dt * w[1], 0.5dt * w[2], 0.5dt * w[3])))
        k % every == 0 && (push!(ts, k * dt); push!(xs, x); push!(qs, q))
        k += 1
        x[3] < 0.02 && break
    end
    push!(ts, k * dt); push!(xs, x); push!(qs, q)
    (; t = ts, pos = xs, q = qs, cg, mass)
end
end
