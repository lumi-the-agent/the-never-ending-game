# The force of the wind on a sail, from the solved flow around it (s162, project landyacht).
# No lift curve: the sail is an immersed body in a 3D WaterLily.jl box (on the GPU through Mantle since the s162
# Lava fix), and the force on it is the pressure the flow puts on its surface (WaterLily.pressure_force).
# Step 1 is a rigid flat plate swept through angles of attack: lift has to rise, peak and stall by itself.
# Later the plate becomes cloth whose shape is the next body in the flow, and the box rides with the cart.
# Looked first (rule 6): RomeoDB has panel and vortex-lattice codes (lifting lines, no separation, so no stall)
# and WaterLily, which resolves the separated flow; WaterLily it is.
module SailFlow
using WaterLily, StaticArrays, LinearAlgebra
import Mantle
const KA = WaterLily.KernelAbstractions

@inline function box_sdf(x, c, h)
    q = abs.(x .- c) .- h
    norm(max.(q, 0)) + min(maximum(q), 0)
end

"""
    sail_sim(alpha; n = (128, 64, 64), chord = 16, span = 32, thick = 2, Re = 2000, mem = Array)

A flat sail plate, `chord` x `span` x `thick` cells, its span along z, turned `alpha` radians about z against
a wind of speed 1 along +x. Time is in chords per wind speed (`sim_time`).
"""
function sail_sim(alpha; n = (128, 64, 64), chord = 16, span = 32, thick = 2, Re = 2000, mem = Array)
    c0 = SVector{3,Float32}(n[1] * 0.3f0, n[2] / 2, n[3] / 2)
    h = SVector{3,Float32}(chord / 2, thick / 2, span / 2)
    ca, sa = cos(Float32(alpha)), -sin(Float32(alpha))   # positive alpha = leading edge up (nose up)
    sdf(x, t) = begin
        d = x - c0
        # into the plate frame; no element type forced: WaterLily differentiates the sdf with ForwardDiff Duals
        xr = SVector(ca * d[1] + sa * d[2], -sa * d[1] + ca * d[2], d[3])
        box_sdf(xr, zero(c0), h)
    end
    Simulation(n, (1f0, 0f0, 0f0), Float32(chord); U = 1f0, ν = Float32(chord) / Float32(Re),
               body = AutoBody(sdf), T = Float32, mem)
end

"""
    arc_sail_sim(alpha; camber = 0.1, n, chord, span, thick, Re, mem)

A cambered sail: a circular arc of `chord` with its deepest point `camber * chord` to leeward (+y at alpha = 0),
`thick` cells thick, extruded over `span`; turned nose up by `alpha`. The sheet's tension sets this depth on a
real sail, so this is what trimming changes.
"""
function arc_sail_sim(alpha; camber = 0.1f0, n = (128, 64, 64), chord = 16, span = 32, thick = 2, Re = 2000, mem = Array)
    c0 = SVector{3,Float32}(n[1] * 0.3f0, n[2] / 2, n[3] / 2)
    f = Float32(camber * chord); hc = Float32(chord / 2)
    R = (hc^2 + f^2) / (2f)                    # arc radius through both ends and the depth f
    yc = f - R                                 # arc centre below the chord line (plate frame)
    phi = asin(hc / R)                         # half angle of the arc
    ca, sa = cos(Float32(alpha)), -sin(Float32(alpha))
    ht, hs = Float32(thick / 2), Float32(span / 2)
    sdf(x, t) = begin
        d = x - c0
        px, py = ca * d[1] + sa * d[2], -sa * d[1] + ca * d[2]
        ry = py - yc
        r = sqrt(px^2 + ry^2)
        th = atan(px, ry)                      # angle from the arc's middle
        d2 = abs(th) <= phi ? abs(r - R) :
             min(sqrt((px - hc)^2 + py^2), sqrt((px + hc)^2 + py^2))   # past an end: distance to the edge
        q1, q2 = d2 - ht, abs(d[3]) - hs
        sqrt(max(q1, 0)^2 + max(q2, 0)^2) + min(max(q1, q2), 0)
    end
    Simulation(n, (1f0, 0f0, 0f0), Float32(chord); U = 1f0, ν = Float32(chord) / Float32(Re),
               body = AutoBody(sdf), T = Float32, mem)
