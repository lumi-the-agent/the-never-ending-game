# The smallest honest motor (s146, project copper-wire): an AA cell stands on a disc magnet, a bent copper wire rests
# with a dimple on the cell's top and touches the magnet's rim. Current runs down the wire's real path; the magnet's
# field (a uniformly magnetised cylinder = a stack of surface current loops, each loop exact straight-segment
# Biot-Savart) pushes on every millimetre of it (dF = I dl x B); the torque about the cell's axis spins it.
# Against it: Coulomb friction at the dimple and at the rim contacts (static, then sliding) and air drag on the wire.
# A wire whose centre of mass is off the axis needs m w^2 e from the dimple: past what the dimple's friction holds, it
# flies off. Current from the cell's EMF and internal resistance and the arms' copper resistance (in parallel).
# Looked first (rule 6): Magnetostatics.jl has CurrentLoopAnalytic and a BiotSavart solver; not used yet (time):
# swap it in for the loop stack when this goes live.
#   include("physics/homopolar.jl"); r = Homopolar.spin(Homopolar.heart(); seconds = 6)
module Homopolar
using LinearAlgebra

const MU0 = 4pi * 1e-7
const RHO_CU = 1.68e-8         # copper resistivity, ohm m
const DENS_CU = 8960.0

V3 = NTuple{3,Float64}
v(a) = collect(Float64, a)

Base.@kwdef struct Rig
    R::Float64 = 0.0125        # magnet radius (25 mm disc)
    H::Float64 = 0.006         # magnet thickness; magnet spans z 0..H
    Br::Float64 = 1.2          # remanence of NdFeB, T
    Lb::Float64 = 0.050        # AA cell height; cell spans z H..H+Lb, radius 7 mm
    emf::Float64 = 1.5
    r_int::Float64 = 0.12      # alkaline AA internal resistance, ohm
    d::Float64 = 0.0010        # wire diameter, m
    mu_s::Float64 = 0.35       # copper on nickel, static
    mu_k::Float64 = 0.25
    E::Float64 = 117e9         # copper's Young's modulus: an arm bent tighter than the magnet springs against it
    c_bounce::Float64 = 1.0e-6 # N m s per rim contact: the contact chatters more the faster it slides (fitted, s146:
                               # brings a heart-shaped wire to ~25 rev/s, as people measure them)
    mu_dimple::Float64 = 0.45  # lateral grip of the dimple on the cell's button
end

"Magnet as nz loops of nseg straight segments, each carrying M H / nz (M = Br / mu0)."
function magnet_segments(r::Rig; nz = 10, nseg = 64)
    Iloop = r.Br / MU0 * r.H / nz
    segs = Tuple{Vector{Float64},Vector{Float64},Float64}[]
    for j in 1:nz
        z = r.H * (j - 0.5) / nz
        for k in 0:nseg-1
            a = [r.R * cos(2pi * k / nseg), r.R * sin(2pi * k / nseg), z]
            b = [r.R * cos(2pi * (k + 1) / nseg), r.R * sin(2pi * (k + 1) / nseg), z]
            push!(segs, (a, b, Iloop))
        end
    end
    return segs
end

"Exact field at p of a straight segment a->b carrying I."
function seg_field(p, a, b, I)
    r1 = p .- a; r2 = p .- b
    n1 = norm(r1); n2 = norm(r2)
    den = n1 * n2 * (n1 * n2 + dot(r1, r2))
    den < 1e-18 && return zeros(3)
    return MU0 * I / (4pi) .* cross(r1, r2) .* ((n1 + n2) / den)
end
field(p, segs) = sum(seg_field(p, a, b, I) for (a, b, I) in segs)

"Resample a polyline to pieces of at most h metres."
function fine(pts; h = 0.0007)
    out = [v(pts[1])]
    for i in 2:length(pts)
        a, b = v(pts[i-1]), v(pts[i])
        n = max(1, ceil(Int, norm(b - a) / h))
        for k in 1:n; push!(out, a + (b - a) * k / n); end
    end
    return out
end

