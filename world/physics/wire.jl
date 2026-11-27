# Copper wire that remembers every bend (s144, project copper-wire). A planar wire as a chain of short segments; each
# joint is a section of round wire under bending: elastic up to the yield moment, then plastic (the bend stays), with
# work hardening (a spot bent before is harder, so a second bend there shifts beside it) and low-cycle fatigue
# (Coffin-Manson with Miner's rule over plastic strain reversals: bent back and forth, a joint cracks and snaps).
# Quasi-static: a bending jig holds the wire left of `i0` and turns the part right of `i1` by an angle; the span
# i0..i1 carries one moment M (pure bending), found by bisection so the joints' angles add up to the turn.
# Let go and M = 0: the elastic part springs back, the plastic part stays.
#   w = Wire(); bend!(w, 40, 46, deg2rad(95)); release!(w); rad2deg(sum(w.thp[40:46]))
# Sources: annealed copper E = 117 GPa, sigma_y0 ~ 60 MPa, Hollomon hardening sigma = sigma0 + K eps^n (K ~ 320 MPa,
# n ~ 0.45, Ludwik fits for OFHC Cu), Coffin-Manson eps_f' ~ 0.6, c ~ -0.6 (Cu fatigue data); a ~1.5 mm wire.

Base.@kwdef mutable struct Wire
    n::Int = 121                 # nodes
    ds::Float64 = 1e-3           # segment length (m)
    d::Float64 = 1.5e-3          # diameter (m)
    E::Float64 = 117e9
    sy0::Float64 = 60e6
    K::Float64 = 320e6
    nh::Float64 = 0.45
    epsf::Float64 = 0.6
    cf::Float64 = -0.6
    thp::Vector{Float64} = zeros(n)      # plastic joint angle (the bend that stays)
    th::Vector{Float64} = zeros(n)       # joint angle now (plastic + elastic)
    ep::Vector{Float64} = zeros(n)       # accumulated plastic strain at the surface (hardening)
    run::Vector{Float64} = zeros(n)      # plastic strain in the current direction of flow
    dir::Vector{Int} = zeros(Int, n)     # direction of the last plastic flow (+1 / -1)
    D::Vector{Float64} = zeros(n)        # fatigue damage (Miner); >= 1 cracks
    broken::Int = 0                      # joint where it snapped (0: whole)
end

EI(w::Wire) = w.E * pi * w.d^4 / 64
Zs(w::Wire) = pi * w.d^3 / 32                       # section modulus: yield moment = sigma * Z
sig(w::Wire, ep) = w.sy0 + w.K * max(ep, 0.0)^w.nh
eps_of(w::Wire, s) = s <= w.sy0 ? 0.0 : ((s - w.sy0) / w.K)^(1 / w.nh)
strain_of(w::Wire, dthp) = abs(dthp) / w.ds * w.d / 2   # surface strain of a plastic joint rotation

"Joint i's angle under moment M, and its plastic increment (not committed)."
function joint_response(w::Wire, i, M)
    My = sig(w, w.ep[i]) * Zs(w)
    dthp = 0.0
    if abs(M) > My
        dep = eps_of(w, abs(M) / Zs(w)) - w.ep[i]
        dthp = sign(M) * dep * w.ds * 2 / w.d
    end
    return w.thp[i] + dthp + M * w.ds / EI(w), dthp
end

function commit!(w::Wire, i, M)
    th, dthp = joint_response(w, i, M)
    w.th[i] = th
    dthp == 0 && return
    s = Int(sign(dthp)); de = strain_of(w, dthp)
    if w.dir[i] != 0 && s != w.dir[i]                 # reversal: close a half cycle
        amp = w.run[i] / 2                            # plastic strain amplitude
        amp > 0 && (w.D[i] += 0.5 / (0.5 * (amp / w.epsf)^(1 / w.cf)))
        w.run[i] = 0.0
    end
    w.dir[i] = s; w.run[i] += de; w.ep[i] += de; w.thp[i] += dthp
    w.D[i] >= 1 && w.broken == 0 && (w.broken = i)
    return
end

