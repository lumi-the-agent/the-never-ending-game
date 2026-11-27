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

"The panels' potential matrix (per coulomb, with the ground's mirror charges): factorise it once per scene."
function panel_matrix(ps::Panels)
    n = length(ps.a)
    P = zeros(n, n)
    for j in 1:n, i in 1:n
        cj = ps.c[j]; ci = ps.c[i]
        P[i, j] = i == j ? 1 / (2pi * EPS0 * sqrt(ps.a[j] / pi)) : KE / norm(ci .- cj)
        P[i, j] -= KE / norm(ci .- (cj[1], cj[2], -cj[3]))
    end
    return P
end

# ---- The stepped leader (s154). The channel carries a line charge lam (C/m) of the cloud's sign, spread over a corona
# sheath of radius `sheath` (real leaders: metres). Its potential and field come from uniformly charged segments,
# each with its mirror (-lam) in the ground. The rods take whatever charge holds them at 0 V in the storm's field
# AND the leader's: so the channel pulls charge up the rods, and that charge pulls the channel toward them.

"Potential and field at `p` of a segment `a`-`b` with line charge `lam`, smoothed over the sheath radius."
function seg_phiE(p, a, b, lam, sheath)
    ab = b .- a; L = norm(ab); u = ab ./ L
    ap = p .- a; t = dot(ap, u)
    perp = ap .- t .* u; ρ = norm(perp)
    ρe2 = ρ^2 + sheath^2; ρe = sqrt(ρe2)
    r1 = sqrt(t^2 + ρe2); r2 = sqrt((L - t)^2 + ρe2)
    φ = KE * lam * (asinh((L - t) / ρe) + asinh(t / ρe))
    Epar = KE * lam * (1 / r2 - 1 / r1)
    Eρ = KE * lam / ρe2 * ((L - t) / r2 + t / r1)
    E = Epar .* u .+ (ρ > 1e-12 ? Eρ .* perp ./ ρ : (0.0, 0.0, 0.0))
    return φ, E
end

mirror(p) = (p[1], p[2], -p[3])

"Potential and field of the whole channel `pts` (and its mirror) at `p`."
function leader_phiE(pts, p, lam, sheath)
    φ = 0.0; E = (0.0, 0.0, 0.0)
    for k in 1:length(pts)-1
        φ1, E1 = seg_phiE(p, pts[k], pts[k+1], lam, sheath)
        φ2, E2 = seg_phiE(p, mirror(pts[k]), mirror(pts[k+1]), -lam, sheath)
        φ += φ1 + φ2; E = E .+ E1 .+ E2
    end
    return φ, E
end

"Potential and field of the panel charges `q` (with mirrors) at `p`."
function panels_phiE(ps::Panels, q, p)
    φ = 0.0; E = (0.0, 0.0, 0.0)
    for j in eachindex(q)
        for (s, src) in ((1.0, ps.c[j]), (-1.0, mirror(ps.c[j])))
            d = p .- src; r = norm(d)
            φ += s * KE * q[j] / r
            E = E .+ (s * KE * q[j] / r^3) .* d
        end
    end
    return φ, E
end

"Fibonacci directions on the unit sphere."
sphere_dirs(n) = [(sqrt(1 - z^2) * cos(2.399963 * k), sqrt(1 - z^2) * sin(2.399963 * k), z)
                  for (k, z) in enumerate(range(1 - 1 / n, -1 + 1 / n; length = n))]

