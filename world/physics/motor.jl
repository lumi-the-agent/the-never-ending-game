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
    drum::Bool = false             # s172: a round iron drum rotor with two coils and 4 segments (physics/motor2d.jl table)
    coils::Int = 1                 # coils in series on the rotor (wire resistance and copper count them)
end

perimeter(t) = sum(norm(collect(t[k+1]) .- t[k]) for k in 1:length(t)-1)
wire_length(b::Build) = b.coils * b.N * perimeter(b.turn)
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

# s172: the iron drum's torque per ampere-turn over its 90 deg period, solved in 2D with saturating iron (physics/motor2d.jl,
# Ferrite.jl; validated: its air core is within 8% of em.jl's 3D one), times the 3D end correction 30.4 / 27.5. The table
# already holds the 4-segment commutation of both coils, so a drum's circuit is always closed.
const DRUM_TABLE = joinpath(@__DIR__, "data", "drum2-torque.csv")
const DRUM_END3D = 30.4 / 27.5
function drum_kt(b::Build, θ)
    rows = [parse.(Float64, split(l, ",")) for l in eachline(DRUM_TABLE) if !startswith(l, "#") && !isempty(strip(l))]
    θt = deg2rad.(getindex.(rows, 1)); kt = getindex.(rows, 2)
    h = θt[2] - θt[1]; x = mod(θ, pi / 2); i = clamp(floor(Int, x / h) + 1, 1, length(θt) - 1); f = (x - θt[i]) / h
    DRUM_END3D * b.N * ((1 - f) * kt[i] + f * kt[i+1])
end

function State(b::Build; θ0 = 0.3, ω0 = 0.0, nθ = 180, on = true)
    θs = range(0, 2pi; length = nθ + 1)[1:end-1]
    kt = zeros(nθ); ke = zeros(nθ)
    for (i, θ) in enumerate(θs)
        kt[i], ke[i] = b.drum ? (k = drum_kt(b, θ); (k, -k)) : coil_coupling(b, θ)   # back-EMF per rad/s = -torque per amp
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
        s, kind = st.on ? (b.drum ? (1, :closed) : circuit_sign(b, st.θ)) : (0, :open)
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

"""
A magnet stone (s158): a lump about a cylinder (radius R, height H, axis z) with one face dressed flat and round at
z = `face` (the pole face toward the rotor) and everything else bulging 0..`bump` R outward, smooth, seeded. Closed and
outward-wound, so em.jl magnetises exactly the shape that is drawn (motorlook.jl draws these same triangles).
"""
function rough_stone(R, H; face = 0.0, seed = 1, bump = 0.12, n = 64, nz = 10)
    rng = UInt64(seed) * 0x9E3779B97F4A7C15
    rnd() = (rng = rng * 6364136223846793005 + 1442695040888963407; Float64(rng >> 11) / 2.0^53)
    # lumps that are not round about the axis: cosines along random 3D directions (a blobby, rock-like field), two
    # octaves; a stone is wider one way than the other (aspect) and leans a little
    dirs = [(begin u = (2rnd() - 1, 2rnd() - 1, 2rnd() - 1); u ./ sqrt(sum(u .^ 2)) end, 2 + 7rnd(), 2pi * rnd(), 0.4 + 0.6rnd())
            for _ in 1:10]
    asp = 0.82 + 0.18rnd(); tilt = 0.12 * (2rnd() - 1)
    function grow(θ, z)                              # small at the dressed face, up to `bump` far from it
        d = abs(z - face) / H
        p = (cos(θ), sin(θ), (z - H / 2) / R)
        s = sum(a * cos(f * sum(p .* u) + ph) for (u, f, ph, a) in dirs) / sum(dv[4] for dv in dirs)
        bump * R * (0.25 + 0.75 * min(1.0, 2.5d)) * (0.5 + 1.2 * s)
    end
    # chipped faces (s158: smooth lumps of +-4 mm drew as a plain can): the stone starts wider and is cut by random
    # planes, flat facets like a broken beach stone; the dressed face stays flat (cuts only reach the far part fully)
    cuts = [(2pi * rnd(), 0.35 * (2rnd() - 1), 0.84 + 0.2rnd()) for _ in 1:8]     # (azimuth, z-slope, distance / R)
    function radius(θ, z)
        r = 1.18R * (1 + (asp - 1) * cos(θ)^2) + tilt * R * cos(θ) * abs(z - face) / H + grow(θ, z)
        d = abs(z - face) / H
        for (ψ, kz, dk) in cuts
            c = cos(θ - ψ)
            c > 0.05 || continue
            lim = (dk * R - kz * R * (d - 0.5)) / c                    # a plane, a little slanted along the stone
            r = min(r, lim)
        end
        r
    end
    v = V3[]; zs = range(0.0, H; length = nz + 1)
    far = face == 0 ? H : 0.0
    push!(v, (0.0, 0.0, 0.0 + (far == 0 ? -0.7bump * R : 0.0)))            # cap centres (the far one domed out)
    push!(v, (0.0, 0.0, H + (far == H ? 0.7bump * R : 0.0)))
    for z in zs, i in 0:n-1
        θ = 2pi * i / n; r = max(0.6R, radius(θ, z))
        dz = abs(z - far) < 1e-12 ? (far == 0 ? -1 : 1) * 0.5 * grow(θ, z) : 0.0   # the far rim lumps outward too
        push!(v, (r * cos(θ), r * sin(θ), z + dz))
    end
    idx(j, i) = 2 + j * n + mod(i, n) + 1
    f = NTuple{3,Int}[]
    for i in 0:n-1
        push!(f, (1, idx(0, i + 1), idx(0, i)))                 # bottom (normal -z)
        push!(f, (2, idx(nz, i), idx(nz, i + 1)))               # top (+z)
        for j in 0:nz-1
            b0, b1, t0, t1 = idx(j, i), idx(j, i + 1), idx(j + 1, i), idx(j + 1, i + 1)
            push!(f, (b0, b1, t1)); push!(f, (b0, t1, t0))
        end
    end
    v, f
