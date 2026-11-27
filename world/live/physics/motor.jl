# A motor fitted by hand (s154, project motor, big goal "From beach stones to an electric cart").
# Nothing in here knows it is a motor. The parts are: magnets (em.jl, any mesh, any material), a coil of wire turns
# on a rotor that turns on an axle, a split copper ring on the same axle, two brushes pressed against the ring, and
# cells. Every step:
#   - contact: each brush touches whichever ring segment lies under it at this angle (or a gap, or both segments);
#   - circuit: from what touches what. Cells, brush contacts and the coil's wire (resistance from its length,
#     section and copper's resistivity) in one loop; the turns cutting the field give the motional EMF (v x B).dl;
#     L dI/dt for the coil's own inductance; an open loop drops the current and the coil's energy 1/2 L I^2 goes
#     into a spark;
#   - force: I dl x B on every segment of every turn in the magnets' field (em.jl) -> torque about the axle;
#   - the rotor: J dw/dt = torque - bearing and brush friction (Coulomb, from the weight and the brush springs).
# So the dead spot, starting or not, the direction, the speed limit (back-EMF), and what a misbuilt motor does all
# come out of the parts. Looked first (rule 6): RomeoDB has circuit simulators (ModelingToolkitStandardLibrary
# Electrical: a DC motor block with a given torque constant, i.e. the answer put in) and Biot-Savart packages; none
# takes a coil's geometry in a magnet's field with contact-made switching, so this couples em.jl's field to a loop.
module Motor
using LinearAlgebra
isdefined(@__MODULE__, :EM) || include(joinpath(@__DIR__, "em.jl"))
using .EM

const V3 = NTuple{3,Float64}

"Rotation about the x axis (the axle) by θ."
Rx(θ) = [1.0 0 0; 0 cos(θ) -sin(θ); 0 sin(θ) cos(θ)]

"""
A build: every part and where it sits. Axle along x through the origin.
- `magnets`: em.jl magnets (stator), placed in the world.
- `turn`: one turn of the coil in the rotor frame (closed polyline, metres); wound `N` times with wire of radius `rw`.
- `ring_r`, `seg_c`: commutator radius and the rotor-frame angles of the two segments' centres (segment 1 joined
  to the coil's start, segment 2 to its end); `gap`: the angular gap between segments.
- `brushes`: world angles (about x, from +y towards +z) where the two brushes touch the ring, `brush_w` their
  angular width, `brush_F` their spring force (N). Brush 1 goes to the cells' plus side.
- `cells`: (emf V, internal resistance Ω) each, in series. `R_contact` per brush.
- `m_rotor`, `J_extra`: the rotor's mass and inertia beside the copper; `r_axle`, `mu_bearing`, `mu_brush`.
"""
Base.@kwdef mutable struct Build
    magnets::Vector{EM.Magnet}
    turn::Vector{V3}
    N::Int = 60
    rw::Float64 = 0.2e-3
    ring_r::Float64 = 0.006
    seg_c::Tuple{Float64,Float64} = (0.0, pi)
    gap::Float64 = deg2rad(20)
    brushes::Tuple{Float64,Float64} = (pi / 2, -pi / 2)
    brush_w::Float64 = deg2rad(8)
    brush_F::Float64 = 0.05
    cells::Vector{Tuple{Float64,Float64}} = [(0.75, 3.0) for _ in 1:3]
    R_contact::Float64 = 0.05
    m_rotor::Float64 = 0.012
    J_extra::Float64 = 2e-6
    r_axle::Float64 = 0.0015
    mu_bearing::Float64 = 0.25
    mu_brush::Float64 = 0.3
end

perimeter(t) = sum(norm(collect(t[k+1]) .- t[k]) for k in 1:length(t)-1)
wire_length(b::Build) = b.N * perimeter(b.turn)
wire_R(b::Build) = EM.MATERIALS[:copper].resistivity * wire_length(b) / (pi * b.rw^2)
copper_mass(b::Build) = EM.MATERIALS[:copper].density * wire_length(b) * pi * b.rw^2

