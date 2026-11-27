# Blowing glass (s142, project glassblowing): a gather of molten soda-lime glass on a blowpipe, inflated by breath,
# sagged by gravity, turned by the pipe, and cooling while it moves, so the thin parts stiffen first.
#
# The model is a viscous membrane (a thin sheet of Newtonian fluid, Trouton): each triangle is a constant-strain-rate
# element whose membrane stress is  N = 2 eta h (D + tr(D) I)  (plane stress, incompressible: equibiaxial 6 eta,
# uniaxial 3 eta). With inertia the step is implicit and linear in the velocities:
#   (M/dt + K(eta, h, x)) v = M v_old/dt + f_pressure + f_gravity
# solved with a sparse Cholesky each step. Every triangle keeps its glass volume, so its thickness is volume/area,
# and that thickness is what cools (radiation + convection from both faces into its own heat capacity), what sets
# the viscosity (Vogel-Fulcher-Tammann fitted to soda-lime's working, softening and annealing points), and what
# bursts (a triangle thinner than BURST_H). No bending stiffness yet: a gather under breath is in tension.
# Checked by `sphere_test()`: a free isothermal sphere must grow as dR/dt = p R^2 / (12 eta h) (thin viscous shell).
using LinearAlgebra, SparseArrays, GeometryBasics

const GB_RHO = 2500.0          # kg/m^3
const GB_CP = 1200.0           # J/(kg K), soda-lime near 1000 C
const GB_EMISS = 0.8           # effective emissivity of hot glass
const GB_HCONV = 15.0          # W/(m^2 K), still air
const GB_TAIR = 300.0          # K
const GB_SIGMA = 5.670e-8
const BURST_H = 1.5e-4         # m: a wall thinner than this tears

"Viscosity of soda-lime glass in Pa s at T kelvin: log10 eta = -2.73 + 4452/(T_C - 242.7) (fits 10^3 at 1020 C,
10^6.6 at 720 C, 10^12 at 545 C), capped where the glass is set."
glass_viscosity(T) = (TC = T - 273.15; TC <= 300 ? 1e14 : min(1e14, 10.0^(-2.73 + 4452 / (TC - 242.7))))