end

"""
The two stator stones in body coordinates with where they sit: [(v, f, pos, Rm)], cylinder axis z turned to +y, the
near (dressed) face `gap/2` from the axle. `rough = false`: plain cylinders (as before s158).
"""
function stator_shapes(; R = 0.012, H = 0.012, gap = 0.024, rough = true)
    Rm = [1.0 0 0; 0 0 1; 0 -1 0]                 # body z -> world y
    map(enumerate((-1.0, 1.0))) do (k, side)
        y0 = side < 0 ? -gap / 2 - H : gap / 2
        v, f = rough ? rough_stone(R, H; face = side < 0 ? H : 0.0, seed = 7 + k) : EM.cylinder_mesh(R, H)
        (; v, f, pos = (0.0, y0, 0.0), Rm)
    end
end

"Two stones either side of the rotor along y, magnetised along +y (`flip` turns one or both round)."
function stator(; material = :ferrite, R = 0.012, H = 0.012, gap = 0.024, flip = (false, false), rough = true)
    Br = EM.MATERIALS[material].Br
    ms = EM.Magnet[]
    for (k, sh) in enumerate(stator_shapes(; R, H, gap, rough))
        M = (flip[k] ? -1 : 1) * Br / EM.MU0
        # the rough stone has 1056 small faces: 3x3 samples each are within 1% of 6x6 (5.13 vs 5.10 mN m) at 1/4 the cost
        push!(ms, EM.magnet(sh.v, sh.f, (0.0, 0.0, M); n = rough ? 3 : 6, pos = sh.pos, R = sh.Rm))
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

"""
The big bench motor with a round iron DRUM rotor (s172, project winch): the stones of big_bench, a 2.3 kg iron drum
(r 3.2 cm, 9 cm long, 4 mm gap) carrying two coils of N turns in slots, 4 commutator segments, on six clay pots
(0.78 V, 0.5 Ohm walls each). `mu_bearing` 0.25 dry wood, ~0.05 greased.
"""
function iron_drum_bench(; N = 80, cells = 6, mu_bearing = 0.25)
    m_fe = 7870 * pi * 0.032^2 * 0.09
    Build(; magnets = stator(; R = 0.036, H = 0.036, gap = 0.072, rough = false), turn = rect_turn(; l = 0.09, a = 0.027),
        N, coils = 2, drum = true, rw = 0.35e-3, ring_r = 0.018, brush_F = 0.06, m_rotor = m_fe, J_extra = 0.5 * m_fe * 0.032^2,
        r_axle = 0.003, mu_bearing, cells = [(0.78, 0.5) for _ in 1:cells])
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