"Turn the wire right of joint `i1` by `phi` (rad) relative to the part left of `i0`, in `steps` small increments.
Returns the moment history (N m) so a film can show how hard it was."
function bend!(w::Wire, i0, i1, phi; steps = 60)
    span = i0:i1
    S0 = sum(w.th[span]); Ms = Float64[]
    for k in 1:steps
        S = S0 + phi * k / steps
        lo, hi = -50.0, 50.0
        for _ in 1:80
            M = (lo + hi) / 2
            sum(first(joint_response(w, i, M)) for i in span) < S ? (lo = M) : (hi = M)
        end
        M = (lo + hi) / 2
        for i in span; commit!(w, i, M); end
        push!(Ms, M)
        w.broken != 0 && break
    end
    return Ms
end

"Let go: every joint springs back to its plastic angle."
release!(w::Wire) = (w.th .= w.thp; w)

"Hang a weight `F` (N, downward) at node `j`: each joint carries the moment of the weight about it; iterate the shape
(plastic opening changes the levers). Returns the joint angles while loaded."
function hang!(w::Wire, j, F; iters = 30)
    for _ in 1:iters
        P = shape(w)
        for i in 2:j-1
            M = -F * (P[j][1] - P[i][1])        # weight pulls the tip down: moment about joint i
            commit!(w, i, M)
        end
    end
    return w.th
end

"A round tube along the planar centre line (nodes `range`), lying flat at `origin`; the including module needs
GeometryBasics. Used by movies/wire.jl and plugins/wirebench.jl."
function wire_tube(w::Wire, th, origin; r = Float32(w.d / 2), nr = 10, range = 1:w.n, cut = w.n)
    P0 = shape(w; angles = th)
    tang(k) = k < w.n ? atan(P0[k+1][2] - P0[k][2], P0[k+1][1] - P0[k][1]) : atan(P0[k][2] - P0[k-1][2], P0[k][1] - P0[k-1][1])
    V = Point3f[]; F = TriangleFace{Int}[]
    nodes = [min(i, cut) for i in range]        # nodes past `cut` fold onto it: same vertex count after a break
    for k in nodes
        a = tang(k)
        nrm = Vec3f(-sin(a), cos(a), 0)
        c = origin + Vec3f(P0[k][1], P0[k][2], r)
        for j in 0:nr-1
            phi = 2pi * j / nr
            push!(V, c + r * (Float32(cos(phi)) * nrm + Float32(sin(phi)) * Vec3f(0, 0, 1)))
        end
    end
    for i in 1:length(nodes)-1, j in 0:nr-1
        a = (i - 1) * nr + j + 1; b = (i - 1) * nr + mod(j + 1, nr) + 1
        push!(F, TriangleFace(a, b, b + nr)); push!(F, TriangleFace(a, b + nr, a + nr))
    end
    cut >= last(range) && return GeometryBasics.normal_mesh(GeometryBasics.Mesh(V, F))
    # folded rings touch only zero-area faces: their normals come out NaN, which must not reach the renderer
    nm = GeometryBasics.normal_mesh(GeometryBasics.Mesh(V, F))
    N = [any(isnan, n) ? Vec3f(0, 0, 1) : Vec3f(n) for n in GeometryBasics.normals(nm)]
    return GeometryBasics.Mesh(GeometryBasics.coordinates(nm), GeometryBasics.faces(nm); normal = N)
end

"Per-vertex colours for `wire_tube`: fresh copper, dulling towards dark brown where a joint has tired (damage D),
so the snap is seen coming. Raster and browser show it; the tracer's measured Copper() ignores `color`."
function wire_colors(w::Wire; nr = 10, range = 1:w.n)
    fresh = (0.85f0, 0.45f0, 0.30f0); tired = (0.28f0, 0.20f0, 0.17f0)
    C = NTuple{3,Float32}[]
    for i in range, _ in 1:nr
        f = Float32(clamp(w.D[i], 0, 1)^0.6)
        push!(C, fresh .+ f .* (tired .- fresh))
    end
    return C
end

"Planar centre line of the wire (first segment along +x from the origin)."
function shape(w::Wire; angles = w.th)
    P = Vector{NTuple{2,Float64}}(undef, w.n); a = 0.0; P[1] = (0.0, 0.0)
    for i in 2:w.n
        a += angles[i - 1]
        P[i] = (P[i - 1][1] + w.ds * cos(a), P[i - 1][2] + w.ds * sin(a))
    end
    return P
end