end

"""
    coefficients(sim; t_end = 12, t_avg = 4, chord = 16, span = 32)

Run to `t_end` chords of wind and average the pressure force over the last `t_avg`: (CL, CD), force over
half the wind speed squared times the plate area (lift along +y, drag along +x).
"""
function coefficients(sim; t_end = 12f0, t_avg = 4f0, chord = 16, span = 32)
    sim_step!(sim, t_end - t_avg; remeasure = false)
    F = zeros(Float64, 3); k = 0
    while sim_time(sim) < t_end
        sim_step!(sim; remeasure = false)
        F .-= WaterLily.pressure_force(sim); k += 1   # WaterLily returns the force on the FLUID (s162: CD came out < 0)
    end
    F ./= k
    q = 0.5 * chord * span
    (CL = F[2] / q, CD = F[1] / q)
end

"""
    converge(; chords = (32, 48), alphas = (-10, -5, 0, 5, 10), camber = 0.1, t_end = 24, t_avg = 10, gpu = true)

Long runs of the cambered sail: for each chord (cells) and angle, the mean CL and CD over the last `t_avg` chords
of wind and their spread between 2-chord windows (min, max), so a short noisy average cannot pass for a result.
Runs on Mantle when `gpu`. Meant for a worker :run job (minutes per case at chord 48).
"""
function converge(; chords = (32, 48), alphas = (-10, -5, 0, 5, 10), camber = 0.1, t_end = 24, t_avg = 10, gpu = true,
                   aspect = 2)
    mem = gpu ? gpu_mem() : Array
    out = NamedTuple[]
    for ch in chords, a in alphas
        # the boxes run s162 (AR 2) and s163 (AR 4, tall sail); multigrid wants sizes a * 2^n, n > 2
        n = aspect == 2 ? Dict(16 => (128, 64, 64), 24 => (192, 128, 96), 32 => (256, 128, 128), 48 => (320, 160, 160))[ch] :
            aspect == 4 ? Dict(24 => (192, 96, 160), 32 => (256, 128, 192), 48 => (384, 192, 288))[ch] : error("no box for aspect $aspect")
        sim = arc_sail_sim(deg2rad(a); camber = Float32(camber), n, chord = ch, span = aspect * ch, thick = 2, mem)
        sim_step!(sim, Float32(t_end - t_avg); remeasure = false)
        q = 0.5 * ch * aspect * ch
        bins = Dict{Int,Vector{NTuple{2,Float64}}}()
        while sim_time(sim) < t_end
            sim_step!(sim; remeasure = false)
            F = -WaterLily.pressure_force(sim)
            push!(get!(bins, floor(Int, sim_time(sim) / 2), NTuple{2,Float64}[]), (F[2] / q, F[1] / q))
        end
        means = [(sum(first, v) / length(v), sum(last, v) / length(v)) for v in values(bins)]
        CL = sum(first, means) / length(means); CD = sum(last, means) / length(means)
        r = (chord = ch, alpha = a, CL = CL, CD = CD, CL_spread = extrema(first.(means)), CD_spread = extrema(last.(means)))
        @info "sail" r...
        push!(out, r)
    end
    out
end

