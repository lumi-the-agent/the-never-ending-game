# Stuck in the sand (s168, idea 'Stuck in the sand: dig, plank, push, rock it free', project stuck): the land yacht's
# wheels roll IN the sand field (physics/sandfield.jl) instead of on a number. Each step, each wheel meets the sand
# surface the field really has ahead of it (fresh sand, its own rut, a berm it pushed up, a ramp Lumi dug), and
# Bekker's pressure-sinkage law at every point of its rim (WheelSand.bekker, Wong's soil constants) decides how deep
# it sits and how hard the sand pushes back; the rim's footprint is pressed into the field (ruts and berms), which
# changes what the next step meets. So a cart pushed too weakly through soft sand stops because the sand under it
# says so, and what the player does to the sand (dig, plank, roll back and forth in its own ruts) is what frees it.
# Looked first (rule 6): physics/wheelsand.jl has Wong-Reece on flat ground only; RomeoDB has no terramechanics.
module Stuck
using ..WheelSand: bekker, SOILS
import ..SandField

"""
    rim(s, r, b, ground, zc, i; nq = 120) -> (; W, R, T, zmax)

WheelSand.arc on real ground: a rigid wheel (radius r, width b) with its axle at height `zc` over the surface
`ground(x)` (height at the horizontal offset x from the axle, forward +), slipping by i. The entry angle θ1 is where
the front of the rim first meets the surface; at every point of the arc the normal stress is Bekker's for the
sinkage the PROFILE gives there (with Wong-Reece's peak moved to θm and the rear mirrored, as in arc), the shear is
Mohr-Coulomb with Janosi-Hanamoto. On flat ground it is arc exactly. W: upward force (N); R: backward force against
rolling (-drawbar pull, N); T: the torque the sand puts on the wheel (N m); zmax: deepest sinkage.
"""
function rim(s, r, b, ground, zc, i; nq = 120, c1 = 0.43, c2 = 0.32, pressed = x -> 0.0)
    zat(θ) = ground(r * sin(θ)) - (zc - r * cos(θ))
    # sand already pressed down by `pressed(x)` carries, on reloading, what it carried then (Wong's repetitive
    # loading, taken as stiff): touching it counts the sinkage from the surface it had before it was pressed
    zload(θ) = (z = zat(θ); z > 0 ? z + pressed(r * sin(θ)) : 0.0)
    # MAIN PATCH: the contact that runs on from the rim's bottom; its entry angle θ1 is where it ends going forward.
    # (s168: taking θ1 from the FRONT-most contact let a berm ahead jump θ1 from 0.39 to ~0.6 rad the moment it
    # touched, and Wong-Reece's mirror then reshaped the whole arc: the forces jumped and the towed slip had no root.)
    nscan = 160; dθs = (pi / 2) / nscan
    θ1 = 0.0
    # the first contact going forward from the bottom (a rolling wheel stands a hair above its own pressed floor, so
    # the bottom itself may not touch), then on to where that contact ends
    qa = findfirst(q -> zat(q * dθs) > 0, 0:nscan)
    if qa !== nothing
        q1 = nscan
        for q in (qa - 1):nscan
            zat(q * dθs) > 0 || (q1 = q; break)
        end
        lo, hi = (q1 - 1) * dθs, q1 * dθs                 # the crossing between the scan's points
        for _ in 1:16
            mid = (lo + hi) / 2
            zat(mid) > 0 ? (lo = mid) : (hi = mid)
        end
        θ1 = lo
    end
    W = 0.0; DP = 0.0; T = 0.0; zmax = 0.0
    if θ1 > 0
        θm = clamp(c1 + c2 * i, 0.05, 0.95) * θ1
        dθ = θ1 / nq
        for q in 1:nq
            θ = (q - 0.5) * dθ
            θe = θ >= θm ? θ : θ1 - (θ / θm) * (θ1 - θm)
            z = zload(θe); zmax = max(zmax, z)
            σ = bekker(s, b, z)
            j = r * ((θ1 - θ) - (1 - i) * (sin(θ1) - sin(θ)))
            τ = σ > 0 ? (s.c + σ * tan(s.phi)) * (1 - exp(-abs(j) / s.K)) * sign(j) : 0.0
            W += (σ * cos(θ) + τ * sin(θ)) * dθ
            DP += (τ * cos(θ) - σ * sin(θ)) * dθ
            T += τ * dθ
        end
    end
    # PATCHES AHEAD (a berm, a step): Bekker at their own sinkage, no mirror; the shear builds from each patch's own
    # entry. A patch grows from nothing as it comes into reach, so the forces stay continuous.
    q = nscan
    while q * dθs > θ1 + dθs
        if zat((q - 0.5) * dθs) > 0
            θb = q * dθs                                   # this patch's entry (its front end on the scan)
            while q * dθs > θ1 + dθs && zat((q - 0.5) * dθs) > 0
                θ = (q - 0.5) * dθs
                z = zload(θ); zmax = max(zmax, z)
                σ = bekker(s, b, z)
                j = r * ((θb - θ) - (1 - i) * (sin(θb) - sin(θ)))
                τ = (s.c + σ * tan(s.phi)) * (1 - exp(-abs(j) / s.K)) * sign(j)
                W += (σ * cos(θ) + τ * sin(θ)) * dθs
                DP += (τ * cos(θ) - σ * sin(θ)) * dθs
                T += τ * dθs
                q -= 1
            end
        else
            q -= 1
        end
    end
    (; W = r * b * W, R = -r * b * DP, T = r^2 * b * T, zmax)
