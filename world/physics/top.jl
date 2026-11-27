# Carved tops (s143, project tops): a solid of revolution from a lathe profile r(z), spun on a plane.
# Its mass, centre and inertia come from the profile; it touches the ground at the lowest point of its own
# surface (which moves as it tilts), with a stiff penalty normal force and regularised Coulomb friction there.
# Nothing is scripted: a pointed top precesses and nutates, a round one with a low centre (the tippe top)
# turns itself over onto its stem by sliding friction alone.
# Looked at first: RigidBodyDynamics (contact at fixed body points on a half space) and Dojo (sphere/point
# contacts); neither has a contact point that moves over a curved surface of revolution.
using LinearAlgebra, StaticArrays

struct TopShape
    z::Vector{Float64}      # profile heights from the bottom (m), increasing
    r::Vector{Float64}      # radius at each height (m)
    rin::Vector{Float64}    # inner radius (a hollow: 0 for solid)
    m::Float64
    zc::Float64             # centre of mass height
    I1::Float64             # about a transverse axis through the centre
    I3::Float64             # about the spin axis
end

"""Integrate discs of the profile: mass, centre of mass and inertia of a solid of revolution of density `rho`."""
function TopShape(z, r, rin = zeros(length(z)); rho = 700.0)
    n = length(z)
    m = 0.0; mz = 0.0; I3 = 0.0; Iz2 = 0.0; Ir = 0.0
    for i in 1:n-1
        dz = z[i+1] - z[i]
        rm = (r[i] + r[i+1]) / 2; zm = (z[i] + z[i+1]) / 2; ri = (rin[i] + rin[i+1]) / 2
        dm = rho * pi * (rm^2 - ri^2) * dz
        m += dm; mz += dm * zm
        I3 += rho * pi * (rm^4 - ri^4) / 2 * dz
        Ir += rho * pi * (rm^4 - ri^4) / 4 * dz
        Iz2 += dm * zm^2
    end
    zc = mz / m
    return TopShape(collect(Float64, z), collect(Float64, r), collect(Float64, rin), m, zc, Ir + Iz2 - m * zc^2, I3)
end

"""The tippe top: a ball of radius `R` cut flat at `cut` R from the bottom, with a stem; its centre sits below the ball's."""
function tippe_profile(; R = 0.02, cut = 1.55, stem_r = 0.22, stem_len = 0.9, n = 120)
    zs = Float64[]; rs = Float64[]
    # KNOWN (s143): rings evenly in height make the ball's bottom a blunt cone (first ring 3.3 mm out), on whose point
    # the top balances from a 0.12 rad tilt. Rings evenly in polar angle fix that (flips from any tilt), but then flips
    # are slower and the 8 cm game top needs retuning: see projects/tops.md before changing this.
    for i in 0:n
        z = cut * R * i / n
        push!(zs, z); push!(rs, sqrt(max(0.0, R^2 - (z - R)^2)))
    end
    rs[1] = 1e-4
    push!(zs, cut * R + 1e-4); push!(rs, stem_r * R)
    z0 = (cut + stem_len - stem_r) * R                 # the stem ends in a half ball, so it can roll up onto it
    push!(zs, z0); push!(rs, stem_r * R)
    for i in 1:16
        z = z0 + stem_r * R * i / 16
        push!(zs, z); push!(rs, max(1e-4, sqrt(max(0.0, (stem_r * R)^2 - (z - z0)^2))))
    end
    return zs, rs
end

"""Inner radius of a hollow in the upper half of the ball (a shell `wall` R thick), which lowers the centre like a real tippe top's."""
tippe_hollow(zs; R = 0.02, wall = 0.18) = [z > R ? sqrt(max(0.0, ((1 - wall) * R)^2 - (z - R)^2)) : 0.0 for z in zs]

"""A classic top: a sharp tip, a wide body and a knob."""
function cone_profile(; H = 0.05, Rmax = 0.025, n = 80)
    zs = Float64[]; rs = Float64[]
    for i in 0:n
        t = i / n; z = H * t
        r = t < 0.55 ? Rmax * (t / 0.55)^0.8 : Rmax * sqrt(max(0.0, 1 - ((t - 0.55) / 0.45)^2 * 0.92))
        push!(zs, z); push!(rs, max(r, 2e-4))
    end
    push!(zs, H + 0.012); push!(rs, 0.004)
    return zs, rs
end

