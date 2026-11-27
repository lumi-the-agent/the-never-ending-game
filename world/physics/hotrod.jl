# A thin wire between two posts that bows as it heats (s156, projects/drawn-wire.md). Copper grows ~1.8e-5 per kelvin:
# a 10 cm wire at 1300 K is ~1.8 mm longer, and between fixed posts that length has nowhere to go but a bow (~8 mm).
# The wire is a planar chain (x along, z up) of inextensible segments whose rest length follows each segment's
# temperature, with bending stiffness E(T) pi r^4 / 4 at each joint, its own weight, both ends clamped (wound on the
# posts: ghost nodes hold the end angles level). XPBD (Macklin 2016): distance constraints with zero compliance,
# bending angle constraints with compliance 1/k. A parted segment loses its constraints and the two halves hang from
# their posts as cantilevers and swing. The thermal strain is elastic only: hot copper also creeps (it would sag more).
# Sources: copper mean expansion 1.7e-5/K at room temperature rising to ~2.0e-5/K near melting (thermal strain ~2%
#   at 1358 K, Touloukian); E 130 GPa at 293 K falling to ~65 GPa near melting (Ledbetter, Simmons-Wang trend).
#   r = HotRod.Rod(l0, r); HotRod.settle!(rod, T, parted; seconds)   # rod.p: node positions (m, relative to the left post)
module HotRod

const G = 9.81
const DENS = 8960.0

thermal_strain(T) = (1.7e-5 + 0.15e-5 * (T - 293.15) / 1065) * (T - 293.15)
youngs(T) = 130e9 * (1 - 0.47 * (T - 293.15) / 1065)

mutable struct Rod
    l0::Vector{Float64}              # rest length of each segment at room temperature
    r::Vector{Float64}               # radius of each segment
    p::Vector{NTuple{2,Float64}}     # nodes (x, z), node 1 and node n+1 are on the posts
    v::Vector{NTuple{2,Float64}}
end

"A wire strung by a beak is never dead straight: `bow` (m) of initial sag (a perfectly straight column never buckles
in Gauss-Seidel: s156 first test kept a 1300 K wire straight)."
function Rod(l0::AbstractVector, r::AbstractVector; bow = 2e-4)
    x = cumsum(vcat(0.0, l0)); Lt = x[end]
    Rod(collect(Float64, l0), collect(Float64, r), [(xi, -bow * sin(pi * xi / Lt)) for xi in x], [(0.0, 0.0) for _ in x])
end

perp(a) = (-a[2], a[1])
sub(a, b) = (a[1] - b[1], a[2] - b[2])
n2(a) = a[1]^2 + a[2]^2
turn(a, b) = atan(a[1] * b[2] - a[2] * b[1], a[1] * b[1] + a[2] * b[2])

"""
    settle!(rod, T, parted; seconds, dt, iters, damping)

Moves the wire `seconds` forward at segment temperatures `T` with the segments `parted` (a Bool per segment)
gone. Real dynamics (it swings), with a light air damping (per second) for a wire this thin.
"""
function settle!(rod::Rod, T, parted; seconds = 1 / 24, dt = 1e-4, iters = 12, damping = 6.0)
    n = length(rod.l0); p = rod.p; v = rod.v
    L = [rod.l0[i] * (1 + thermal_strain(T[i])) for i in 1:n]
    m = [DENS * pi * rod.r[i]^2 * L[i] for i in 1:n]
    w = zeros(n + 1)                       # inverse node masses; the posts' nodes are fixed
    for i in 1:n
        parted[i] && continue
        w[i] += 0.5 * m[i]; w[i+1] += 0.5 * m[i]
    end
    w = [i in (1, n + 1) || wi == 0 ? 0.0 : 1 / wi for (i, wi) in enumerate(w)]
    # bending stiffness at each node 1..n+1 (node j joins segments j-1 and j; at the posts the ghost segment)
    EI(i) = youngs(T[i]) * pi * rod.r[i]^4 / 4
    left = (p[1][1] - L[1], p[1][2]); right = (p[n+1][1] + L[n], p[n+1][2])
    steps = max(1, round(Int, seconds / dt)); h = seconds / steps
    keep = exp(-damping * h)
    for _ in 1:steps
        old = copy(p)
        for j in 1:n+1
            w[j] == 0 && continue
            p[j] = (p[j][1] + h * v[j][1], p[j][2] + h * v[j][2] - G * h^2)
        end
        lam = zeros(n + 1)
        for _ in 1:iters
            for i in 1:n                                   # length of each whole segment
                parted[i] && continue
                a, b = i, i + 1
                d = sub(p[b], p[a]); len = sqrt(n2(d)); ws = w[a] + w[b]
                (ws == 0 || len == 0) && continue
                c = (len - L[i]) / (len * ws)
                p[a] = (p[a][1] + w[a] * c * d[1], p[a][2] + w[a] * c * d[2])
                p[b] = (p[b][1] - w[b] * c * d[1], p[b][2] - w[b] * c * d[2])
            end
            for j in 1:n+1                                 # bending at node j between the segment before and after it
                i0 = j - 1; i1 = j
                (i0 >= 1 && parted[i0]) && continue
                (i1 <= n && parted[i1]) && continue
                pa = i0 >= 1 ? p[j-1] : left; pc = i1 <= n ? p[j+1] : right
                wa = i0 >= 1 ? w[j-1] : 0.0; wc = i1 <= n ? w[j+1] : 0.0
                a = sub(p[j], pa); b = sub(pc, p[j])
                la = n2(a); lb = n2(b)
                (la == 0 || lb == 0) && continue
                ga = perp(a) ./ la; gb = perp(b) ./ lb    # d(theta)/d(pa) = ga, d/d(pc) = gb, d/d(p_j) = -ga - gb
                gj = (-ga[1] - gb[1], -ga[2] - gb[2])
                th = turn(a, b)
                lseg = 0.5 * ((i0 >= 1 ? L[i0] : L[1]) + (i1 <= n ? L[i1] : L[n]))
                k = EI(clamp(j, 1, n)) / lseg
                alpha = 1 / (k * h^2)
                den = wa * n2(ga) + w[j] * n2(gj) + wc * n2(gb) + alpha
                den == 0 && continue
                dl = (-th - alpha * lam[j]) / den; lam[j] += dl
                i0 >= 1 && (p[j-1] = (p[j-1][1] + wa * dl * ga[1], p[j-1][2] + wa * dl * ga[2]))
                p[j] = (p[j][1] + w[j] * dl * gj[1], p[j][2] + w[j] * dl * gj[2])
                i1 <= n && (p[j+1] = (p[j+1][1] + wc * dl * gb[1], p[j+1][2] + wc * dl * gb[2]))
            end
        end
        for j in 1:n+1
            v[j] = w[j] == 0 ? (0.0, 0.0) : (keep * (p[j][1] - old[j][1]) / h, keep * (p[j][2] - old[j][2]) / h)
        end
    end
    return rod
end

"Lowest point of the wire below the posts (m, positive down)."
sag(rod::Rod) = -minimum(q -> q[2], rod.p)

end