"""
    grow_leader(ps, F; E0, start, lam = 1e-3, step = 10.0, sheath = 1.0, Ejump = 500e3, eta = 2.0, cone = 60, rng)

A downward stepped leader from `start` (x, y, z). Each step goes `step` metres in a direction drawn with weight
(E . d)^eta from the field half a step ahead (within `cone` degrees of the last direction: the streamer zone lies
ahead of the tip). Before each step: if the tip's potential over the distance to an earthed point (a rod panel, or
the ground straight below) passes `Ejump`, the gap breaks down and the channel jumps there. `F = lu(panel_matrix(ps))`.
Returns (; path, hit = :ground or panel index, jump (m), steps).
"""
function grow_leader(ps::Panels, F; E0, start, lam = 1e-3, step = 10.0, sheath = 1.0, Ejump = 500e3, eta = 2.0,
                     cone = 60.0, rng, maxsteps = 400, ndirs = 96)
    pts = NTuple{3,Float64}[Tuple(float.(start))]
    last = (0.0, 0.0, -1.0)
    dirs = sphere_dirs(ndirs)
    s = sign(lam)
    cosmin = cosd(cone)
    for n in 1:maxsteps
        tip = pts[end]
        # charges the rods need to sit at 0 V in the storm's field and the channel's
        rhs = [-(E0 * c[3] + (length(pts) > 1 ? leader_phiE(pts, c, lam, sheath)[1] : 0.0)) for c in ps.c]
        q = F \ rhs
        φtip = E0 * tip[3] + panels_phiE(ps, q, tip)[1] + (length(pts) > 1 ? leader_phiE(pts, tip, lam, sheath)[1] : 0.0)
        # the final jump: the strongest mean field from the tip to anything earthed
        best = (φtip / tip[3], :ground, (tip[1], tip[2], 0.0))
        for j in eachindex(ps.c)
            g = φtip / norm(tip .- ps.c[j])
            abs(g) > abs(best[1]) && (best = (g, j, ps.c[j]))
        end
        if s * best[1] > Ejump
            push!(pts, best[3])
            return (; path = pts, hit = best[2], jump = norm(tip .- best[3]), steps = n)
        end
        w = zeros(length(dirs))
        for (k, d) in enumerate(dirs)
            dot(d, last) < cosmin && continue
            mid = tip .+ (step / 2) .* d
            mid[3] <= 0 && continue
            E = (0.0, 0.0, -E0) .+ panels_phiE(ps, q, mid)[2] .+
                (length(pts) > 1 ? leader_phiE(pts, mid, lam, sheath)[2] : (0.0, 0.0, 0.0))
            w[k] = max(0.0, s * dot(E, d))^eta
        end
        sum(w) > 0 || return (; path = pts, hit = :stalled, jump = NaN, steps = n)
        r = rand(rng) * sum(w); k = findfirst(>=(r), cumsum(w))
        last = dirs[k]
        push!(pts, tip .+ step .* last)
    end
    return (; path = pts, hit = :none, jump = NaN, steps = maxsteps)
end

"Potential and field at `p` of channel segments pts[k]-pts[k+1] carrying `lams[k]` (with mirrors)."
function segs_phiE(pts, lams, p, sheath)
    φ = 0.0; E = (0.0, 0.0, 0.0)
    for k in eachindex(lams)
        φ1, E1 = seg_phiE(p, pts[k], pts[k+1], lams[k], sheath)
        φ2, E2 = seg_phiE(p, mirror(pts[k]), mirror(pts[k+1]), -lams[k], sheath)
        φ += φ1 + φ2; E = E .+ E1 .+ E2
    end
    return φ, E
end

