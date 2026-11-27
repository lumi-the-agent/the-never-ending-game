# General magnetostatics for the island (s147, todo #701, the human's ask: real fields that push any parts, any
# materials). A permanent magnet is ANY closed triangle mesh with a magnetisation M (A/m): its field is the field of
# its equivalent surface magnetic charge sigma = M . n (the "charge model", Furlani, Permanent Magnet and
# Electromechanical Devices, ch. 2), integrated over every face with a subdivided quadrature. That gives
#   H(p) anywhere outside the material, B = mu0 H there,
#   the force and torque on another magnet (mu0 q H on each of its charges),
#   the force and torque on any current path (I dl x B, segment by segment).
# Nothing in here knows a shape: a disc, a bar, a beach stone mesh all go through the same code. Materials come from
# MATERIALS, not from the caller.
# Looked first (rule 6): Magnetostatics.jl (Biot-Savart solver, analytic current loops: no magnet meshes, no forces
# between bodies), MicroMagnetic.jl (micromagnetics at nm scale), FastMultipole.jl (for when this needs to scale).
# Checked: tests at the end of this file (axis field of a cylinder vs the closed form, the far force vs two dipoles).
# Still missing: soft iron (induced magnetisation: a volume solve), the GPU kernel (Mantle), coupling to PrintSim bodies.
module EM
using LinearAlgebra

const MU0 = 4pi * 1e-7
const V3 = NTuple{3,Float64}

# what the island's materials are, magnetically and electrically (SI)
const MATERIALS = Dict(
    :ndfeb    => (; Br = 1.2,  density = 7500.0, resistivity = 1.4e-6, mu_r = 1.05),   # neodymium magnet
    :ferrite  => (; Br = 0.38, density = 4900.0, resistivity = 1e2,    mu_r = 1.1),    # ceramic magnet
    :magnetite => (; Br = 0.06, density = 5170.0, resistivity = 1e-2,  mu_r = 5.0),    # a lodestone from the beach (weak, natural)
    :copper   => (; Br = 0.0,  density = 8960.0, resistivity = 1.68e-8, mu_r = 1.0),
    :iron     => (; Br = 0.0,  density = 7870.0, resistivity = 9.7e-8, mu_r = 5000.0),
    :wood     => (; Br = 0.0,  density = 600.0,  resistivity = 1e14,   mu_r = 1.0),
)

"""A magnetised body: its charges (quadrature points with magnetic charge q, A m) in its own frame, and a pose."""
mutable struct Magnet
    pts::Vector{V3}           # body frame
    q::Vector{Float64}
    pos::V3                   # world position of the body origin
    R::Matrix{Float64}        # body -> world rotation
end

# subdivide triangle (a, b, c) into n^2 sub-triangles and give each centroid with its area
function tri_quad(a, b, c, n)
    a, b, c = collect(a), collect(b), collect(c)
    P(i, j) = a + (b - a) * (i / n) + (c - a) * (j / n)
    out = Tuple{V3,Float64}[]
    for i in 0:n-1, j in 0:n-1-i
        for (p1, p2, p3) in ((P(i, j), P(i + 1, j), P(i, j + 1)),
                             (i + j < n - 1 ? (P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)) : (nothing, nothing, nothing)))
            p1 === nothing && continue
            ar = norm(cross(p2 - p1, p3 - p1)) / 2
            push!(out, (Tuple((p1 + p2 + p3) / 3), ar))
        end
    end
    out
end

"""
    magnet(verts, faces, M; n = 6, pos = (0,0,0), R = I)

A magnet from a closed, outward-wound triangle mesh (`faces` as index triples) with uniform magnetisation `M` (A/m,
body frame; Br / mu0 along the axis for a permanent magnet).
"""
function magnet(verts, faces, M; n = 6, pos = (0.0, 0.0, 0.0), R = Matrix(1.0I, 3, 3))
    pts = V3[]; q = Float64[]
    Mv = collect(Float64, M)
    for f in faces
        a, b, c = (collect(Float64, verts[i]) for i in f)
        nrm = normalize(cross(b - a, c - a))
        s = dot(Mv, nrm)
        abs(s) < 1e-12 && continue
        for (p, ar) in tri_quad(a, b, c, n)
            push!(pts, p); push!(q, s * ar)
        end
    end
    Magnet(pts, q, Tuple(Float64.(pos)), Matrix{Float64}(R))
end

world(m::Magnet, k) = collect(m.pos) + m.R * collect(m.pts[k])

