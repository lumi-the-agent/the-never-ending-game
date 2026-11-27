# Fire (s152, project fire): heat and burning carried by real things. Every fuel body (a log, a fence post, a plank,
# a tuft of grass, a stool) has a temperature, a fuel mass, moisture and a material; burning bodies heat the others by
# radiation and by their plume, wind leans the flames, and wood loses strength as it chars.
#
# Per body (lumped over a heated skin, so a thick post heats at its surface like real wood does):
#   m_s c_p dT/dt = q_rad,in A_seen + q_conv,in A - eps sigma (T^4 - T_amb^4) A - h (T - T_amb) A
#   below 100 C the heat raises T; at 100 C it boils the body's water first (latent 2.26 MJ/kg): wet wood will not catch
#   T > T_ig (piloted ignition of the surface): it burns. Mass loss m' = G A_burn (G per material); HRR Q = m' dH_c.
# A flame of HRR Q over a fuel of size D stands L = 0.235 Q^(2/5) - 1.02 D tall (Heskestad, Q in kW) and leans downwind
# (Thomas: cos(theta) = 0.7 u*^-0.49, u* = u / (g Q / (rho cp T D))^(1/3)); it radiates chi_r Q from its centre as a
# point source (Modak): q'' = chi_r Q cos(phi) / (4 pi R^2) onto a target seeing it at distance R, angle phi.
# A target inside the flame or its plume gets h_f (T_flame - T) besides.
# Wood chars inward at beta = 0.65 mm/min (Eurocode 5, softwood); its strength is the section left after
# d_ef = char + 7 mm (EN 1995-1-2 reduced cross-section method), so a burning post's bending capacity falls as
# (b - 2 d_ef)(t - 2 d_ef)^2 / (b t^2) and it breaks under its own load when that passes 1 / safety.
#
# Looked at (RomeoDB s152): WildlandFire.jl (ModelingToolkit Rothermel/Clark spread over landscapes), Wildfires.jl
# (Rothermel rate of spread, KernelAbstractions): both spread over fuel BEDS by rate, not heat between objects; the
# grass bed may later take Rothermel's spread rate from Wildfires.jl. Nothing for heat and char of single bodies.

const FIRE_SIGMA = 5.670374f-8
const FIRE_TAMB = 293f0
const FIRE_TFLAME = 1100f0          # K, a wood flame's mean temperature
const FIRE_CHI_R = 0.3f0            # radiated fraction of the heat release (wood, small fires 0.25-0.35)
const FIRE_HF = 25f0                # W/m^2K, flame/plume contact on a body inside it
const FIRE_LATENT = 2.26f6          # J/kg, water
const FIRE_EPS_FLAME = 0.3f0        # emissivity of a small wood flame
const FIRE_KAPPA = 0.8f0            # 1/m, absorption coefficient of a wood flame (its emissivity 1 - exp(-kappa D))
const FIRE_QCONV = 8f3              # W/m^2, a flame's convective heat back to its own fuel
const FIRE_TCHAR = 773f0            # K, a burning char surface
const FIRE_MCRIT = 3f-3             # kg/m^2s, below this wood's flame goes out (critical mass flux 2.5-4 g/m^2s)

"A fuel's properties: density, heat capacity, piloted ignition, heat of combustion, burning mass flux, char rate."
struct FuelMaterial
    name::Symbol
    rho::Float32        # kg/m^3
    cp::Float32         # J/kgK
    T_ig::Float32       # K, surface ignition under a pilot flame
    dHc::Float32        # J/kg, effective heat of combustion
    G::Float32          # kg/m^2s, burning mass flux of the exposed surface
    beta::Float32       # m/s, char rate (0 = does not char)
    eps::Float32        # emissivity
    skin::Float32       # m, the heated layer the lumped temperature stands for
    Lg::Float32         # J/kg, heat of gasification (wood with its char layer ~1.8 MJ/kg)
end

const FUELS = Dict(
    :wood  => FuelMaterial(:wood, 450f0, 1700f0, 623f0, 1.5f7, 0.011f0, 0.65f-3 / 60, 0.9f0, 0.006f0, 1.8f6),
    :grass => FuelMaterial(:grass, 300f0, 1500f0, 573f0, 1.6f7, 0.03f0, 0f0, 0.9f0, 0.001f0, 0.6f6),   # dry blades: thin, all skin
    :leaves => FuelMaterial(:leaves, 250f0, 1500f0, 553f0, 1.6f7, 0.03f0, 0f0, 0.9f0, 0.0008f0, 0.6f6),
    :stone => FuelMaterial(:stone, 2600f0, 800f0, 1f9, 0f0, 0f0, 0f0, 0.9f0, 0.02f0, 1f9),           # heats, never burns
)

