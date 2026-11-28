# The clay-pot cell (s159, big goal road: "the clay-pot cell"; idea "The friends are the battery").
#
#   Fe | brine (outside the pot) || porous fired clay wall || CuSO4 (inside) | Cu
#
# Daniell's porous-pot cell (1836, his was zinc; with iron the standard emf is 0.34 + 0.44 = 0.78 V). The s159 power
# budget (NOTES 'Power budget') showed why the pot is needed: copper in plain sea water can only reduce the dissolved
# oxygen, j_lim = 4 F D C / delta = 0.32 A/m2 (1.5 mW from a 10 x 10 cm plate); with its own Cu2+ at 1 mol/l the
# limit is ~270 A/m2 and the clay wall, not the chemistry, decides the current.
#
# What the game simulates per pot:
# - emf from Nernst with the real concentrations: E = E0 + RT/(2F) ln([Cu2+]/[Fe2+])
# - the wall's resistance from its porosity (Archie: rho_eff = rho_w phi^-m, m = 2), the porosity from how hot the
#   kiln fired it (a typical red earthenware curve: ~30% at 900 C, vitrified ~2% by 1180 C: stoneware barely conducts)
# - concentration polarisation at the copper plate: eta = RT/(2F) ln(1 - I/I_lim), I_lim = 2 F D [Cu2+] A / delta
# - Faraday's law: every coulomb plates Cu out of the blue (it thins) and eats iron off the bar.
module PotCell

const F = 96485.0; const Rg = 8.314; const T = 293.0
const E0 = 0.337 + 0.447          # Cu2+/Cu and Fe2+/Fe standard potentials (V, vs SHE): 0.784 V
const D_CU = 0.7e-9               # Cu2+ diffusivity in water (m2/s)
const DELTA = 5e-4                # diffusion layer in still liquid (m)
const RHO_W = 0.2                 # resistivity of 1 M CuSO4 / sea water (Ohm m; both ~5 S/m)
const M_FE = 0.05585; const M_CU = 0.06355

"Apparent porosity of a fired red earthenware body vs peak kiln temperature (C): a typical firing curve."
function porosity(Tfire)
    pts = ((800.0, 0.32), (900.0, 0.30), (1000.0, 0.21), (1100.0, 0.09), (1150.0, 0.04), (1200.0, 0.015))
    Tfire <= pts[1][1] && return pts[1][2]
    for i in 1:length(pts)-1
        (a, pa), (b, pb) = pts[i], pts[i+1]
        Tfire <= b && return pa + (pb - pa) * (Tfire - a) / (b - a)
    end
    pts[end][2]
end

Base.@kwdef mutable struct Pot
    r::Float64 = 0.05             # pot radius (m)
    h::Float64 = 0.10             # wetted height (m)
    wall::Float64 = 0.008         # wall thickness (m)
    Tfire::Float64 = 950.0        # kiln peak temperature it was fired at (C)
    plate::Float64 = 0.02         # copper plate area, both faces (m2)
    V_in::Float64 = 0.5e-3        # blue liquid inside (m3)
    cu::Float64 = 1000.0          # [Cu2+] (mol/m3)
    fe::Float64 = 1.0             # [Fe2+] outside (mol/m3), grows as the iron dissolves
    V_out::Float64 = 2e-3         # brine outside (m3)
    m_fe::Float64 = 0.08          # iron bar left (kg)
    m_cu::Float64 = 0.0           # copper plated so far (kg)
end

emf(p::Pot) = E0 + Rg * T / (2F) * log(p.cu / p.fe)
wall_R(p::Pot) = RHO_W * porosity(p.Tfire)^-2 * p.wall / (2pi * p.r * p.h)
"Liquid paths to and from the wall (inside to the plate, outside to the bar), ~r / (sigma A)."
liquid_R(p::Pot) = 2 * RHO_W * p.r / (2pi * p.r * p.h)
R(p::Pot) = wall_R(p) + liquid_R(p)
I_lim(p::Pot) = 2F * D_CU * p.cu * p.plate / DELTA

"Terminal voltage at current I (A): emf - I R + the copper plate's concentration overpotential (-Inf past the limit)."
function voltage(p::Pot, I)
    I >= I_lim(p) && return -Inf
    emf(p) - I * R(p) + Rg * T / (2F) * log(1 - max(I, 0.0) / I_lim(p))
end

"(emf, R) as the circuit solvers take a cell, linearised at current I."
function linear(p::Pot, I = 0.1)
    dI = 1e-4
    Rd = -(voltage(p, I + dI) - voltage(p, I)) / dI
    (voltage(p, I) + I * Rd, Rd)
end

"Faraday's law: I amperes for dt seconds plate copper out of the blue and dissolve iron off the bar."
function run!(p::Pot, I, dt)
    n = I * dt / (2F)
    p.cu = max(p.cu - n / p.V_in, 1e-6); p.m_cu += n * M_CU
    p.fe += n / p.V_out; p.m_fe = max(p.m_fe - n * M_FE, 0.0)
    p
end

"How blue the inside looks, 0..1 (absorbance follows [Cu2+], Beer-Lambert through the pot's depth)."
blueness(p::Pot) = 1 - exp(-1.2 * p.cu / 1000 * 2p.r / 0.05)

end