# --- three bends, each a list of arms from the dimple (on the axis at the cell's top) to a rim contact -----------
top(r) = r.H + r.Lb + 0.0005
"Two mirrored arms: out, down outside the cell, in to the rim at mid-magnet. Balanced."
heart(r = Rig(); ro = 0.016) = [[(0.0, 0.0, top(r)), (s * 0.006, 0.0, top(r) + 0.004), (s * ro, 0.0, top(r) - 0.006),
                                 (s * ro, 0.0, r.H * 0.5 + 0.003), (s * (r.R + 0.0004), 0.0, r.H * 0.5)] for s in (1.0, -1.0)]
"One arm only, the same path: it spins, but its centre of mass is off the axis."
onearm(r = Rig(); ro = 0.016) = heart(r; ro)[1:1]
"Two mirrored arms that come down far from the magnet (5 cm out) and run in along its top face to the rim."
wide(r = Rig(); ro = 0.05) = [[(0.0, 0.0, top(r)), (s * 0.010, 0.0, top(r) + 0.006), (s * ro, 0.0, top(r) - 0.004),
                               (s * ro, 0.0, r.H + 0.0008), (s * (r.R - 0.0005), 0.0, r.H + 0.0008), (s * (r.R + 0.0004), 0.0, r.H * 0.5)]
                              for s in (1.0, -1.0)]

"Torque about z per ampere for each arm, the wire's mass, inertia, centre of mass offset and drag factor."
function analyse(arms, r::Rig)
    segs = magnet_segments(r)
    A = pi * r.d^2 / 4
    tq = Float64[]; Larm = Float64[]
    m = 0.0; J = 0.0; cm = zeros(3); kd = 0.0
    for arm in arms
        P = fine(arm)
        t = 0.0; L = 0.0
        for i in 2:length(P)
            dl = P[i] - P[i-1]; c = (P[i] + P[i-1]) / 2
            F = cross(dl, field(c, segs))               # per ampere
            t += c[1] * F[2] - c[2] * F[1]
            L += norm(dl)
            dm = DENS_CU * A * norm(dl); m += dm
            rr = hypot(c[1], c[2]); J += dm * rr^2; cm .+= dm .* c
            kd += 0.5 * 1.2 * 1.2 * r.d * rr^3 * norm(dl[3])   # air drag on the vertical parts: torque = kd w^2
        end
        push!(tq, t); push!(Larm, L)
    end
    cm ./= m
    return (; tq, Larm, m, J, e = hypot(cm[1], cm[2]), kd)
end

"Spin it up from rest. Returns angle and speed per step, whether and when it flew off."
function spin(arms, r::Rig = Rig(); seconds = 6.0, dt = 1e-4, squeeze = 0.1e-3)
    a = analyse(arms, r)
    # each arm is a cantilever hanging from the dimple: bent `squeeze` metres tighter than the magnet's radius it
    # presses with 3 E I / Lv^3 * squeeze (Lv = its drop from the cell's top to the contact)
    Lv = top(r) - r.H * 0.5
    N_rim = 3 * r.E * (pi * r.d^4 / 64) / Lv^3 * squeeze
    Rk = [RHO_CU * L / (pi * r.d^2 / 4) + 0.02 for L in a.Larm]  # + contact resistance per arm
    Rpar = 1 / sum(1 ./ Rk)
    Itot = r.emf / (r.r_int + Rpar)
    Iarm = Itot * Rpar ./ Rk
    tauL = sum(a.tq .* Iarm)
    narm = length(arms)
    tau_s = r.mu_s * (N_rim * narm * r.R + a.m * 9.81 * 0.0005)    # rim contacts + the dimple (0.5 mm radius)
    tau_k = r.mu_k * (N_rim * narm * r.R + a.m * 9.81 * 0.0005)
    w_off = a.e > 1e-5 ? sqrt(r.mu_dimple * 9.81 / a.e) : Inf
    th = 0.0; w = 0.0; off_t = NaN
    ths = Float64[]; ws = Float64[]
    for k in 1:round(Int, seconds / dt)
        if w == 0.0 && abs(tauL) <= tau_s
            # stuck: static friction holds it
        else
            w += dt * (tauL - sign(w == 0 ? tauL : w) * tau_k - sign(w) * a.kd * w^2 - narm * r.c_bounce * w) / a.J
        end
        th += dt * w
        if isnan(off_t) && abs(w) > w_off
            off_t = k * dt
        end
        push!(ths, th); push!(ws, w)
    end
    return (; ths, ws, dt, off_t, w_off, I = Itot, tauL, tau_s, N_rim, a.m, a.J, a.e)
end

end
