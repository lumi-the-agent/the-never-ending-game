# A blade, tine or stick pushed through soil (s171, project sled: the stick brake, digging, a plank's edge).
# Nothing here knows about carts or sticks: a flat blade of width w, depth d, rake angle α (from the horizontal; a
# vertical stick is π/2) moves forward through a soil (WheelSand.SOILS: c, phi; plus unit weight γ). Two classical
# failure mechanisms, the soil takes the easier one at each depth:
#   - near the surface the soil fails UPWARD: a wedge ahead of the blade sliding on a plane at β, plus two side
#     crescents (McKyes & Ali 1977, as in McKyes, Soil Cutting and Tillage, 1985). Its force is minimised over β
#     (the soil fails on the weakest plane). For a wide blade it IS Rankine/Coulomb passive pressure;
#   - deeper down a narrow tine cannot lift the soil above it, so the soil flows SIDEWAYS round it (Godwin & Spoor
#     1977's critical depth): lateral pressure 3 Kp σv (Broms 1964, measured on laterally loaded piles in sand), plus
#     the cohesion term 3 x Rankine's 2c√Kp.
#   The critical depth dc is where the total horizontal force is least.
# Looked first (rule 6, s171): RomeoDB has land-surface soil models (ClimaLand, Terrarium: water and heat), no soil
# cutting or earth pressure; wheelsand.jl has Bekker-Wong for wheels.
module SoilTool

const G = 9.81

"""
    wedge(s, γ, d, w; α = π/2, δ = 2s.phi/3, ca = 0, q = 0, ρ = π/2, nβ = 200) -> (; H, V, β)

The upward failure of the soil ahead of a blade (McKyes-Ali): horizontal force H (N, against the motion) and
vertical V (N, + pushes the blade down) on a blade of width w (m) at depth d (m), the soil's unit weight γ (N/m3),
soil-blade friction δ, adhesion ca (Pa), surcharge q (Pa). ρ: how far round the side crescents reach (π/2 =
quarter discs, the full McKyes-Ali crescent; 0 = no side failure, the 2D wedge).
"""
function wedge(s, γ, d, w; α = π / 2, δ = 2s.phi / 3, ca = 0.0, q = 0.0, ρ = π / 2, nβ = 200)
    d <= 0 && return (; H = 0.0, V = 0.0, β = NaN)
    φ = s.phi; c = s.c
    best = (; H = Inf, V = 0.0, β = NaN)
    for k in 1:nβ
        β = (k - 0.5) / nβ * (π / 2 - φ / 2)          # β + φ < π/2 keeps cot(β + φ) > 0
        cb = cot(β); cbf = cot(β + φ)
        den = cos(α + δ) + sin(α + δ) * cbf
        den <= 0 && continue
        r = d * (cot(α) + cb)                          # where the rupture plane meets the surface
        Nγ = r / (2d) * (1 + 2r / (3w) * sin(ρ)) / den
        Nc = (1 + cb * cbf) * (1 + r / w * sin(ρ)) / den
        Nq = r / d * (1 + r / w * sin(ρ)) / den
        Na = (1 - cot(α) * cbf) / den
        F = (γ * d^2 * Nγ + c * d * Nc + q * d * Nq + ca * d * Na) * w
        H = F * sin(α + δ) + ca * d * w * cot(α)
        H < best.H && (best = (; H, V = F * cos(α + δ) - ca * d * w, β))
    end
    best
end

"Rankine's passive coefficient tan²(45° + φ/2)."
kp(φ) = tan(π / 4 + φ / 2)^2

"""
    tine(s, γ, d, w; kw...) -> (; H, V, dc)

The whole tine: the upward wedge down to the critical depth dc, sideways flow below it (Broms' 3 Kp γ z plus
3 x 2c√Kp per unit width), dc chosen where the total horizontal force is least (Godwin-Spoor).
"""
function tine(s, γ, d, w; n = 60, kw...)
    K = kp(s.phi)
    lateral(z1, z2) = w * (3K * γ * (z2^2 - z1^2) / 2 + 3 * 2s.c * sqrt(K) * (z2 - z1))
    best = (; H = Inf, V = 0.0, dc = 0.0)
    for k in 0:n
        dc = d * k / n
        wd = wedge(s, γ, dc, w; kw...)
        H = wd.H + lateral(dc, d)
        H < best.H && (best = (; H, V = wd.V, dc))
    end
    best
end

end
