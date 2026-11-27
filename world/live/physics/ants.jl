# Ants on a honey road (s137, project ant-road). Stigmergy and cooperative transport on a flat patch of ground.
# - Two pheromone fields on a grid (h = 2 cm) that diffuse and evaporate: `food` (laid by ants coming home with a crumb,
#   and seeded by the honey line the player draws) and `home` (laid by ants going out).
# - Each ant steers by three antennae sensors ahead (left, centre, right), plus noise; going home it also keeps a
#   path-integration bias towards the nest (real ants know roughly where home is).
# - The biscuit is a rigid disc on the ground: ants that reach it either grab a free slot on its rim and pull, or bite
#   off a crumb and carry it home. Pullers follow Gelblum et al. 2015 (Nat. Commun. 6:7729, Paratrechina longicornis):
#   a few informed ants pull towards the nest, the rest pull along the load's current motion, with noise. The disc
#   slides only when the summed pull beats Coulomb friction (overdamped: velocity from the excess force), and turns from
#   the summed torque the same way, so misaligned pullers stall and spin it.
# Written for the CPU first; GPU port (KernelAbstractions on Mantle) is the project's next step.
using Random, LinearAlgebra

Base.@kwdef mutable struct AntWorld
    h::Float64 = 0.02                 # cell size (m)
    n::Int = 150                      # grid n x n
    food::Matrix{Float32} = zeros(Float32, 150, 150)
    home::Matrix{Float32} = zeros(Float32, 150, 150)
    honey::Matrix{Float32} = zeros(Float32, 150, 150)   # the drawn honey: food scent that fades slowly
    nest::NTuple{2,Float64} = (0.3, 1.5)
    nest_r::Float64 = 0.08
    # ants
    x::Vector{Float64} = Float64[]; y::Vector{Float64} = Float64[]; th::Vector{Float64} = Float64[]
    state::Vector{Int8} = Int8[]      # 0 out, 1 carrying a crumb home, 2 pulling the biscuit
    slot::Vector{Int} = Int[]
    err::Vector{Float64} = Float64[]  # a puller's own angle error (rad)
    informed::Vector{Bool} = Bool[]
    speed::Float64 = 0.15             # m/s (a big leaf-cutter's walk)
    # biscuit (rigid disc)
    bx::Float64 = 2.5; by::Float64 = 1.5; ba::Float64 = 0.0
    bvx::Float64 = 0.0; bvy::Float64 = 0.0; bw::Float64 = 0.0
    br::Float64 = 0.10                # radius (m)
    bm::Float64 = 0.030               # mass (kg)
    mu::Float64 = 0.20                # ground friction
    fant::Float64 = 0.005             # one ant's pull (N)
    c_lin::Float64 = 2.0              # N s / m above friction
    nslots::Int = 32
    holder::Vector{Int} = zeros(Int, 32)
    crumbs::Int = 0                   # crumbs carried home
    t::Float64 = 0.0
    rng::MersenneTwister = MersenneTwister(137)
end

cellof(W, x, y) = (clamp(floor(Int, x / W.h) + 1, 1, W.n), clamp(floor(Int, y / W.h) + 1, 1, W.n))
sense(F, W, x, y) = F[cellof(W, x, y)...]

"Spread `n` ants around the nest."
function ants!(W::AntWorld, n::Int)
    for _ in 1:n
        a = 2pi * rand(W.rng); r = W.nest_r * sqrt(rand(W.rng))
        push!(W.x, W.nest[1] + r * cos(a)); push!(W.y, W.nest[2] + r * sin(a)); push!(W.th, 2pi * rand(W.rng))
        push!(W.state, 0); push!(W.slot, 0); push!(W.err, 0.0); push!(W.informed, rand(W.rng) < 0.15)
    end
    W
end

"The player's honey line: a polyline of points (m), smeared into the honey field."
function honey!(W::AntWorld, pts; strength = 1f0)
    for k in 1:length(pts)-1
        (x0, y0), (x1, y1) = pts[k], pts[k+1]
        L = hypot(x1 - x0, y1 - y0); m = max(1, ceil(Int, L / (W.h / 2)))
        for s in 0:m
            u = s / m; x = x0 + u * (x1 - x0); y = y0 + u * (y1 - y0)
            i, j = cellof(W, x, y)
            for di in -1:1, dj in -1:1
                ii, jj = clamp(i + di, 1, W.n), clamp(j + dj, 1, W.n)
                W.honey[ii, jj] = max(W.honey[ii, jj], strength * (di == 0 && dj == 0 ? 1f0 : 0.6f0))
            end
        end
    end
    W
end

slotpos(W, k) = (a = W.ba + 2pi * (k - 1) / W.nslots; (W.bx + (W.br + 0.008) * cos(a), W.by + (W.br + 0.008) * sin(a)))