qmul(a, b) = SVector(a[1]*b[1] - a[2]*b[2] - a[3]*b[3] - a[4]*b[4], a[1]*b[2] + a[2]*b[1] + a[3]*b[4] - a[4]*b[3],
                     a[1]*b[3] - a[2]*b[4] + a[3]*b[1] + a[4]*b[2], a[1]*b[4] + a[2]*b[3] - a[3]*b[2] + a[4]*b[1])
function qrot(q)
    w, x, y, z = q
    return SMatrix{3,3}(1 - 2(y^2 + z^2), 2(x*y + w*z), 2(x*z - w*y),
                        2(x*y - w*z), 1 - 2(x^2 + z^2), 2(y*z + w*x),
                        2(x*z + w*y), 2(y*z - w*x), 1 - 2(x^2 + y^2))
end

"""Lowest point of the surface (world, relative to the centre of mass) for spin axis `a`."""
function lowest_point(S::TopShape, R)
    a = R[:, 3]
    h = SVector(0.0, 0.0, 1.0)
    d = h - dot(h, a) * a
    nd = norm(d)
    d = nd > 1e-9 ? -d / nd : -R[:, 1]          # points down, perpendicular to the axis
    sa = sqrt(max(0.0, 1 - a[3]^2))
    best = Inf; bi = 1
    h(i) = (S.z[i] - S.zc) * a[3] - S.r[i] * sa
    for i in eachindex(S.z)
        hz = h(i)
        hz < best && (best = hz; bi = i)
    end
    n = length(S.z)
    (bi == 1 || bi == n) && return (S.z[bi] - S.zc) * a + S.r[bi] * d
    # between rings: a parabola through the three lowest, so the contact slides smoothly over the curve. Snapping
    # from ring to ring made the round body a polyhedron resting on a facet, which held a 0.12 rad tilt (s143).
    hm, h0, hp = h(bi - 1), best, h(bi + 1)
    den = hm - 2h0 + hp
    u = den > 1e-15 ? clamp((hm - hp) / (2den), -1.0, 1.0) : 0.0
    lag(ym, y0, yp) = y0 + u * (yp - ym) / 2 + u^2 * (yp - 2y0 + ym) / 2
    z = lag(S.z[bi-1], S.z[bi], S.z[bi+1]); r = max(0.0, lag(S.r[bi-1], S.r[bi], S.r[bi+1]))
    return (z - S.zc) * a + r * d
end

"""
    spin_top(S; omega, tilt, seconds, dt, mu, frames_every) -> frames

Spin top `S` at `omega` rad/s, its axis tilted `tilt` rad, on a plane at z = 0, and return frames of
(t, pos (centre), q (quaternion body->world), height of the axis tip, spin, axis tilt).
"""
function spin_top(S::TopShape; omega = 120.0, tilt = 0.1, seconds = 6.0, dt = 2e-5, mu = 0.3,
                  k = 4e3, c = nothing, air = 2e-6, record = 1 / 60, v0 = (0.0, 0.0, 0.0))
    c === nothing && (c = 1.0 * sqrt(k * S.m))
    q = SVector(cos(tilt / 2), sin(tilt / 2), 0.0, 0.0)
    Rm = qrot(q)
    p0 = lowest_point(S, Rm)
    x = SVector(0.0, 0.0, -p0[3]); v = SVector(v0...)
    w = SVector(0.0, 0.0, omega)                   # body frame
    Ib = SVector(S.I1, S.I1, S.I3)
    g = SVector(0.0, 0.0, -9.81)
    frames = NamedTuple[]
    nrec = max(1, round(Int, record / dt)); nsteps = round(Int, seconds / dt)
    for step in 0:nsteps
        Rm = qrot(q)
        if step % nrec == 0
            push!(frames, (t = step * dt, pos = x, q = q, spin = w[3], tilt = acos(clamp(Rm[3, 3], -1, 1))))
        end
        rp = lowest_point(S, Rm)
        ww = Rm * w
        vp = v + cross(ww, rp)
        pen = -(x[3] + rp[3])
        F = S.m * g; tau = -air * ww * norm(ww)
        if pen > 0
            N = max(0.0, k * pen - c * vp[3])
            vt = SVector(vp[1], vp[2], 0.0)
            Ft = -mu * N * vt / max(norm(vt), 1e-3)
            Fc = SVector(Ft[1], Ft[2], N)
            F += Fc; tau += cross(rp, Fc)
        end
        v += dt * F / S.m
        x += dt * v
        tb = Rm' * tau
        w += dt * (tb - cross(w, Ib .* w)) ./ Ib
        q = qmul(q, SVector(1.0, w[1] * dt / 2, w[2] * dt / 2, w[3] * dt / 2))
        q /= norm(q)
    end
    return frames
end
