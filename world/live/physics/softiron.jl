# Soft iron rods that magnetise each other (s148, big goal "Sparks from stones": iron magnetises iron).
#
# Every rod is cut into K segments along its axis, each with its own magnetisation M (A/m, along the axis). A segment
# is a little magnet: charge +A*M on its front face, -A*M on its back face (A = the rod's cross section), so a rod
# carries charge where M changes along it: at its ends, and spread along it where flux leaks out of its sides. Every
# segment of every rod is solved TOGETHER: M = chi * (axial H at the segment's centre), where H is the outside field
# plus the field of all charges (the rod's own charges are its demagnetisation). Iron saturates at Ms: segments over
# it are held at +-Ms and the rest solved again. Forces on a rod = the field of everything else on its charges.
#
# Field of a face charge: a disc of radius a on its own rod's axis (exact), a 7-point disc rule on other rods' points
# within 4a, a point charge further away.
#   S = SoftIron.Rods(centres, axes; L, a, K); SoftIron.solve!(S, Hext); F, T = SoftIron.force_torque(S, i, Hext)
#   Hext(p) -> NTuple{3,Float64} in A/m.  SoftIron.selftest() checks it against the rod demagnetising factor.
module SoftIron

using LinearAlgebra

const V3 = NTuple{3,Float64}
add(a, b) = (a[1] + b[1], a[2] + b[2], a[3] + b[3]); sub(a, b) = (a[1] - b[1], a[2] - b[2], a[3] - b[3])
mul(s, a) = (s * a[1], s * a[2], s * a[3]); dot3(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

mutable struct Rods
    c::Vector{V3}; u::Vector{V3}          # centres and unit axes
    L::Float64; a::Float64; K::Int        # length, radius, segments per rod
    s::Vector{Float64}                    # the K+1 face positions along a rod (-L/2 .. L/2), finer towards the ends
    chi::Float64; Ms::Float64             # susceptibility (soft iron ~ 5000), saturation (A/m)
    M::Matrix{Float64}                    # K x n, along each rod's axis
    G::Matrix{Float64}; h::Vector{Float64}   # work space
end
function Rods(c, u; L, a, K = 10, graded = true, chi = 5000.0, Ms = 1.7e6)
    n = length(c); N = n * K
    # graded: faces at -L/2 cos(pi b/K): where two rods touch M changes fast, and even segments got the pull at a
    # joint wrong (s148: 8 even segments let the stone hold 4 spikes in a chain, 32 say 3)
    s = graded ? [-L / 2 * cos(pi * b / K) for b in 0:K] : [-L / 2 + b * L / K for b in 0:K]
    Rods(collect(V3, c), collect(V3, u), L, a, K, s, chi, Ms, zeros(K, n), zeros(N, N), zeros(N))
end
nrods(S) = length(S.c)
area(S) = pi * S.a^2
"Point along rod i at axial coordinate s (-L/2 .. L/2)."
along(S, i, s) = add(S.c[i], mul(s, S.u[i]))
"Face b of rod i (b = 0..K) and the centre of segment k (1..K), between faces k-1 and k."
face(S, i, b) = along(S, i, S.s[b+1])
segs(S, k) = (S.s[k] + S.s[k+1]) / 2
segc(S, i, k) = along(S, i, segs(S, k))

# H at p from a unit charge (A*M = 1 A m) at x: softened point charge
@inline function hq(p, x, eps2)
    d = sub(p, x); r2 = dot3(d, d) + eps2
    mul(1 / (4pi * r2 * sqrt(r2)), d)
end
# H at p from a disc of total charge 1, radius a, centre x, normal n: within 4a a 7-point disc rule (centre 1/4, six
# at a*sqrt(2/3) 1/8 each), else a point. A softened point alone gives NO field close in front of a face (the disc's
# is sigma/2 there), so finer segments at a joint pulled less and less (s148, 64 even segments still not settled).
function hface(p, x, n, a)
    d = sub(p, x)
    dot3(d, d) > 16a^2 && return hq(p, x, 0.0)
    e1 = abs(n[1]) < 0.9 ? (0.0, n[3], -n[2]) : (-n[3], 0.0, n[1]); e1 = mul(1 / sqrt(dot3(e1, e1)), e1)
    e2 = (n[2] * e1[3] - n[3] * e1[2], n[3] * e1[1] - n[1] * e1[3], n[1] * e1[2] - n[2] * e1[1])
    r = a * sqrt(2 / 3); eps2 = (0.25a)^2
    h = mul(0.25, hq(p, x, eps2))
    for t in 0:5
        st, ct = sincospi(t / 3)
        h = add(h, mul(0.125, hq(p, add(x, add(mul(r * ct, e1), mul(r * st, e2))), eps2)))
    end
    h
end
# axial H on a rod's own axis at signed distance z ahead of a disc of total charge 1 and radius a (exact)
@inline hdisc(z, a) = sign(z) * (1 - abs(z) / sqrt(z * z + a * a)) / (2pi * a * a)

"Influence of segment (j,l) with M = 1 on the axial field at the centre of segment (i,k)."
function infl(S, i, k, j, l)
    A = area(S)
    if i == j                         # same rod: exact disc fields on the axis
        zf = segs(S, k) - S.s[l+1]          # centre of k relative to the front face of l
        zb = segs(S, k) - S.s[l]
        return A * (hdisc(zf, S.a) - hdisc(zb, S.a))
    end
    p = segc(S, i, k)
    A * dot3(S.u[i], sub(hface(p, face(S, j, l), S.u[j], S.a), hface(p, face(S, j, l - 1), S.u[j], S.a)))
end

"""
Solve every segment's magnetisation in the outside field `Hext(p)` together. `active` picks the rods taking part (the
others keep M = 0). Saturated segments are held at +-Ms and the rest solved again (up to 4 passes).
"""
function solve!(S::Rods, Hext; active = 1:nrods(S))
    K = S.K; act = collect(active); n = length(act); N = n * K
    fill!(S.M, 0.0)
    n == 0 && return S
    G = view(S.G, 1:N, 1:N); h = view(S.h, 1:N)
    idx(ii, k) = (ii - 1) * K + k
    for (ii, i) in enumerate(act), k in 1:K
        r = idx(ii, k)
        h[r] = dot3(S.u[i], Hext(segc(S, i, k)))
        for (jj, j) in enumerate(act), l in 1:K
            G[r, idx(jj, l)] = -infl(S, i, k, j, l)
        end
        G[r, r] += 1 / S.chi
    end
    # (I/chi - Infl) M = h, with saturated segments moved to the right side
    fixed = falses(N); Mv = zeros(N)
    for pass in 1:4
        free = findall(!, fixed)
        rhs = h[free] .- G[free, fixed] * Mv[fixed]
        Mv[free] = G[free, free] \ rhs
        over = [r for r in free if abs(Mv[r]) > S.Ms]
        isempty(over) && break
        for r in over; Mv[r] = sign(Mv[r]) * S.Ms; fixed[r] = true; end
    end
    for (ii, i) in enumerate(act), k in 1:K
        S.M[k, i] = Mv[idx(ii, k)]
    end
    S
end

"Face charges of rod i (A m): K+1 of them, face b = A*(M_b - M_{b+1}) with M outside the rod 0."
function charges(S, i)
    A = area(S); K = S.K
    [A * ((b >= 1 ? S.M[b, i] : 0.0) - (b + 1 <= K ? S.M[b+1, i] : 0.0)) for b in 0:K]
end

"H at p from all rods except `skip` (A/m)."
function H(S::Rods, p; skip = 0)
    hx = (0.0, 0.0, 0.0)
    for j in 1:nrods(S)
        j == skip && continue
        q = charges(S, j)
        for b in 0:S.K
            q[b+1] == 0.0 && continue
            hx = add(hx, mul(q[b+1], hface(p, face(S, j, b), S.u[j], S.a)))
        end
    end
    hx
end

"Force (N) and torque about its centre (N m) on rod i from the outside field and all other rods: F = mu0 q H on each charge."
function force_torque(S::Rods, i, Hext)
    mu0 = 4pi * 1e-7
    q = charges(S, i); F = (0.0, 0.0, 0.0); T = (0.0, 0.0, 0.0)
    for b in 0:S.K
        q[b+1] == 0.0 && continue
        x = face(S, i, b)
        f = mul(mu0 * q[b+1], add(Hext(x), H(S, x; skip = i)))
        F = add(F, f)
        r = sub(x, S.c[i])
        T = add(T, (r[2] * f[3] - r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] - r[2] * f[1]))
    end
    F, T