"""
    leader_eq(ps, F; E0, start, zcloud = 1500, ...)

The stepped leader as a CONDUCTOR (the dielectric breakdown model's physics): the channel from the cloud base at
`zcloud` down to the tip sits at the cloud's potential Vc = E0 zcloud, the rods at 0 V; the charges on every
channel segment and every rod panel are solved together each step (rods' LU `F` reused by a Schur complement).
So charge piles up at the tip and grows as the tip nears the ground or a rod, and that is what steers it.
Steps and the final jump as in `grow_leader` (jump when Vc / distance > Ejump).
"""
function leader_eq(ps::Panels, F; E0, start, zcloud = 1500.0, top_seg = 50.0, step = 10.0, sheath = 1.0,
                   Ejump = 500e3, eta = 2.0, cone = 60.0, rng, maxsteps = 300, ndirs = 96)
    x0, y0, z0 = float.(start)
    pts = [(x0, y0, z) for z in range(zcloud, z0; length = max(2, round(Int, (zcloud - z0) / top_seg) + 1))]
    Vc = E0 * zcloud
    np = length(ps.a)
    bp = [-E0 * c[3] for c in ps.c]
    Fbp = F \ bp
    unitcol(a, b) = [seg_phiE(c, a, b, 1.0, sheath)[1] + seg_phiE(c, mirror(a), mirror(b), -1.0, sheath)[1] for c in ps.c]
    unitrow(m) = [KE * (1 / norm(m .- c) - 1 / norm(m .- mirror(c))) for c in ps.c]
    X = reduce(hcat, [F \ unitcol(pts[k], pts[k+1]) for k in 1:length(pts)-1])
    dirs = sphere_dirs(ndirs); last = (0.0, 0.0, -1.0); cosmin = cosd(cone)
    for n in 1:maxsteps
        m = length(pts) - 1
        mids = [(pts[k] .+ pts[k+1]) ./ 2 for k in 1:m]
        Pss = [seg_phiE(mids[i], pts[k], pts[k+1], 1.0, sheath)[1] +
               seg_phiE(mids[i], mirror(pts[k]), mirror(pts[k+1]), -1.0, sheath)[1] for i in 1:m, k in 1:m]
        Psp = reduce(vcat, [unitrow(mids[i])' for i in 1:m])
        bs = [Vc - E0 * mi[3] for mi in mids]
        lams = (Pss - Psp * X) \ (bs - Psp * Fbp)
        q = Fbp - X * lams
        tip = pts[end]
        best = (tip[3], :ground, (tip[1], tip[2], 0.0))
        for j in 1:np
            d = norm(tip .- ps.c[j]); d < best[1] && (best = (d, j, ps.c[j]))
        end
        if Vc / best[1] > Ejump
            push!(pts, best[3])
            return (; path = pts, hit = best[2], jump = best[1], steps = n, tip_lam = lams[end])
        end
        w = zeros(length(dirs))
        for (k, d) in enumerate(dirs)
            dot(d, last) < cosmin && continue
            mid = tip .+ (step / 2) .* d
            mid[3] <= 0 && continue
            E = (0.0, 0.0, -E0) .+ panels_phiE(ps, q, mid)[2] .+ segs_phiE(pts, lams, mid, sheath)[2]
            w[k] = max(0.0, sign(Vc) * dot(E, d))^eta
        end
        sum(w) > 0 || return (; path = pts, hit = :stalled, jump = NaN, steps = n, tip_lam = lams[end])
        r = rand(rng) * sum(w); k = findfirst(>=(r), cumsum(w))
        last = dirs[k]
        push!(pts, tip .+ step .* last)
        X = hcat(X, F \ unitcol(pts[end-1], pts[end]))
    end
    return (; path = pts, hit = :none, jump = NaN, steps = maxsteps, tip_lam = NaN)
end

"Panels of an earthed rod (capped cylinder) at (x, y) of height h and radius r."
function rod_panels(x, y, h, r; nθ = 12, nz = 30)
    verts = NTuple{3,Float64}[]; faces = NTuple{3,Int}[]
    for z in range(0.0, h; length = nz), k in 0:nθ-1
        push!(verts, (x + r * cos(2pi * k / nθ), y + r * sin(2pi * k / nθ), z))
    end
    push!(verts, (x, y, h + r))
    id(i, k) = (i - 1) * nθ + mod(k, nθ) + 1
    for i in 1:nz-1, k in 0:nθ-1
        push!(faces, (id(i, k), id(i, k + 1), id(i + 1, k + 1)), (id(i, k), id(i + 1, k + 1), id(i + 1, k)))
    end
    for k in 0:nθ-1
        push!(faces, (id(nz, k), id(nz, k + 1), length(verts)))
    end
    return verts, faces
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