"""
    telltales(alpha_deg; chord = 32, span = 128, n = (256, 128, 192), camber = 0.1, t_end = 14, t_avg = 4,
              xs = (0.05, 0.15, 0.3), zs = (0.0, 0.5), off = 2.5, every = 4)

Where a telltale yarn on the arc sail (AR 4 box by default, on Mantle) would point: the solved velocity `off` cells
off each face (:lee, the convex side, and :wind) at chord stations `xs` (fraction from the luff) and span stations
`zs` (fraction of the half-span from the middle), sampled every `every` steps over the last `t_avg` chords.
Per probe: mean tangential speed `ut` (wind = 1, + = towards the leech), outward normal speed `un`, the fraction of
samples with reversed flow `rev`, and the yarn's angle off the cloth `yarn_deg`. s164: the windward luff yarn
stands off 25-60 deg at 0-2.5 deg (luffing), lies down at 5-10; at 20 the LEE one lifts 15 deg (projects/landyacht.md).
"""
function telltales(alpha_deg; chord = 32, span = 128, n = (256, 128, 192), camber = 0.1f0, t_end = 14f0, t_avg = 4f0,
                   xs = (0.05, 0.15, 0.3), zs = (0.0, 0.5), off = 2.5f0, every = 4)
    sim = arc_sail_sim(deg2rad(alpha_deg); camber, n, chord, span, thick = 2, mem = gpu_mem())
    c0 = SVector{3,Float32}(n[1] * 0.3f0, n[2] / 2, n[3] / 2)
    f = Float32(camber * chord); hc = Float32(chord / 2); R = (hc^2 + f^2) / (2f); yc = f - R
    a = Float32(deg2rad(alpha_deg)); ca, sa = cos(a), sin(a)
    toworld(p) = SVector(ca * p[1] + sa * p[2], -sa * p[1] + ca * p[2])     # plate frame -> world (x, y)
    probes = NamedTuple[]
    for xf in xs, zf in zs, side in (:lee, :wind)
        px = -hc + Float32(xf) * chord; th = asin(px / R)
        nrm = SVector(sin(th), cos(th)); tng = SVector(cos(th), -sin(th))
        r = side == :lee ? R + 1f0 + off : R - 1f0 - off               # plate half thickness 1 cell
        w = toworld(SVector(0f0, yc) + r * nrm); tw = toworld(tng); nw = toworld(side == :lee ? nrm : -nrm)
        push!(probes, (xf = xf, zf = zf, side = side, x = SVector(c0[1] + w[1], c0[2] + w[2], c0[3] + Float32(zf) * span / 2),
                       t = SVector(tw[1], tw[2], 0f0), nout = SVector(nw[1], nw[2], 0f0)))
    end
    sim_step!(sim, t_end - t_avg; remeasure = false)
    ucpu = Array{Float32}(undef, size(sim.flow.u))
    ut = [Float32[] for _ in probes]; un = [Float32[] for _ in probes]
    k = 0
    while sim_time(sim) < t_end
        sim_step!(sim; remeasure = false); k += 1
        k % every == 0 || continue
        copyto!(ucpu, sim.flow.u)
        for (i, p) in enumerate(probes)
            v = WaterLily.interp(p.x .+ 1.5f0, ucpu)     # WaterLily's cell centre of index I sits at I - 1.5
            push!(ut[i], v' * p.t); push!(un[i], v' * p.nout)
        end
    end
    [(xf = p.xf, zf = p.zf, side = p.side, ut = sum(ut[i]) / length(ut[i]), ut_min = minimum(ut[i]),
      un = sum(un[i]) / length(un[i]), rev = count(<(0), ut[i]) / length(ut[i]),
      yarn_deg = rad2deg(atan(sum(un[i]), sum(ut[i]))), nsamp = length(ut[i])) for (i, p) in enumerate(probes)]
end

"""
    arc2d_sim(alpha; camber = 0.1, chord = 32, n = (256, 128), thick = 3, Re = 2000)

One 2D section of the cambered sail (CPU; 33k cells at chord 32 step in ~1 ms, 10x faster than real time for a
2.5 m chord in 5 m/s). `retrim!` turns it inside the running flow.
"""
function arc2d_sim(alpha; camber = 0.1f0, chord = 32, n = (256, 128), thick = 3, Re = 2000)
    flat = camber == 0
    f = Float32(max(camber, 1f-3) * chord); hc = Float32(chord / 2); R = (hc^2 + f^2) / (2f); yc = f - R; phi = asin(hc / R)
    c0 = SVector{2,Float32}(n[1] * 0.3f0, n[2] / 2); ht = Float32(thick / 2)
    # a new sdf of the same closure type per angle (kernels take no Refs; Simulation is mutable, so retrim swaps it)
    body(a) = begin
        ca, sa = cos(Float32(a)), -sin(Float32(a))
        sdf(x, t) = begin
            d = x - c0; px, py = ca * d[1] + sa * d[2], -sa * d[1] + ca * d[2]
            flat ? sqrt(max(abs(px) - hc, 0f0)^2 + py^2) - ht :         # camber 0: a flat plate, round ends
            begin
                ry = py - yc; r = sqrt(px^2 + ry^2); th = atan(px, ry)
                (abs(th) <= phi ? abs(r - R) : min(sqrt((px - hc)^2 + py^2), sqrt((px + hc)^2 + py^2))) - ht
            end
        end
        AutoBody(sdf)
    end
    sim = Simulation(n, (1f0, 0f0), Float32(chord); U = 1f0, ν = Float32(chord) / Float32(Re), body = body(alpha), T = Float32)
    (sim = sim, body = body, chord = chord)
