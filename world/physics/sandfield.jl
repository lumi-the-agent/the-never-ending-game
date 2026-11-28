# Sand that keeps what pressed it (s160, project plank-road, big goal road step 'wheels on a plank track and in sand').
# A height field of loose sand over a hard bed. Anything that presses into it (a wheel rim, a foot, a plank end) gives
# its underside as a height map; where the sand stands above it:
#   - part of the pressed column COMPACTS: loose dry sand (~1500 kg/m3) densifies towards ~1700 kg/m3, so a layer one
#     footprint-width deep (the pressure bulb, Boussinesq) can lose e = 1 - rho0/rhomax ~ 12% of its height, once;
#     `comp` remembers how much each cell has already given, so a second pass over a rut compacts no further;
#   - the rest is DISPLACED to the nearest free cells outside the footprint (Sumner, O'Brien & Hodgins 1999,
#     'Animating sand, mud and snow'): that is the berm beside a rut and the bow wave ahead of a dug-in wheel;
#   - then the sand SLUMPS wherever it stands steeper than its angle of repose (dry ~33 deg, damp steeper), as pairwise
#     flows that conserve the sand exactly; nothing moves into or out of cells a body still covers.
# How deep a body presses comes from its load and the soil (physics/wheelsand.jl, Bekker/Wong-Reece), not from here.
# Kernels are KernelAbstractions (CPU or Mantle.Device()). Looked first (rule 6): RomeoDB has terrain-following
# atmosphere/ocean grids and soil erosion by water (Wflow, EarthBox), no granular height field; physics/snow.jl
# had a CPU repose relaxation for snow caps, which this replaces with a race-free, mass-exact GPU form.
module SandField
import Raycore
const KA = Raycore.KernelAbstractions
using .KA: @kernel, @index

mutable struct Field{A<:AbstractMatrix{Float32}}
    h::A          # sand surface height (m)
    bed::A        # hard bed below the sand (m)
    comp::A       # compaction already taken by each cell (m)
    under::A      # underside of whatever presses now (m), Inf where nothing does
    tmp::A
    dx::Float32
    repose::Float32   # degrees
    e::Float32        # compactable fraction (1 - rho0/rhomax)
end

function Field(nx, ny, dx; depth = 0.5f0, repose = 33f0, e = 0.12f0, backend = KA.CPU())
    z(v) = (a = KA.zeros(backend, Float32, nx, ny); fill!(a, v); a)
    Field(z(0f0), z(-Float32(depth)), z(0f0), z(Inf32), z(0f0), Float32(dx), Float32(repose), Float32(e))
end

KA.get_backend(f::Field) = KA.get_backend(f.h)
sand_volume(f::Field) = sum(Array(f.h) .- Array(f.bed)) * f.dx^2

# The free cells a covered cell (i, j) sends its sand to: along the 8 directions, the nearest uncovered cell
# (diagonals count sqrt 2 per step); ties share equally. Returns (distance, how many directions tie) or (Inf, 0).
@inline function nearest_free(under, i, j, nx, ny, R)
    best = Inf32; cnt = 0
    for (a, b) in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
        L = (a != 0 && b != 0) ? 1.4142135f0 : 1f0
        for s in 1:R
            p, q = i + s * a, j + s * b
            (1 <= p <= nx && 1 <= q <= ny) || break
            if isinf(under[p, q])
                d = s * L
                if d < best - 1f-4
                    best = d; cnt = 1
                elseif abs(d - best) <= 1f-4
                    cnt += 1
                end
                break
            end
        end
    end
    best, cnt
end

@inline function sends_to(under, i, j, p, q, nx, ny, R)
    best, cnt = nearest_free(under, i, j, nx, ny, R)
    cnt == 0 && return 0f0
    a, b = sign(p - i), sign(q - j)
    # (p, q) must lie on one of the 8 rays from (i, j) and be its first free cell at the best distance
    (p - i == 0 || q - j == 0 || abs(p - i) == abs(q - j)) || return 0f0
    s = max(abs(p - i), abs(q - j))
    L = (a != 0 && b != 0) ? 1.4142135f0 : 1f0
    abs(s * L - best) <= 1f-4 || return 0f0
    for t in 1:s-1
        isinf(under[i + t * a, j + t * b]) && return 0f0
    end
    1f0 / cnt
