# A snowball that grows as it rolls (s140, project snowball). The ball rolls over a snow depth field (metres of snow
# per cell, laid by physics/snow.jl's fall) on the island's ground. Everything it gets comes from the snow:
# - pick-up: every cell under the ball's contact strip gives ALL its snow to the ball (sticky snow peels down to
#   the grass), so mass is conserved and the trail is bare ground; packed density turns the mass into a radius.
# - inertia: I = 2/5 m r^2 grows with it, a rolling ball's effective mass is 7/5 m, and snow picked up at rest has to be
#   brought to the ball's speed (d(m v)/dt): a fat ball slows down as it eats.
# - rolling resistance: Bekker's pressure-sinkage law p = (kc/b + kphi) z^n (Wong, Theory of Ground Vehicles, US
#   snow: n 1.6, kc 4.37 kN/m^(n+1), kphi 196.72 kN/m^(n+2)); the ball sinks until the snow carries its weight and
#   pays the compaction work b (kc/b + kphi) z^(n+1)/(n+1) per metre (capped by the snow there is).
#   Snowball.roll(height, field; start, v0, push, seconds) -> NamedTuple of per-step arrays; `field` is changed.
module Snowball

const G = 9.81
const N_B, KC, KPHI = 1.6, 4.37e3, 196.72e3       # Bekker, US snow (Wong)
const RHO_SNOW, RHO_BALL = 150.0, 450.0           # fresh snow, a packed snowball (kg/m^3)

mutable struct Field
    x0::Float64; y0::Float64; h::Float64          # corner and cell size (m)
    depth::Matrix{Float64}                        # snow depth (m)
    peeled::Matrix{Float64}                       # time the ball took it (Inf = still there)
end
Field(x0, y0, h, depth) = Field(x0, y0, h, depth, fill(Inf, size(depth)))

cell(f::Field, x, y) = (floor(Int, (x - f.x0) / f.h) + 1, floor(Int, (y - f.y0) / f.h) + 1)
function depth_at(f::Field, x, y)
    i, j = cell(f, x, y)
    (1 <= i <= size(f.depth, 1) && 1 <= j <= size(f.depth, 2)) ? f.depth[i, j] : 0.0
end

"Sinkage that carries `W` newtons on a ball of radius `r` (contact b = 2 sqrt(2rz) wide, sqrt(2rz) long), at most `d`."
function sinkage(W, r, d)
    d <= 1e-4 && return 0.0
    load(z) = (b = 2sqrt(2r * z); (KC / b + KPHI) * z^N_B * b * sqrt(2r * z))
    load(d) <= W && return d                       # snow too shallow to carry it: down to the grass
    lo, hi = 0.0, d
    for _ in 1:40
        z = (lo + hi) / 2
        load(z) < W ? (lo = z) : (hi = z)
    end
    return (lo + hi) / 2
end

"Compaction resistance (N) of a ball of radius `r` sunk `z` deep."
compaction(r, z) = z <= 0 ? 0.0 : (b = 2sqrt(2r * z); b * (KC / b + KPHI) * z^(N_B + 1) / (N_B + 1))

"Take the snow under the strip the ball touches; returns the mass picked up."
function pickup!(f::Field, x, y, r, t)
    m = 0.0
    reach = r                                       # the band it can touch at the deepest snow it meets
    i0, j0 = cell(f, x - reach, y - reach); i1, j1 = cell(f, x + reach, y + reach)
    for i in max(i0, 1):min(i1, size(f.depth, 1)), j in max(j0, 1):min(j1, size(f.depth, 2))
        d = f.depth[i, j]
        d > 0 || continue
        cx = f.x0 + (i - 0.5) * f.h; cy = f.y0 + (j - 0.5) * f.h
        ρ2 = (cx - x)^2 + (cy - y)^2
        dd = min(d, r)
        ρ2 < 2r * dd - dd^2 || continue             # the ball's footprint in a layer d deep (spherical cap)
        m += RHO_SNOW * d * f.h^2
        f.depth[i, j] = 0.0; f.peeled[i, j] = t
    end
    return m
end

radius(m) = cbrt(3m / (4π * RHO_BALL))

"Roll a ball from `start` (x, y) with velocity `v0`; `push` (N, along the motion) for the first `push_s` seconds
(Lumi pushing). `height(x, y)` is the ground. Integrates at `dt` and returns the track."
function roll(height, f::Field; start, v0 = (0.0, 0.0), r0 = 0.12, push = 0.0, push_s = 0.0, seconds = 10.0,
              dt = 1 / 240, grass_crr = 0.06)
    x, y = Float64.(start); vx, vy = Float64.(v0)
    m = 4π / 3 * r0^3 * RHO_BALL; ang = 0.0; ax_x, ax_y = 1.0, 0.0
    out = (t = Float64[], x = Float64[], y = Float64[], r = Float64[], m = Float64[], v = Float64[], angle = Float64[],
           axis = Tuple{Float64,Float64}[], sink = Float64[])
    for k in 0:round(Int, seconds / dt)
        t = k * dt; r = radius(m)
        e = 0.05
        gx = (height(x + e, y) - height(x - e, y)) / 2e; gy = (height(x, y + e) - height(x, y - e)) / 2e
        s = sqrt(1 + gx^2 + gy^2)
        sp = hypot(vx, vy); ux, uy = sp > 1e-6 ? (vx / sp, vy / sp) : (0.0, 0.0)
        d = depth_at(f, x + ux * (r + f.h), y + uy * (r + f.h))  # the snow it rolls INTO (its footprint is peeled)
        z = sinkage(m * G / s, r, d)
        R = compaction(r, z) + (d < 1e-3 ? grass_crr * m * G / s : 0.0)
        Fx = -m * G * gx / s^2; Fy = -m * G * gy / s^2      # gravity along the slope
        if t < push_s
            px, py = sp > 0.05 ? (ux, uy) : (Float64.(v0) ./ max(hypot(v0...), 1e-9))
            Fx += push * px; Fy += push * py
        end
        dm = sp > 1e-4 ? pickup!(f, x, y, r, t) : 0.0
        meff = 7 / 5 * m
        # resistance only against motion, and it can stop the ball but not push it back
        if sp < 1e-3 && hypot(Fx, Fy) <= R
            vx = vy = 0.0
        else
            vx += dt * (Fx - R * ux) / meff; vy += dt * (Fy - R * uy) / meff
            # picked-up snow was at rest: momentum shared with the new mass
            vx *= meff / (meff + 7 / 5 * dm); vy *= meff / (meff + 7 / 5 * dm)
            if sp > 1e-3 && vx * ux + vy * uy < 0           # resistance overshoot: stopped
                vx = vy = 0.0
            end
        end
        m += dm
        x += vx * dt; y += vy * dt
        sp = hypot(vx, vy)
        sp > 1e-6 && ((ax_x, ax_y) = (-vy / sp, vx / sp))   # spin axis: horizontal, across the motion
        ang += sp * dt / radius(m)
        if k % 10 == 0
            push!(out.t, t); push!(out.x, x); push!(out.y, y); push!(out.r, radius(m)); push!(out.m, m)
            push!(out.v, sp); push!(out.angle, ang); push!(out.axis, (ax_x, ax_y)); push!(out.sink, z)
        end
    end
    return out
end

end
