# Thin ice (s133, project glass-sea): sea ice as a floating Kirchhoff plate that bends, makes flexural waves and cracks.
#
#   (ρ_i h + m_a) ẅ = -∇²(D ∇²w) - ρ_w g w - c ẇ + q,      D = E h³ / (12 (1 - ν²))
#
# w: deflection (down is negative), q: load per area (skaters' weight), ρ_w g w: the water pushing back (Winkler
# foundation), m_a = ρ_w ℓ: water dragged along (added mass of a deep-water flexural mode with wavelength ~ ℓ,
# ℓ = (D / ρ_w g)^¼ the characteristic length, ~1 m for 3 cm ice). Bending stress at the surface σ = 6 M / h² from the
# principal moment; a cell whose stress passes its strength (flexural strength ~0.6 MPa, ±25% per cell) cracks: its
# stiffness drops to 2 %, so it becomes a hinge, the stress moves to the crack tip and the crack runs on. The crack's
# direction is perpendicular to the principal stress at the moment it broke. Water floods the ice where it sinks
# below its freeboard h (1 - ρ_i / ρ_w): the sign of thin ice a skater can read.
#
# Looked at (RomeoDB): Peridynamics.jl / PeriLab (3D bond fracture, far too heavy for a floating sheet in real time),
# ClimaSeaIce (climate-scale sea ice rheology, no bending or cracks). Nothing for a floating plate with cracks.
# Explicit symplectic Euler, KernelAbstractions (CPU now; the same kernels run on Mantle.Device()).
import Raycore
using Random
using Raycore.KernelAbstractions   # the env reaches KernelAbstractions through Raycore (as physics/echo.jl does)
const KernelAbstractions = Raycore.KernelAbstractions

const ICE_E = 4f9        # effective Young's modulus of sea ice, Pa
const ICE_NU = 0.33f0
const ICE_RHO = 917f0
const WATER_RHO = 1025f0
const ICE_G = 9.81f0
const ICE_STRENGTH = 6f5 # flexural strength, Pa
# Stiffness a cracked cell keeps: a 0.2 m cell crossed by a crack is still mostly whole floe, and the floes press on
# each other across the wet crack. s133, 5 skaters 25 s on 6.5 cm ice with a 2.2 cm vein: 0.02 (slush) spreads cracks
# through thick ice (2011 cells, 869 thick); 0.15: 204 cells, none in thick ice; 0.3: 44; 0.5: 29.
const ICE_RESIDUAL = Ref(0.15f0)

mutable struct IceSheet{A}
    n::Int
    dx::Float32
    x0::Float32          # world x, y of cell (1, 1)
    y0::Float32
    h::A                 # thickness, m
    D::A                 # bending stiffness (with cracks), N m
    m::A                 # moving mass per area (ice + water dragged along), kg/m²
    strength::A          # per-cell strength, Pa
    crack::A             # 0 intact, 1 cracked
    angle::A             # crack direction (radians, world xy) when it broke
    w::A
    v::A
    M::A                 # isotropic moment D ∇²w (scratch)
    σ::A                 # last bending stress, Pa
    q::A                 # load, N/m²
    backend::Any
end

ice_D(h) = ICE_E * h^3 / (12 * (1 - ICE_NU^2))
ice_length(h) = (ice_D(h) / (WATER_RHO * ICE_G))^0.25f0

"""
    ice_sheet(n, dx, x0, y0, thickness; seed, backend = CPU())

`thickness(x, y)` in metres gives the ice at each world point.
"""
function ice_sheet(n, dx, x0, y0, thickness; seed = 133, backend = CPU())
    rng = Xoshiro(seed)
    h = Float32[thickness(x0 + (i - 1) * dx, y0 + (j - 1) * dx) for i in 1:n, j in 1:n]
    D = ice_D.(h)
    m = @. ICE_RHO * h + WATER_RHO * ice_length(h)
    strength = ICE_STRENGTH .* (0.75f0 .+ 0.5f0 .* rand(rng, Float32, n, n))
    z() = KernelAbstractions.zeros(backend, Float32, n, n)
    up(a) = (b = z(); copyto!(b, a); b)
    IceSheet(n, Float32(dx), Float32(x0), Float32(y0), up(h), up(D), up(m), up(strength), z(), z(), z(), z(), z(), z(), z(), backend)