end

"The axle height where the sand carries `W` newtons at slip i (bisection from the rim just touching to 0.9 r down)."
function settle_at(s, r, b, ground, W, i; xs = range(0, r; length = 40), pressed = x -> 0.0)
    # the highest axle at which the rim touches the ground anywhere ahead (s169: this was ground + r - sqrt(r^2 - x^2),
    # which is right only on flat ground; in a rut lower 35 cm ahead the bracket's top had the rim 4 mm deep already,
    # the bisection pinned there and the 'full settle' returned a wheel carrying 426 N of its 233)
    top = maximum(ground(x) + sqrt(max(r^2 - x^2, 0.0)) for x in xs) + 0.002   # + a bump between the 9 mm samples
    lo, hi = top - 0.9r, top
    for _ in 1:30
        mid = (lo + hi) / 2
        rim(s, r, b, ground, mid, i; pressed).W > W ? (lo = mid) : (hi = mid)
    end
    zc = (lo + hi) / 2
    (; zc, i, rim(s, r, b, ground, zc, i; pressed)...)
end

"A towed wheel (free on its axle) settled on the ground: the slip where the sand's torque on it is zero."
function settle(s, r, b, ground, W; pressed = x -> 0.0)
    # T(slip) jumps where the rim's contact changes (a berm coming into reach), so bisecting [-0.9, 0.5] can close on
    # a jump instead of a zero (s168: 4 N m left, R 25% off). Scan out from slip 0 for a real sign change first.
    Tat(i) = settle_at(s, r, b, ground, W, i; pressed).T
    lo, hi = -0.9, 0.5
    for k in 0:44
        a, c = -0.02 * (k + 1), -0.02 * k                 # skidding side first: a towed wheel skids a little
        if Tat(a) <= 0 < Tat(c)
            lo, hi = a, c; break
        end
        c2 = 0.02 * (k + 1)
        if c2 <= 0.5 && Tat(c) <= 0 < Tat(c2)
            lo, hi = c, c2; break
        end
    end
    for _ in 1:20
        mid = (lo + hi) / 2
        settle_at(s, r, b, ground, W, mid; pressed).T > 0 ? (hi = mid) : (lo = mid)
    end
    settle_at(s, r, b, ground, W, (lo + hi) / 2; pressed)
end

