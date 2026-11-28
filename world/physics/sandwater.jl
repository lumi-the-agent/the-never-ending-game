# How damp the beach sand is, and what that does to its strength (s171, project sled: the same dune runs differently
# near the water). The sea's level is the water table under the beach; in still weather the water in the sand sits in
# hydrostatic equilibrium with it, so a point h metres above the sea holds water at a suction head of h (Richards'
# equation at rest). The sand's water retention curve (van Genuchten 1980, measured parameters) says how much water
# that is; the suction stress of the water menisci between the grains (Lu & Likos 2006: σs = suction x effective
# saturation) is an apparent cohesion c_app = σs tan φ (Vanapalli 1996). So:
#   - at the waterline (h = 0) the sand is saturated, the suction is zero: no apparent cohesion, it slumps;
#   - a little above it the menisci pull hardest: damp sand holds walls (sandcastles, the casting's print);
#   - high up the dune the pores have drained: dry loose sand.
# Rain (wetting from above) and the sun drying the top are not in yet: still-weather equilibrium only.
# Looked first (rule 6): ClimaLand has van Genuchten retention for its land model (Soil.pressure_head), too big a
# dependency for two closed-form lines; nothing on suction stress or apparent cohesion.
module SandWater

const ρW, G = 1000.0, 9.81

"""
Water retention (van Genuchten α 1/m, n; residual and saturated volumetric water θr, θs) and dry density (kg/m3).
Carsel & Parrish (1988), the USDA mean for sand; fine beach sand holds water to a higher suction (smaller α): the
'fine_sand' row is the Lu & Likos (2004, Unsaturated Soil Mechanics, Table 12.1) fine sand.
"""
const RETENTION = Dict(
    :sand      => (; α = 14.5, n = 2.68, θr = 0.045, θs = 0.43, ρd = 1600.0),
    :fine_sand => (; α = 4.0,  n = 4.0,  θr = 0.05,  θs = 0.38, ρd = 1650.0),
)

"Effective saturation at suction head ψ (m of water, >= 0)."
se(v, ψ) = (1 + (v.α * max(ψ, 0.0))^v.n)^(-(1 - 1 / v.n))

"""
    damp(s, h; v = RETENTION[:fine_sand]) -> (; soil, γ, θ, Se, c_app)

The soil `s` (WheelSand.SOILS row) at h metres above the water table: its cohesion raised by the suction stress,
its unit weight by the water it holds.
"""
function damp(s, h; v = RETENTION[:fine_sand])
    S = se(v, h); θ = v.θr + S * (v.θs - v.θr)
    c_app = ρW * G * max(h, 0.0) * S * tan(s.phi)
    γ = (v.ρd + ρW * θ) * G
    h <= 0 && (γ -= ρW * G)          # at and below the water table the grains are buoyed: effective (submerged) weight
    (; soil = (; s..., c = s.c + c_app), γ, θ, Se = S, c_app)
end

end
