# Flames as hot glowing gas (s153, the human: "materials as realistic as possible, the full potential of RayMakie and
# Hikari"). Each merged flame of physics/fire.jl becomes a temperature field round its leaning centreline: hottest in
# the core near the fuel (~1400 K), cooling with height and distance from the axis, stirred by a moving swirl. The
# gas is drawn by Hikari's volume path tracer as an RGBGridMedium: soot absorbs (sigma_a) and, by Kirchhoff, emits
# sigma_a * B(T), Planck's law at three wavelengths, so 1400 K is yellow-orange, 1000 K a dull red a thousand times
# fainter, and the colour of every part of the flame comes from its temperature, not from a palette.
using LinearAlgebra

const FLAME_TAMB = 300f0
const FLAME_TCORE = 1400f0
const FLAME_SOOT = 7f0           # 1/m: absorption of the luminous core (soot volume fraction ~1e-6)
const FLAME_LAMBDA = (610f0, 550f0, 465f0)   # nm: the R, G, B of the emission

"Planck spectral radiance (per nm, arbitrary unit) at λ nm and T kelvin."
planck(λ, T) = T <= 0 ? 0f0 : (um = λ * 1f-3; x = 1.4387769f4 / (um * T); x > 80 ? 0f0 : 1f0 / (um^5 * (exp(x) - 1f0)))
const FLAME_B0 = planck(550f0, FLAME_TCORE)     # Le = 1 at 550 nm in the core: Le_scale sets the exposure

"The centreline of one merged flame: base on the fuel, full flame vector F (length L, along base -> centre)."
function flame_axis(c, L, ids, o, byid)
    g = [byid[i] for i in ids]
    bx = sum(b -> b.pos[1], g) / length(g); by = sum(b -> b.pos[2], g) / length(g)
    bz = minimum(b -> b.pos[3] + 0.5f0 * b.size[3], g)
    base = Point3f(o[1] + bx, o[2] + by, o[3] + bz)
    F = Float32(L) * normalize(Vec3f(o[1] + c[1], o[2] + c[2], o[3] + c[3]) - base)
    sp = clamp(0.5f0 * maximum(b -> max(b.size[1], b.size[2]), g), 0.05f0, 0.4f0)
    return base, F, sp
end

"""
    flame_volume(flames, t, o, byid; h = 0.03) -> (box_mesh, medium) or nothing

The hot gas of every flame `(c, L, Q, ids)` at time `t`, on a grid `h` metres apart: a box mesh to carry the
medium (`MediumInterface(NullMaterial(); inside = medium)`) and the RGBGridMedium.
"""
function flame_volume(flames, t, o, byid; h = 0.03f0, Le_scale = 1.5f0, nmax = 72)
    ax = [flame_axis(c, L, ids, o, byid) for (c, L, Q, ids) in flames if L >= 0.03f0]
    isempty(ax) && return nothing
    lo = Point3f(Inf32); hi = Point3f(-Inf32)
    for (base, F, sp) in ax
        R = sp + 0.1f0
        lo = min.(lo, min.(base, base + F) .- R); hi = max.(hi, max.(base, base + F) .+ R)
    end
    lo = Point3f(lo[1], lo[2], max(lo[3], Float32(o[3]) - 0.05f0))
    n = Tuple(clamp.(ceil.(Int, (hi .- lo) ./ h), 4, nmax))
    d = (hi .- lo) ./ Vec3f(n...)
    σa = Array{NG.Hikari.RGBSpectrum,3}(undef, n...)
    σs = Array{NG.Hikari.RGBSpectrum,3}(undef, n...)   # MUST be given: pbrt's RGBGridMedium takes a missing grid as 1/m (s153: a milky box)
    Le = Array{NG.Hikari.RGBSpectrum,3}(undef, n...)
    paths = [[base + Float32(s) * Vec3f(0, 0, F[3]) + Float32(s)^1.6f0 * Vec3f(F[1], F[2], 0) for s in range(0f0, 1f0; length = 25)]
             for (base, F, sp) in ax]
    for k in 1:n[3], j in 1:n[2], i in 1:n[1]
        p = lo + (Vec3f(i, j, k) .- 0.5f0) .* d
        # the swirl: rising eddies displace where the gas is (turbulence the size of the flame's width)
        q = p + 0.05f0 * Vec3f(sin(17f0 * p[3] - 9f0 * t + 3f0 * p[2]), sin(15f0 * p[3] - 7.5f0 * t + 2.3f0 * p[1]), 0.6f0 * sin(11f0 * p[1] + 13f0 * p[2] - 6f0 * t))
        T = FLAME_TAMB; soot = 0f0
        for (m, (base, F, sp)) in enumerate(ax)
            P = paths[m]
            dmin = Inf32; smin = 0f0
            for (si, c) in enumerate(P)
                dd = norm(q - c)
                dd < dmin && (dmin = dd; smin = (si - 1) / 24f0)
            end
            R = (0.55f0 * sp + 0.02f0) * (0.6f0 + 0.4f0 * sin(min(smin / 0.3f0, 1f0) * Float32(pi) / 2)) * (1.05f0 - smin)^0.7f0
            w = exp(-(dmin / R)^2)
            Tm = FLAME_TAMB + (FLAME_TCORE - FLAME_TAMB) * (1f0 - 0.5f0 * smin^1.5f0)
            T = max(T, FLAME_TAMB + (Tm - FLAME_TAMB) * w)
            soot = max(soot, FLAME_SOOT * w * (smin < 0.98f0 ? 1f0 : 0f0))
        end
        σa[i, j, k] = NG.Hikari.RGBSpectrum(soot)
        σs[i, j, k] = NG.Hikari.RGBSpectrum(0.1f0 * soot)     # soot scatters little next to what it absorbs
        Le[i, j, k] = NG.Hikari.RGBSpectrum((planck(λ, T) / FLAME_B0 for λ in FLAME_LAMBDA)...)
    end
    b = NG.Hikari.Bounds3(lo, hi)
    med = NG.Hikari.RGBGridMedium(; σ_a_grid = σa, σ_s_grid = σs, Le_grid = Le, Le_scale = Float32(Le_scale), bounds = b,
                                  majorant_res = Vec3i(8, 8, 8))
    box = GeometryBasics.normal_mesh(Rect3f(Vec3f(lo...), Vec3f((hi .- lo)...)))
    return box, med
end