# ---- a drum rotor: several coils on an n-segment ring (s157, todo #743) ----
# One coil on a 2-segment ring has a TRUE dead spot: at the angle where the coil faces the stones its torque is zero
# whatever the current, and the brushes change over right there. Every toy motor has three coils at 120 deg and a
# 3-segment ring instead (Hefner-Alteneck's drum winding, 1872: the coils wound across the drum, crossing at the
# ends). The coils form a closed ring (a delta): coil k joins segment k to segment k+1, each junction soldered to its
# segment. The brushes feed whichever segments lie under them and the current splits between the coils by the
# circuit itself (one coil straight across, the other two in series), so at every angle some coil pulls.

"""
A drum build. `turns[k]`: one turn of coil k in the rotor frame (closed polyline), wound `N` times; coil k runs from
segment k to segment mod1(k+1, n). `seg_c`: the rotor-frame angles of the n segments' centres; `gap` between
neighbouring segments. The rest as in `Build`.
"""
Base.@kwdef mutable struct Drum
    magnets::Vector{EM.Magnet}
    turns::Vector{Vector{V3}}
    N::Int = 60
    rw::Float64 = 0.2e-3
    ring_r::Float64 = 0.006
    seg_c::Vector{Float64}
    gap::Float64 = deg2rad(10)
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

ncoils(d::Drum) = length(d.turns)
coil_R(d::Drum, k) = EM.MATERIALS[:copper].resistivity * d.N * perimeter(d.turns[k]) / (pi * d.rw^2)
coil_build(d::Drum, k) = Build(; magnets = d.magnets, turn = d.turns[k], N = d.N, rw = d.rw)

"Segments brush `k` overlaps with the rotor at θ (a Bool per segment: none in a gap, two when it bridges them)."
function touching(d::Drum, k, θ)
    β = d.brushes[k] - θ
    half = (2pi / length(d.seg_c) - d.gap) / 2
    [abs(angdiff(β, c)) < half + d.brush_w / 2 for c in d.seg_c]
end

"Neumann's mutual inductance between two closed paths (N1 N2 turns); the same path gives the self inductance."
function neumann(p, q, N1, N2, rw; sub = 6)
    fine(t) = (pts = V3[]; for k in 1:length(t)-1, s in 0:sub-1
                   push!(pts, Tuple(collect(t[k]) .+ (s / sub) .* (collect(t[k+1]) .- t[k]))) end; push!(pts, t[end]); pts)
    a = fine(p); c = fine(q); L = 0.0
    for i in 1:length(a)-1, j in 1:length(c)-1
        dli = collect(a[i+1]) .- a[i]; dlj = collect(c[j+1]) .- c[j]
        r = norm((collect(a[i+1]) .+ a[i]) ./ 2 .- (collect(c[j+1]) .+ c[j]) ./ 2)
        L += dot(dli, dlj) / max(r, rw * 0.78)
    end
    EM.MU0 / (4pi) * L * N1 * N2
end

"""
A drum rotor being stepped. Coupling tables per coil (torque per amp and motional EMF per rad/s over θ), the coils'
inductance matrix (self and mutual: they share the drum), coil currents `I` (from segment k to k+1 through coil k).
"""
mutable struct DrumState
    θ::Float64; ω::Float64; I::Vector{Float64}; τ::Float64; t::Float64; on::Bool
    kt::Matrix{Float64}; ke::Matrix{Float64}            # (nθ, ncoils)
    J::Float64; L::Matrix{Float64}; R::Vector{Float64}; E::Float64; Rs::Float64; τfric::Float64
    touch::Vector{BitVector}; sparks::Vector{Tuple{Float64,Float64}}; Ibrush::Float64
end

