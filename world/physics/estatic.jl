# Electrostatics on the island (s153, project lightning): grounded conductors under a storm's field. The first step
# of "Lightning makes a lodestone": where the field is strongest is where a leader steps and where a strike attaches,
# and that depends on what the player has put up. Boundary elements: each conductor surface is cut into flat panels
# with a constant surface charge; the panels' charges are solved so every conductor sits at its potential (0: earthed)
# in the storm's background potential phi0 = E0 z (E0 > 0: the field points down, E = -grad phi). The sea
# and the wet ground are a conducting plane at z = 0, done by images (each charge has a mirror charge -q at -z).
using LinearAlgebra

const EPS0 = 8.8541878128e-12
const KE = 1 / (4pi * EPS0)

struct Panels
    c::Vector{NTuple{3,Float64}}   # centroids
    a::Vector{Float64}             # areas
end

"Flat panels from triangle `faces` (index triples) over `verts` (x, y, z)."
function panels(verts, faces)
    c = NTuple{3,Float64}[]; a = Float64[]
    for f in faces
        p1, p2, p3 = (collect(Float64, verts[f[k]]) for k in 1:3)
        A = 0.5 * norm(cross(p2 - p1, p3 - p1))
        A > 0 || continue
        push!(c, Tuple((p1 + p2 + p3) / 3)); push!(a, A)
    end
    return Panels(c, a)
end

"""
    solve_charges(ps; E0, V = 0) -> q (C per panel)

Charges on the panels that hold the conductor at potential `V` in the background field `E0` (V/m, pointing down)
over an earthed plane at z = 0. Collocation at the centroids; a panel's own potential is that of a disc of its area.
"""
function solve_charges(ps::Panels; E0, V = 0.0)
    n = length(ps.a)
    P = zeros(n, n)
    for j in 1:n, i in 1:n
        cj = ps.c[j]; ci = ps.c[i]
        img = (cj[1], cj[2], -cj[3])
        if i == j
            r = sqrt(ps.a[j] / pi)                       # disc of the same area: phi_centre = sigma r / (2 eps0)
            P[i, j] = 1 / (2pi * EPS0 * r) / 1           # per coulomb: (q / (pi r^2)) * r / (2 eps0)
        else
            P[i, j] = KE / norm(ci .- cj)
        end
        P[i, j] -= KE / norm(ci .- img)                  # the mirror charge in the ground
    end
    rhs = [V - E0 * c[3] for c in ps.c]                  # V - phi0, phi0 = E0 z
    return P \ rhs
end

"The electric field (V/m) at point `p`: the storm's background plus every panel charge and its mirror."
function efield(ps::Panels, q, p; E0)
    E = [0.0, 0.0, -E0]
    for j in eachindex(q)
        cj = ps.c[j]
        for (s, src) in ((1.0, cj), (-1.0, (cj[1], cj[2], -cj[3])))
            d = collect(p) .- collect(src)
            E .+= s * KE * q[j] .* d ./ norm(d)^3
        end
    end
    return E
end

"Selftest: a lone earthed rod (a hemispherically capped stick) on flat ground. Returns the field just above its tip
over the storm's own field (the enhancement), for a few heights and radii."
function estatic_selftest(; E0 = 20e3)
    out = []
    for (h, r) in ((1.0, 0.01), (2.0, 0.01), (2.0, 0.05))
        verts = NTuple{3,Float64}[]; faces = NTuple{3,Int}[]
        nθ = 12; nz = 40
        zs = range(0.0, h; length = nz)
        for z in zs, k in 0:nθ-1
            push!(verts, (r * cos(2pi * k / nθ), r * sin(2pi * k / nθ), z))
        end
        push!(verts, (0.0, 0.0, h + r))                    # the tip
        id(i, k) = (i - 1) * nθ + mod(k, nθ) + 1
        for i in 1:nz-1, k in 0:nθ-1
            push!(faces, (id(i, k), id(i, k + 1), id(i + 1, k + 1)), (id(i, k), id(i + 1, k + 1), id(i + 1, k)))
        end
        tip = length(verts)
        for k in 0:nθ-1
            push!(faces, (id(nz, k), id(nz, k + 1), tip))
        end
        ps = panels(verts, faces)
        q = solve_charges(ps; E0)
        Etip = norm(efield(ps, q, (0.0, 0.0, h + r + 2r); E0))
        push!(out, (; h, r, enhancement = Etip / E0, charge_nC = sum(q) * 1e9))
    end
    return out
end
