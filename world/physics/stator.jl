# The iron stator (s172, project winch: the cart's motor). How much field does an electromagnet stator put where the
# rotor's copper is, for what the clay pots can drive, and what does iron in the ROTOR do to it?
#
# Nothing new is solved here: the field coils are wound wire (coilcrane.jl's Biot-Savart over every piece of the
# wire) and all the iron (pole legs, the back yoke, the rotor's own core) is soft iron rods solved together in that
# field (softiron.jl: magnetisation, demagnetisation, saturation). The iron is a chain of short equal rods along each
# path (softiron.jl's rods share one length and radius; chains carry flux round corners, s148).
#   Stator.gap_field(; N, I, yoke, rotor_iron) -> B (T) in the air gap where the rotor's copper runs
# Compare: the two ferrite stones of the big bench motor (motor.jl big_bench) give `stones_field()` at the same place.
module Stator

using LinearAlgebra
isdefined(@__MODULE__, :CoilCrane) || Base.include(@__MODULE__, joinpath(@__DIR__, "coilcrane.jl"))
using .CoilCrane: hseg
const SoftIron = CoilCrane.SoftIron
const V3 = NTuple{3,Float64}
const MU0 = 4pi * 1e-7

"A field coil: N turns of radius R wound along the y axis over `len`, centred at `c`, 24 pieces a turn; current I."
function wind_y(; N, R, len, c, I, per = 24)
    n = N * per
    path = [(c[1] + R * cos(2pi * k / per), c[2] - len / 2 + len * k / n, c[3] + R * sin(2pi * k / per)) for k in 0:n]
    return CoilCrane.Coil(path, I)
end

"Points every `L` along a straight path from p to q (centres of the rods of a chain) and the unit axis."
function chain(p, q, L)
    d = q .- p; len = norm(collect(d)); u = d ./ len
    m = max(1, round(Int, len / L))
    return [p .+ ((k - 0.5) * len / m) .* u for k in 1:m], u
end

"""
The stator of the big bench (rotor turn 9 cm long, 5.4 cm across, turning about x): two iron pole legs along y either
side of the rotor, each wound with N turns carrying I; `yoke`: a back iron frame closing the legs round over the top
(z); `rotor_iron`: an iron core through the rotor, leaving an air gap `gap` each side. Returns B_y (T) at the middle of
the air gap on the +y side (where the rotor's copper side passes), the iron's peak M / Ms, and the field-coil copper.
"""
function gap_field(; N = 200, I = 0.8, yoke = true, rotor_iron = true, gap = 0.004, rpole = 0.036, leg = 0.08,
                   L = 0.016, a = 0.012, K = 6, coil_R = 0.016, rw = 0.5e-3)
    cs = V3[]; us = V3[]
    function add!(p, q)
        c, u = chain(p, q, L)
        append!(cs, c); append!(us, fill(u, length(c)))
    end
    top = rpole + leg                                 # the legs' outer ends (y = +-top)
    add!((0.0, rpole, 0.0), (0.0, top, 0.0))          # +y leg, magnetised outward-in by its coil
    add!((0.0, -top, 0.0), (0.0, -rpole, 0.0))        # -y leg
    if yoke                                           # up from each leg's end, across the top
        zt = 0.11
        add!((0.0, top + a, 0.0), (0.0, top + a, zt))
        add!((0.0, top + a, zt), (0.0, -top - a, zt))
        add!((0.0, -top - a, zt), (0.0, -top - a, 0.0))
    end
    if rotor_iron                                     # the rotor's core: from pole face to pole face less two gaps
        add!((0.0, -rpole + gap, 0.0), (0.0, rpole - gap, 0.0))
    end
    S = SoftIron.Rods(cs, us; L, a, K)
    # both coils drive flux the same way round the loop: -y leg towards +y at its face, +y leg away from the rotor
    c1 = wind_y(; N, R = coil_R, len = 0.8leg, c = (0.0, rpole + leg / 2, 0.0), I)
    c2 = wind_y(; N, R = coil_R, len = 0.8leg, c = (0.0, -rpole - leg / 2, 0.0), I)
    Hext = p -> CoilCrane.Hcoil(c1, p) .+ CoilCrane.Hcoil(c2, p)
    SoftIron.solve!(S, Hext)
    probe = (0.0, rpole - gap / 2, 0.0)
    Hp = Hext(probe) .+ SoftIron.H(S, probe)
    wire = 2 * N * 2pi * coil_R
    R = 1.7e-8 * wire / (pi * rw^2)
    return (B = MU0 * Hp[2], Mmax = maximum(abs, S.M) / S.Ms, rods = length(cs), wire_m = wire, R_coils = R, NI = N * I)
end

"""
The torque about the axle (N m) on a motor.jl rotor at angle θ carrying I in its N turns, with or without an iron core
through the coil (a bar along the coil's axis, from -half to +half, radius a, as a chain of soft iron rods). The iron
is magnetised by the stones AND the rotor's own coil (solved together); the torque on the rotor as one rigid body is
what the STONES' field does to it: mu0 q H on every face charge of its iron, and I dl x B on its copper (the coil's
pull on its own iron is internal and cancels). `Hst(p)` = the stones' H (A/m), `Bst(p)` their B (T).
"""
function rotor_torque(b, θ, I, Hst, Bst; iron = true, half = 0.032, a = 0.012, L = 0.016, K = 6)
    M = isdefined(Main, :Motor) ? Main.Motor : error("load physics/motor.jl first")
    path = M.coil_path(b, θ)
    _, T = M.EM.force(p -> collect(Bst(p)), path, 1.0)
    τ = b.N * I * T[1]
    iron || return (τ = τ, τ_cu = τ, τ_fe = 0.0)
    ax = Tuple(M.Rx(θ) * [0.0, 1.0, 0.0])              # the coil's axis at θ (the turn lies in x-z at θ = 0)
    c, u = chain(ax .* (-half), ax .* half, L)
    S = SoftIron.Rods(c, fill(u, length(c)); L, a, K)
    NI = b.N * I
    Hcoil(p) = (h = (0.0, 0.0, 0.0); for k in 1:length(path)-1; h = h .+ hseg(path[k], path[k+1], p, NI); end; h)
    SoftIron.solve!(S, p -> Hst(p) .+ Hcoil(p))
    τfe = 0.0
    for i in 1:SoftIron.nrods(S)
        q = SoftIron.charges(S, i)
        for f in 0:S.K
            q[f+1] == 0.0 && continue
            p = SoftIron.face(S, i, f)
            F = MU0 * q[f+1] .* Hst(p)
            τfe += p[2] * F[3] - p[3] * F[2]           # (p x F) about x
        end
    end
    return (τ = τ + τfe, τ_cu = τ, τ_fe = τfe)
end

end
