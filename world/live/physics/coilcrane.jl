# The scrap crane's electromagnet (s150, idea "The scrap crane", big goal "Sparks from stones" road step 5).
#
# A coil of N turns wound as a real helix round an iron spike (the core), with a current I. The coil's field is
# Biot-Savart summed over every straight piece of the wound wire (exact per segment, no dipole shortcut). The core
# and every spike near it are soft iron rods solved TOGETHER by physics/softiron.jl in that field, so the core
# multiplies the coil's pull, and a spike already hanging from the core magnetises the next (chains, no special case).
# What a spike on the sand does is the vertical force on it against its weight: nothing here decides "lift".
#   cc = CoilCrane.Coil(; N, I, R, len, centre); CoilCrane.Hcoil(cc, p) -> A/m
#   CoilCrane.lift_check(; N, I, h)  -> which spikes on the ground (at what distance) the magnet lifts
# I looked first: em.jl has the force OF a field ON a current path, not the field a current makes; SoftIron takes
# any Hext(p). RomeoDB not searched this time (out of session time): next session look for a Biot-Savart package.
module CoilCrane

using LinearAlgebra
Base.include(@__MODULE__, joinpath(@__DIR__, "softiron.jl"))
using .SoftIron

const V3 = NTuple{3,Float64}
const RHO_IRON = 7870.0

"A wound coil: the wire's polyline (world points, m) and its current (A)."
struct Coil
    path::Vector{V3}
    I::Float64
end

"N turns of radius R wound along `len` metres of the axis +z (centred at `centre`), 24 straight pieces a turn."
function Coil(; N = 300, I = 1.0, R = 0.006, len = 0.05, centre = (0.0, 0.0, 0.0), per = 24)
    n = N * per
    path = [(centre[1] + R * cos(2pi * k / per), centre[2] + R * sin(2pi * k / per), centre[3] - len / 2 + len * k / n) for k in 0:n]
    return Coil(path, I)
end

"H (A/m) at p of a straight current I from a to b (exact; zero on the line itself)."
function hseg(A, B, p, I)
    a = (A[1] - p[1], A[2] - p[2], A[3] - p[3]); b = (B[1] - p[1], B[2] - p[2], B[3] - p[3])
    na = sqrt(a[1]^2 + a[2]^2 + a[3]^2); nb = sqrt(b[1]^2 + b[2]^2 + b[3]^2)
    c = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
    den = na * nb * (na * nb + a[1] * b[1] + a[2] * b[2] + a[3] * b[3])
    den < 1e-18 && return (0.0, 0.0, 0.0)
    s = I / (4pi) * (na + nb) / den
    return (s * c[1], s * c[2], s * c[3])
end

"The coil's H (A/m) at p: Biot-Savart over every piece of the wound wire."
function Hcoil(cc::Coil, p)
    hx = hy = hz = 0.0
    @inbounds for k in 1:length(cc.path)-1
        h = hseg(cc.path[k], cc.path[k+1], p, cc.I)
        hx += h[1]; hy += h[2]; hz += h[3]
    end
    return (hx, hy, hz)
end

"""
The crane hangs the coil (core spike inside, vertical) with the core's lower end `h` above the sand; spikes lie flat
on the sand at horizontal distances `ds` from under it. Solves core + spikes together and returns, per spike, the
upward pull over its weight (> 1: it jumps up). Spikes: length L, radius a (an iron nail).
"""
function lift_check(; N = 300, I = 1.0, h = 0.02, ds = [0.0, 0.01, 0.02, 0.03, 0.05], L = 0.05, a = 0.0015, K = 10,
                    R = 0.006, I_off = false)
    zc = h + L / 2                                   # the core's centre
    cc = Coil(; N, I = I_off ? 0.0 : I, R, len = 0.8L, centre = (0.0, 0.0, zc))
    c = V3[(0.0, 0.0, zc)]; u = V3[(0.0, 0.0, 1.0)]
    for (k, d) in enumerate(ds)                      # flat on the sand, pointing round the crane like spokes
        ang = 2pi * k / length(ds)
        push!(c, (d * cos(ang), d * sin(ang), a)); push!(u, (cos(ang + 1.0), sin(ang + 1.0), 0.0))
    end
    S = SoftIron.Rods(c, u; L, a, K)
    Hext = p -> Hcoil(cc, p)
    SoftIron.solve!(S, Hext)
    w = RHO_IRON * pi * a^2 * L * 9.81
    out = map(eachindex(ds)) do k
        F, T = SoftIron.force_torque(S, k + 1, Hext)
        # tipping: the torque about the spike's horizontal cross axis against its weight's lever when one end lies down
        ax = (-u[k+1][2], u[k+1][1], 0.0)
        (d = ds[k], up_over_weight = F[3] / w, tip_over_weight = abs(T[1] * ax[1] + T[2] * ax[2]) / (w * L / 2), Fz = F[3])
    end
    Hc = Hcoil(cc, (0.0, 0.0, zc))
    return (spikes = out, H_centre = Hc[3], NI = N * I, weight = w)
end

end
