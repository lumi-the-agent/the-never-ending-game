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
function converge(; chords = (32, 48), alphas = (-10, -5, 0, 5, 10), camber = 0.1, t_end = 24, t_avg = 10, gpu = true)
    mem = gpu ? gpu_mem() : Array
    out = NamedTuple[]
    for ch in chords, a in alphas
        # the boxes run s162 (multigrid wants sizes a * 2^n, n > 2)
        n = Dict(16 => (128, 64, 64), 24 => (192, 128, 96), 32 => (256, 128, 128), 48 => (320, 160, 160))[ch]
        sim = arc_sail_sim(deg2rad(a); camber = Float32(camber), n, chord = ch, span = 2ch, thick = 2, mem)
        sim_step!(sim, Float32(t_end - t_avg); remeasure = false)
        q = 0.5 * ch * 2ch
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

"""The `mem` for WaterLily on Mantle: arrays allocated on the GPU and filled from the CPU ones."""
gpu_mem() = x -> (a = KA.allocate(Mantle.Device(), eltype(x), size(x)); copyto!(a, x); a)

"""Sweep `alphas` (degrees) and return a vector of (alpha, CL, CD)."""
sweep(alphas; mem = Array, kw...) =
    [(alpha = a, coefficients(sail_sim(deg2rad(a); mem); kw...)...) for a in alphas]

end