function diffuse!(F::Matrix{Float32}, keep::Float32, D::Float32)
    G = copy(F); n = size(F, 1)
    @inbounds for j in 2:n-1, i in 2:n-1
        F[i, j] = keep * ((1 - 4D) * G[i, j] + D * (G[i-1, j] + G[i+1, j] + G[i, j-1] + G[i, j+1]))
    end
    F
end

"One step of dt seconds: ants walk and lay scent, pullers pull, the biscuit slides if the pull beats friction."
function step!(W::AntWorld, dt::Float64)
    rng = W.rng; s = 0.04; sa = 0.55
    nx, ny = W.nest
    for k in eachindex(W.x)
        st = W.state[k]
        if st == 2
            W.x[k], W.y[k] = slotpos(W, W.slot[k]); continue
        end
        x, y, th = W.x[k], W.y[k], W.th[k]
        F = st == 0 ? W.food : W.home
        f(a) = (xs = x + s * cos(th + a); ys = y + s * sin(th + a);
                st == 0 ? sense(W.food, W, xs, ys) + sense(W.honey, W, xs, ys) : sense(W.home, W, xs, ys))
        l, c, r = f(sa), f(0.0), f(-sa)
        turn = c >= l && c >= r ? 0.0 : (l > r ? 0.35 : -0.35)
        th += turn + 0.35 * randn(rng) * sqrt(dt / 0.05)
        if st == 1     # path integration: a pull towards home
            ah = atan(ny - y, nx - x); d = mod(ah - th + pi, 2pi) - pi
            th += 0.12 * d
        end
        x += W.speed * dt * cos(th); y += W.speed * dt * sin(th)
        lim = W.h * (W.n - 1)
        (x < 0.02 || x > lim - 0.02) && (th = pi - th); (y < 0.02 || y > lim - 0.02) && (th = -th)
        x = clamp(x, 0.02, lim - 0.02); y = clamp(y, 0.02, lim - 0.02)
        i, j = cellof(W, x, y)
        if st == 0
            W.home[i, j] += 0.05f0
            if hypot(x - W.bx, y - W.by) < W.br + 0.012
                free = findfirst(==(0), W.holder)
                if free !== nothing && rand(rng) < 0.7
                    W.holder[free] = k; W.slot[k] = free; W.state[k] = 2
                    W.err[k] = 0.7 * randn(rng)
                    W.x[k], W.y[k] = slotpos(W, free); W.th[k] = W.ba + 2pi * (free - 1) / W.nslots + pi
                    continue
                end
                W.state[k] = 1; th += pi
            end
        else
            W.food[i, j] += 0.08f0
            if hypot(x - nx, y - ny) < W.nest_r
                W.state[k] = 0; th += pi; W.crumbs += 1
            end
        end
        W.x[k], W.y[k], W.th[k] = x, y, th
    end
    # the biscuit: summed pulls, Coulomb friction, overdamped sliding and turning
    v = (W.bvx, W.bvy); vn = hypot(v...)
    Fx = 0.0; Fy = 0.0; tau = 0.0
    for q in 1:W.nslots
        k = W.holder[q]; k == 0 && continue
        px, py = slotpos(W, q)
        an = atan(ny - W.by, nx - W.bx)
        dir = W.informed[k] || vn < 1e-3 ? an : atan(v[2], v[1])
        a = dir + W.err[k]
        fx, fy = W.fant * cos(a), W.fant * sin(a)
        Fx += fx; Fy += fy; tau += (px - W.bx) * fy - (py - W.by) * fx
        W.th[k] = a
        rand(rng) < dt / 4 && (W.err[k] = 0.7 * randn(rng))   # every few seconds a puller re-grips
        if rand(rng) < dt / 20                               # and now and then lets go
            W.holder[q] = 0; W.state[k] = 1
        end
    end
    Ff = W.mu * W.bm * 9.81; Fn = hypot(Fx, Fy)
    if Fn > Ff
        sp = (Fn - Ff) / W.c_lin; W.bvx, W.bvy = sp * Fx / Fn, sp * Fy / Fn
    else
        W.bvx, W.bvy = 0.0, 0.0
    end
    tf = Ff * W.br * 2 / 3
    W.bw = abs(tau) > tf ? sign(tau) * (abs(tau) - tf) / (W.c_lin * W.br^2) : 0.0
    W.bx += W.bvx * dt; W.by += W.bvy * dt; W.ba += W.bw * dt
    diffuse!(W.food, 0.996f0, 0.08f0); diffuse!(W.home, 0.995f0, 0.08f0)
    W.honey .*= 0.9995f0
    W.t += dt
    W
end

"How far the biscuit has come towards the nest (m)."
biscuit_travel(W, x0, y0) = hypot(x0 - W.nest[1], y0 - W.nest[2]) - hypot(W.bx - W.nest[1], W.by - W.nest[2])
