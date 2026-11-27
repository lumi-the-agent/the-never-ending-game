# A falling plate in 2D (s128), after Andersen, Pesavento & Wang 2005 (JFM 541): body frame u along the chord,
# v across it, angle th of the chord from horizontal. Kirchhoff equations with added mass (m11 along, m22 across,
# Ia rotational), circulation lift G (translational CT + rotational CR), drag by angle (A, B) and rotational damping.
# The Munk moment (m11 - m22) u v turns the plate broadside: that is what makes it flutter or tumble by itself.
# The coefficients are as I remember them from the paper; I have NOT checked them against its text.
# RK4: dt 1/120 matches dt 1e-4 over 2 s; dt 1/60 stays finite but wanders off the path. ~0.5 us a step.
# Load: M = Module(:M); Base.include(M, "physics/fallingcard.jl"); M.Card.fall(M.Card.Plate(l = 0.2))
module Card

Base.@kwdef struct Plate
    l::Float64 = 0.02      # chord, m
    w::Float64 = 1e-4      # thickness, m
    rs::Float64 = 800.0    # solid density (paper ~800: 80 g/m² at 0.1 mm)
    rf::Float64 = 1.2      # air
    g::Float64 = 9.81
    A::Float64 = 1.4; B::Float64 = 1.0; CT::Float64 = 1.2; CR::Float64 = pi
    mu1::Float64 = 0.2; mu2::Float64 = 0.2; nu::Float64 = 1.5e-5
end

"I* = ρs w / (ρf l): small flutters (swoops), large tumbles."
Istar(p::Plate) = p.rs * p.w / (p.rf * p.l)

"Time derivative of s = (x, y, th, u, v, om), per unit span."
function deriv(p::Plate, s)
    x, y, th, u, v, om = s
    a = p.l / 2; b = p.w / 2
    m = p.rs * p.l * p.w; mf = p.rf * p.l * p.w
    m11 = pi * p.rf * b^2; m22 = pi * p.rf * a^2
    I = m * (p.l^2 + p.w^2) / 12; Ia = pi * p.rf * (a^2 - b^2)^2 / 8
    V = sqrt(u^2 + v^2) + 1e-12
    G = -0.5 * p.CT * p.l * u * v / V + 0.5 * p.CR * p.l^2 * om
    c = 0.5 * p.rf * p.l * (p.A - p.B * (u^2 - v^2) / V^2) * V
    Fu = -p.rf * G * v - (m - mf) * p.g * sin(th) - c * u
    Fv =  p.rf * G * u - (m - mf) * p.g * cos(th) - c * v
    tau = pi * p.rf * a^4 * (p.mu1 * p.nu / a^2 + p.mu2 * abs(om)) * om
    du = ((m + m22) * om * v + Fu) / (m + m11)
    dv = (-(m + m11) * om * u + Fv) / (m + m22)
    dom = ((m11 - m22) * u * v - tau) / (I + Ia)
    dx = u * cos(th) - v * sin(th); dy = u * sin(th) + v * cos(th)
    return (dx, dy, om, du, dv, dom)
end

function rk4(p::Plate, s, dt)
    k1 = deriv(p, s)
    k2 = deriv(p, s .+ (dt / 2) .* k1)
    k3 = deriv(p, s .+ (dt / 2) .* k2)
    k4 = deriv(p, s .+ dt .* k3)
    return s .+ (dt / 6) .* (k1 .+ 2 .* k2 .+ 2 .* k3 .+ k4)
end

"Drop from rest at angle th0; every 50th state."
function fall(p::Plate; th0 = 0.3, T = 3.0, dt = 1e-4)
    s = (0.0, 0.0, th0, 0.0, 0.0, 0.0)
    out = [s]
    for i in 1:round(Int, T / dt)
        s = rk4(p, s, dt)
        i % 50 == 0 && push!(out, s)
    end
    return out
end

end
