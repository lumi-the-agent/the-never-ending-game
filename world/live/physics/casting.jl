# Casting lead in the beach (s170, idea 'Cast your own lead plates in the beach', project casting): molten lead
# poured onto the sand runs downhill, pools in whatever hole is there (a pressed wheel, a foot, a plank end: the sand
# field's own casts), loses its heat into the sand under it and the air over it, and freezes from where it is
# thinnest. What comes out is the hole it filled, as far as the lead got before it froze: pour too slowly or into a
# thin channel and it freezes on the way (a misrun), the way real sand casting goes.
#
# Model (per cell of a height field, the mould = the sand surface `ground`):
#   - FLOW: virtual pipes between neighbours (O'Brien & Hodgins 1995, Mei et al. 2007), cross-section = the upwind
#     liquid depth, so the front spreads at shallow-water speed sqrt(g d). Liquid lead does not wet sand and its
#     surface tension is high (0.45 N/m): a front cannot advance thinner than ~2 capillary lengths (2 x 2.1 mm), which
#     is how thick a puddle of lead stands on flat ground.
#   - HEAT: lead conducts 30 W/m K, so a cell's column is one temperature (Biot ~ 1e-3). Into the sand: the contact
#     flux of a semi-infinite solid, e (T - T0) / sqrt(pi t) since the cell was wetted (e = sand's effusivity); into
#     the air: convection + radiation. Superheat goes first, then the latent heat freezes liquid into solid.
#   - CHOKE: a cell more than half frozen passes no more liquid (the critical solid fraction of a pure metal's
#     fluidity test).
# Looked first (rule 6): RomeoDB has depression filling (Geomorphometry.filldepressions fills every pit to its brim,
# not a poured volume that freezes on the way) and climate-scale enthalpy sea ice (ClimaSeaIce); no casting or
# metal-flow solver. CPU arrays now; the same loops go to KernelAbstractions when it runs in the game.
module Casting

const g = 9.81
const LEAD = (; rho_l = 10660.0, rho_s = 11340.0, c = 142.0, L = 23_000.0, Tm = 327.5, gamma = 0.45, eps = 0.4)
const SANDS = (; damp = (; e = 1200.0, T0 = 15.0), dry = (; e = 600.0, T0 = 20.0))   # effusivity sqrt(k rho c)

mutable struct Pour
    ground::Matrix{Float64}   # mould surface (m)
    dl::Matrix{Float64}       # liquid depth (m)
    ds::Matrix{Float64}       # frozen depth (m), on top of ground
    T::Matrix{Float64}        # liquid temperature (C)
    tw::Matrix{Float64}       # seconds since first wetted (-1: never)
    fx::Matrix{Float64}       # flux i -> i+1 (m3/s), size (nx-1, ny)
    fy::Matrix{Float64}       # flux j -> j+1
    dx::Float64
    t::Float64
    poured::Float64           # m3 of liquid poured so far
end
function Pour(ground::AbstractMatrix, dx)
    nx, ny = size(ground)
    z = zeros(nx, ny)
    Pour(Float64.(ground), copy(z), copy(z), copy(z), fill(-1.0, nx, ny), zeros(nx - 1, ny), zeros(nx, ny - 1), dx, 0.0, 0.0)
end

hmin(m = LEAD) = 2 * sqrt(m.gamma / (m.rho_l * g))             # 4.2 mm for lead
frozen(p, i, j) = p.ds[i, j] > p.dl[i, j] * LEAD.rho_l / LEAD.rho_s     # more than half the column solid