end

# Pass 1: every covered cell is pressed down to the underside; what it loses beyond its compaction goes into `tmp`.
@kernel function press_k!(h, comp, tmp, bed, @Const(under), cap)
    i, j = @index(Global, NTuple)
    u = under[i, j]
    out = 0f0
    if !isinf(u) && h[i, j] > u
        pen = h[i, j] - max(u, bed[i, j])
        c = clamp(cap - comp[i, j], 0f0, pen)
        comp[i, j] += c
        out = pen - c
        h[i, j] -= pen
    end
    tmp[i, j] = out
end

# Pass 2: every free cell gathers what the covered cells within R send it (no atomics: each pair recomputed).
@kernel function berm_k!(h, @Const(tmp), @Const(under), R)
    i, j = @index(Global, NTuple)
    nx, ny = size(h)
    if isinf(under[i, j])
        acc = 0f0
        for p in max(1, i - R):min(nx, i + R), q in max(1, j - R):min(ny, j + R)
            v = tmp[p, q]
            v > 0f0 && (acc += v * sends_to(under, p, q, i, j, nx, ny, R))
        end
        h[i, j] += acc
    end
end

# Slumping: flow(a->b) = k max(0, h_a - h_b - tan(repose) L), limited by a's sand; each cell sums what its 8
# neighbours send it minus what it sends them, so sand is conserved to rounding. k = 1/16 keeps it stable.
@inline function flow(h, bed, under, a1, a2, b1, b2, t, L)
    (isinf(under[a1, a2]) && isinf(under[b1, b2])) || return 0f0
    ex = h[a1, a2] - h[b1, b2] - t * L
    ex > 0f0 || return 0f0
    min(ex * 0.0625f0, (h[a1, a2] - bed[a1, a2]) * 0.125f0)
end

@kernel function slump_k!(hn, @Const(h), @Const(bed), @Const(under), t, dx)
    i, j = @index(Global, NTuple)
    nx, ny = size(h)
    d = 0f0
    for (a, b) in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
        p, q = i + a, j + b
        if 1 <= p <= nx && 1 <= q <= ny
            L = ((a != 0 && b != 0) ? 1.4142135f0 : 1f0) * dx
            d += flow(h, bed, under, p, q, i, j, t, L) - flow(h, bed, under, i, j, p, q, t, L)
        end
    end
    hn[i, j] = h[i, j] + d
end

"""
    press!(f, under; bulb, R = 16)

`under` (same size as the field, Inf where nothing touches) is the underside of the bodies pressing now. Sand above
it compacts by up to `f.e * bulb` per cell (bulb: the footprint's width, m) and the rest goes to the nearest free
cells. Returns the volume displaced (m^3).
"""
function press!(f::Field, under; bulb, R = 16)
    copyto!(f.under, under)
    be = KA.get_backend(f.h)
    press_k!(be)(f.h, f.comp, f.tmp, f.bed, f.under, Float32(f.e * bulb); ndrange = size(f.h))
    berm_k!(be)(f.h, f.tmp, f.under, R; ndrange = size(f.h))
    KA.synchronize(be)
    sum(f.tmp) * f.dx^2
end

"Let the sand slump `n` sweeps towards its angle of repose."
function slump!(f::Field, n = 50)
    be = KA.get_backend(f.h)
    t = tand(f.repose)
    for _ in 1:n
        slump_k!(be)(f.tmp, f.h, f.bed, f.under, t, f.dx; ndrange = size(f.h))
        f.h, f.tmp = f.tmp, f.h
    end
    KA.synchronize(be)
    f
end