"Inertia of the copper turns about the axle (each segment's mass at its distance from x) plus the rest."
function inertia(b::Build)
    mper = EM.MATERIALS[:copper].density * pi * b.rw^2 * b.N
    J = b.J_extra
    for k in 1:length(b.turn)-1
        a = collect(b.turn[k]); c = collect(b.turn[k+1]); mid = (a + c) / 2
        J += mper * norm(c - a) * (mid[2]^2 + mid[3]^2)
    end
    J
end

"Self inductance of the coil: Neumann's double integral over one turn (wire radius as the cut-off), times N^2."
function inductance(b::Build; sub = 8)
    pts = V3[]
    for k in 1:length(b.turn)-1, s in 0:sub-1
        push!(pts, Tuple(collect(b.turn[k]) .+ (s / sub) .* (collect(b.turn[k+1]) .- b.turn[k])))
    end
    push!(pts, b.turn[end])
    L = 0.0
    for i in 1:length(pts)-1, j in 1:length(pts)-1
        dli = collect(pts[i+1]) .- pts[i]; dlj = collect(pts[j+1]) .- pts[j]
        r = norm((collect(pts[i+1]) .+ pts[i]) ./ 2 .- (collect(pts[j+1]) .+ pts[j]) ./ 2)
        L += dot(dli, dlj) / max(r, b.rw * 0.78)       # GMD of a round wire's cross-section
    end
    EM.MU0 / (4pi) * L * b.N^2
end

angdiff(a, c) = mod(a - c + pi, 2pi) - pi

"Which ring segment (1, 2, or 0 for a gap) brush `k` touches with the rotor at θ: overlap of its patch with a segment."
function touching(b::Build, k, θ)
    β = b.brushes[k] - θ                          # the brush's angle in the rotor frame
    half = (pi - b.gap) / 2                       # each segment spans pi - gap
    hits = [abs(angdiff(β, c)) < half + b.brush_w / 2 for c in b.seg_c]
    return hits[1] && hits[2] ? 3 : hits[1] ? 1 : hits[2] ? 2 : 0
end

"""
    circuit_sign(b, θ) -> s

+1: current flows into the coil's start (brush 1 on segment 1, brush 2 on segment 2); -1: reversed; 0: open (a brush
in a gap) or the coil bypassed (a brush bridging both segments: the cells short through the ring, :short).
"""
function circuit_sign(b::Build, θ)
    t1 = touching(b, 1, θ); t2 = touching(b, 2, θ)
    (t1 == 0 || t2 == 0) && return 0, :open
    (t1 == 3 || t2 == 3 || t1 == t2) && return 0, :short
    return (t1 == 1 ? 1 : -1), :closed
end

"The coil's world path at rotor angle θ (one turn)."
coil_path(b::Build, θ) = (R = Rx(θ); [Tuple(R * collect(p)) for p in b.turn])

"Torque about the axle per amp (N m / A, all N turns) and the motional EMF per rad/s along the coil (V s), at θ."
function coil_coupling(b::Build, θ)
    path = coil_path(b, θ)
    Bf(p) = EM.B(b.magnets, p)
    _, T = EM.force(Bf, path, 1.0)
    # motional EMF of a turn turning at 1 rad/s: v = x̂ × r; emf = Σ (v × B) · dl
    e = 0.0
    for k in 1:length(path)-1
        a = collect(path[k]); c = collect(path[k+1]); mid = (a + c) / 2
        v = cross([1.0, 0, 0], mid)
        e += dot(cross(v, Bf(mid)), c - a)
    end
    return b.N * T[1], b.N * e
end

"""
A rotor being stepped (live in a plugin, or by `spin`). The field coupling of a rigid rotor depends only on θ, so it
is tabulated once per build (rebuild the State when a part moves). `on`: the last wire touches (the switch).
"""
mutable struct State
    θ::Float64; ω::Float64; I::Float64; τ::Float64; s_prev::Int; t::Float64; on::Bool
    kt::Vector{Float64}; ke::Vector{Float64}
    J::Float64; L::Float64; Rw::Float64; Rloop::Float64; E::Float64; τfric::Float64
    sparks::Vector{Tuple{Float64,Float64}}; shorts::Int
end