end

"Mean magnetisation of rod i along its axis (A/m)."
meanM(S, i) = sum(S.M[k, i] * (S.s[k+1] - S.s[k]) for k in 1:S.K) / S.L

"""
Self test. (1) One rod (12 cm x 6 mm, chi = 5000) in a weak uniform field along it: its mean M against the rod formula
M = H/N, N = (ln(2a) - 1)/a^2 for aspect a = L/d (the one magnetstone.jl used). (2) Two rods end to end magnetise each
other more than one alone, and pull together. (3) Across the field a rod barely magnetises.
"""
function selftest(; verbose = true)
    L = 0.12; a = 0.003; H0 = 200.0
    asp = L / (2a); Npar = (log(2asp) - 1) / asp^2
    one = solve!(Rods([(0.0, 0.0, 0.0)], [(1.0, 0.0, 0.0)]; L, a, K = 16), p -> (H0, 0.0, 0.0))
    m1 = meanM(one, 1)
    two = solve!(Rods([(0.0, 0.0, 0.0), (L + 0.001, 0.0, 0.0)], [(1.0, 0.0, 0.0), (1.0, 0.0, 0.0)]; L, a, K = 16),
                 p -> (H0, 0.0, 0.0))
    m2 = meanM(two, 1)
    F12, _ = force_torque(two, 2, p -> (H0, 0.0, 0.0))
    side = solve!(Rods([(0.0, 0.0, 0.0)], [(0.0, 1.0, 0.0)]; L, a, K = 16), p -> (H0, 0.0, 0.0))
    r = (; M_one = m1, M_formula = H0 / Npar, ratio = m1 / (H0 / Npar), M_two = m2, pull_two_N = F12[1],
         M_across = meanM(side, 1))
    verbose && @info "SoftIron self test" r...
    @assert 0.6 < r.ratio < 1.6 "a rod in a uniform field: $(r.ratio) of the formula"
    @assert r.M_two > r.M_one "two rods end to end magnetise each other more"
    @assert r.pull_two_N < 0 "the second rod is pulled back towards the first"
    @assert abs(r.M_across) < 1e-6 "across the field: no axial M"
    r
end

end # module