"Steepest free slope in degrees (8 neighbours)."
function max_slope(f::Field)
    h = Array(f.h); u = Array(f.under); m = 0.0
    nx, ny = size(h)
    for i in 1:nx, j in 1:ny, (a, b) in ((1, 0), (0, 1), (1, 1), (1, -1))
        p, q = i + a, j + b
        (1 <= p <= nx && 1 <= q <= ny) || continue
        (isinf(u[i, j]) && isinf(u[p, q])) || continue
        L = (a != 0 && b != 0 ? sqrt(2) : 1.0) * f.dx
        m = max(m, atand(abs(h[i, j] - h[p, q]) / L))
    end
    m
end

"""
Underside of a rigid wheel (radius r, width b, axle across y) whose rim bottom stands at `zb`, centre (xc, yc):
Inf outside the rim's footprint.
"""
function wheel_under(f::Field, xc, yc, r, b, zb; x0 = 0.0, y0 = 0.0)
    nx, ny = size(f.h)
    U = fill(Inf32, nx, ny)
    for i in 1:nx, j in 1:ny
        x = x0 + (i - 0.5) * f.dx; y = y0 + (j - 0.5) * f.dx
        (abs(y - yc) <= b / 2 && abs(x - xc) < r) || continue
        U[i, j] = Float32(zb + r - sqrt(r^2 - (x - xc)^2))
    end
    U
end

"""
    plank_rest(f, href, P, loads; soil, bekker) -> (; z, pitch, roll, under, ok)

A rigid plank (P: centre xc, yc, length Lp along x, width bp, mass m) lying on the sand whose surface was `href`
(height map when the plank was laid). Each covered cell pushes back with Bekker's pressure for its own sinkage
(soil constants and `bekker(soil, b, z)` from wheelsand.jl, plate width bp); sand cannot pull, so an end that rises
lifts off. Finds the heave, pitch and roll where the sand carries the plank's weight and the point loads
`loads` = [(x, y, N), ...] with no net moment (Newton on 3 unknowns, numerical Jacobian, halving line search).
`under` is the plank's underside for `press!`.
"""
function plank_rest(f::Field, href, P, loads; soil, bekker)
    nx, ny = size(href)
    cells = [(i, j, (i - 0.5) * f.dx - P.xc, (j - 0.5) * f.dx - P.yc) for i in 1:nx for j in 1:ny
             if abs((i - 0.5) * f.dx - P.xc) <= P.Lp / 2 && abs((j - 0.5) * f.dx - P.yc) <= P.bp / 2]
    A = f.dx^2
    Wt = P.m * 9.81 + sum(l[3] for l in loads; init = 0.0)
    Mx = sum(l[3] * (l[1] - P.xc) for l in loads; init = 0.0)
    My = sum(l[3] * (l[2] - P.yc) for l in loads; init = 0.0)
    sc = [Wt, Wt * P.Lp, Wt * P.bp]
    href0 = sum(href[c[1], c[2]] for c in cells) / length(cells)
    function resid(v)
        z, tp, tr = v
        F = 0.0; Mp = 0.0; Mr = 0.0
        for (i, j, x, y) in cells
            p = bekker(soil, P.bp, href[i, j] - (z + x * tp + y * tr)) * A
            F += p; Mp += p * x; Mr += p * y
        end
        [F - Wt, Mp - Mx, Mr - My]
    end
    v = [href0 - 0.005, 0.0, 0.0]
    ok = false
    for it in 1:80
        r = resid(v)
        maximum(abs, r ./ sc) < 1e-6 && (ok = true; break)
        J = zeros(3, 3)
        for k in 1:3
            dv = zeros(3); dv[k] = 1e-6
            J[:, k] = (resid(v .+ dv) .- r) ./ 1e-6
        end
        step = J \ r
        α = 1.0
        while α > 1e-4 && sum(abs2, resid(v .- α .* step) ./ sc) >= sum(abs2, r ./ sc)
            α /= 2
        end
        v .-= α .* step
    end
    U = fill(Inf32, nx, ny)
    for (i, j, x, y) in cells
        U[i, j] = Float32(v[1] + x * v[2] + y * v[3])
    end
    (; z = v[1], pitch = atand(v[2]), roll = atand(v[3]), under = U, ok)
end

end
