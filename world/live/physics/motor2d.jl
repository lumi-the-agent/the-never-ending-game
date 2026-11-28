# The motor's cross-section as 2D magnetostatics (s172, project winch). softiron.jl's rods magnetise only along their
# own axes, so ROUND rotor iron (a drum or ring armature, the iron real motors use) is out of its reach; this solves the
# field properly: the axle along x, the cross-section is the (y, z) plane, the unknown is the vector potential A_x:
#     -div(nu grad A) = J + curl M      (B = curl A, H = nu B - M)
# with Ferrite.jl (bilinear quads on a 1 mm grid, cells take their material from their centre). Iron has its own nu
# (linear mu_r for now: check |B| in the iron against saturation), the stones are magnets with M = Br / mu0 along +y,
# the copper sides carry N I spread over their cells. The torque on the rotor is Arkkio's Maxwell stress average over
# an air annulus in the gap: T = L / (mu0 (r2 - r1)) * integral of r B_r B_theta dA. No torque constant is put in.
# Looked first (rule 6, RomeoDB): no electric-machine package in the registry; Ferrite.jl / Gridap / VoronoiFVM are the
# FEM toolboxes. Runs in its own env (world/tools/magnet2d), not the game's: a design tool, its tables go to the game.
#   Motor2D.torque(; rotor = :drum | :air, θ, NI)   Motor2D.sweep(; rotor)
module Motor2D

using Ferrite, SparseArrays, LinearAlgebra

const MU0 = 4pi * 1e-7
const NU0 = 1 / MU0

"""
The big bench motor (motor.jl big_bench, x3): stones R 3.6 cm, 3.6 cm thick, faces at y = +-3.6 cm, ferrite Br 0.38 T
(EM.MATERIALS[:ferrite] -- passed in); the coil's two sides at 2.7 cm from the axle, wire bundle radius rc.
"""
Base.@kwdef struct Geo
    W::Float64 = 0.15            # half the square domain (A = 0 on its edge)
    n::Int = 300                 # cells per side
    pole::Float64 = 0.036        # stone face distance from the axle
    stone_t::Float64 = 0.036     # stone thickness along y
    stone_w::Float64 = 0.036     # stone half-width along z (its radius)
    Br::Float64 = 0.38
    rs::Float64 = 0.027          # the coil sides' radius
    rc::Float64 = 0.003          # the wire bundle's radius
    rd::Float64 = 0.032          # the drum's radius (4 mm gap at the pole's middle)
    mur::Float64 = 2000.0        # soft iron
    L::Float64 = 0.072           # axial length the torque is counted over (the stones' depth along x)
    coils::Int = 1               # coils on the rotor, spread evenly over a half turn (2 = Siemens' drum, 4 segments)
end

"""
The coil sides at rotor angle θ: coil k sits at θ + (k - 1) pi / coils; the commutator turns each coil's current round
as it passes its neutral (sin of its angle changes sign), so side 1 of coil k carries s_k N I out of the plane and side 2
the same back. Returns [(position, sign)].
"""
function sides(g, θ)
    out = Tuple{NTuple{2,Float64},Int}[]
    for k in 1:g.coils
        φ = θ + (k - 1) * pi / g.coils
        sk = sin(φ) >= 0 ? 1 : -1
        push!(out, ((g.rs * sin(φ), -g.rs * cos(φ)), sk), ((-g.rs * sin(φ), g.rs * cos(φ)), -sk))
    end
    out
end

"Material at a cell centre: (nu, which copper side 0/1.., M vector)."
function material(g, x, θ, rotor)
    y, z = x
    if abs(z) <= g.stone_w && g.pole <= abs(y) <= g.pole + g.stone_t
        return (NU0, 0, (g.Br / MU0, 0.0))                      # both stones magnetised along +y
    end
    for (k, (p, _)) in enumerate(sides(g, θ))
        hypot(y - p[1], z - p[2]) <= g.rc && return (NU0, k, (0.0, 0.0))
    end
    rotor === :drum && hypot(y, z) <= g.rd && return (NU0 / g.mur, 0, (0.0, 0.0))
    return (NU0, 0, (0.0, 0.0))
end