"An icosphere (radius r, `level` subdivisions) as vertices and CCW (outward) faces."
function icosphere(r, level)
    t = (1 + sqrt(5)) / 2
    V = [normalize([x...]) for x in ((-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                                     (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1))]
    F = [(1, 12, 6), (1, 6, 2), (1, 2, 8), (1, 8, 11), (1, 11, 12), (2, 6, 10), (6, 12, 5), (12, 11, 3), (11, 8, 7), (8, 2, 9),
         (4, 10, 5), (4, 5, 3), (4, 3, 7), (4, 7, 9), (4, 9, 10), (5, 10, 6), (3, 5, 12), (7, 3, 11), (9, 7, 8), (10, 9, 2)]
    for _ in 1:level
        mid = Dict{Tuple{Int,Int},Int}()
        m(a, b) = get!(mid, minmax(a, b)) do
            push!(V, normalize(V[a] + V[b])); length(V)
        end
        F = reduce(vcat, [[(a, m(a, b), m(c, a)), (b, m(b, c), m(a, b)), (c, m(c, a), m(b, c)), (m(a, b), m(b, c), m(c, a))] for (a, b, c) in F])
    end
    X = reduce(hcat, V) .* r
    return X, F
end

mutable struct Gather
    X::Matrix{Float64}            # 3 x n vertex positions (pipe frame: the pipe runs along -x into the bubble)
    V::Matrix{Float64}            # 3 x n velocities
    F::Vector{NTuple{3,Int}}
    vol::Vector{Float64}          # glass volume per triangle (constant)
    T::Vector{Float64}            # temperature per triangle, K
    fixed::BitVector              # vertices held by the pipe
    t::Float64
    burst::Int                    # triangle that tore (0: none)
end

"A gather: a sphere of radius `r` with walls `h` thick at `T` kelvin, held by the pipe over a cap of `cap` degrees."
function gather(; r = 0.03, h = 0.006, T = 1373.0, level = 4, cap = 28)
    X, F = icosphere(r, level)
    X[1, :] .+= r                                   # the pipe end at the origin, the bubble out along +x
    n = size(X, 2)
    fixed = BitVector([X[1, i] < r * (1 - cosd(cap)) for i in 1:n])
    A = tri_areas(X, F)
    return Gather(X, zeros(3, n), F, A .* h, fill(T, length(F)), fixed, 0.0, 0)
end

"Inner edges as (opposite vertex 1, opposite vertex 2, edge a, edge b, triangle 1, triangle 2)."
function hinges(g)
    get!(HINGES, objectid(g.F)) do
        seen = Dict{Tuple{Int,Int},Tuple{Int,Int}}()      # edge -> (opposite vertex, triangle)
        out = NTuple{6,Int}[]
        for (ti, (a, b, c)) in enumerate(g.F), (p, q, o) in ((a, b, c), (b, c, a), (c, a, b))
            k = minmax(p, q)
            if haskey(seen, k)
                o2, t2 = seen[k]
                push!(out, (o, o2, p, q, ti, t2))
            else
                seen[k] = (o, ti)
            end
        end
        out
    end
end
const HINGES = Dict{UInt,Vector{NTuple{6,Int}}}()

function tri_areas(X, F)
    [norm(cross(X[:, b] - X[:, a], X[:, c] - X[:, a])) / 2 for (a, b, c) in F]
end
thickness(g::Gather) = g.vol ./ tri_areas(g.X, g.F)

"One implicit step: `p` breath pressure (Pa), `grav` gravity in the pipe frame (m/s^2), `eta` a fixed viscosity
(for tests) or `nothing` (from each triangle's temperature)."
function step!(g::Gather, dt; p = 2000.0, grav = (0.0, 0.0, -9.81), eta = nothing, cool = true)
    X, F = g.X, g.F
    n = size(X, 2)
    Is = Int[]; Js = Int[]; Ks = Float64[]
    f = zeros(3n)
    m = zeros(n)
    gv = collect(grav)
    for (ti, (a, b, c)) in enumerate(F)
        x1, x2, x3 = X[:, a], X[:, b], X[:, c]
        nn = cross(x2 - x1, x3 - x1)
        A2 = norm(nn); A = A2 / 2; nrm = nn / A2
        h = g.vol[ti] / A
        e1 = normalize(x2 - x1); e2 = cross(nrm, e1)
        # gradients of the barycentric coordinates
        gr = (cross(nrm, x3 - x2) / A2, cross(nrm, x1 - x3) / A2, cross(nrm, x2 - x1) / A2)
        B = zeros(3, 9)
        for i in 1:3
            ai = dot(gr[i], e1); bi = dot(gr[i], e2)
            B[1, 3i-2:3i] = ai * e1; B[2, 3i-2:3i] = bi * e2; B[3, 3i-2:3i] = bi * e1 + ai * e2
        end
        et = eta === nothing ? glass_viscosity(g.T[ti]) : eta
        C = 2et * h * [2.0 1 0; 1 2 0; 0 0 0.5]
        Kt = A * (B' * C * B)
        idx = (3a-2, 3a-1, 3a, 3b-2, 3b-1, 3b, 3c-2, 3c-1, 3c)
        for i in 1:9, j in 1:9
            push!(Is, idx[i]); push!(Js, idx[j]); push!(Ks, Kt[i, j])
        end
        mt = GB_RHO * g.vol[ti]
        fp = p * A * nrm / 3 + mt * gv / 3
        for v in (a, b, c)
            f[3v-2:3v] .+= fp; m[v] += mt / 3
        end
    end
    for v in 1:n, k in 1:3
        push!(Is, 3v-3+k); push!(Js, 3v-3+k); push!(Ks, m[v] / dt)
        f[3v-3+k] += m[v] / dt * g.V[k, v]
    end
    # viscous bending (a viscous plate: D = eta h^3/3), the discrete-shell hinge on every inner edge, as a dashpot on
    # the dihedral angle's rate: without it the held gather has free out-of-plane modes and runs away
    hA = tri_areas(X, F)
    for (o1, o2, ea, eb, t1, t2) in hinges(g)
        x1, x2, x3, x4 = X[:, o1], X[:, o2], X[:, ea], X[:, eb]
        E = x4 - x3; le = norm(E)
        N1 = cross(x1 - x3, x1 - x4); N2 = cross(x2 - x4, x2 - x3)
        q1 = N1 / dot(N1, N1); q2 = N2 / dot(N2, N2)
        u = (le * q1, le * q2, dot(x1 - x4, E) / le * q1 + dot(x2 - x4, E) / le * q2,
             -dot(x1 - x3, E) / le * q1 - dot(x2 - x3, E) / le * q2)
        hh = (g.vol[t1] / hA[t1] + g.vol[t2] / hA[t2]) / 2
        et = eta === nothing ? (glass_viscosity(g.T[t1]) + glass_viscosity(g.T[t2])) / 2 : eta
        Cb = 6 * (et * hh^3 / 3) * le^2 / (hA[t1] + hA[t2])
        vs = (o1, o2, ea, eb)
        for i in 1:4, j in 1:4, k in 1:3, l in 1:3
            push!(Is, 3vs[i]-3+k); push!(Js, 3vs[j]-3+l); push!(Ks, Cb * u[i][k] * u[j][l])
        end
    end
    K = sparse(Is, Js, Ks, 3n, 3n)
    free = [3v-3+k for v in 1:n if !g.fixed[v] for k in 1:3]
    vel = zeros(3n)
    vel[free] = cholesky(Symmetric(K[free, free])) \ f[free]
    g.V .= reshape(vel, 3, n)
    g.X .+= dt .* g.V
    h = thickness(g)
    if cool
        for ti in eachindex(g.T)
            T = g.T[ti]
            q = 2 * (GB_EMISS * GB_SIGMA * (T^4 - GB_TAIR^4) + GB_HCONV * (T - GB_TAIR))   # both faces
            g.T[ti] = T - dt * q / (GB_RHO * GB_CP * h[ti])
        end
    end
    g.t += dt
    thin = argmin(h)
    h[thin] < BURST_H && (g.burst = thin)
    return g
end

"A free isothermal sphere against the thin viscous shell's dR/dt = p R^2/(12 eta h)."
function sphere_test(; r = 0.03, h = 0.004, eta = 1e4, p = 2000.0, dt = 2e-3, steps = 50)
    X, F = icosphere(r, 3)
    n = size(X, 2)
    A = tri_areas(X, F)
    g = Gather(X, zeros(3, n), F, A .* h, fill(1300.0, length(F)), falses(n), 0.0, 0)
    R(g) = sum(norm, eachcol(g.X)) / size(g.X, 2)
    R0 = R(g); V0 = 4pi * R0^2 * h
    for _ in 1:steps
        step!(g, dt; p, grav = (0.0, 0.0, 0.0), eta, cool = false)
    end
    # integrate the closed form: dR/dt = p R^4 / (12 eta h0 R0^2)  =>  R^-3 = R0^-3 - 3 p t / (12 eta h0 R0^2)
    t = steps * dt
    Rx = (R0^-3 - 3p * t / (12eta * h * R0^2))^(-1 / 3)
    return (; R0, R_sim = R(g), R_closed = Rx, rel_err = (R(g) - Rx) / (Rx - R0), volume_kept = sum(g.vol) / V0)
end

"A blow: `plan(t)` gives (breath Pa, pipe pitch rad (0 level, +down), turns per second); returns frames of
(time, positions, triangle temperatures, thicknesses) every `every` steps and the gather."
function blow(plan; dt = 2e-3, seconds = 6.0, every = 5, kw...)
    g = gather(; kw...)
    frames = NamedTuple[]
    spin = 0.0
    for s in 1:round(Int, seconds / dt)
        p, pitch, tps = plan(g.t)
        spin += 2pi * tps * dt
        gw = (sin(pitch) * 9.81, 0.0, -cos(pitch) * 9.81)            # gravity in a pipe that dips its end by `pitch`
        gp = (gw[1], gw[2] * cos(spin) + gw[3] * sin(spin), -gw[2] * sin(spin) + gw[3] * cos(spin))  # seen from the turning pipe
        step!(g, dt; p, grav = gp)
        s % every == 0 && push!(frames, (; t = g.t, X = copy(g.X), T = copy(g.T), h = thickness(g), spin, pitch))
        g.burst > 0 && break
    end
    return frames, g
end