"""
    settle_from(s, r, b, ground, W, guess; pressed, tol = 1e-3) -> settled or nothing

The game's settle: from last frame's (zc, i) a damped 2D Newton on (zc, slip) for load = W and zero torque, with a
finite-difference Jacobian: ~3 rim evaluations an iteration instead of settle's ~600. Returns `nothing` when it does
not converge in `iters` (the caller then runs the full `settle`, which always brackets).
"""
function settle_from(s, r, b, ground, W, guess; pressed = x -> 0.0, iters = 12, tol = 1e-3)
    zc, i = guess.zc, guess.i
    res(z, ii) = (q = rim(s, r, b, ground, z, ii; pressed); (q.W - W, q.T, q))
    # The load grows monotonically as the axle goes down (slip barely moves it), so every evaluation brackets the
    # height. s169: where the rim first touches stiffly PRESSED sand (a rear wheel in the front wheel's rut, on a
    # diagonal heading where the rut is a staircase on the grid) W(zc) has a kink: ~230 N/mm just below the touch,
    # ~22 above, and Newton 2-cycled across it (317.5 <-> 319.7 mm, every frame) into the full settle. When Newton
    # leaves the bracket, false position (Illinois) inside it instead.
    zdeep, fdeep = -Inf, 0.0                         # a height where the sand carries too much: the root is above
    zhigh, fhigh = Inf, 0.0                          # too little: the root is below
    side = 0
    for _ in 1:iters
        fW, fT, q = res(zc, i)
        abs(fW) < tol * W && abs(fT) < tol * W * r && return (; zc, i, q...)
        if fW > 0
            side == 1 && (fhigh /= 2)                # Illinois: the far end stuck twice, halve its weight
            zdeep, fdeep, side = zc, fW, 1
        else
            side == -1 && (fdeep /= 2)
            zhigh, fhigh, side = zc, fW, -1
        end
        # a resting contact on a STEP: a rim point newly touching pressed sand adds Bekker's stress for all it carried
        # at once (a few N), so no height carries W exactly (the full settle ends 1.9 N off there too). Bracket closed
        # to 0.01 mm, torque zero, load within 3%: that is the wheel sitting on the step.
        zhigh - zdeep < 1e-5 && abs(fT) < tol * W * r && abs(fW) < 0.03 * W && return (; zc, i, q...)
        hz, hi = 1e-5, 1e-4
        aW, aT, _ = res(zc + hz, i); bW, bT, _ = res(zc, i + hi)
        J11, J12, J21, J22 = (aW - fW) / hz, (bW - fW) / hi, (aT - fT) / hz, (bT - fT) / hi
        d = J11 * J22 - J12 * J21
        bracketed = isfinite(zdeep) && isfinite(zhigh)
        # off the ground entirely (a wheel perched on a bump overshoots into the air): W and T are flat, d = 0; with a
        # bracket that is no dead end (s169: half the remaining fallbacks were this), keep the slip and cut the bracket
        abs(d) > 0 || bracketed || return nothing
        dz, di = abs(d) > 0 ? ((J22 * fW - J12 * fT) / d, (J11 * fT - J21 * fW) / d) : (Inf, 0.0)
        dz = clamp(dz, -0.01, 0.01); di = clamp(di, -0.1, 0.1)       # damped: never more than 1 cm or 0.1 slip a step
        znew = abs(d) > 0 ? zc - dz : NaN
        if bracketed && !(zdeep < znew < zhigh)
            znew = zdeep + fdeep * (zhigh - zdeep) / (fdeep - fhigh)
        end
        zc = znew; i -= di
    end
    fW, fT, q = res(zc, i)
    abs(fW) < tol * W && abs(fT) < tol * W * r ? (; zc, i, q...) : nothing
end

"""
    CartSand(cx, cy; size = 8.0, dx = 0.04, soil)

A square of the sand field under a cart (centre cx, cy in world metres), for any number of wheels at any heading:
each wheel keeps its last settle (warm start), its load history, and presses its own rotated footprint.
"""
mutable struct CartSand{F,S}
    f::F                       # concrete types: sample() runs ~600 times a rim, an Any here cost 0.3 ms a rim (s168)
    P::Matrix{Float32}
    x0::Float64
    y0::Float64
    soil::S
    last::Dict{Int,Any}
    fallbacks::Int             # frames where the warm start did not converge and the full settle ran
end
function CartSand(cx, cy; size = 8.0, dx = 0.04, soil = SOILS[:dry_sand])
    n = round(Int, size / dx)
    CartSand(SandField.Field(n, n, dx; depth = 0.5f0), zeros(Float32, n, n), cx - size / 2, cy - size / 2, soil, Dict{Int,Any}(), 0)
end

"Bilinear sample of a cell array at world (x, y)."
function sample(cs::CartSand, A, x, y)
    dx = cs.f.dx; nx, ny = size(A)
    u = clamp((x - cs.x0) / dx + 0.5, 1.0, nx - 1e-6); v = clamp((y - cs.y0) / dx + 0.5, 1.0, ny - 1e-6)
    i = floor(Int, u); j = floor(Int, v); a = u - i; c = v - j
    Float64((1 - a) * (1 - c) * A[i, j] + a * (1 - c) * A[i + 1, j] + (1 - a) * c * A[i, j + 1] + a * c * A[i + 1, j + 1])
end

