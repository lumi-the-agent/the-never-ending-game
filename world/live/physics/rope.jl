# A hemp rope on a winch drum (s173, project winch). The tether model airborne-wind-energy simulators use
# (KiteModels.jl / SymbolicAWEModels.jl: point masses joined by spring-dampers that pull but never push; WinchModels.jl:
# reel-in shortens the unstretched length by drum angle x drum radius): particles on the ground with Coulomb friction,
# the first at the drum, the last tied to a load that slides (or rolls) with its own friction. The tension at the drum
# goes back to the motor as a load torque through the gear ratio, so the motor slows, stalls or hauls by its circuit.
# Nothing sets a speed. Looked first (rule 6): no rope in PrintSim; the AWE packages' tethers are tied to their kite
# models, the equations are these few lines.
module Rope

using LinearAlgebra, StaticArrays

const G = 9.81

"""
A rope of `n` segments from the drum at `anchor` to a load. Hemp, 6 mm: E*A ~ 25 kN (E ~ 0.9 GPa on 28 mm^2, a laid
rope stretches ~4% at its working load), 25 g/m, damping ratio ~0.3 a segment.
"""
Base.@kwdef mutable struct Tether
    x::Vector{NTuple{3,Float64}}
    v::Vector{NTuple{3,Float64}}
    L::Float64                    # unstretched length still off the drum (m)
    EA::Float64 = 25e3
    lin_mass::Float64 = 0.025     # kg/m
    zeta::Float64 = 0.3
    mu_ground::Float64 = 0.5      # rope on sand
    anchor::NTuple{3,Float64} = (0.0, 0.0, 0.0)
end

"A load the rope drags: mass (kg), sliding (mu) or rolling resistance coefficient, on flat ground for now."
Base.@kwdef mutable struct Load
    m::Float64
    mu::Float64
    x::NTuple{3,Float64}
    v::NTuple{3,Float64} = (0.0, 0.0, 0.0)
    grade::Float64 = 0.0          # s176: the ground's rise per metre along +x (the rope's run away from the drum)
end

const V = SVector{3,Float64}
v3(a) = V(a[1], a[2], a[3])
t3(a) = (a[1], a[2], a[3])

"A straight rope from `anchor` to `to`, `n` segments, slack `slack` (unstretched / distance)."
function Tether(anchor, to; n = 12, slack = 1.0, kw...)
    xs = [t3(v3(anchor) .+ (k / n) .* (v3(to) .- v3(anchor))) for k in 0:n]
    Tether(; x = xs, v = [(0.0, 0.0, 0.0) for _ in xs], L = slack * norm(v3(to) .- v3(anchor)), anchor = t3(anchor), kw...)
end

"""
    wound_radius(r0, d, W, Lw) -> r

The rope's working radius on a drum of core radius `r0` and width `W` once `Lw` metres of rope of diameter `d` are
wound on (s176): the coil's cross-section grows by about d^2 a metre (square packing), r^2 = r0^2 + d^2 Lw / (pi W).
A drum that fills turns slower in pull (torque / r) and faster in speed (omega r) as it fills.
"""
wound_radius(r0, d, W, Lw) = sqrt(r0^2 + d^2 * max(Lw, 0.0) / (pi * W))

"Tension in segment k (N): pulls only."
function tension(r::Tether, k)
    n = length(r.x) - 1; L0 = r.L / n
    d = v3(r.x[k+1]) - v3(r.x[k]); l = norm(d)
    l < 1e-9 && return 0.0, zero(V)
    u = d / l
    m = r.lin_mass * L0
    k_s = r.EA / L0
    c = 2r.zeta * sqrt(k_s * m)
    rate = dot(v3(r.v[k+1]) - v3(r.v[k]), u)
    T = k_s * (l - L0) + c * rate
    return max(T, 0.0), u
end

"Coulomb friction on a body resting on flat ground, z = 0: the force that opposes motion, or holds it still."
function ground_friction(F, v, m, mu, h)
    vh = V(v[1], v[2], 0.0); Fh = V(F[1], F[2], 0.0)
    N = m * G
    s = norm(vh)
    if s < 1e-6 && norm(Fh) <= mu * N
        return -Fh                                   # static: holds
    end
    dir = s > 1e-6 ? vh / s : Fh / norm(Fh)
    return -mu * N * dir                            # kinetic (a reversal inside a step is caught by `slide`)
end

"New velocity after a step with force F: kinetic friction stops a sliding body, never pushes it back."
function slide(v, F, m, h)
    vn = v3(v) + (h / m) * v3(F)
    (v[1] != 0 || v[2] != 0) && vn[1] * v[1] + vn[2] * v[2] < 0 && (vn = V(0.0, 0.0, vn[3]))
    vn
end

"""
    step!(r, load, dt; reel = 0.0, h = 1e-4) -> tension at the drum (N)

Advance by `dt` in substeps `h`: `reel` metres of rope wound onto the drum over the step (unstretched length shrinks).
The first particle stays at the drum; the last is the load's hook. Rope particles lie on the ground (z = 0) with friction.
"""
function step!(r::Tether, load::Load, dt; reel = 0.0, h = 1e-4)
    n = length(r.x) - 1
    # explicit springs are stable for h * omega < ~0.6; a segment's omega = sqrt(EA / L0 / (lin_mass L0)) grows as
    # the rope reels in, so the substep follows the shortest the rope gets in this step
    L0 = max(r.L - reel, 0.3) / n
    h = min(h, 0.3 * L0 / sqrt(r.EA / r.lin_mass))
    nsub = max(1, ceil(Int, dt / h)); h = dt / nsub
    T0 = 0.0
    F = Vector{V}(undef, n + 1)
    for _ in 1:nsub
        r.L = max(r.L - reel / nsub, 0.3)          # (the last 30 cm: the hook is at the drum)
        fill!(F, zero(V))
        for k in 1:n
            T, u = tension(r, k)
            F[k] += T * u; F[k+1] -= T * u
            k == 1 && (T0 = T)
        end
        m = r.lin_mass * r.L / n
        for i in 2:n                                     # free particles: gravity, ground, friction
            Fi = F[i] + V(0.0, 0.0, -m * G)
            z = r.x[i][3]
            if z <= 0.0                                  # lying on the ground: held up, rubbing
                Fi += ground_friction(F[i], r.v[i], m, r.mu_ground, h)
                Fi = V(Fi[1], Fi[2], max(Fi[3], 0.0))
            end
            v = slide(r.v[i], Fi, m, h)
            x = v3(r.x[i]) + h * v
            x[3] < 0 && (x = V(x[1], x[2], 0.0); v = V(v[1], v[2], max(v[3], 0.0)))
            r.v[i] = t3(v); r.x[i] = t3(x)
        end
        # the load at the rope's end
        Fl = F[n+1] + V(-load.m * G * load.grade / sqrt(1 + load.grade^2), 0.0, 0.0)   # downhill pull (s176)
        Fl += ground_friction(Fl, load.v, load.m, load.mu, h)
        Fl = V(Fl[1], Fl[2], 0.0)
        vl = slide(load.v, Fl, load.m, h)
        xl = v3(load.x) + h * vl
        load.v = t3(vl); load.x = t3(xl)
        r.x[n+1] = load.x; r.v[n+1] = load.v
        r.x[1] = r.anchor; r.v[1] = (0.0, 0.0, 0.0)
    end
    return T0
end

end