"Soft iron's B(H) (T from A/m): mu0 H + Js tanh(mu0 (mu_r - 1) H / Js), Js = 1.7 T: linear at first, saturating."
B_of_H(H, mur; Js = 1.7) = MU0 * H + Js * tanh(MU0 * (mur - 1) * H / Js)
"The H for a given B (bisection on the monotone curve)."
function H_of_B(B, mur)
    lo, hi = 0.0, max(B / MU0, 1.0)
    for _ in 1:60
        m = (lo + hi) / 2
        B_of_H(m, mur) < B ? (lo = m) : (hi = m)
    end
    (lo + hi) / 2
end

"""
Solve with SATURATING iron: Picard iteration, each iron cell's nu = H(B) / B at its own |B| (relaxed); `iters` passes.
Returns the last solve and the iron's peak |B|.
"""
function solve_nl(g::Geo; θ = pi / 2, NI = 80.0, rotor = :drum, iters = 12, relax = 0.5)
    s = solve(g; θ, NI, rotor)
    nu = Dict{Int,Float64}()
    for it in 1:iters
        for cell in CellIterator(s.dh)
            c = cellid(cell)
            s.mats[c][1] < NU0 / 2 || continue
            reinit!(s.cv, cell)
            ∇A = function_gradient(s.cv, 1, s.A[celldofs(cell)])
            B = max(hypot(∇A...), 1e-4)
            target = H_of_B(B, g.mur) / B
            nu[c] = haskey(nu, c) ? (1 - relax) * nu[c] + relax * target : target
        end
        s = solve(g; θ, NI, rotor, nu)
    end
    return s
end

"Solve the field for a rotor at θ carrying NI in its coil (`nu`: iron cells' own nu); returns (dh, cellvalues, A, mats)."
function solve(g::Geo; θ = pi / 2, NI = 80.0, rotor = :drum, nu = nothing)
    grid = generate_grid(Quadrilateral, (g.n, g.n), Vec{2}((-g.W, -g.W)), Vec{2}((g.W, g.W)))
    ip = Lagrange{RefQuadrilateral,1}(); qr = QuadratureRule{RefQuadrilateral}(2)
    cv = CellValues(qr, ip)
    dh = DofHandler(grid); add!(dh, :A, ip); close!(dh)
    ch = ConstraintHandler(dh)
    edge = union(getfacetset(grid, "left"), getfacetset(grid, "right"), getfacetset(grid, "top"), getfacetset(grid, "bottom"))
    add!(ch, Dirichlet(:A, edge, (x, t) -> 0.0)); close!(ch)
    # copper cells per side, so each side carries exactly NI however the staircase falls
    mats = [material(g, sum(getcoordinates(grid, c)) / 4, θ, rotor) for c in 1:getncells(grid)]
    if nu !== nothing                                   # the saturating iron's own nu per cell (solve_nl)
        for (c, v) in nu
            m = mats[c]; mats[c] = (v, m[2], m[3])
        end
    end
    h = 2g.W / g.n
    sd = sides(g, θ)
    ncu = [count(m -> m[2] == k, mats) for k in eachindex(sd)]
    K = allocate_matrix(dh); f = zeros(ndofs(dh))
    asm = start_assemble(K, f)
    nb = getnbasefunctions(cv); ke = zeros(nb, nb); fe = zeros(nb)
    for cell in CellIterator(dh)
        reinit!(cv, cell)
        nu, side, M = mats[cellid(cell)]
        J = side == 0 ? 0.0 : sd[side][2] * NI / (ncu[side] * h^2)
        fill!(ke, 0); fill!(fe, 0)
        for q in 1:getnquadpoints(cv)
            dΩ = getdetJdV(cv, q)
            for i in 1:nb
                ∇v = shape_gradient(cv, q, i); v = shape_value(cv, q, i)
                fe[i] += (J * v + M[1] * ∇v[2] - M[2] * ∇v[1]) * dΩ
                for j in 1:nb
                    ke[i, j] += nu * (∇v ⋅ shape_gradient(cv, q, j)) * dΩ
                end
            end
        end
        assemble!(asm, celldofs(cell), ke, fe)
    end
    apply!(K, f, ch)
    A = K \ f
    return (; dh, cv, A, mats)
end

