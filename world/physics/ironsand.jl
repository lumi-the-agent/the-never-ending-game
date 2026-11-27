# Iron sand over a buried magnet stone (s149, idea "Read the sand, find the stone").
# Every grain is a small soft-iron sphere that magnetises in the field it sits in (induced dipole, m = chi V B / mu0,
# chi = 3 for a sphere: Jackson 5.11), and feels
#   - the buried stone's field through EM (physics/em.jl, the charge model; any stone mesh, any pose, any depth),
#   - every neighbour grain's dipole field (so grains chain head to tail along the field lines),
#   - the force on an induced dipole, F = grad(m . B) / 2 = chi V / (2 mu0) grad |B|^2, plus the dipole-dipole force,
#   - contact (grains do not overlap) and Coulomb friction on the sand: a grain only slides when the magnetic pull
#     beats mu m g. A TAP lifts the grains for a moment (friction ~ gone), which is why you tap the paper.
# Motion is overdamped (a grain on sand has no momentum to speak of): v = F / gamma while it slides.
# A grain is a needle along its own field: it stands as steep as the field's dip (a needle is axial, so it points up).
# Looked first (rule 6): no Julia package simulates magnetic granular media; Magnetostatics.jl / MicroMagnetic.jl
# are the wrong scale. The dipole-dipole force is the textbook one (Furlani 2001, eq. 3.112).
# Still CPU and threaded; the per-grain step is written as one function per grain so it moves into a Mantle kernel.
module IronSand
using LinearAlgebra
import ..EM

const MU0 = EM.MU0
const V2 = NTuple{2,Float64}

Base.@kwdef struct Grain
    a::Float64 = 0.0012          # radius, m (a clump of real iron sand)
    chi::Float64 = 3.0           # induced moment of a soft-iron sphere
    rho::Float64 = 5170.0        # magnetite
    mu_s::Float64 = 0.55         # on dry sand, at rest
    mu_tap::Float64 = 0.04       # while a tap has it in the air
end

mutable struct Sand
    g::Grain
    pos::Vector{V2}              # on the sand surface (z = 0 at the sand, grain centre at z = a)
    dir::Vector{NTuple{3,Float64}}  # unit, along the grain's field, pointing up
    Bmag::Vector{Float64}        # |B| at the grain, T
    stones::Vector{EM.Magnet}
    # the stones' field on a grid at grain height (it is costly; grains move inside it)
    x0::Float64; y0::Float64; h::Float64; nx::Int; ny::Int
    Bx::Matrix{Float64}; By::Matrix{Float64}; Bz::Matrix{Float64}
end