function State(b::Build; θ0 = 0.3, ω0 = 0.0, nθ = 180, on = true)
    θs = range(0, 2pi; length = nθ + 1)[1:end-1]
    kt = zeros(nθ); ke = zeros(nθ)
    for (i, θ) in enumerate(θs)
        kt[i], ke[i] = coil_coupling(b, θ)
    end
    Rw = wire_R(b)
    E = sum(first, b.cells; init = 0.0); Rc = sum(last, b.cells; init = 0.0)
    m = b.m_rotor + copper_mass(b)
    τfric = b.mu_bearing * m * 9.81 * b.r_axle + 2 * b.mu_brush * b.brush_F * b.ring_r
    State(θ0, ω0, 0.0, 0.0, 0, 0.0, on, kt, ke, inertia(b), inductance(b), Rw, Rc + Rw + 2b.R_contact, E, τfric,
          Tuple{Float64,Float64}[], 0)
end

function interp(tab, θ)
    n = length(tab); x = mod(θ, 2pi) / (2pi / n); i = floor(Int, x); f = x - i
    (1 - f) * tab[mod(i, n)+1] + f * tab[mod(i + 1, n)+1]
end

"A flick of the beak: the rotor's spin changes by Δω (rad/s)."
flick!(st::State, Δω) = (st.ω += Δω; st)

"""
    step!(st, b, dt; h = 2e-4)

Advance the rotor by `dt` seconds in substeps of at most `h`: contact -> circuit (L dI/dt = s E + emf - R I) ->
torque -> Coulomb friction -> θ.
"""
function step!(st::State, b::Build, dt; h = 2e-4)
    n = max(1, ceil(Int, dt / h)); h = dt / n
    for _ in 1:n
        s, kind = st.on ? circuit_sign(b, st.θ) : (0, :open)
        kind == :short && (st.shorts += 1)
        if s == 0
            st.I != 0 && push!(st.sparks, (st.t, 0.5 * st.L * st.I^2))   # the coil's energy goes into a spark
            st.I = 0.0
        else
            s != st.s_prev && st.s_prev != 0 && push!(st.sparks, (st.t, 0.5 * st.L * st.I^2))  # handover under current
            s != st.s_prev && (st.I = 0.0)
            emf = interp(st.ke, st.θ) * st.ω                  # motional EMF along the turn
            st.I = (st.I + h / st.L * (s * st.E + emf)) / (1 + h * st.Rloop / st.L)   # implicit in I
        end
        st.s_prev = s
        st.τ = interp(st.kt, st.θ) * st.I
        ω = st.ω
        α = (ω == 0.0 && abs(st.τ) <= st.τfric) ? 0.0 : (st.τ - st.τfric * sign(ω == 0 ? st.τ : ω)) / st.J
        ωn = ω + α * h
        (ω != 0 && sign(ωn) != sign(ω)) && (ωn = 0.0)        # friction stops, never reverses
        st.ω = ωn; st.θ += ωn * h; st.t += h
    end
    st
end

"""
    spin(b; seconds = 2, dt = 2e-4, θ0 = 0.3, ω0 = 0, nudges = [])

Runs the build. `nudges`: (time, Δω) flicks of the beak. Returns the time series and events (sparks with their
energy, shorts, the final state: :runs, :stalled, :backwards).
"""
function spin(b::Build; seconds = 2.0, dt = 2e-4, θ0 = 0.3, ω0 = 0.0, nudges = Tuple{Float64,Float64}[], nθ = 180)
    st = State(b; θ0, ω0, nθ)
    ts = Float64[]; θh = Float64[]; ωh = Float64[]; Ih = Float64[]; τh = Float64[]
    nexti = 1; nn = sort(nudges; by = first)
    for n in 0:round(Int, seconds / dt)
        t = n * dt
        while nexti <= length(nn) && nn[nexti][1] <= t
            flick!(st, nn[nexti][2]); nexti += 1
        end
        step!(st, b, dt; h = dt)
        if n % 25 == 0
            push!(ts, t); push!(θh, st.θ); push!(ωh, st.ω); push!(Ih, st.I); push!(τh, st.τ)
        end
    end
    tail = ωh[max(1, end - 20):end]
    state = all(==(0.0), tail) ? :stalled : sum(tail) > 0 ? :runs : :backwards
    return (; t = ts, θ = θh, ω = ωh, I = Ih, τ = τh, sparks = st.sparks, shorts = st.shorts, state,
              rev_s = st.ω / 2pi, J = st.J, L = st.L, R_wire = st.Rw, R_loop = st.Rloop, τ_friction = st.τfric,
              peak_τ = maximum(abs, st.kt) * st.E / st.Rloop)