function DrumState(d::Drum; θ0 = 0.3, ω0 = 0.0, nθ = 180, on = true)
    n = ncoils(d)
    θs = range(0, 2pi; length = nθ + 1)[1:end-1]
    kt = zeros(nθ, n); ke = zeros(nθ, n)
    for k in 1:n
        b = coil_build(d, k)
        for (i, θ) in enumerate(θs)
            kt[i, k], ke[i, k] = coil_coupling(b, θ)
        end
    end
    L = [neumann(d.turns[i], d.turns[j], d.N, d.N, d.rw) for i in 1:n, j in 1:n]
    L = (L + L') / 2
    R = [coil_R(d, k) for k in 1:n]
    E = sum(first, d.cells; init = 0.0); Rs = sum(last, d.cells; init = 0.0)
    mcu = sum(EM.MATERIALS[:copper].density * d.N * perimeter(t) * pi * d.rw^2 for t in d.turns)
    τfric = d.mu_bearing * (d.m_rotor + mcu) * 9.81 * d.r_axle + 2 * d.mu_brush * d.brush_F * d.ring_r
    J = d.J_extra + sum(inertia(coil_build(d, k)) - coil_build(d, k).J_extra for k in 1:n)
    DrumState(θ0, ω0, zeros(n), 0.0, 0.0, on, kt, ke, J, L, R, E, Rs, τfric,
              [falses(n), falses(n)], Tuple{Float64,Float64}[], 0.0)
end

function interp(tab::Matrix, θ, k)
    n = size(tab, 1); x = mod(θ, 2pi) / (2pi / n); i = floor(Int, x); f = x - i
    (1 - f) * tab[mod(i, n)+1, k] + f * tab[mod(i + 1, n)+1, k]
end

"""
    drum_currents(st, d, θ, ω, h) -> (I, Ibrush)

One implicit step of the coil network: L (I' - I)/h = D V + emf - R I' for the coils, Kirchhoff at every segment and
at the plus brush, the cells as their Norton equivalent, the minus brush as ground. `h = Inf` gives the steady (DC)
currents. A segment no brush touches hangs only on its coils (a tiny leak keeps the solve regular).
"""
function drum_currents(st::DrumState, d::Drum, θ, ω, h)
    n = ncoils(d)
    D = zeros(n, n)                       # (V_a - V_b) of coil k = (D V)_k
    for k in 1:n
        D[k, k] += 1; D[k, mod1(k + 1, n)] -= 1
    end
    e = [interp(st.ke, θ, k) * ω for k in 1:n]
    M = isinf(h) ? Diagonal(st.R) * 1.0 : st.L ./ h + Diagonal(st.R)
    c = isinf(h) ? e : st.L * st.I ./ h + e
    Y = inv(M)
    t1 = st.on ? touching(d, 1, θ) : falses(n); t2 = st.on ? touching(d, 2, θ) : falses(n)
    gc = 1 / d.R_contact
    A = zeros(n + 1, n + 1); rhs = zeros(n + 1)
    A[1:n, 1:n] .= D' * Y * D
    for j in 1:n
        A[j, j] += gc * (t1[j] + t2[j]) + 1e-9
        A[j, n+1] -= gc * t1[j]; A[n+1, j] -= gc * t1[j]
    end
    A[n+1, n+1] += 1 / st.Rs + gc * sum(t1) + 1e-9
    rhs[1:n] .= -(D' * Y * c); rhs[n+1] = st.E / st.Rs * st.on
    x = A \ rhs
    V = x[1:n]; Vb = x[n+1]
    I = Y * (c + D * V)
    Ib = sum(gc * (Vb - V[j]) for j in 1:n if t1[j]; init = 0.0)
    return I, Ib, (t1, t2)
end

"Torque at θ with the rotor held still, after the currents have settled (what decides whether it starts)."
function stall_torque(st::DrumState, d::Drum, θ)
    I, _, _ = drum_currents(st, d, θ, 0.0, Inf)
    sum(interp(st.kt, θ, k) * I[k] for k in 1:ncoils(d))
end

flick!(st::DrumState, Δω) = (st.ω += Δω; st)

function step!(st::DrumState, d::Drum, dt; h = 2e-4)
    n = max(1, ceil(Int, dt / h)); h = dt / n
    for _ in 1:n
        Iold = copy(st.I)
        I, Ib, tch = drum_currents(st, d, st.θ, st.ω, h)
        for k in 1:2                                     # a brush leaving a segment under current: a spark
            any(st.touch[k] .& .!tch[k]) && abs(st.Ibrush) > 1e-3 &&
                push!(st.sparks, (st.t, max(0.0, 0.5 * dot(Iold, st.L * Iold) - 0.5 * dot(I, st.L * I))))
        end
        st.touch = [BitVector(tch[1]), BitVector(tch[2])]
        st.I = I; st.Ibrush = Ib
        st.τ = sum(interp(st.kt, st.θ, k) * I[k] for k in 1:length(I))
        ω = st.ω
        α = (ω == 0.0 && abs(st.τ) <= st.τfric) ? 0.0 : (st.τ - st.τfric * sign(ω == 0 ? st.τ : ω)) / st.J
        ωn = ω + α * h
        (ω != 0 && sign(ωn) != sign(ω)) && (ωn = 0.0)
        st.ω = ωn; st.θ += ωn * h; st.t += h
    end
    st
end

"Runs a drum build (as `spin` does a two-segment one)."
function spin(d::Drum; seconds = 2.0, dt = 2e-4, θ0 = 0.3, ω0 = 0.0, nudges = Tuple{Float64,Float64}[], nθ = 180)
    st = DrumState(d; θ0, ω0, nθ)
    ts = Float64[]; θh = Float64[]; ωh = Float64[]; Ih = Float64[]; τh = Float64[]
    nexti = 1; nn = sort(nudges; by = first)
    for n in 0:round(Int, seconds / dt)
        t = n * dt
        while nexti <= length(nn) && nn[nexti][1] <= t
            st.ω += nn[nexti][2]; nexti += 1
        end
        step!(st, d, dt; h = dt)
        if n % 25 == 0
            push!(ts, t); push!(θh, st.θ); push!(ωh, st.ω); push!(Ih, st.Ibrush); push!(τh, st.τ)
        end
    end
    tail = ωh[max(1, end - 20):end]
    state = all(==(0.0), tail) ? :stalled : sum(tail) > 0 ? :runs : :backwards
    return (; t = ts, θ = θh, ω = ωh, I = Ih, τ = τh, sparks = st.sparks, state, rev_s = st.ω / 2pi, J = st.J,
              L = st.L, R_coils = st.R, τ_friction = st.τfric)
end

"""
Three coils at 120 deg across a drum (each the bench's rectangular turn turned by 2pi k/3 about the axle, a little
longer each so their ends cross without touching), a 3-segment ring turned by `ring_turn` against the coils.
"""
function drum_bench(; n = 3, s = 1.0, material = :ferrite, flip = (false, false), N = 60, cells = 3,
                    ring_turn = 0.0, gap = deg2rad(10), kw...)
    turns = [begin
                 t = rect_turn(; l = (0.03 + 0.002 * (k - 1)) * s, a = 0.009s)
                 R = Rx(2pi * (k - 1) / n); [Tuple(R * collect(p)) for p in t]
             end for k in 1:n]
    Drum(; magnets = stator(; material, flip, R = 0.012s, H = 0.012s, gap = 0.024s), turns, N, ring_r = 0.006s,
         seg_c = [ring_turn + 2pi * (k - 1) / n for k in 1:n], gap, r_axle = 0.0015s,
         cells = [(0.75, 3.0) for _ in 1:cells], kw...)
end

"The drum built right: brushes wider than the ring's gaps (6 deg slots, 12 deg brushes), the ring turned 30 deg."
drum_right(; kw...) = drum_bench(; ring_turn = deg2rad(30), gap = deg2rad(6), brush_w = deg2rad(12), kw...)

"""
The drum three times bench size (film, bench, cart): big_bench's rotor and winding, 6 cells, on a 4 mm axle. On the
9 mm axle the bearing friction (5.2 mN m) beat the weakest stall torque (4.3) and it stuck; on 4 mm (2.7) it starts
from all 12 angles and reaches ~2.1 rev/s at 4 s (s157).
"""
drum_film(; s = 3.0, kw...) = drum_right(; s, N = 80, rw = 0.35e-3, brush_F = 0.06, m_rotor = 0.012 * s^3 * 0.5,
                                         J_extra = 2e-6 * s^5 * 0.5, cells = 6, r_axle = 0.002, kw...)

"""
The test for the drum (s157): built right it starts by itself from every angle (stall torque never below friction);
each misbuild does what a real one does. Returns the start table and the cases.
"""
function drum_cases(; seconds = 1.5)
    starts = map(range(0, 2pi; length = 13)[1:end-1]) do θ0
        r = spin(drum_right(); seconds, θ0)
        (; θ0_deg = round(rad2deg(θ0)), state = r.state, rev_s = round(r.rev_s, digits = 2))
    end
    cases = [("built right", drum_right(), 0.0),
             ("ring turned 110 deg on the axle", drum_bench(; ring_turn = deg2rad(110), gap = deg2rad(6), brush_w = deg2rad(12)), 0.0),
             ("both stones turned round", drum_right(; flip = (true, true)), 0.0),
             ("brushes narrower than the gap", drum_bench(; ring_turn = deg2rad(30), gap = deg2rad(10), brush_w = deg2rad(8)), deg2rad(120)),
             ("beach lodestone", drum_right(; material = :magnetite), 0.0),
             ("one cell", drum_right(; cells = 1), 0.0)]
    res = map(cases) do (name, d, θ0)
        r = spin(d; seconds, θ0)
        (; name, state = r.state, rev_s = round(r.rev_s, digits = 2))
    end
    (; starts, cases = res)
end

end # module