end

"""Turn a 2D slice to angle `a` (radians) inside its running flow."""
retrim!(s, a) = (s.sim.body = s.body(a); measure!(s.sim, sum(s.sim.flow.Δt)); s)

"""Section lift coefficient of a 2D slice from its pressure force, averaged over `nsteps` steps from now."""
function slice_cl!(s; chords = 1.0)
    t1 = sim_time(s.sim) + chords; F = 0.0; k = 0
    while sim_time(s.sim) < t1
        sim_step!(s.sim; remeasure = false)
        F -= WaterLily.pressure_force(s.sim)[2]; k += 1
    end
    F / k / (0.5 * s.chord)
end

"""
    sail_slices(alpha_geo; aspect = 4, stations = 3, chord = 32, warm = 8, rounds = 12, relax = 0.5, twist = zeros)

The tall sail as `stations` 2D slices of solved flow joined by Prandtl's lifting line (Glauert's series, all terms,
so foot and head may differ): each slice is re-trimmed to its effective angle alpha_geo + twist - alpha_induced,
where the induced angle comes from the circulation the slices' own solved lift makes. No lift curve anywhere: the
section lift is the flow's, the downwash is the trailing vortices'. Returns the 3D CL (pi AR A1), the section CLs and
induced angles. Checked against the 3D AR-4 box (s164).
"""
function sail_slices(alpha_geo; aspect = 4, stations = 3, chord = 32, warm = 8, rounds = 12, relax = 0.5,
                     twist = zeros(stations), chords_per_round = 1.5, camber = 0.1f0)
    N = stations
    th = [j * pi / (N + 1) for j in 1:N]                    # stations at z = -b/2 cos(th), foot to head
    S = [sin(n * t) for t in th, n in 1:N]                    # Gamma_j = 2 b U sum_n A_n sin(n th_j)
    ai = zeros(N)
    slices = [arc2d_sim(alpha_geo + twist[j]; chord, camber = Float32(camber)) for j in 1:N]
    for s in slices; sim_step!(s.sim, Float32(warm); remeasure = false); end
    cl = zeros(N); A = zeros(N)
    for r in 1:rounds
        for j in 1:N; cl[j] = slice_cl!(slices[j]; chords = chords_per_round); end
        # Gamma_j / (U c) = cl_j / 2 ; with b = aspect * c:  sum_n A_n sin(n th_j) = cl_j / (4 aspect)
        A = S \ (cl ./ (4aspect))
        ainew = [sum(n * A[n] * sin(n * th[j]) for n in 1:N) / sin(th[j]) for j in 1:N]
        ai .= (1 - relax) .* ai .+ relax .* ainew
        for j in 1:N; retrim!(slices[j], alpha_geo + twist[j] - ai[j]); end
    end
    (CL = pi * aspect * A[1], cl = copy(cl), alpha_i_deg = rad2deg.(ai), A = A)
end

"""The `mem` for WaterLily on Mantle: arrays allocated on the GPU and filled from the CPU ones."""
gpu_mem() = x -> (a = KA.allocate(Mantle.Device(), eltype(x), size(x)); copyto!(a, x); a)

"""Sweep `alphas` (degrees) and return a vector of (alpha, CL, CD)."""
sweep(alphas; mem = Array, kw...) =
    [(alpha = a, coefficients(sail_sim(deg2rad(a); mem); kw...)...) for a in alphas]

end