"""
    wheel_step!(cs, k, x, y, fwd, W, moving; r, b) -> settled (R: N against rolling along fwd)

Wheel `k` at (x, y), rolling along the unit vector `fwd`, carrying W: settle it on the sand it meets (from its last
state when it has one), then press its footprint (only behind its bottom while it rolls, the whole contact standing).
"""
function wheel_step!(cs::CartSand, k, x, y, fwd, W, moving; r = 0.35, b = 0.10, h = Array(cs.f.h))
    g(ξ) = sample(cs, h, x + ξ * fwd[1], y + ξ * fwd[2])
    pr(ξ) = sample(cs, cs.P, x + ξ * fwd[1], y + ξ * fwd[2])
    prev = get(cs.last, k, nothing)
    st = prev === nothing ? nothing : settle_from(cs.soil, r, b, g, W, prev; pressed = pr)
    st === nothing && (st = settle(cs.soil, r, b, g, W; pressed = pr))
    cs.last[k] = st
    # the footprint: cells within the rim's length along fwd and its width across
    f = cs.f; dx = f.dx; nx, ny = size(h)
    U = fill(Inf32, nx, ny)
    zb = st.zc - r
    i0 = clamp(floor(Int, (x - r - cs.x0) / dx), 1, nx); i1 = clamp(ceil(Int, (x + r - cs.x0) / dx) + 1, 1, nx)
    j0 = clamp(floor(Int, (y - r - cs.y0) / dx), 1, ny); j1 = clamp(ceil(Int, (y + r - cs.y0) / dx) + 1, 1, ny)
    for i in i0:i1, j in j0:j1
        px = cs.x0 + (i - 0.5) * dx - x; py = cs.y0 + (j - 0.5) * dx - y
        along = px * fwd[1] + py * fwd[2]; across = -px * fwd[2] + py * fwd[1]
        (abs(across) <= b / 2 && abs(along) < r) || continue
        moving && along > 0 && continue
        U[i, j] = Float32(zb + r - sqrt(r^2 - along^2))
    end
    h0 = Array(f.h)
    SandField.press!(f, U; bulb = b)
    h1 = Array(f.h)
    @. cs.P += ifelse(isinf(U), 0f0, max(h0 - h1, 0f0))
    st
end

"""
    cart_step!(cs, wheels, fwd, W, moving; r, b, R = 4) -> settles

All the cart's wheels in one go (the game's call): `wheels` = [(x, y), ...] world positions, each rolling along
`fwd` and carrying W. One read of the field, a warm-started settle per wheel, ONE footprint map for all of them and
ONE press! (berm search radius R cells: a 10 cm rim sheds its sand sideways within 2-3 cells).
"""
function cart_step!(cs::CartSand, wheels, fwd, W, moving; r = 0.35, b = 0.10, R = 4, soils = nothing)
    f = cs.f; dx = f.dx; h = Array(f.h); nx, ny = size(h)
    U = fill(Inf32, nx, ny)
    sts = map(enumerate(wheels)) do (k, (x, y))
        g(ξ) = sample(cs, h, x + ξ * fwd[1], y + ξ * fwd[2])
        pr(ξ) = sample(cs, cs.P, x + ξ * fwd[1], y + ξ * fwd[2])
        so = soils === nothing ? cs.soil : soils[k]    # s169: each wheel's own soil (the wet band vs the dry cove)
        prev = get(cs.last, k, nothing)
        st = prev === nothing ? nothing : settle_from(so, r, b, g, W, prev; pressed = pr)
        if st === nothing
            prev === nothing || (cs.fallbacks += 1)
            st = settle(so, r, b, g, W; pressed = pr)
        end
        cs.last[k] = st
        zb = st.zc - r
        i0 = clamp(floor(Int, (x - r - cs.x0) / dx), 1, nx); i1 = clamp(ceil(Int, (x + r - cs.x0) / dx) + 1, 1, nx)
        j0 = clamp(floor(Int, (y - r - cs.y0) / dx), 1, ny); j1 = clamp(ceil(Int, (y + r - cs.y0) / dx) + 1, 1, ny)
        for i in i0:i1, j in j0:j1
            px = cs.x0 + (i - 0.5) * dx - x; py = cs.y0 + (j - 0.5) * dx - y
            along = px * fwd[1] + py * fwd[2]; across = -px * fwd[2] + py * fwd[1]
            (abs(across) <= b / 2 && abs(along) < r) || continue
            moving && along > 0 && continue
            U[i, j] = min(U[i, j], Float32(zb + r - sqrt(r^2 - along^2)))
        end
        st
    end
    SandField.press!(f, U; bulb = b, R)
    h1 = Array(f.h)
    loosen!(cs.P, h, h1, U)
    sts