"""
One body that can heat and burn. `pos` its centre, `size` (width, depth, height) of its box, `fuel` the dry fuel mass
left (kg), `water` its moisture (kg), `char` the char depth (m), `load` the share of its bending capacity its own use
needs (a post holding up a fence rail: 0.3), `broken` once the char took more than that.
"""
mutable struct FireBody
    id::Int
    mat::FuelMaterial
    pos::NTuple{3,Float32}
    size::NTuple{3,Float32}
    T::Float32
    fuel::Float32
    water::Float32
    char::Float32
    burning::Bool
    load::Float32
    broken::Bool
    ignited_at::Float32
    broke_at::Float32
    mflux::Float32      # kg/m^2s it burns at now (from the heat balance of its surface)
end

function fire_body(id, mat::Symbol, pos, size; moisture = 0.12f0, load = 0f0, T = FIRE_TAMB, burning = false)
    m = FUELS[mat]
    dry = m.rho * size[1] * size[2] * size[3]
    # only the heated skin's water has to boil off before it can catch (the core stays wet; s152: counting the whole
    # post's water held a post 0.8 m downwind of a campfire at 100 C for 20 minutes)
    A = 2 * (size[1] * size[2] + size[1] * size[3] + size[2] * size[3])
    skin = min(m.rho * m.skin * A, dry)
    FireBody(id, m, Float32.(Tuple(pos)), Float32.(Tuple(size)), Float32(T), dry, Float32(moisture * skin), 0f0,
             burning, Float32(load), false, burning ? 0f0 : -1f0, -1f0, m.G)
end

surface_area(b::FireBody) = 2f0 * (b.size[1] * b.size[2] + b.size[1] * b.size[3] + b.size[2] * b.size[3])
"The fuel's own size D for the flame correlations: the mean of its footprint."
fuel_D(b::FireBody) = max(0.5f0 * (b.size[1] + b.size[2]), 0.02f0)

"Heat release rate (W) of a burning body: the burning flux over its surface (top and sides; the base sits on the ground)."
function hrr(b::FireBody)
    b.burning || return 0f0
    A = surface_area(b) - b.size[1] * b.size[2]
    return b.mflux * A * b.mat.dHc
end

"Flame height (m, Heskestad) and the lean from the vertical (rad, Thomas) of a burning body in wind `u` (m/s)."
function flame_shape(b::FireBody, u::Float32)
    Q = hrr(b)
    Q <= 0 && return 0f0, 0f0
    D = fuel_D(b)
    L = max(0.235f0 * (Q / 1000f0)^0.4f0 - 1.02f0 * D, 0.1f0 * D + 0.05f0)
    uc = (9.81f0 * (Q / 1000f0) / (1.2f0 * 1.0f0 * FIRE_TAMB * D))^(1f0 / 3)    # characteristic plume velocity
    us = u / max(uc, 1f-3)
    c = us <= 1f0 ? 1f0 : min(1f0, 0.7f0 * us^(-0.49f0))
    return L, acos(c)
end

"Where the flame's radiating centre stands: half its height up, leaning downwind along `wind` (m/s, x/y)."
function flame_centre(b::FireBody, wind::NTuple{2,Float32})
    u = hypot(wind...)
    L, th = flame_shape(b, u)
    top = b.pos[3] + 0.5f0 * b.size[3]
    dx, dy = u > 0 ? (wind[1] / u, wind[2] / u) : (0f0, 0f0)
    s = 0.5f0 * L
    return (b.pos[1] + s * sin(th) * dx, b.pos[2] + s * sin(th) * dy, top + s * cos(th)), L
end

"The area of body `t` a point at `p` sees (projected box area towards p) and the distance to its centre."
function seen_area(t::FireBody, p)
    d = (t.pos[1] - p[1], t.pos[2] - p[2], t.pos[3] - p[3])
    R = sqrt(d[1]^2 + d[2]^2 + d[3]^2)
    R < 1f-3 && return surface_area(t) / 2, R
    n = (abs(d[1]) / R, abs(d[2]) / R, abs(d[3]) / R)
    A = n[1] * t.size[2] * t.size[3] + n[2] * t.size[1] * t.size[3] + n[3] * t.size[1] * t.size[2]
    return A, R
end

