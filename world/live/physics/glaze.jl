# Glaze in the kiln (s141, free part): a molten glaze film on a pot's body, levelled by surface tension
# and sagged by gravity (lubrication equation), then coloured by how thick it ended up (Beer-Lambert twice:
# through the glaze to the pale body and back). Incised lines fill and turn darker, raised cordons "break"
# (the glaze thins to ~0.09 mm on top and the body shows), and a pale halo forms beside each groove
# where the glaze was drawn in. None of that is painted: it comes out of the film flow.
#   h_t = -div(q),  q = h^3/(3μ) (σ ∇(∇² s) - ρ g ŷ),  s = b + h (free surface), y up the pot
# Grid (x round the pot, periodic; y up), step L. Explicit: stable for dt <= ~0.005 s at L = 0.5 mm, h ~ 1 mm.
# Swalbe.jl (RomeoDB) is a CUDA lattice-Boltzmann thin-film solver on FLAT substrates; we need a grooved body.
# Pictures: media/s141-celadon-pair2.png (museum pot left, mine right).
module Glaze

const L = 0.0005  # grid step 0.5 mm

"Body relief b (m) of an unwrapped patch: two pairs of incised vertical lines, a double incised ring, a raised cordon."
function body(nx, ny)
    b = zeros(nx, ny)
    groove(d, w, depth) = d < w ? -depth * (1 - d / w) : 0.0         # V cut
    ridge(d, w, height) = d < w ? height * sqrt(1 - (d / w)^2) : 0.0  # round cordon
    for j in 1:ny, i in 1:nx
        x = (i - 0.5) * L; y = (j - 0.5) * L
        v = 0.0
        for x0 in (0.030, 0.0345, 0.080, 0.0845)
            v = min(v, groove(abs(x - x0), 0.0008, 0.0006))
        end
        for y0 in (0.040, 0.0445)
            v = min(v, groove(abs(y - y0), 0.0008, 0.0006))
        end
        v += ridge(abs(y - 0.085), 0.0012, 0.0010)
        b[i, j] = v
    end
    b
end

lap(a, i, j, nx, ny) = (a[mod1(i+1, nx), j] + a[mod1(i-1, nx), j] + a[i, min(j+1, ny)] + a[i, max(j-1, 1)] - 4a[i, j]) / L^2

"Fire the glaze film `h` (m) on body `b`: viscosity μ (Pa s), surface tension σ (N/m). 12000 steps of 5 ms = 60 s at peak."
function fire!(h, b; μ = 300.0, σ = 0.3, ρ = 2500.0, g = 9.81, dt = 0.005, steps = 12000)
    nx, ny = size(h)
    s = similar(h); κ = similar(h); qx = zeros(nx, ny); qy = zeros(nx, ny)
    for _ in 1:steps
        s .= b .+ h
        Threads.@threads for j in 1:ny
            for i in 1:nx
                κ[i, j] = lap(s, i, j, nx, ny)
            end
        end
        Threads.@threads for j in 1:ny
            for i in 1:nx
                ip = mod1(i + 1, nx)
                hm = 0.5 * (h[i, j] + h[ip, j])
                qx[i, j] = hm^3 / (3μ) * σ * (κ[ip, j] - κ[i, j]) / L
                if j < ny
                    hm = 0.5 * (h[i, j] + h[i, j+1])
                    qy[i, j] = hm^3 / (3μ) * (σ * (κ[i, j+1] - κ[i, j]) / L - ρ * g)
                else
                    qy[i, j] = 0.0
                end
            end
        end
        Threads.@threads for j in 1:ny
            for i in 1:nx
                dv = (qx[i, j] - qx[mod1(i-1, nx), j]) / L + (qy[i, j] - (j > 1 ? qy[i, j-1] : 0.0)) / L
                h[i, j] = max(h[i, j] - dt * dv, 0.0)
            end
        end
    end
    h
end