"""
Soft iron's reluctivity at |B| = b: nu = H(b) / b, and its slope dnu/d(b^2) (what Newton's Jacobian needs).
Newton on H for H(b) (B_of_H is monotone and concave), bisection as the safe start.
"""
function nu_iron(b, mur)
    Js = 1.7                                                            # as B_of_H
    b = max(b, 1e-7)
    H = H_of_B(b, mur)
    dB = MU0 + MU0 * (mur - 1) * sech(MU0 * (mur - 1) * H / Js)^2      # dB/dH at H
    nu = H / b
    dnu_db = (b / dB - H) / b^2
    return nu, dnu_db / (2b)
end

"""
Solve with SATURATING iron by NEWTON-RAPHSON (s175, todo #786): the residual r(A) = int nu(|grad A|^2) grad A . grad v
- int (J v + M x grad v), its Jacobian adds 2 dnu/d(b^2) (grad A . grad v_i)(grad A . grad v_j) per quadrature point,
so each iron point carries its OWN nu (not one per cell from its first point, as solve_nl). Starts from the linear
solve, damps a step that does not lower the residual. Returns (; dh, cv, A, mats, nuq, its, res) with res the
history of |r| / |f| per pass.
"""
function solve_newton(g::Geo; θ = pi / 2, NI = 80.0, rotor = :drum, tol = 1e-9, maxit = 40, A0 = nothing)
    s = A0 === nothing ? solve(g; θ, NI, rotor) : A0
    dh, cv, mats = s.dh, s.cv, s.mats
    grid = dh.grid
    ch = ConstraintHandler(dh)
    edge = union(getfacetset(grid, "left"), getfacetset(grid, "right"), getfacetset(grid, "top"), getfacetset(grid, "bottom"))
    add!(ch, Dirichlet(:A, edge, (x, t) -> 0.0)); close!(ch)
    h = 2g.W / g.n
    sd = sides(g, θ)
    ncu = [count(m -> m[2] == k, mats) for k in eachindex(sd)]
    isiron = [rotor === :drum && m[2] == 0 && m[1] < NU0 / 2 for m in mats]
    # the linear solve marked iron with nu0/mur; a cell is iron by its material, keep that mask fixed
    A = copy(s.A)
    nb = getnbasefunctions(cv); nq = getnquadpoints(cv)
    nuq = zeros(getncells(grid), nq)
    function assemble_at(A; jac = true)
        K = allocate_matrix(dh); r = zeros(ndofs(dh)); fnorm = zeros(ndofs(dh))
        asm = start_assemble(K, r)
        ke = zeros(nb, nb); re = zeros(nb); fe = zeros(nb)
        for cell in CellIterator(dh)
            c = cellid(cell)
            reinit!(cv, cell)
            _, side, M = mats[c]
            J = side == 0 ? 0.0 : sd[side][2] * NI / (ncu[side] * h^2)
            ae = A[celldofs(cell)]
            fill!(ke, 0); fill!(re, 0); fill!(fe, 0)
            for q in 1:nq
                dΩ = getdetJdV(cv, q)
                ∇A = function_gradient(cv, q, ae)
                if isiron[c]
                    nu, dnu = nu_iron(norm(∇A), g.mur)
                else
                    nu, dnu = NU0, 0.0
                end
                nuq[c, q] = nu
                for i in 1:nb
                    ∇v = shape_gradient(cv, q, i); v = shape_value(cv, q, i)
                    src = (J * v + M[1] * ∇v[2] - M[2] * ∇v[1]) * dΩ
                    re[i] += nu * (∇A ⋅ ∇v) * dΩ - src
                    fe[i] += src
                    jac || continue
                    for j in 1:nb
                        ∇w = shape_gradient(cv, q, j)
                        ke[i, j] += (nu * (∇v ⋅ ∇w) + 2dnu * (∇A ⋅ ∇v) * (∇A ⋅ ∇w)) * dΩ
                    end
                end
            end
            assemble!(asm, celldofs(cell), ke, re)
            fnorm[celldofs(cell)] .+= abs.(fe)
        end
        apply_zero!(K, r, ch)
        return K, r, norm(fnorm)
    end
    res = Float64[]; its = 0
    K, r, fn = assemble_at(A)
    push!(res, norm(r) / fn)
    for it in 1:maxit
        its = it
        dA = -(K \ r)
        α = 1.0; Anew = A .+ dA
        Kn, rn, _ = assemble_at(Anew)
        while norm(rn) > norm(r) && α > 1 / 64            # damp a step that overshoots the knee
            α /= 2; Anew = A .+ α .* dA
            Kn, rn, _ = assemble_at(Anew)
        end
        A, K, r = Anew, Kn, rn
        push!(res, norm(r) / fn)
        res[end] < tol && break
    end
    return (; dh, cv, A, mats, nuq, its, res)
