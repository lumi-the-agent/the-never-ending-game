# A boomerang that comes back (s136). One rigid body, two wings cut into blade elements. Every step each element
# gets lift and drag from ITS OWN air speed (the body's speed plus spin x radius, minus the wind): the wing that
# advances lifts more, that uneven lift is a torque, the spinning body precesses, and precession bends the flight
# into a loop. Nothing about the path is written in. (Looked first: CCBlade/DuctAPE are steady blade-element-momentum
# for rotors in axial flow, SixDOF is an aircraft 6DOF with its own aero model; a boomerang flies edgewise, every
# element sees a different flow each instant, so the element sum is direct, as in Azuma et al. 2004.)
# Element forces run as one KernelAbstractions kernel (CPU arrays here; `Mantle.Device()` arrays for many bodies).
using StaticArrays, LinearAlgebra
import Raycore
const BKA = Raycore.KernelAbstractions

const V3 = SVector{3, Float64}
const M3 = SMatrix{3, 3, Float64, 9}

"""
    boomerang_shape(; arm = 0.25, chord = 0.05, elbow = 105.0, n = 16, mass = 0.08, thick = 0.008)

Two straight wings of length `arm` from an elbow, `elbow` degrees apart, in the body's x-y plane (body z is the
cambered top face). Returns element positions (from the centre of mass), span directions, leading-edge directions
(the way spin about +z drives each element), element length, chord, mass and the inertia tensor.
"""
function boomerang_shape(; arm = 0.25, chord = 0.05, elbow = 105.0, n = 16, mass = 0.08, thick = 0.008)
    dirs = (V3(1, 0, 0), V3(cosd(elbow), sind(elbow), 0))
    ds = arm / n
    p = V3[]; s = V3[]
    for d in dirs, k in 1:n
        push!(p, (k - 0.5) * ds * d); push!(s, d)
    end
    com = sum(p) / length(p)
    p = [q - com for q in p]
    m = mass / length(p)
    I = zeros(3, 3)
    for (q, d) in zip(p, s)
        I .+= m .* (dot(q, q) .* Matrix(1.0I3) .- q * q')
        c = normalize(cross(V3(0, 0, 1), d))           # the chord's own extent adds a little
        I .+= m * chord^2 / 12 .* (Matrix(1.0I3) .- c * c')
    end
    I[3, 3] += 0; I .+= Diagonal([1, 1, 0]) .* (mass * thick^2 / 12)
    e = [(t = normalize(cross(V3(0, 0, 1), d)); dot(cross(V3(0, 0, 1), q), t) >= 0 ? t : -t) for (q, d) in zip(p, s)]
    return (; p, s, e, ds, chord, mass, I = M3(I), arm)
end
const I3 = Diagonal(ones(3))

# Lift and drag of a thin cambered blade at any angle of attack: 2 pi alpha for small angles (pi sin 2a), camber
# lift only while the leading edge leads, flat plate drag 2 sin^2 a past stall.
@inline function blade_coeffs(α, cl0)
    cl = pi * sin(2α) + cl0 * max(cos(α), 0.0)
    cd = 0.04 + 1.6 * sin(α)^2
    return cl, cd
end

"Force on one blade element (world frame) and its arm from the centre of mass."
@inline function blade_force(pk, sk, ek, R, v, ω, wind, ρ, chord, ds, cl0)
    r = R * pk; sp = R * sk; le = R * ek; nrm = R * V3(0, 0, 1)
    u = v + cross(ω, r) - wind                         # the element's speed through the air
    u = u - dot(u, sp) * sp                             # span flow does nothing
    U = norm(u)
    f = V3(0, 0, 0)
    if U > 1e-6
        α = atan(-dot(u, nrm), dot(u, le))             # air from below the blade: positive
        cl, cd = blade_coeffs(α, cl0)
        û = u / U
        lift = nrm - dot(nrm, û) * û
        ln = norm(lift)
        q = 0.5 * ρ * U^2 * chord * ds
        f = q * (ln > 1e-9 ? cl * lift / ln : V3(0, 0, 0)) - q * cd * û
    end
    return f, r
end

BKA.@kernel function blade_forces!(F, T, p, s, e, R, v, ω, wind, ρ, chord, ds, cl0)
    k = BKA.@index(Global)
    @inbounds begin
        f, r = blade_force(p[k], s[k], e[k], R, v, ω, wind, ρ, chord, ds, cl0)
        F[k] = f
        T[k] = cross(r, f)
    end
end

"""
    BoomerangBody(shape; x, v, R, ω)

A flying boomerang for the live game: `boomerang_step!` advances it with the same element forces as the kernel,
summed in a plain loop (32 elements: a kernel launch per substep costs more than the sum, ~0.6 ms vs ~5 us).
"""
mutable struct BoomerangBody
    shape::Any
    x::V3; v::V3; R::M3; ω::V3
end

function boomerang_release(shape; at, heading, speed = 22.0, spin = 120.0, layover = 15.0, aim = 2.0)
    f = V3(cos(heading), sin(heading), 0); l = V3(-sin(heading), cos(heading), 0); up = V3(0, 0, 1)
    nrm = cosd(layover) * l + sind(layover) * up
    x_ = normalize(cross(nrm, f)); y_ = cross(nrm, x_)
    BoomerangBody(shape, V3(at), speed * (cosd(aim) * f + sind(aim) * up), M3(hcat(x_, y_, nrm)), spin * nrm)
end

function boomerang_step!(b::BoomerangBody, dt; wind = V3(0, 0, 0), ρ = 1.2, cl0 = 0.4)
    sh = b.shape
    Ft = V3(0, 0, 0); Tt = V3(0, 0, 0)
    @inbounds for k in eachindex(sh.p)
        f, r = blade_force(sh.p[k], sh.s[k], sh.e[k], b.R, b.v, b.ω, wind, ρ, sh.chord, sh.ds, cl0)
        Ft += f; Tt += cross(r, f)
    end
    b.v += (Ft / sh.mass + V3(0, 0, -9.81)) * dt
    b.x += b.v * dt
    ωb = b.R' * b.ω
    ωb += inv(sh.I) * (b.R' * Tt - cross(ωb, sh.I * ωb)) * dt
    b.R = b.R * rotexp(ωb * dt)
    b.ω = b.R * ωb
    return b
end

@inline skew(w) = M3(0, w[3], -w[2], -w[3], 0, w[1], w[2], -w[1], 0)
function rotexp(w)
    θ = norm(w)
    θ < 1e-12 && return M3(I3) + skew(w)
    K = skew(w / θ)
    return M3(I3) + sin(θ) * K + (1 - cos(θ)) * K * K
end

"""
    throw_boomerang(; at, heading = 0.0, speed = 14.0, spin = 55.0, layover = 20.0, aim = 4.0, wind = zeros, seconds = 6,
                     dt = 5e-4, ρ = 1.2, cl0 = 0.4, ground = 0.0, shape = boomerang_shape(), every = 1/60)

A right-handed throw: the boomerang leaves the hand nearly upright, its flat top facing left, tipped `layover` degrees
so the top leans right, flying along `heading` (radians, 0 = +x), `aim` degrees up, spinning so the top wing goes
forward. Returns `(t, pos, R)` samples every `every` seconds until it lands (z < `ground(x, y)`) or `seconds` pass,
and `:landed` / `:flying`.
"""
function throw_boomerang(; at = V3(0, 0, 1.6), heading = 0.0, speed = 14.0, spin = 55.0, layover = 20.0, aim = 4.0,
                         wind = V3(0, 0, 0), seconds = 6.0, dt = 5e-4, ρ = 1.2, cl0 = 0.4, ground = (x, y) -> 0.0,
                         shape = boomerang_shape(), every = 1 / 60, backend = BKA.CPU())
    f = V3(cos(heading), sin(heading), 0); l = V3(-sin(heading), cos(heading), 0); up = V3(0, 0, 1)
    nrm = cosd(layover) * l + sind(layover) * up       # the cambered face looks left and a little up
    x_ = normalize(cross(nrm, f))                       # body x: a wing pointing (about) up at release
    y_ = cross(nrm, x_)
    R = M3(hcat(x_, y_, nrm))
    v = speed * (cosd(aim) * f + sind(aim) * up)
    ω = spin * nrm                                      # top wing forward: right-handed spin
    x = V3(at)
    n = length(shape.p)
    tobk(a) = (b = BKA.allocate(backend, eltype(a), length(a)); copyto!(b, a); b)
    P, S, E = tobk(shape.p), tobk(shape.s), tobk(shape.e)
    F = BKA.allocate(backend, V3, n); T = BKA.allocate(backend, V3, n)
    kern = blade_forces!(backend, 64)
    Ib, Ibinv = shape.I, inv(shape.I)
    g = V3(0, 0, -9.81)
    out = Tuple{Float64, V3, M3}[(0.0, x, R)]
    t, next = 0.0, every
    state = :flying
    while t < seconds
        kern(F, T, P, S, E, R, v, ω, V3(wind), ρ, shape.chord, shape.ds, cl0; ndrange = n)
        Ftot, Ttot = sum(Array(F)), sum(Array(T))
        v += (Ftot / shape.mass + g) * dt
        x += v * dt
        ωb = R' * ω                                     # Euler's equations in the body frame
        τb = R' * Ttot
        ωb += Ibinv * (τb - cross(ωb, Ib * ωb)) * dt
        R = R * rotexp(ωb * dt)
        ω = R * ωb
        t += dt
        if t >= next
            push!(out, (t, x, R)); next += every
        end
        if x[3] < ground(x[1], x[2]) + 0.02
            state = :landed; push!(out, (t, x, R)); break
        end
    end
    return out, state
end

"""
Closest the flight comes back to the thrower on its FIRST loop, and how far out that loop went. (s136: taking the
farthest point of the whole flight picked the drifting second loop in a wind and called good throws misses.)
"""
function boomerang_return(track, at = track[1][2])
    d = [norm((q[2] - at)[1:2]) for q in track]
    n = length(d)
    kf = something(findfirst(k -> d[k] > 2 && d[k + 1] < d[k], 1:n-1), argmax(d))      # first turn back
    ke = something(findfirst(k -> k > kf && d[k + 1] > d[k] + 1e-9 && d[k] < 0.5d[kf], 1:n-1), n)   # next way out
    kb = kf - 1 + argmin(d[kf:ke])
    return (; far = d[kf], back = d[kb], t_back = track[kb][1], t_end = track[end][1])
end