end

"""
The load history after the sand moved from `h0` to `h1`: a covered cell (U finite) that went down was pressed by
that much; sand that LANDED on a cell (a berm, a slump into a rut) is loose, so it takes that much off the cell's
pressed depth. (s168: without the second half, sand slumping back into a rut was pressed out and counted again every
frame: `pressed` reached 72 mm under a 26 mm rut, and the wheels stood on a step they could not settle on.)
"""
function loosen!(P, h0, h1, U = nothing)
    @inbounds for k in eachindex(P)
        d = h1[k] - h0[k]
        if d < 0 && U !== nothing && !isinf(U[k])          # only a body presses; sand sliding away is not pressed
            P[k] -= d
        elseif d > 0
            P[k] = max(P[k] - d, 0f0)
        end
    end
    P
end

"Slump the cart's sand `n` sweeps, keeping the load history honest (what slides in is loose)."
function slump!(cs::CartSand, n = 2)
    h0 = Array(cs.f.h)
    SandField.slump!(cs.f, n)
    loosen!(cs.P, h0, Array(cs.f.h))
    cs
end

"""
    run_wheel(; soil, W, r, b, push, L = 3.0, dx = 0.02, dt = 0.005, T = 8.0, m = W / 9.81, v0 = 0.0)

One wheel (a quarter of the cart: load W, mass m) pushed with `push` newtons along a strip of fresh sand (the field
is L long, 0.4 m wide). Each step: the ground ahead along the wheel's middle is read from the field, the wheel
settles, the sand's R slows it, its footprint is pressed in (rut and berm, compaction once) and the sand slumps.
Returns the time series and the field.
"""
function run_wheel(; soil = SOILS[:dry_sand], W = 95 * 9.81 / 4, r = 0.35, b = 0.10, push = 60.0, L = 3.0,
                   dx = 0.02, dt = 0.005, T = 8.0, m = W / 9.81, v0 = 0.0, x0 = 0.5, field = nothing, slumps = 4,
                   P = nothing)
    nx, ny = round(Int, L / dx), round(Int, 0.4 / dx)
    f = field === nothing ? SandField.Field(nx, ny, dx; depth = 0.5f0) : field
    yc = 0.2
    jc = round(Int, yc / dx) + 1
    x = x0; v = v0; out = NamedTuple[]
    P = P === nothing ? zeros(Float32, nx, ny) : P   # how far each cell has been pressed down (its load history)
    lin(A, xx) = (u = clamp(xx / dx + 0.5, 1.0, nx - 1e-6); i = floor(Int, u); a = u - i; Float64((1 - a) * A[i, jc] + a * A[i + 1, jc]))
    for k in 1:round(Int, T / dt)
        h = Array(f.h)
        st = settle(soil, r, b, ξ -> lin(h, x + ξ), W; pressed = ξ -> lin(P, x + ξ))
        net = push - st.R
        v = v > 1e-4 ? v + net / m * dt : max(net, 0.0) / m * dt     # the sand holds it still until the push beats R
        v = max(v, 0.0)
        x += v * dt
        (x > L - r - 0.05) && break
        if k % 4 == 1 || v > 0
            U = SandField.wheel_under(f, x, yc, r, b, st.zc - r)
            # only behind the rim's bottom does the sand STAY pressed: ahead of it the arc is still compressing it
            # (that is Wong-Reece's front stress). Pressing the whole footprint left the next step riding on a
            # sliver it had pressed itself, mm off the fresh sand ahead: 38 N rolling instead of 48.5 (s168)
            # A wheel standing still has pressed its whole contact (the friends' holes).
            if v > 0
                for ii in 1:nx
                    (ii - 0.5) * dx > x && (U[ii, :] .= Inf32)
                end
            end
            h0 = Array(f.h)
            SandField.press!(f, U; bulb = b)
            h1 = Array(f.h)
            @. P += ifelse(isinf(U), 0f0, max(h0 - h1, 0f0))
            SandField.slump!(f, slumps)
        end
        push!(out, (; t = k * dt, x, v, R = st.R, sink = st.zmax, zc = st.zc))
    end
    out, f, P
end

end