end

"""
Flux linkage per turn per metre of the coil k (Wb/m): the mean of A_x over side 1's copper minus over side 2's (the
bundle's own average, so the winding's spread counts). lambda = N * L_axial * this.
"""
function linkage(s, g::Geo, θ; k = 1)
    acc = zeros(2); area = zeros(2)
    for cell in CellIterator(s.dh)
        side = s.mats[cellid(cell)][2]
        (side == 2k - 1 || side == 2k) || continue
        reinit!(s.cv, cell)
        ae = s.A[celldofs(cell)]
        j = side == 2k - 1 ? 1 : 2
        for q in 1:getnquadpoints(s.cv)
            dΩ = getdetJdV(s.cv, q)
            acc[j] += function_value(s.cv, q, ae) * dΩ; area[j] += dΩ
        end
    end
    sg = sides(g, θ)[2k - 1][2]                           # the commutated sign: the linkage the circuit sees
    return sg * (acc[1] / area[1] - acc[2] / area[2])
end

"Torque (N m, about +x) by Arkkio's Maxwell stress over the gap annulus r1..r2, and the peak |B| in the iron (T).
The iron saturates (solve_nl, `iters` Picard passes; 0 = linear iron; `newton = true`: solve_newton, s175: Picard does
NOT converge near the slot bridges' knee; `s`: a solution already made)."
function torque(g::Geo = Geo(); θ = pi / 2, NI = 80.0, rotor = :drum, r1 = 0.0325, r2 = 0.0355, iters = 12,
                newton = false, s = nothing)
    s = s !== nothing ? s : rotor === :air || iters == 0 ? solve(g; θ, NI, rotor) :
        newton ? solve_newton(g; θ, NI, rotor) : solve_nl(g; θ, NI, rotor, iters)
    acc = 0.0; Bfe = 0.0
    for cell in CellIterator(s.dh)
        xs = getcoordinates(cell); c = sum(xs) / 4; r = norm(c)
        iron = s.mats[cellid(cell)][1] < NU0 / 2
        (r1 <= r <= r2 || iron) || continue
        reinit!(s.cv, cell)
        ae = s.A[celldofs(cell)]
        for q in 1:getnquadpoints(s.cv)
            ∇A = function_gradient(s.cv, q, ae)
            B = (∇A[2], -∇A[1])                                   # B = curl A in the (y, z) plane
            iron && (Bfe = max(Bfe, hypot(B...)))
            r1 <= r <= r2 || continue
            x = spatial_coordinate(s.cv, q, xs); rr = norm(x)
            er = (x[1] / rr, x[2] / rr); et = (-x[2] / rr, x[1] / rr)
            acc += rr * (B[1] * er[1] + B[2] * er[2]) * (B[1] * et[1] + B[2] * et[2]) * getdetJdV(s.cv, q)
        end
    end
    return (τ = g.L * acc / (MU0 * (r2 - r1)), Bfe = Bfe)
end

"Drive torque per ampere-turn and cogging over a half turn: drive = (τ(+NI) - τ(-NI)) / 2, cog = τ(0)."
function sweep(g::Geo = Geo(); rotor = :drum, NI = 80.0, nθ = 7)
    map(range(0, pi; length = nθ)) do θ
        tp = torque(g; θ, NI, rotor); tm = torque(g; θ, NI = -NI, rotor); t0 = torque(g; θ, NI = 0.0, rotor)
        (θ = round(Int, rad2deg(θ)), drive_mNm = 1000 * (tp.τ - tm.τ) / 2, cog_mNm = 1000 * t0.τ, Bfe = tp.Bfe)
    end
end

end
