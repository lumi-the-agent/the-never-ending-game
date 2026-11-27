# A spinning top floating over a ring magnet (s148, project levitron; big goal "Sparks from stones").
#
# Earnshaw: no magnet held still floats in a static field. A top that spins keeps its axis (gyroscopically) along the
# field it moves through, so its energy is +mu|B| + m g z, and |B| over a ring magnet has a true 3D minimum in a narrow
# band of heights (Berry 1996, Simon, Heflinger & Ridgway 1997). Nothing here knows that: the top is a full rigid body
# (position, velocity, orientation, angular momentum) under gravity, F = mu0 G m (G = the field's gradient) and torque
# m x B; whether it floats comes out of the integration.
#
# The base: a ferrite ring magnetised along +z, as surface charge sigma = M.n on its top and bottom faces (the same
# model as em.jl), laid out as rings of quadrature points (Gauss-Legendre across, nth around: the ripple between
# points falls off as exp(-2 pi z / spacing), invisible a few cm up).
module Levitron

using LinearAlgebra

const MU0 = 4pi * 1e-7
const V3 = NTuple{3,Float64}

struct Ring
    pts::Vector{V3}; q::Vector{Float64}
end

"Ferrite ring: outer/inner radius, thickness h (top face at z = 0), remanence Br, magnetised +z."
function ring(; Ro = 0.075, Ri = 0.025, h = 0.025, Br = 0.38, nr = 8, nth = 96)
    M = Br / MU0
    x, w = gauss(nr)
    pts = V3[]; q = Float64[]
    for (zf, s) in ((0.0, M), (-h, -M)), k in 1:nr, j in 1:nth
        r = Ri + (Ro - Ri) * (x[k] + 1) / 2
        dA = (Ro - Ri) / 2 * w[k] * r * 2pi / nth
        t = 2pi * (j - 0.5) / nth
        push!(pts, (r * cos(t), r * sin(t), zf)); push!(q, s * dA)
    end
    Ring(pts, q)
end

"Gauss-Legendre points and weights on [-1, 1] (Golub-Welsch)."
function gauss(n)
    b = [k / sqrt(4k^2 - 1) for k in 1:n-1]
    E = eigen(SymTridiagonal(zeros(n), b))
    E.values, 2 .* E.vectors[1, :] .^ 2
end

"H (A/m) and its gradient G[i,j] = dH_i/dx_j at p."
function field(R::Ring, p)
    H = zeros(3); G = zeros(3, 3)
    @inbounds for k in eachindex(R.q)
        d1 = p[1] - R.pts[k][1]; d2 = p[2] - R.pts[k][2]; d3 = p[3] - R.pts[k][3]
        r2 = d1 * d1 + d2 * d2 + d3 * d3; r = sqrt(r2)
        c = R.q[k] / (4pi * r2 * r); c5 = 3c / r2
        d = (d1, d2, d3)
        for i in 1:3
            H[i] += c * d[i]
            for j in 1:3
                G[i, j] += (i == j ? c : 0.0) - c5 * d[i] * d[j]
            end
        end
    end
    H, G
end

mutable struct Top
    x::Vector{Float64}; v::Vector{Float64}
    Rm::Matrix{Float64}            # body -> world
    L::Vector{Float64}             # angular momentum about the centre of mass, world
    mass::Float64; I1::Float64; I3::Float64
    mu::Float64                    # dipole moment (A m^2) along the body's own axis (third column of Rm)
end

"A ferrite ring top (outer/inner radius, thickness) on a spindle, plus `washers` kg of copper on it."
function top(; Ro = 0.015, Ri = 0.003, h = 0.006, Br = 0.38, rho = 4900.0, spindle = 0.002, washers = 0.0)
    V = pi * (Ro^2 - Ri^2) * h
    m = rho * V + spindle + washers
    I3 = 0.5 * (rho * V) * (Ro^2 + Ri^2) + 0.5 * washers * (0.006^2)
    I1 = 0.25 * (rho * V) * (Ro^2 + Ri^2) + (rho * V) * h^2 / 12 + spindle * 0.03^2 / 3
    Top(zeros(3), zeros(3), Matrix(1.0I, 3, 3), zeros(3), m, I1, I3, Br / MU0 * V)
end

