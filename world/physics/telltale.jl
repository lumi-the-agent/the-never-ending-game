# A wool telltale: a short yarn tied to the sail, moved by the air around it and by its own weight (s164, landyacht).
# The yarn is a chain of `n` segments (position Verlet + length constraints, the hotrod/XPBD way): each node feels
# gravity and the drag of the air passing it, split into the part across the yarn (cylinder, Cd ~1.2) and along it
# (skin friction, ~0.05 of that). The air comes from the solved flow (a function x -> velocity in m/s), so the yarn
# streams in fast air, hangs in a slow bubble and twitches where the flow is unsteady. Nothing is set per trim.
module Telltale
using StaticArrays, LinearAlgebra

const V3 = SVector{3,Float64}

Base.@kwdef struct Yarn
    length::Float64 = 0.15        # m
    diameter::Float64 = 0.002     # m (2 ply wool)
    mass::Float64 = 0.3e-3        # kg (loose wool, ~1.3 g/cm3 fibres, half air)
    n::Int = 8
    cd_n::Float64 = 1.2           # drag across a cylinder at Re ~ 500
    cd_t::Float64 = 0.06          # along it
    rho_air::Float64 = 1.2
end

"""A yarn hanging straight down from `anchor`: (positions, previous positions)."""
function hang(y::Yarn, anchor::V3)
    p = [anchor - V3(0, 0, (i - 1) * y.length / y.n) for i in 1:y.n+1]
    (p, copy(p))
end

"""
    step!(y, p, q, anchor, air, dt; g = 9.81, iters = 8)

One Verlet step of the yarn with node 1 tied to `anchor`; `air(x)` is the wind velocity (m/s, a V3) at `x`.
`q` holds the previous positions. Damping comes only from the air drag.
"""
function step!(y::Yarn, p, q, anchor::V3, air, dt; g = 9.81, iters = 8)
    m = y.mass / y.n; l = y.length / y.n
    for i in 2:y.n+1
        v = (p[i] - q[i]) / dt
        t = normalize(p[i] - p[i-1])
        w = air(p[i]) - v                                  # the air as this node feels it
        wt = dot(w, t) * t; wn = w - wt
        F = 0.5 * y.rho_air * y.diameter * l * (y.cd_n * norm(wn) * wn + y.cd_t * norm(wt) * wt)
        a = F / m + V3(0, 0, -g)
        pn = 2p[i] - q[i] + a * dt^2
        q[i] = p[i]; p[i] = pn
    end
    p[1] = anchor; q[1] = anchor
    for _ in 1:iters, i in 2:y.n+1                          # inextensible: pull each node back to l from the last
        d = p[i] - p[i-1]; L = norm(d)
        L > 0 && (p[i] = p[i-1] + d * (l / L))
    end
    p
end

"""Angle (deg) of the yarn's tip direction off the downward vertical (0 = hanging, 90 = streaming level)."""
lift_deg(p) = (d = normalize(p[end] - p[1]); rad2deg(acos(clamp(-d[3], -1, 1))))

end