end

# ---- the parts as built on the bench (a two-stone stator, a rectangular coil, a split ring) ----

"Two stones either side of the rotor along y, magnetised along +y (`flip` turns one or both round)."
function stator(; material = :ferrite, R = 0.012, H = 0.012, gap = 0.024, flip = (false, false))
    v, f = EM.cylinder_mesh(R, H)
    Br = EM.MATERIALS[material].Br
    ms = EM.Magnet[]
    for (k, side) in enumerate((-1.0, 1.0))
        # cylinder axis along +y: rotate z -> y; its near face sits `gap/2` from the axle
        Rm = [1.0 0 0; 0 0 1; 0 -1 0]             # body z -> world y
        y0 = side < 0 ? -gap / 2 - H : gap / 2
        M = (flip[k] ? -1 : 1) * Br / EM.MU0
        push!(ms, EM.magnet(v, f, (0.0, 0.0, M); pos = (0.0, y0, 0.0), R = Rm))
    end
    ms
end

"One rectangular turn in the rotor frame: sides along the axle at z = ±a, length l (closed)."
function rect_turn(; l = 0.03, a = 0.009, n = 10)
    c = V3[(-l / 2, 0, -a), (l / 2, 0, -a), (l / 2, 0, a), (-l / 2, 0, a), (-l / 2, 0, -a)]
    pts = V3[]
    for k in 1:4, s in 0:n-1                       # n points per side: the field is sampled along each side
        push!(pts, Tuple(collect(c[k]) .+ (s / n) .* (collect(c[k+1]) .- c[k])))
    end
    push!(pts, c[end]); pts
end

"The bench motor three times bench size (film and live bench): stones 7 cm, rotor 9 cm, 6 cells, a 10 deg ring gap."
function big_bench(; s = 3.0, flip = (false, false), cells = 6)
    Build(; magnets = stator(; R = 0.012s, H = 0.012s, gap = 0.024s, flip), turn = rect_turn(; l = 0.03s, a = 0.009s),
        N = 80, rw = 0.35e-3, ring_r = 0.006s, brush_F = 0.06, gap = deg2rad(10), m_rotor = 0.012 * s^3 * 0.5,
        J_extra = 2e-6 * s^5 * 0.5, r_axle = 0.0015s, cells = [(0.75, 3.0) for _ in 1:cells])
end

"A bench build with sensible parts; keywords change any of them."
function bench(; material = :ferrite, flip = (false, false), N = 60, cells = 3, brush_shift = 0.0, kw...)
    Build(; magnets = stator(; material, flip), turn = rect_turn(), N,
          cells = [(0.75, 3.0) for _ in 1:cells], brushes = (pi / 2 + brush_shift, -pi / 2 + brush_shift), kw...)
end

"What each misbuild does (the test for this file): a table of builds and what came out."
function motor_cases(; seconds = 1.5)
    cases = [
        ("built right", bench(), (; θ0 = pi / 2)),
        ("started on the dead spot", bench(), (; θ0 = 0.0)),
        ("dead spot, then a beak flick", bench(), (; θ0 = 0.0, nudges = [(0.3, 40.0)])),
        ("both stones turned round", bench(flip = (true, true)), (; θ0 = pi / 2)),
        ("one stone turned round", bench(flip = (true, false)), (; θ0 = pi / 2)),
        ("beach lodestone stator", bench(material = :magnetite), (; θ0 = pi / 2)),
        ("brushes a quarter turn off", bench(brush_shift = pi / 2), (; θ0 = pi / 2)),
        ("one cell", bench(cells = 1), (; θ0 = pi / 2)),
    ]
    map(cases) do (name, b, kw)
        r = spin(b; seconds, kw...)
        (; name, state = r.state, rev_s = round(r.rev_s, digits = 2), sparks = length(r.sparks),
           spark_mJ = round(1e3 * sum(last, r.sparks; init = 0.0), digits = 3), peak_mNm = round(1e3 * r.peak_τ, digits = 3),
           fric_mNm = round(1e3 * r.τ_friction, digits = 3))
    end
end

end # module