function omega(t::Top)
    Ib = Diagonal([t.I1, t.I1, t.I3])
    t.Rm * (Ib \ (t.Rm' * t.L))
end

skew(w) = [0 -w[3] w[2]; w[3] 0 -w[1]; -w[2] w[1] 0]

"Derivatives of (x, v, Rm, L) for top t over ring R; the moment points along -axis*sign (sgn = -1: anti-aligned)."
function deriv(R::Ring, t::Top, sgn; drag = 0.0)
    H, G = field(R, t.x)
    m = sgn * t.mu .* t.Rm[:, 3]
    F = MU0 .* (G' * m) .+ [0.0, 0.0, -9.81 * t.mass]
    T = cross(m, MU0 .* H)
    w = omega(t)
    T = T .- drag .* w                                  # air on the spinning top
    (t.v, F ./ t.mass, skew(w) * t.Rm, T)
end

function rk4!(R::Ring, t::Top, dt, sgn; drag = 0.0)
    s0 = (copy(t.x), copy(t.v), copy(t.Rm), copy(t.L))
    set!(s) = (t.x .= s[1]; t.v .= s[2]; t.Rm .= s[3]; t.L .= s[4])
    k1 = deriv(R, t, sgn; drag)
    set!(map((a, b) -> a .+ (dt / 2) .* b, s0, k1)); k2 = deriv(R, t, sgn; drag)
    set!(map((a, b) -> a .+ (dt / 2) .* b, s0, k2)); k3 = deriv(R, t, sgn; drag)
    set!(map((a, b) -> a .+ dt .* b, s0, k3)); k4 = deriv(R, t, sgn; drag)
    set!(map((a, b1, b2, b3, b4) -> a .+ (dt / 6) .* (b1 .+ 2 .* b2 .+ 2 .* b3 .+ b4), s0, k1, k2, k3, k4))
    F = svd(t.Rm); t.Rm .= F.U * F.Vt                   # keep it a rotation
    t
end

"""
On-axis height where the field holds the top's weight, the moment fixed along `sgn` z (it does not flip as the top
moves: s148's first scan flipped it where the ring's Bz changes sign, about 2 cm up, and found a false balance).
Vertically stable: pushed up below it, down above it.
"""
function hover_height(R::Ring, t::Top; sgn = -1.0, z0 = 0.005, z1 = 0.15)
    prev = nothing
    for z in z0:0.0002:z1
        H, G = field(R, [0.0, 0.0, z])
        Fz = MU0 * G[3, 3] * sgn * t.mu - 9.81 * t.mass
        prev !== nothing && prev > 0 && Fz <= 0 && return z, sgn
        prev = Fz
    end
    nothing
end

"""
Spin the top at `spin` rev/s at the height where it balances, nudged `dr` sideways and tilted `tilt` rad, and run it
for `secs`. Returns how long it stayed up (no fall below the ring's face, no drift past the inner radius x 2) and its
path's spread.
"""
function float_test(; washers = 0.0, spin = 25.0, secs = 6.0, dt = 2e-4, dr = 0.001, tilt = 0.01, drag = 0.0,
                    ring_kw = (;), z = nothing, record = 0)
    R = ring(; ring_kw...)
    t = top(; washers)
    hz = hover_height(R, t)
    hz === nothing && return (; floats = 0.0, reason = :too_heavy, mass = t.mass)
    z0, sgn = z === nothing ? hz : (z, hz[2])
    t.x .= [dr, 0.0, z0]
    t.Rm .= [1 0 0; 0 cos(tilt) -sin(tilt); 0 sin(tilt) cos(tilt)]
    t.L .= t.I3 * 2pi * spin .* t.Rm[:, 3]
    n = round(Int, secs / dt); up = secs; path = NTuple{4,Float64}[]
    every = record > 0 ? max(1, round(Int, 1 / (record * dt))) : 0
    for i in 1:n
        rk4!(R, t, dt, sgn; drag)
        every > 0 && i % every == 0 && push!(path, (i * dt, t.x[1], t.x[2], t.x[3]))
        if t.x[3] < 0.004 || hypot(t.x[1], t.x[2]) > 0.05 || t.x[3] > 0.3
            up = i * dt; break
        end
    end
    (; floats = up, z0, mass = t.mass, x = copy(t.x), axis = t.Rm[:, 3], spin_now = dot(omega(t), t.Rm[:, 3]) / 2pi, path)
end

"""
The top spins on a clear plate that holds it where the field balances its weight (found by `hover_height`); after
`hold` s the plate sinks away (`sink` m/s) and from then on only the field holds it. (s148: lifting it off the plate
from below let it leave at the low edge of its well with all the well's energy; it bobbed 2 cm and left the narrow
band of heights where it is stable sideways, so it fell at 3.6 s.)
Returns frames (t, centre, body->world rotation, plate height, spin angle) at `fps`, and when it fell (NaN: never).
"""
function launch(; washers = 0.00575, spin = 25.0, secs = 10.0, dt = 2e-4, fps = 24, hold = 1.5, sink = 0.03,
                tip = 0.012, dr = 0.0005, drag = 0.0)
    R = ring(); t = top(; washers)
    z0, _ = hover_height(R, t)
    t.x .= [dr, 0.0, z0]; t.L .= t.I3 * 2pi * spin .* t.Rm[:, 3]
    fell = NaN; zp = z0 - tip; phi = 0.0
    frames = Tuple{Float64,Vector{Float64},Matrix{Float64},Float64,Float64}[]
    every = round(Int, 1 / (fps * dt)); n = round(Int, secs / dt)
    for i in 1:n
        tt = i * dt
        if tt < hold
            t.v .= 0.0                                     # resting on the plate, spinning in place
        else
            zp = max(zp - sink * dt, -0.01)
            rk4!(R, t, dt, -1.0; drag)
            if t.x[3] - tip < zp
                t.x[3] = zp + tip; t.v[3] = max(t.v[3], 0.0)
            end
            isnan(fell) && (t.x[3] < 0.02 || hypot(t.x[1], t.x[2]) > 0.05) && (fell = tt)
        end
        phi += dot(omega(t), t.Rm[:, 3]) * dt
        i % every == 0 && push!(frames, (tt, copy(t.x), copy(t.Rm), zp, phi))
    end
    (; frames, fell, z0, mass = t.mass)
end

end # module