"""
    step!(p, dt; src = nothing, rate = 0.0, Tpour = 400.0, sand = SANDS[:damp], damp = 2.0)

One step: pour `rate` m3/s at cell `src` (a stream from the ladle at Tpour), let the liquid flow, lose heat, freeze.
"""
function step!(p::Pour, dt; src = nothing, rate = 0.0, Tpour = 400.0, sand = SANDS[:damp], damp = 2.0, m = LEAD)
    nx, ny = size(p.dl); dx = p.dx; A = dx^2; hm = hmin(m)
    if src !== nothing && rate > 0
        i, j = src; dv = rate * dt / A
        p.T[i, j] = (p.dl[i, j] * p.T[i, j] + dv * Tpour) / (p.dl[i, j] + dv)
        p.dl[i, j] += dv; p.poured += rate * dt
        p.tw[i, j] < 0 && (p.tw[i, j] = 0.0)
    end
    η(i, j) = p.ground[i, j] + p.ds[i, j] + p.dl[i, j]
    # a pipe a -> b carries liquid only out of a liquid, unchoked cell, and onto a dry one only above the front's depth
    open(a, b) = p.dl[a...] > 1e-6 && !frozen(p, a...) && (p.dl[b...] > 1e-6 || p.dl[a...] > hm)
    fr = exp(-damp * dt)
    for j in 1:ny, i in 1:nx-1
        a, b = (i, j), (i + 1, j)
        dh = η(a...) - η(b...)
        up, dn = dh > 0 ? (a, b) : (b, a)
        f = (p.fx[i, j] + dt * g * dx * p.dl[up...] * dh / dx) * fr
        p.fx[i, j] = open(up, dn) && sign(f) == sign(dh) ? f : 0.0
    end
    for j in 1:ny-1, i in 1:nx
        a, b = (i, j), (i, j + 1)
        dh = η(a...) - η(b...)
        up, dn = dh > 0 ? (a, b) : (b, a)
        f = (p.fy[i, j] + dt * g * dx * p.dl[up...] * dh / dx) * fr
        p.fy[i, j] = open(up, dn) && sign(f) == sign(dh) ? f : 0.0
    end
    # no cell gives more than it has
    out = zeros(nx, ny)
    for j in 1:ny, i in 1:nx-1
        f = p.fx[i, j]; f > 0 ? (out[i, j] += f) : (out[i + 1, j] -= f)
    end
    for j in 1:ny-1, i in 1:nx
        f = p.fy[i, j]; f > 0 ? (out[i, j] += f) : (out[i, j + 1] -= f)
    end
    K = map((o, d) -> o * dt > d * A ? d * A / (o * dt) : 1.0, out, p.dl)
    H = p.dl .* p.T; V = copy(p.dl)                             # heat (m C) and volume (m) per cell, moved upwind
    move(a, b, f) = (v = f * dt / A; V[a...] -= v; V[b...] += v; H[a...] -= v * p.T[a...]; H[b...] += v * p.T[a...])
    for j in 1:ny, i in 1:nx-1
        f = p.fx[i, j]
        f > 0 ? (p.fx[i, j] = f *= K[i, j]; move((i, j), (i + 1, j), f)) : f < 0 && (p.fx[i, j] = f *= K[i + 1, j]; move((i + 1, j), (i, j), -f))
    end
    for j in 1:ny-1, i in 1:nx
        f = p.fy[i, j]
        f > 0 ? (p.fy[i, j] = f *= K[i, j]; move((i, j), (i, j + 1), f)) : f < 0 && (p.fy[i, j] = f *= K[i, j + 1]; move((i, j + 1), (i, j), -f))
    end
    σ = 5.67e-8; T0 = sand.T0
    for k in eachindex(V)
        v = max(V[k], 0.0)
        p.T[k] = v > 1e-9 ? H[k] / v : p.T[k]
        p.dl[k] = v
        (v > 1e-9 || p.ds[k] > 0) || continue
        p.tw[k] < 0 && (p.tw[k] = 0.0)
        p.tw[k] += dt
        Tc = v > 1e-9 ? p.T[k] : m.Tm                          # the column's temperature (a frozen one sits at Tm here)
        q = sand.e * (Tc - T0) / sqrt(pi * p.tw[k]) +         # into the sand under it
            10.0 * (Tc - T0) + m.eps * σ * ((Tc + 273.15)^4 - (T0 + 273.15)^4)    # into the air over it
        v > 1e-9 || continue
        E = q * dt                                             # J/m2 this step
        sup = m.rho_l * m.c * v * (p.T[k] - m.Tm)              # superheat left, J/m2
        if E <= sup
            p.T[k] -= E / (m.rho_l * m.c * v)
        else
            p.T[k] = m.Tm
            dsol = min((E - sup) / (m.rho_s * m.L), v * m.rho_l / m.rho_s)   # freeze what the rest of the heat takes
            p.ds[k] += dsol; p.dl[k] -= dsol * m.rho_s / m.rho_l
        end
    end
    p.t += dt
    p
end

"""
    pour!(p; src, volume, rate, Tpour, sand, dt = 1e-3, tmax = 120) -> p

Pour `volume` m3 at `rate` m3/s into cell `src`, then wait until everything has frozen (or tmax).
"""
function pour!(p::Pour; src, volume, rate, Tpour = 400.0, sand = SANDS[:damp], dt = 1e-3, tmax = 120.0)
    while p.t < tmax
        r = p.poured < volume ? min(rate, (volume - p.poured) / dt) : 0.0
        step!(p, dt; src, rate = r, Tpour, sand)
        r == 0 && all(<(1e-7), p.dl) && break
    end
    p
end

"The casting: its mass (kg), volume (m3), how many cells and how thick at most."
casting(p::Pour) = (; kg = sum(p.ds) * p.dx^2 * LEAD.rho_s, cm3 = 1e6 * sum(p.ds) * p.dx^2,
                    cells = count(>(1e-5), p.ds), max_mm = 1000 * maximum(p.ds), t_s = p.t)

end