"""A box stone (half sizes `half`, m) of `material` buried with its centre at `depth` below the sand at (x, y), its
magnetisation along body x, turned by R (R = I: lying on its side, pole axis along x; a turn about y by 90 degrees:
standing, north up)."""
function stone(x, y, depth; half = (0.07, 0.055, 0.045), material = :magnetite, R = Matrix(1.0I, 3, 3), n = 6)
    hx, hy, hz = half
    v = NTuple{3,Float64}[(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    # corners: index = 1 + (sx>0)*4 + (sy>0)*2 + (sz>0)
    f = NTuple{3,Int}[(1, 2, 4), (1, 4, 3),   # -x
                      (5, 7, 8), (5, 8, 6),   # +x
                      (1, 5, 6), (1, 6, 2),   # -y
                      (3, 4, 8), (3, 8, 7),   # +y
                      (1, 3, 7), (1, 7, 5),   # -z
                      (2, 6, 8), (2, 8, 4)]   # +z
    EM.magnet(v, f, (EM.MATERIALS[material].Br / MU0, 0.0, 0.0); n, pos = (x, y, -depth), R)
end

"""Sand patch `w` x `w` m centred at the origin, `N` grains scattered at random, field grid spacing `h`."""
function Sand(stones; N = 2500, w = 0.6, h = 0.006, g = Grain(), seed = 1)
    nx = ny = round(Int, w / h) + 1
    x0 = y0 = -w / 2
    Bx = zeros(nx, ny); By = zeros(nx, ny); Bz = zeros(nx, ny)
    Threads.@threads for i in 1:nx
        for j in 1:ny
            b = EM.B(stones, (x0 + (i - 1) * h, y0 + (j - 1) * h, g.a))
            Bx[i, j], By[i, j], Bz[i, j] = b
        end
    end
    s = seed % UInt32
    rnd() = (s = s * UInt32(1664525) + UInt32(1013904223); s / typemax(UInt32))
    pos = [(x0 + 0.02 + (w - 0.04) * rnd(), y0 + 0.02 + (w - 0.04) * rnd()) for _ in 1:N]
    S = Sand(g, pos, fill((0.0, 0.0, 1.0), N), zeros(N), stones, x0, y0, h, nx, ny, Bx, By, Bz)
    orient!(S)
    S
end

# the stones' field at a point on the sand, bilinear from the grid
function Bext(S::Sand, p::V2)
    fx = clamp((p[1] - S.x0) / S.h, 0, S.nx - 1.001); fy = clamp((p[2] - S.y0) / S.h, 0, S.ny - 1.001)
    i = floor(Int, fx) + 1; j = floor(Int, fy) + 1; u = fx - (i - 1); v = fy - (j - 1)
    bl(M) = (1 - u) * (1 - v) * M[i, j] + u * (1 - v) * M[i+1, j] + (1 - u) * v * M[i, j+1] + u * v * M[i+1, j+1]
    (bl(S.Bx), bl(S.By), bl(S.Bz))
end
B2(S, p) = sum(abs2, Bext(S, p))
# horizontal gradient of |B|^2 (the sand holds the grains in z)
function gradB2(S, p)
    e = S.h / 2
    ((B2(S, (p[1] + e, p[2])) - B2(S, (p[1] - e, p[2]))) / 2e, (B2(S, (p[1], p[2] + e)) - B2(S, (p[1], p[2] - e))) / 2e)
end

# a uniform grid of the grains for neighbour search
function cells(S, r)
    d = Dict{NTuple{2,Int},Vector{Int}}()
    for (k, p) in enumerate(S.pos)
        push!(get!(d, (floor(Int, p[1] / r), floor(Int, p[2] / r)), Int[]), k)
    end
    d
end

"""Each grain's moment from the stones' field plus its neighbours' (two Jacobi sweeps), direction and |B|."""
function moments(S::Sand, cl, r)
    g = S.g; V = 4pi / 3 * g.a^3; c = g.chi * V / MU0
    B = [collect(Bext(S, p)) for p in S.pos]
    m = [c .* b for b in B]
    for _ in 1:2
        Bn = [copy(b) for b in B]
        Threads.@threads for k in eachindex(S.pos)
            p = S.pos[k]; ci = (floor(Int, p[1] / r), floor(Int, p[2] / r))
            for dx in -1:1, dy in -1:1, j in get(cl, (ci[1] + dx, ci[2] + dy), Int[])
                j == k && continue
                d = [p[1] - S.pos[j][1], p[2] - S.pos[j][2], 0.0]; rr = norm(d)
                (rr > r || rr < 1e-9) && continue
                n̂ = d ./ rr
                Bn[k] .+= MU0 / (4pi * max(rr, 2g.a)^3) .* (3dot(m[j], n̂) .* n̂ .- m[j])
            end
        end
        m = [c .* b for b in Bn]; B = Bn
    end
    m, B
end

function orient!(S::Sand; r = 8S.g.a)
    cl = cells(S, r); _, B = moments(S, cl, r)
    for k in eachindex(B)
        b = B[k]; nb = norm(b); S.Bmag[k] = nb
        u = nb > 0 ? b ./ nb : [0.0, 0.0, 1.0]
        u[3] < 0 && (u = -u)                       # a needle is axial: it points up out of the sand
        S.dir[k] = Tuple(u)
    end
    S
end

"""One tap: the grains are free (friction mu_tap) for `t` seconds and slide, overdamped, where the field pulls them."""
function tap!(S::Sand; t = 0.04, dt = 0.002)
    for _ in 1:round(Int, t / dt)
        substep!(S; t, dt)
    end
    orient!(S)
end

"""One `dt` of a tap's flight (a game spreads a tap over frames with this; call orient! after the last)."""
function substep!(S::Sand; t = 0.04, dt = 0.002)
    g = S.g; V = 4pi / 3 * g.a^3; mass = g.rho * V; r = 8g.a
    gamma = 2mass / t          # in the air for t: a grain flies F t^2 / 2m, the same as sliding at F / gamma for t
    cl = cells(S, r); m, _ = moments(S, cl, r)
    new = similar(S.pos)
    Threads.@threads for k in eachindex(S.pos)
        new[k] = step(S, k, m, cl, r, V, mass, dt, gamma)
    end
    S.pos = new
    S
end

function step(S, k, m, cl, r, V, mass, dt, gamma)
    g = S.g; p = S.pos[k]
    gb = gradB2(S, p)
    F = [g.chi * V / (2MU0) * gb[1], g.chi * V / (2MU0) * gb[2]]
    ci = (floor(Int, p[1] / r), floor(Int, p[2] / r))
    for dx in -1:1, dy in -1:1, j in get(cl, (ci[1] + dx, ci[2] + dy), Int[])
        j == k && continue
        d = [p[1] - S.pos[j][1], p[2] - S.pos[j][2], 0.0]; rr = norm(d)
        (rr > r || rr < 1e-9) && continue
        n̂ = d ./ rr; mi = m[k]; mj = m[j]; re = max(rr, 2g.a)
        f = 3MU0 / (4pi * re^4) .* (dot(mi, n̂) .* mj .+ dot(mj, n̂) .* mi .+ dot(mi, mj) .* n̂ .- 5dot(mi, n̂) * dot(mj, n̂) .* n̂)
        F .+= f[1:2]
        rr < 2g.a && (F .+= 2.0 * mass * 9.81 * (2g.a - rr) / g.a .* n̂[1:2])   # contact: grains push apart
    end
    fn = norm(F); fr = g.mu_tap * mass * 9.81
    fn <= fr && return p
    v = (fn - fr) / gamma .* F ./ fn
    vmax = g.a / dt                                   # a grain moves at most its radius per step
    nv = norm(v); nv > vmax && (v = v .* (vmax / nv))
    (p[1] + v[1] * dt, p[2] + v[2] * dt)
end

"""How far each grain stands up out of the sand, 0..1 (its field's dip)."""
standing(S) = [d[3] for d in S.dir]

end