end

@inline lap(a, i, j, n) = (a[max(i - 1, 1), j] + a[min(i + 1, n), j] + a[i, max(j - 1, 1)] + a[i, min(j + 1, n)] - 4 * a[i, j])

@kernel function ice_moment!(M, D, w, n, inv_dx2)
    i, j = @index(Global, NTuple)
    @inbounds M[i, j] = D[i, j] * lap(w, i, j, n) * inv_dx2
end

@kernel function ice_accel!(w, v, M, m, q, n, inv_dx2, k, c, dt)
    i, j = @index(Global, NTuple)
    @inbounds begin
        # free edges: the moment is zero outside the sheet
        a = (-lap(M, i, j, n) * inv_dx2 - k * w[i, j] - c * v[i, j] + q[i, j]) / m[i, j]
        # the sheet is a window onto a larger sheet of ice: its rim is held by the ice beyond (s133: a free rim with no
        # bending made a kink under any skater near it, 47 MPa at 4 m/s, and the whole field shattered)
        v[i, j] = (i <= 2 || j <= 2 || i >= n - 1 || j >= n - 1) ? 0f0 : v[i, j] + a * dt
    end
end

@kernel function ice_move!(w, v, dt)
    i, j = @index(Global, NTuple)
    @inbounds w[i, j] += v[i, j] * dt
end

@kernel function ice_stress!(σ, crack, angle, D, h, w, n, inv_dx2)
    i, j = @index(Global, NTuple)
    @inbounds if 1 < i < n && 1 < j < n && crack[i, j] == 0
        # a crack is a free edge: no moment crosses it, so no curvature is read across a cracked neighbour
        # (without this the hinge's kink looks like a huge curvature and the crack cascades through thick ice)
        kxx = (crack[i + 1, j] + crack[i - 1, j]) > 0 ? 0f0 : (w[i + 1, j] - 2 * w[i, j] + w[i - 1, j]) * inv_dx2
        kyy = (crack[i, j + 1] + crack[i, j - 1]) > 0 ? 0f0 : (w[i, j + 1] - 2 * w[i, j] + w[i, j - 1]) * inv_dx2
        kxy = (crack[i + 1, j + 1] + crack[i + 1, j - 1] + crack[i - 1, j + 1] + crack[i - 1, j - 1]) > 0 ? 0f0 :
              (w[i + 1, j + 1] - w[i + 1, j - 1] - w[i - 1, j + 1] + w[i - 1, j - 1]) * inv_dx2 / 4
        Dij = D[i, j]
        Mxx = Dij * (kxx + ICE_NU * kyy); Myy = Dij * (kyy + ICE_NU * kxx); Mxy = Dij * (1 - ICE_NU) * kxy
        mid = (Mxx + Myy) / 2; rad = sqrt(((Mxx - Myy) / 2)^2 + Mxy^2)
        M1 = mid + rad; M2 = mid - rad
        Mmax = abs(M1) >= abs(M2) ? M1 : M2
        s = 6 * abs(Mmax) / h[i, j]^2
        σ[i, j] = s
        # the crack's direction: perpendicular to the principal moment of the plate's own bending here, read without
        # the free-edge mask (the masked curvature is axis-aligned next to a crack and draws grid-straight cracks)
        rxx = (w[i + 1, j] - 2 * w[i, j] + w[i - 1, j]); ryy = (w[i, j + 1] - 2 * w[i, j] + w[i, j - 1])
        rxy = (w[i + 1, j + 1] - w[i + 1, j - 1] - w[i - 1, j + 1] + w[i - 1, j - 1]) / 4
        Rxx = rxx + ICE_NU * ryy; Ryy = ryy + ICE_NU * rxx; Rxy = (1 - ICE_NU) * rxy
        rm = (Rxx + Ryy) / 2; rr = sqrt(((Rxx - Ryy) / 2)^2 + Rxy^2)
        angle[i, j] = 0.5f0 * atan(2 * Rxy, Rxx - Ryy) + (abs(rm + rr) >= abs(rm - rr) ? 0f0 : Float32(pi) / 2) + Float32(pi) / 2
    end