"""H (A/m) at world point p from magnet m (valid outside the material, and away from its surface by more than a quadrature cell)."""
function H(m::Magnet, p)
    # no allocation per charge (s154: the motor's coupling table took 10 s with `world(m, k)` vectors)
    R = m.R; o = m.pos
    px = Float64(p[1]); py = Float64(p[2]); pz = Float64(p[3])
    hx = 0.0; hy = 0.0; hz = 0.0
    @inbounds for k in eachindex(m.q)
        a = m.pts[k]
        dx = px - (o[1] + R[1, 1] * a[1] + R[1, 2] * a[2] + R[1, 3] * a[3])
        dy = py - (o[2] + R[2, 1] * a[1] + R[2, 2] * a[2] + R[2, 3] * a[3])
        dz = pz - (o[3] + R[3, 1] * a[1] + R[3, 2] * a[2] + R[3, 3] * a[3])
        r2 = dx * dx + dy * dy + dz * dz
        c = m.q[k] / (4pi * r2 * sqrt(r2))
        hx += c * dx; hy += c * dy; hz += c * dz
    end
    [hx, hy, hz]
end
B(ms::AbstractVector{Magnet}, p) = MU0 .* sum(H(m, p) for m in ms)
B(m::Magnet, p) = MU0 .* H(m, p)

"""Force (N) and torque (N m, about `about`) that the field of `src` puts on magnet `dst`."""
function force(src::Magnet, dst::Magnet; about = dst.pos)
    F = zeros(3); T = zeros(3); o = collect(Float64, about)
    for k in eachindex(dst.q)
        p = world(dst, k)
        f = MU0 * dst.q[k] .* H(src, p)
        F .+= f; T .+= cross(p - o, f)
    end
    F, T
end

"""Force and torque of field `Bf(p)` on a current `I` (A) along the polyline `path` (world points), dF = I dl x B."""
function force(Bf, path::AbstractVector, I; about = (0.0, 0.0, 0.0))
    F = zeros(3); T = zeros(3); o = collect(Float64, about)
    for k in 1:length(path)-1
        a = collect(Float64, path[k]); b = collect(Float64, path[k+1])
        mid = (a + b) / 2
        f = I .* cross(b - a, Bf(mid))
        F .+= f; T .+= cross(mid - o, f)
    end
    F, T
end

# ---- meshes for tests (any closed mesh works) ----
function cylinder_mesh(Rr, Hh; n = 48)
    v = V3[(0.0, 0.0, 0.0), (0.0, 0.0, Hh)]
    for i in 0:n-1
        t = 2pi * i / n
        push!(v, (Rr * cos(t), Rr * sin(t), 0.0)); push!(v, (Rr * cos(t), Rr * sin(t), Hh))
    end
    f = NTuple{3,Int}[]
    for i in 0:n-1
        j = mod(i + 1, n)
        b0, t0, b1, t1 = 3 + 2i, 4 + 2i, 3 + 2j, 4 + 2j
        push!(f, (1, b1, b0)); push!(f, (2, t0, t1))           # bottom (normal -z), top (+z)
        push!(f, (b0, b1, t1)); push!(f, (b0, t1, t0))         # side (outward)
    end
    v, f
end

# closed form: on the axis of a cylinder magnet spanning z 0..L, radius R, remanence Br
axis_Bz(z, R, L, Br) = Br / 2 * ((z) / sqrt(z^2 + R^2) - (z - L) / sqrt((z - L)^2 + R^2))

function selftest()
    R, L, Br = 0.0125, 0.006, MATERIALS[:ndfeb].Br
    v, f = cylinder_mesh(R, L; n = 64)
    m = magnet(v, f, (0.0, 0.0, Br / MU0); n = 8)
    axis = [(z, B(m, (0.0, 0.0, z))[3], axis_Bz(z, R, L, Br)) for z in (0.008, 0.012, 0.02, 0.04)]
    # two coaxial discs far apart attract like two dipoles: F = 3 mu0 m1 m2 / (2 pi d^4)
    mom = Br / MU0 * pi * R^2 * L
    far = map((0.08, 0.15)) do d
        m2 = magnet(v, f, (0.0, 0.0, Br / MU0); n = 6, pos = (0.0, 0.0, d))
        F, _ = force(m, m2)
        (d, F[3], -3MU0 * mom^2 / (2pi * d^4))
    end
    (; axis, far)
end

end