# ── The same firing as KernelAbstractions kernels (KA.CPU() or Mantle.Device()), Float32 ──────────────
# Two launches per step: fluxes on faces (curvature computed inline, stencil radius 2), then the update.
import Raycore
const KA = Raycore.KernelAbstractions
using .KA: @Const

@inline sv(b, h, i, j) = b[i, j] + h[i, j]
@inline function κat(b, h, i, j, nx, ny, iL2)
    (sv(b, h, mod1(i + 1, nx), j) + sv(b, h, mod1(i - 1, nx), j) + sv(b, h, i, min(j + 1, ny)) +
     sv(b, h, i, max(j - 1, 1)) - 4 * sv(b, h, i, j)) * iL2
end

KA.@kernel function flux_kernel!(qx, qy, @Const(h), @Const(b), nx, ny, iL, iL2, c, g)
    i, j = KA.@index(Global, NTuple)
    ip = mod1(i + 1, nx)
    k0 = κat(b, h, i, j, nx, ny, iL2)
    hm = (h[i, j] + h[ip, j]) * 0.5f0
    qx[i, j] = hm^3 * c * (κat(b, h, ip, j, nx, ny, iL2) - k0) * iL
    if j < ny
        hm = (h[i, j] + h[i, j+1]) * 0.5f0
        qy[i, j] = hm^3 * (c * (κat(b, h, i, j + 1, nx, ny, iL2) - k0) * iL - g)
    else
        qy[i, j] = 0f0
    end
end

KA.@kernel function update_kernel!(h, @Const(qx), @Const(qy), nx, dtiL)
    i, j = KA.@index(Global, NTuple)
    dv = qx[i, j] - qx[mod1(i - 1, nx), j] + qy[i, j] - (j > 1 ? qy[i, j-1] : 0f0)
    h[i, j] = max(h[i, j] - dtiL * dv, 0f0)
end

"""
    fire_ka!(h, b, backend; μ, σ, ρ, g, dt, steps) -> h (on the host)

`fire!` on a KernelAbstractions backend: h and b are host matrices (m), copied over, fired, copied back.
"""
function fire_ka!(h, b, backend; μ = 300.0, σ = 0.3, ρ = 2500.0, g = 9.81, dt = 0.005, steps = 12000)
    nx, ny = size(h)
    hd = KA.allocate(backend, Float32, nx, ny); copyto!(hd, Float32.(h))
    bd = KA.allocate(backend, Float32, nx, ny); copyto!(bd, Float32.(b))
    qx = KA.zeros(backend, Float32, nx, ny); qy = KA.zeros(backend, Float32, nx, ny)
    fk = flux_kernel!(backend); uk = update_kernel!(backend)
    c = Float32(σ / (3μ)); gg = Float32(ρ * g / σ) * c   # q = h^3 (c Δκ/L - ρg/(3μ))
    iL = Float32(1 / L); iL2 = Float32(1 / L^2); dtiL = Float32(dt / L)
    for _ in 1:steps
        fk(qx, qy, hd, bd, nx, ny, iL, iL2, c, gg; ndrange = (nx, ny))
        uk(hd, qx, qy, nx, dtiL; ndrange = (nx, ny))
    end
    KA.synchronize(backend)
    h .= Array(hd)
    h
end

"Olive celadon colour (r, g, b) of a glaze `hm` metres thick: absorption α and bubble scattering β per mm."
function celadon(hm; α = (0.70, 0.62, 1.05), β = 0.12, tint = (0.62, 0.62, 0.56))
    hmm = 1e3 * hm
    bc = hmm < 0.03 ? (0.74, 0.52, 0.38) : (0.84, 0.80, 0.72)   # bare body re-oxidises orange
    ntuple(k -> clamp(bc[k] * exp(-2(α[k] + β) * hmm) + tint[k] * (1 - exp(-2β * hmm)) * exp(-α[k] * hmm) + 0.03, 0, 1), 3)
end

end
