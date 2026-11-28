# s182 (project plante): forming lead plates the way Gaston Plante did (1859): two lead sheets in dilute sulphuric acid,
# charged from the pots until they fizz, the leads swapped, charged again. Each plate is an electrode whose current
# splits between its solid reaction and splitting water by their own Tafel kinetics at the plate's one potential;
# nothing says "x % goes to gas". What is formed is a porous layer: on the positive it turns to brown PbO2, and a
# reversal reduces it to spongy lead, which re-opens the lead underneath (its passivating film is gone) so the next
# anodic half deepens the layer. Leave a plate on charge and its fresh film passivates, the potential climbs and the
# current goes to oxygen: bubbles instead of capacity.
#
# Kinetics (25 C, 1.2 g/cm3 acid, potentials vs SHE; orders from Pavlov, "Lead-Acid Batteries: Science and
# Technology" (2011) ch. 2-3, and Bockris & Reddy for H2 on Pb):
#   positive, anodic:  PbSO4 -> PbO2   E0 1.69 V, b 0.04 V/dec, i0 0.1 A/m2 of true surface
#                      O2 on PbO2      E0 1.229 V, b 0.12 V/dec, i0 1e-5 A/m2 (1e-9 A/cm2)
#   negative, cathodic: PbSO4 -> Pb    E0 -0.356 V, b 0.04 V/dec, i0 0.1 A/m2
#                      H2 on Pb        E0 0, b 0.12 V/dec, i0 1e-8 A/m2 (1e-12 A/cm2, lead's huge H2 overpotential)
# The surface the solid reactions see is the formed layer's inner surface (a_v x depth x the share not yet
# converted) plus, on the positive, the bare lead under the layer, which passivates under its own fresh film
# (exp(-film / 0.15 um)). One Pb atom is 4 electrons between Pb and PbO2 (via PbSO4).
module Plante

const F = 96485.0
const C_PB = 11340 / 0.2072 * 0.5       # mol of lead per m3 of formed layer (spongy, porosity 0.5)
const A_V = 2.0e5                        # inner surface of the formed layer, m2 per m3 (spongy lead / PbO2, 5 um grains)
const DELTA_P = 0.15e-6                  # m: the fresh film on bare lead that halves... e-folds its current

Base.@kwdef struct Kin
    E_s::Float64 = 1.69;  b_s::Float64 = 0.04;  i0_s::Float64 = 0.1      # PbSO4/PbO2
    E_n::Float64 = -0.356; b_n::Float64 = 0.04; i0_n::Float64 = 0.1      # PbSO4/Pb
    E_O2::Float64 = 1.229; b_O2::Float64 = 0.12; i0_O2::Float64 = 1e-5
    E_H2::Float64 = 0.0;  b_H2::Float64 = 0.12; i0_H2::Float64 = 1e-8
end

"One plate: formed depth d (m), share x of the layer that is PbO2 (the rest spongy Pb), fresh film on the bare lead."
mutable struct Plate
    d::Float64
    x::Float64
    film::Float64
end
Plate() = Plate(0.0, 0.0, 0.0)

tafel(i0, E, E0, b) = i0 * 10^((E - E0) / b)

"Anodic split at potential E (A per m2 of plate): (into the layer, into new depth, oxygen)."
function anodic(p::Plate, E, k::Kin)
    s = tafel(k.i0_s, E, k.E_s, k.b_s)
    (s * A_V * p.d * (1 - p.x), s * exp(-p.film / DELTA_P), tafel(k.i0_O2, E, k.E_O2, k.b_O2) * (1 + A_V * p.d * p.x))
end

"Cathodic split at potential E (A per m2, positive numbers): (oxide reduced to spongy lead, hydrogen)."
function cathodic(p::Plate, E, k::Kin)
    (tafel(k.i0_n, -E, -k.E_n, k.b_n) * A_V * p.d * p.x, tafel(k.i0_H2, -E, -k.E_H2, k.b_H2) * (1 + A_V * p.d * (1 - p.x)))
end

"The potential at which the plate passes current density j (A/m2): bisection on the monotone total."
function potential(f, p, j, k; lo = -3.0, hi = 4.0, up = true)
    for _ in 1:60
        m = (lo + hi) / 2
        t = sum(f(p, m, k))
        (t < j) == up ? (lo = m) : (hi = m)
    end
    (lo + hi) / 2
end
E_pos(p, j, k) = potential(anodic, p, j, k; up = true)
E_neg(p, j, k) = potential(cathodic, p, j, k; up = false)

"""
    form(; schedule, E_src, R_src, area, R_acid, dt) -> NamedTuple of time series

Charge two plates (area m2 each, both faces) from a source (the pots: E_src V behind R_src ohm). `schedule` is a list
of (hours, polarity): polarity +1 makes plate A the positive. The current is the one where source and cell agree.
"""
function form(; schedule = [(1.0, 1), (1.0, -1), (1.0, 1)], E_src = 5.2, R_src = 3.8, area = 0.03, R_acid = 0.05,
              dt = 5.0, k = Kin(), plates = (Plate(), Plate()))
    A, B = plates
    last = plates[1].d > 0 || plates[2].d > 0 ? schedule[1][2] : 0     # plates passed in go on where they were
    out = (t = Float64[], I = Float64[], V = Float64[], pol = Int[], O2 = Float64[], H2 = Float64[],
           dA = Float64[], xA = Float64[], dB = Float64[], xB = Float64[], front = Float64[])
    t = 0.0
    for (hours, pol) in schedule
        pos, neg = pol > 0 ? (A, B) : (B, A)
        pol != last && (pos.film = 0.0)      # the reversal just reduced its oxide to spongy lead: no passive film
        last = pol
        for _ in 1:round(Int, hours * 3600 / dt)
            lo, hi = 0.0, E_src / R_src
            for _ in 1:50                    # source and cell agree on the current
                I = (lo + hi) / 2; j = I / area
                V = E_pos(pos, j, k) - E_neg(neg, j, k) + I * R_acid
                E_src - I * R_src > V ? (lo = I) : (hi = I)
            end
            I = (lo + hi) / 2; j = I / area
            Ep = E_pos(pos, j, k); En = E_neg(neg, j, k)
            jl, jf, jo = anodic(pos, Ep, k)
            jr, jh = cathodic(neg, En, k)
            nl = C_PB * pos.d                # mol/m2 in the layer before the step
            new = jf * dt / (4F) / C_PB      # m of new depth, born as PbO2
            ox = pos.x * nl + (jl + jf) * dt / (4F)
            pos.d += new; pos.film += new
            pos.x = clamp(ox / (C_PB * pos.d), 0.0, 1.0)
            neg.d > 0 && (neg.x = clamp(neg.x - jr * dt / (4F) / (C_PB * neg.d), 0.0, 1.0))
            t += dt
            push!(out.t, t); push!(out.I, I); push!(out.V, Ep - En + I * R_acid); push!(out.pol, pol)
            push!(out.O2, jo * area / (4F)); push!(out.H2, jh * area / (2F))      # mol/s of gas
            push!(out.dA, A.d); push!(out.xA, A.x); push!(out.dB, B.d); push!(out.xB, B.x); push!(out.front, jf / j)
        end
    end
    (; out..., A, B, area)
end

"What the formed pair holds (A h): oxide on the positive against spongy lead on the negative, 2 e- each way on discharge."
function capacity(r)
    pos, neg = r.pol[end] > 0 ? (r.A, r.B) : (r.B, r.A)
    n = min(C_PB * pos.d * pos.x, C_PB * neg.d * (1 - neg.x)) * r.area
    n * 2F / 3600
end

end
