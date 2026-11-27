# A rigid wheel on soft ground (s157, big goal road step 'wheels with rolling contact on the terrain').
# Nothing here knows about carts or friends. A wheel (radius, width) carries a load on a soil and turns with some slip;
# the soil's measured constants decide everything (Wong, Theory of Ground Vehicles, ch. 2; Wong & Reece 1967):
#   - normal stress under the rim from Bekker's pressure-sinkage law  sigma = (kc/b + kphi) z^n  at each point of the
#     contact arc (entry angle theta1, rear angle 0 for a rigid wheel in loose ground), with the stress peak moved
#     forward to theta_m = (c1 + c2 i) theta1 when the wheel slips (Wong-Reece);
#   - shear stress from Mohr-Coulomb and Janosi-Hanamoto: tau = (c + sigma tan phi)(1 - exp(-j / K)), j the soil's
#     shear displacement at that point, which grows with slip;
#   - integrated over the arc: the load the soil carries (sets theta1, so the sinkage), the drawbar pull (thrust minus
#     the soil pushed ahead), and the torque the axle must give.
# So a narrow rim sinks and bogs, a wide one rides; a wheel that slips digs; a towed wheel costs a pull; on clay or
# snow the same code gives their answers. Looked first (rule 6): RomeoDB has land-surface soil models (ClimaLand,
# Terrarium: water and heat in soil), no terramechanics; snowball.jl had Bekker's sinkage for a ball only.
module WheelSand

"""
Soils: Bekker n, kc (N/m^(n+1)), kphi (N/m^(n+2)), cohesion c (Pa), friction angle phi (rad), shear deformation
modulus K (m). Wong, Theory of Ground Vehicles (4th ed.), Table 2.3; K from his shear tests (sand ~1-2.5 cm).
"""
const SOILS = Dict(
    :dry_sand   => (; n = 1.1, kc = 0.99e3,  kphi = 1528.43e3, c = 1.04e3, phi = deg2rad(28.0), K = 0.025),
    :sandy_loam => (; n = 0.7, kc = 5.27e3,  kphi = 1515.04e3, c = 1.72e3, phi = deg2rad(29.0), K = 0.025),
    :snow       => (; n = 1.6, kc = 4.37e3,  kphi = 196.72e3,  c = 1.03e3, phi = deg2rad(19.7), K = 0.04),
    :clay       => (; n = 0.5, kc = 13.19e3, kphi = 692.15e3,  c = 4.14e3, phi = deg2rad(13.0), K = 0.06),
)

bekker(s, b, z) = (s.kc / b + s.kphi) * max(z, 0.0)^s.n

"""
    arc(s, r, b, θ1, i; nq = 240) -> (; W, DP, T)

Integrate the stresses over the contact arc of a wheel (radius r, width b) that enters the ground at θ1 and slips
by i (0: rolling freely over the ground, 1: spinning in place, < 0: dragged). W: vertical load the soil carries (N);
DP: drawbar pull (N, forward); T: torque the soil puts against the wheel's turning (N m).
"""
function arc(s, r, b, θ1, i; nq = 240, c1 = 0.43, c2 = 0.32)
    θm = clamp(c1 + c2 * i, 0.05, 0.95) * θ1
    W = 0.0; DP = 0.0; T = 0.0; dθ = θ1 / nq
    for q in 1:nq
        θ = (q - 0.5) * dθ
        θe = θ >= θm ? θ : θ1 - (θ / θm) * (θ1 - θm)          # rear part mirrors the front's stress (Wong-Reece)
        σ = bekker(s, b, r * (cos(θe) - cos(θ1)))
        j = r * ((θ1 - θ) - (1 - i) * (sin(θ1) - sin(θ)))      # shear displacement of the soil at θ
        τ = (s.c + σ * tan(s.phi)) * (1 - exp(-abs(j) / s.K)) * sign(j)
        W += (σ * cos(θ) + τ * sin(θ)) * dθ
        DP += (τ * cos(θ) - σ * sin(θ)) * dθ
        T += τ * dθ
    end
    (; W = r * b * W, DP = r * b * DP, T = r^2 * b * T)
end

"""
    wheel(s, W, r, b, i) -> (; z, θ1, DP, T)

A wheel carrying `W` newtons at slip `i`: the entry angle (so the sinkage z = r (1 - cos θ1)) where the soil carries
exactly the load, then its drawbar pull and torque.
"""
function wheel(s, W, r, b, i)
    lo = 1e-5; hi = 1.4
    arc(s, r, b, hi, i).W < W && return (; z = r, θ1 = hi, DP = -Inf, T = Inf, bogged = true)
    for _ in 1:60
        mid = (lo + hi) / 2
        arc(s, r, b, mid, i).W < W ? (lo = mid) : (hi = mid)
    end
    θ1 = (lo + hi) / 2; a = arc(s, r, b, θ1, i)
    (; z = r * (1 - cos(θ1)), θ1, DP = a.DP, T = a.T, bogged = false)
end

"A towed wheel (no torque at the axle): find the slip where the soil's torque is zero; the pull it costs is -DP."
function towed(s, W, r, b)
    lo = -0.9; hi = 0.5
    for _ in 1:50
        mid = (lo + hi) / 2
        wheel(s, W, r, b, mid).T > 0 ? (hi = mid) : (lo = mid)
    end
    w = wheel(s, W, r, b, (lo + hi) / 2)
    (; z = w.z, slip = (lo + hi) / 2, resistance = -w.DP)
end

"""
    cart_climb(; soil, mass, wheels = 4, r, b, slope_deg, pullers_N)

Pulling a cart up a slope: each towed wheel's resistance at its share of the weight plus the weight's component down
the slope, against what the pullers can give (each: its own weight times its feet's friction on that ground).
"""
function cart_climb(; soil = SOILS[:dry_sand], mass = 35.0, wheels = 4, r = 0.2, b = 0.03, slope_deg = 15.0,
                    pullers = Float64[])
    α = deg2rad(slope_deg); W = mass * 9.81 * cos(α) / wheels
    t = towed(soil, W, r, b)
    need = wheels * t.resistance + mass * 9.81 * sin(α)
    can = sum(m * 9.81 * tan(soil.phi) * 0.8 for m in pullers; init = 0.0)   # feet slip short of the full angle
    (; sinkage_cm = round(100t.z, digits = 2), roll_N = round(wheels * t.resistance, digits = 1),
       grade_N = round(mass * 9.81 * sin(α), digits = 1), need_N = round(need, digits = 1), can_N = round(can, digits = 1),
       climbs = can > need)
end

end # module