end

# Nonlocal strength test (Pijaudier-Cabot & Bazant 1987): a crack tip is a stress singularity, so a local
# "stress > strength" test on a grid depends on the cell size and cracks run on through thick ice. The stress is
# averaged over the intact cells within 2 cells (0.4 m at dx 0.2, about half the characteristic length).
@kernel function ice_break!(crack, D, σ, strength, n, broke, residual)
    i, j = @index(Global, NTuple)
    @inbounds if 4 < i < n - 3 && 4 < j < n - 3 && crack[i, j] == 0
        acc = 0f0; cnt = 0f0
        for di in -2:2, dj in -2:2
            if crack[i + di, j + dj] == 0
                acc += σ[i + di, j + dj]; cnt += 1f0
            end
        end
        if acc / cnt > strength[i, j]
            crack[i, j] = 1f0
            D[i, j] = residual * D[i, j]
            broke[1] = 1f0
        end
    end
end

"""
    ice_step!(s, dt; damping = 0.3) -> cracked this step::Bool

Advance by `dt` seconds with as many stable substeps as needed. `s.q` must hold the load.
"""
function ice_step!(s::IceSheet, dt; damping = 0.25f0)
    be = s.backend; n = s.n; inv = 1f0 / s.dx^2
    # stable substep for the stiffest cell: dt < dx² / (4 sqrt(D/m)) (a margin of 0.7)
    Dmax = maximum(s.D); mmin = minimum(s.m)
    sub = 0.7f0 * s.dx^2 / (4 * sqrt(Dmax / mmin))
    nsub = max(1, ceil(Int, dt / sub)); h = Float32(dt / nsub)
    k = WATER_RHO * ICE_G
    c = damping * 2 * sqrt(k * mmin)     # a fraction of critical damping of the floating mode
    for _ in 1:nsub
        ice_moment!(be)(s.M, s.D, s.w, n, inv; ndrange = (n, n))
        ice_accel!(be)(s.w, s.v, s.M, s.m, s.q, n, inv, k, c, h; ndrange = (n, n))
        ice_move!(be)(s.w, s.v, h; ndrange = (n, n))
    end
    broke = KernelAbstractions.zeros(be, Float32, 1)
    ice_stress!(be)(s.σ, s.crack, s.angle, s.D, s.h, s.w, n, inv; ndrange = (n, n))
    ice_break!(be)(s.crack, s.D, s.σ, s.strength, n, broke, ICE_RESIDUAL[]; ndrange = (n, n))
    KernelAbstractions.synchronize(be)
    Array(broke)[1] > 0
end

"Add a body of `mass` kg standing at world (x, y) on a footprint of radius `r` m to the load."
function ice_load!(s::IceSheet, x, y, mass; r = 0.15f0)
    # nobody loads the 0.8 m by the held rim (they stand on the ice beyond the window, which carries them)
    edge = 0.8f0 + 2 * s.dx; far = s.x0 + (s.n - 1) * s.dx
    (s.x0 + edge < x < far - edge && s.y0 + edge < y < s.y0 + (s.n - 1) * s.dx - edge) || return 0
    q = s.q isa Array ? s.q : Array(s.q)
    area = 0f0; cells = Tuple{Int,Int}[]
    for i in 1:s.n, j in 1:s.n
        cx = s.x0 + (i - 1) * s.dx; cy = s.y0 + (j - 1) * s.dx
        if (cx - x)^2 + (cy - y)^2 <= max(r, s.dx / 2)^2
            push!(cells, (i, j)); area += s.dx^2
        end
    end
    for (i, j) in cells; q[i, j] -= mass * ICE_G / area; end
    q === s.q || copyto!(s.q, q)
    length(cells)
end

"Water on the ice: cells pushed below their freeboard."
ice_flooded(s::IceSheet) = Array(s.w) .< -(Array(s.h) .* (1 - ICE_RHO / WATER_RHO))
