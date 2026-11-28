# Checks for physics/stuck.jl (s168): include("physics/stuck_check.jl"); stuck_check()
# The wheel on real ground must be WheelSand's wheel on flat ground; rolled through the sand field it must meet the
# same resistance (its own load history may not dig it in while it stands); a wheel left in the hole three friends
# pressed costs more to break out than fresh sand, and a ramp dug in front makes it cheaper than fresh sand.
include(joinpath(@__DIR__, "wheelsand.jl")); include(joinpath(@__DIR__, "sandfield.jl")); include(joinpath(@__DIR__, "stuck.jl"))

function stuck_check()
    dry = WheelSand.SOILS[:dry_sand]; r, b = 0.35, 0.10
    Wl = 95 * 9.81 / 4; Wh = 275 * 9.81 / 4
    flat = Stuck.settle(dry, r, b, x -> 0.0, Wl); ref = WheelSand.towed(dry, Wl, r, b)
    @assert abs(flat.R - ref.resistance) < 0.02 * ref.resistance "flat ground: $(flat.R) vs towed $(ref.resistance)"
    out, _, _ = Stuck.run_wheel(; soil = dry, W = Wl, push = 55.0, dt = 0.02, T = 3.0)
    Rroll = sum(p.R for p in out[10:end]) / length(out[10:end])
    @assert out[end].x > 1.5 && abs(Rroll - ref.resistance) < 0.15 * ref.resistance "in the field: R $(Rroll), x $(out[end].x)"
    still, _, _ = Stuck.run_wheel(; soil = dry, W = Wl, push = 0.0, dt = 0.02, T = 1.0)
    # depth of the rim's bottom below the fresh surface (zmax samples the mirrored arc and misses the bottom)
    @assert r - still[end].zc < 1.05 * (r - flat.zc) "a standing wheel digs itself in: $(r - still[end].zc) vs $(r - flat.zc)"
    _, f, P = Stuck.run_wheel(; soil = dry, W = Wh, push = 0.0, dt = 0.02, T = 1.0)
    dx = f.dx; jc = round(Int, 0.2 / dx) + 1; nx = size(f.h, 1)
    lin(A, xx) = (u = clamp(xx / dx + 0.5, 1.0, nx - 1e-6); i = floor(Int, u); a = u - i; Float64((1 - a) * A[i, jc] + a * A[i + 1, jc]))
    out_of(h) = Stuck.settle(dry, r, b, ξ -> lin(h, 0.5 + ξ), Wl; pressed = ξ -> lin(P, 0.5 + ξ))
    h = Array(f.h); hole = out_of(h)
    hf = minimum(h[:, jc])
    for i in 1:nx, j in jc-3:jc+3                     # a ramp dug from the hole's floor back up over 40 cm
        x = (i - 0.5) * dx - 0.5
        0 < x < 0.6 && (h[i, j] = min(h[i, j], Float32(hf + max(0.0, x - 0.2) / 0.4 * -hf)))
    end
    ramp = out_of(h)
    @assert hole.R > 1.2 * ref.resistance "the hole is no harder than fresh sand: $(hole.R)"
    @assert ramp.R < 0.5 * ref.resistance "the dug ramp does not help: $(ramp.R)"
    (; flat_N = 4flat.R, towed_N = 4ref.resistance, rolling_N = 4Rroll, hole_N = 4hole.R, ramp_N = 4ramp.R,
       hole_cm = 100maximum(Array(P)))
end