"""
The flames of burning bodies closer than `gap` merge into one (a log pile burns as one fire, not four small ones):
each group's flame has the summed heat release, the group's footprint as its size D, and stands over the
heat-weighted centre. Returns `(centre, L, Q, ids)` per flame.
"""
function merged_flames(bodies::Vector{FireBody}, wind::NTuple{2,Float32}; gap = 0.3f0)
    burning = [b for b in bodies if b.burning]
    n = length(burning)
    parent = collect(1:n)
    root(i) = parent[i] == i ? i : (parent[i] = root(parent[i]))
    for i in 1:n, j in i+1:n
        a, b = burning[i], burning[j]
        d = hypot(a.pos[1] - b.pos[1], a.pos[2] - b.pos[2]) - 0.5f0 * (max(a.size[1], a.size[2]) + max(b.size[1], b.size[2]))
        d < gap && (parent[root(i)] = root(j))
    end
    groups = Dict{Int,Vector{FireBody}}()
    for i in 1:n
        push!(get!(groups, root(i), FireBody[]), burning[i])
    end
    u = hypot(wind...)
    dx, dy = u > 0 ? (wind[1] / u, wind[2] / u) : (0f0, 0f0)
    out = Tuple{NTuple{3,Float32},Float32,Float32,Vector{Int},Float32}[]
    for g in values(groups)
        Q = sum(hrr, g)
        Q <= 0 && continue
        x = sum(b -> hrr(b) * b.pos[1], g) / Q; y = sum(b -> hrr(b) * b.pos[2], g) / Q
        top = sum(b -> hrr(b) * (b.pos[3] + 0.5f0 * b.size[3]), g) / Q   # heat-weighted (s152: the max put a log
                                                                          # pile's flame over the 1 m stake beside it)
        xs = [(b.pos[1] - 0.5f0 * b.size[1], b.pos[1] + 0.5f0 * b.size[1]) for b in g]
        ys = [(b.pos[2] - 0.5f0 * b.size[2], b.pos[2] + 0.5f0 * b.size[2]) for b in g]
        D = max(0.5f0 * ((maximum(last, xs) - minimum(first, xs)) + (maximum(last, ys) - minimum(first, ys))), 0.02f0)
        L = max(0.235f0 * (Q / 1000f0)^0.4f0 - 1.02f0 * D, 0.1f0 * D + 0.05f0)
        uc = (9.81f0 * (Q / 1000f0) / (1.2f0 * FIRE_TAMB * D))^(1f0 / 3)
        us = u / max(uc, 1f-3)
        th = acos(us <= 1f0 ? 1f0 : min(1f0, 0.7f0 * us^(-0.49f0)))
        s = 0.5f0 * L
        push!(out, ((x + s * sin(th) * dx, y + s * sin(th) * dy, top + s * cos(th)), L, Q, [b.id for b in g], D))
    end
    return out
end

