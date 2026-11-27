# Putting over buried magnet stones (s151, idea "Putting over buried magnet stones", project ironsand).
#
# An iron ball rolls on a flat sand tray; magnet stones lie buried under it at any pose. The ball is soft iron: in a
# field H it carries the induced moment of an iron sphere, m = 3V H (mu_r >> 1, the sphere's demagnetisation limits
# it), so the force is F = mu0 (m.grad) H = (3 V mu0 / 2) grad |H|^2. Nothing else pulls it. It rolls without
# slipping (a solid sphere: 7/5 of its mass resists a sideways push), and rolling resistance on sand takes
# Crr * (weight + the stones' downward pull), so a ball over a stone also gets sticky. A ball slow enough near a
# stone's pole stops in its pull. The honest numbers (projects/ironsand.md): a lodestone 1 cm down acts like a
# 2 degree dimple ~15 cm wide, so this is a tray game with slow putts.
#   s = MagnetGolf.Stone(...) ; MagnetGolf.putt(stones, p0, v0) -> path (vector of (t, x, y)), why it stopped
module MagnetGolf

using LinearAlgebra
# share the parent's EM when it has one (a plugin with iron sand passes these stones to IronSand.Sand)
if isdefined(parentmodule(@__MODULE__), :EM)
    import ..EM
else
    Base.include(@__MODULE__, joinpath(@__DIR__, "em.jl"))
end

const RHO = 7870.0
const G = 9.81

"A buried stone: a lodestone cylinder (radius R, height h), its centre at (x, y, -depth - h/2), its magnetic axis
tilted `tilt` from vertical towards azimuth `az` (radians). Br from EM.MATERIALS[:magnetite] unless given."
function Stone(; x = 0.0, y = 0.0, depth = 0.01, R = 0.05, h = 0.08, tilt = 0.0, az = 0.0,
               Br = EM.MATERIALS[:magnetite].Br, sides = 48, quad = 6)
    # sides 16, quad 3: forces within ~10% of the fine stone at 1/17 the cost (s151), for play at frame rate
    v, f = EM.cylinder_mesh(R, h; n = sides)         # spans z 0..h in its frame, axis +z
    v = [(p[1], p[2], p[3] - h / 2) for p in v]      # centred on its own origin, so tilting turns it about its middle
    ax = (sin(tilt) * cos(az), sin(tilt) * sin(az), cos(tilt))
    # rotation taking +z to ax
    z = [0.0, 0.0, 1.0]; a = collect(ax); c = dot(z, a); k = cross(z, a); s = norm(k)
    Rm = s < 1e-9 ? (c > 0 ? Matrix(1.0I, 3, 3) : [1.0 0 0; 0 -1 0; 0 0 -1]) :
         (K = [0 -k[3] k[2]; k[3] 0 -k[1]; -k[2] k[1] 0] / s; Matrix(1.0I, 3, 3) + s * K + (1 - c) * K * K)
    # the top of a tilted stone reaches higher: keep its highest point `depth` under the sand
    top = maximum((Rm * collect(p))[3] for p in v)
    return EM.magnet(v, f, (0.0, 0.0, Br / EM.MU0); n = quad, pos = (x, y, -depth - top), R = Rm)
end

H2(stones, p) = sum(abs2, reduce(.+, (EM.H(s, p) for s in stones); init = (0.0, 0.0, 0.0)))

"Force (N) on an iron ball of radius r centred at p, from the buried stones."
function ballforce(stones, p, r)
    V = 4pi / 3 * r^3; h = 5e-4
    g = ntuple(i -> (H2(stones, p .+ h .* ntuple(j -> j == i, 3)) - H2(stones, p .- h .* ntuple(j -> j == i, 3))) / 2h, 3)
    return 1.5 * EM.MU0 * V .* g
end

"""One step of a rolling iron ball at (x, y) with velocity (vx, vy): the new (x, y, vx, vy, resting).
The same physics as `putt`, for a game that steps the ball every frame."""
function rollstep(stones, x, y, vx, vy; r = 0.015, Crr = 0.06, dt = 4e-3)
    m = RHO * 4pi / 3 * r^3
    F = ballforce(stones, (x, y, r), r)
    N = m * G - F[3]
    sp = hypot(vx, vy)
    ax = F[1] / (1.4m); ay = F[2] / (1.4m)
    if sp < 1e-3
        hypot(F[1], F[2]) <= Crr * N && return (x, y, 0.0, 0.0, true)
    else
        ax -= Crr * N / (1.4m) * vx / sp; ay -= Crr * N / (1.4m) * vy / sp
    end
    nvx = vx + ax * dt; nvy = vy + ay * dt
    sp > 1e-3 && nvx * vx + nvy * vy < 0 && hypot(F[1], F[2]) <= Crr * N && return (x, y, 0.0, 0.0, true)
    return (x + nvx * dt, y + nvy * dt, nvx, nvy, false)
end

"""Roll an iron ball (radius r) from (x, y) at velocity (vx, vy) over the tray until it stops, leaves the tray
(half width `half`) or drops in the cup (at `cup`, radius 0.025, if given; a ball faster than `vcup` lips out).
Crr: rolling resistance on sand. Returns (path = [(t, x, y)], end = :stopped | :out | :cup, t)."""
function putt(stones, p0, v0; r = 0.01, Crr = 0.06, dt = 2e-3, tmax = 12.0, half = 0.6, cup = nothing, vcup = 0.6)
    m = RHO * 4pi / 3 * r^3
    x, y = Float64.(p0); vx, vy = Float64.(v0)
    path = [(0.0, x, y)]; t = 0.0
    while t < tmax
        F = ballforce(stones, (x, y, r), r)
        N = m * G - F[3]                              # the stones pull it down into the sand too
        sp = hypot(vx, vy)
        # sideways field push on a rolling solid sphere: a = F / (7/5 m)
        ax = F[1] / (1.4m); ay = F[2] / (1.4m)
        if sp < 1e-3
            # at rest: it starts again only if the pull beats rolling resistance
            hypot(F[1], F[2]) <= Crr * N && return (path = path, stop = :stopped, t = t)
        else
            ax -= Crr * N / (1.4m) * vx / sp; ay -= Crr * N / (1.4m) * vy / sp
        end
        nvx = vx + ax * dt; nvy = vy + ay * dt
        # resistance cannot reverse a ball: it stops
        sp > 1e-3 && nvx * vx + nvy * vy < 0 && hypot(F[1], F[2]) <= Crr * N && return (path = push!(path, (t, x, y)), stop = :stopped, t = t)
        vx, vy = nvx, nvy
        x += vx * dt; y += vy * dt; t += dt
        length(path) < 100000 && (round(Int, t / dt) % 10 == 0) && push!(path, (t, x, y))
        (abs(x) > half || abs(y) > half) && return (path = push!(path, (t, x, y)), stop = :out, t = t)
        if cup !== nothing && hypot(x - cup[1], y - cup[2]) < 0.025 && hypot(vx, vy) < vcup
            return (path = push!(path, (t, cup[1], cup[2])), stop = :cup, t = t)
        end
    end
    return (path = path, stop = :time, t = t)
end

end