"""
    fire_step!(bodies, dt; wind = (0, 0), rain = 0) -> events

Advance every body by `dt` s. Returns `(id, :ignite | :break | :out, time)` events of this step.
`rain` (kg/m^2 s of water reaching the bodies) wets their tops; `water!(b, kg)` throws water on one.
"""
function fire_step!(bodies::Vector{FireBody}, dt::Real, t::Real; wind = (0f0, 0f0), rain = 0f0)
    dt = Float32(dt); wind = Float32.(wind)
    events = Tuple{Int,Symbol,Float32}[]
    flames = merged_flames(bodies, wind)
    for b in bodies
        A = surface_area(b)
        qin = 0f0
        for (c, L, Q, ids) in flames
            b.id in ids && continue
            As, R = seen_area(b, c)
            R = max(R, 0.25f0 * L + 0.05f0)             # inside the flame the point source no longer holds
            qin += FIRE_CHI_R * Q / (4f0 * Float32(pi) * R^2) * As * b.mat.eps
            # in the flame or its plume: contact heating (the plume rises and leans with the flame)
            dz = b.pos[3] - c[3]
            dh = hypot(b.pos[1] - c[1], b.pos[2] - c[2])
            # immersed in a small wood flame: convection plus the flame's own radiation (emissivity ~0.3 for flames
            # 0.2-0.5 m thick): ~45 kW/m^2 on a cold surface, what measurements in small crib fires give (s152: with
            # convection alone, 10 kW/m^2, a stake inside the leaning flame never caught)
            if dz > -0.5f0 * L && dh < 0.3f0 * L + 0.5f0 * fuel_D(b)
                qin += (FIRE_HF * (FIRE_TFLAME - b.T) + FIRE_EPS_FLAME * FIRE_SIGMA * (FIRE_TFLAME^4 - b.T^4)) * 0.5f0 * A
            end
        end
        qext = qin / A                                   # W/m^2 from every other flame
        qloss = b.mat.eps * FIRE_SIGMA * (b.T^4 - FIRE_TAMB^4) * A + 10f0 * (b.T - FIRE_TAMB) * A
        net = (qin - qloss) * dt
        rain > 0 && (b.water += rain * b.size[1] * b.size[2] * dt)
        mskin = max(min(b.mat.rho * b.mat.skin * A, b.fuel + 1f-4), 1f-4)
        if b.water > 1f-5 && b.T >= 373f0 && net > 0
            boil = min(net / FIRE_LATENT, b.water)          # the heat boils water first
            b.water -= boil
            net -= boil * FIRE_LATENT
        end
        dT = net / (mskin * b.mat.cp)
        b.water > 1f-5 && b.T + dT > 373f0 && (dT = 373f0 - b.T)
        # explicit step on a skin that burns away gets stiff: nothing heated by flames gets hotter than them, and
        # nothing cools below the air (s152: a burnt-out grass tuft overshot to NaN)
        b.T = clamp(b.T + dT, FIRE_TAMB, FIRE_TFLAME + 100f0)
        if !b.burning && b.mat.dHc > 0 && b.fuel > 0 && b.T >= b.mat.T_ig
            b.burning = true; b.ignited_at = Float32(t); b.mflux = b.mat.G; push!(events, (b.id, :ignite, Float32(t)))
        end
        if b.burning
            # the burning rate is what the surface's heat balance pays for (Drysdale ch. 5): its own flame (thicker
            # flames radiate more: emissivity 1 - exp(-kappa D) of the merged fire), heat from other flames, minus the
            # charred surface's re-radiation, over the heat of gasification. Below the critical mass flux the flame
            # goes out: a lone stake dies down, a crib whose logs feed each other keeps going.
            i = findfirst(f -> b.id in f[4], flames)
            Dg = i === nothing ? fuel_D(b) : flames[i][5]
            qfl = (1f0 - exp(-FIRE_KAPPA * Dg)) * FIRE_SIGMA * FIRE_TFLAME^4 + FIRE_QCONV
            qsurf = b.mat.eps * FIRE_SIGMA * (FIRE_TCHAR^4 - FIRE_TAMB^4)
            b.mflux = clamp((qfl + qext - qsurf) / b.mat.Lg, 0f0, 2f0 * b.mat.G)
            if b.mflux < FIRE_MCRIT && b.mat.beta > 0
                b.burning = false; b.T = b.mat.T_ig - 30f0; push!(events, (b.id, :out, Float32(t)))
                continue
            end
            b.fuel -= hrr(b) / b.mat.dHc * dt
            b.char += b.mat.beta * dt
            b.T = max(b.T, b.mat.T_ig)
            if b.fuel <= 0 || b.water > 0.5f0 * b.mat.rho * b.mat.skin * A
                b.burning = false; b.fuel = max(b.fuel, 0f0); push!(events, (b.id, :out, Float32(t)))
            end
        end
        if !b.broken && b.load > 0 && capacity(b) < b.load
            b.broken = true; b.broke_at = Float32(t); push!(events, (b.id, :break, Float32(t)))
            fall!(b, wind)
        end
    end
    return events
end

"""
Bending capacity left, 0..1: the reduced cross-section of EN 1995-1-2 (char depth + 7 mm zero-strength layer off
every heated face). The two thinnest dimensions are the section.
"""
function capacity(b::FireBody)
    b.mat.beta == 0 && return 1f0
    s = sort(collect(b.size))
    w, d = s[1], s[2]
    def = b.char > 0 ? b.char + 0.007f0 : 0f0
    w2, d2 = max(w - 2def, 0f0), max(d - 2def, 0f0)
    return (w2 * d2^2) / (w * d^2)
end

"""
A broken upright body falls over the way the wind pushes it (calm: along +x) and lies on the ground: its box turns
on its side, so its flame now stands low and long (s152: the fallen stake kept burning a metre up in the air).
"""
function fall!(b::FireBody, wind)
    b.size[3] > max(b.size[1], b.size[2]) || return b
    u = hypot(wind...)
    d = u > 0 ? (wind[1] / u, wind[2] / u) : (1f0, 0f0)
    h = b.size[3]; w = b.size[1]
    base = (b.pos[1], b.pos[2], b.pos[3] - h / 2)
    b.pos = (base[1] + d[1] * h / 2, base[2] + d[2] * h / 2, base[3] + w / 2)
    b.size = abs(d[1]) >= abs(d[2]) ? (h, b.size[2], w) : (b.size[1], h, w)
    return b
end

"Throw `kg` of water on a body: it soaks in and cools it (the water heated to 100 C and boiled off the surface)."
function water!(b::FireBody, kg::Real)
    b.water += Float32(kg)
    cool = Float32(kg) * (4186f0 * max(b.T - FIRE_TAMB, 0f0) * 0.5f0)
    mskin = max(b.mat.rho * b.mat.skin * surface_area(b), 1f-4)
    b.T = max(FIRE_TAMB, b.T - cool / (mskin * b.mat.cp))
    return b
end
