# Knock on anything (s138): the notes an object really sings, from its own mesh.
# The mesh is filled with voxels (rays along x per (y,z) column, fill between hit pairs), FinEtools turns the voxels
# into 8-node hexahedra (H8voximg), its linear elasticity gives stiffness and mass, Arpack the lowest modes
# (base fixed: the thing stands on the ground). A knock at a point excites each mode by its shape there.
#   include("physics/modes.jl"); m = Modes.solve(mesh; height = 1.0, n = 18, E = 30e9, rho = 2500.0)
#   Modes.knock_wav("x.wav", m, p_world)
module Modes
using FinEtools, FinEtoolsDeforLinear, Arpack, LinearAlgebra, SparseArrays, GeometryBasics

struct ModeSet
    xyz::Matrix{Float64}        # FE nodes, metres, object frame (base at z = 0)
    freqs::Vector{Float64}      # Hz
    shapes::Matrix{Float64}     # 3 nnodes x nmodes, mass normalised
    damping::Vector{Float64}    # decay rate 1/s per mode
    scale::Float64              # mesh units -> metres
    lo::Vec3f                   # mesh min corner (mesh units)
end

"Solid voxels of a triangle mesh, `n` cells along its longest side: cells holding a vertex are shell, the outside is
flooded from the border, everything the flood cannot reach is solid (robust to the generated meshes' open seams,
where counting ray crossings filled 27 of 1296 cells). Returns (image, cell size, lo corner)."
function voxelize(pts::AbstractVector, tris::AbstractVector, n::Int)
    lo = Vec3f(minimum(p[1] for p in pts), minimum(p[2] for p in pts), minimum(p[3] for p in pts))
    hi = Vec3f(maximum(p[1] for p in pts), maximum(p[2] for p in pts), maximum(p[3] for p in pts))
    h = maximum(hi - lo) / n
    N = max.(1, ceil.(Int, (hi - lo) ./ h)) .+ 2          # one cell of air all round
    shell = falses(N...)
    for p in pts
        shell[clamp.(floor.(Int, (p - lo) ./ h) .+ 2, 1, N)...] = true
    end
    outside = falses(N...); stack = [CartesianIndex(1, 1, 1)]; outside[1, 1, 1] = true
    nb = (CartesianIndex(1, 0, 0), CartesianIndex(-1, 0, 0), CartesianIndex(0, 1, 0), CartesianIndex(0, -1, 0),
          CartesianIndex(0, 0, 1), CartesianIndex(0, 0, -1))
    R = CartesianIndices(outside)
    while !isempty(stack)
        c = pop!(stack)
        for d in nb
            q = c + d
            (q in R && !outside[q] && !shell[q]) || continue
            outside[q] = true; push!(stack, q)
        end
    end
    img = Int.(.!outside)[2:end-1, 2:end-1, 2:end-1]
    return img, h, lo
end

"Lowest `nev` modes of the solid mesh, scaled so it is `height` metres tall, base (lowest voxel layer) fixed."
function solve(mesh; height = 1.0, n = 18, E = 30e9, nu = 0.25, rho = 2500.0, zeta = 0.004, nev = 12)
    pts = coordinates(mesh); tris = faces(mesh)
    img, h, lo = voxelize(pts, tris, n)
    zext = maximum(p[3] for p in pts) - lo[3]
    s = Float64(height) / Float64(zext)
    hm = Float64(h) * s
    fens, fes = H8voximg(img, [hm, hm, hm], [1])
    fens.xyz[:, 3] .-= minimum(fens.xyz[:, 3])
    MR = DeforModelRed3D
    mat = MatDeforElastIso(MR, rho, E, nu, 0.0)
    geom = NodalField(fens.xyz)
    u = NodalField(zeros(size(fens.xyz, 1), 3))
    base = selectnode(fens; box = [-Inf Inf -Inf Inf 0.0 0.0], inflate = hm / 4)
    for d in 1:3
        setebc!(u, base, true, d, 0.0)
    end
    applyebc!(u); numberdofs!(u)
    femm = FEMMDeforLinear(MR, IntegDomain(fes, GaussRule(3, 2)), mat)
    associategeometry!(femm, geom)
    nf = nfreedofs(u)                       # dofs are numbered free first; the matrices hold all of them
    K = stiffness(femm, geom, u)[1:nf, 1:nf]
    M = mass(femm, geom, u)[1:nf, 1:nf]
    d, v = eigs(Symmetric(K), Symmetric(M); nev, which = :LM, sigma = 0.0)
    ω = sqrt.(max.(real.(d), 0.0)); o = sortperm(ω)
    shapes = zeros(3, size(fens.xyz, 1), nev)
    for (m, idx) in enumerate(o)
        scattersysvec!(u, real.(v[:, idx]))
        shapes[:, :, m] .= u.values'
    end
    return ModeSet(fens.xyz, ω[o] ./ 2π, reshape(shapes, 3size(fens.xyz, 1), nev), zeta .* ω[o], s, lo), (; fens, fes, img, voxel = hm)
end

"The sound of a knock at `p` (object frame, metres) along direction `dir`: decaying modes plus the contact click."
function knock(m::ModeSet, p, dir; sr = 44100, seconds = 1.5, contact = 0.0006)
    nn = size(m.xyz, 1)
    i = argmin([sum(abs2, m.xyz[q, :] .- p) for q in 1:nn])
    t = (0:round(Int, seconds * sr)-1) ./ sr
    y = zeros(length(t))
    for k in eachindex(m.freqs)
        f = m.freqs[k]; f < 20 && continue
        φ = m.shapes[3i-2:3i, k]
        a = dot(φ, dir)
        g = abs(sinc(2f * contact))          # a short half-sine contact rolls off the high modes
        y .+= a * g .* sin.(2π * f .* t) .* exp.(-m.damping[k] .* t)
    end
    return y ./ maximum(abs, y)
end

function write_wav(path, y; sr = 44100)
    n = length(y)
    open(path, "w") do io
        write(io, "RIFF", UInt32(36 + 2n), "WAVE", "fmt ", UInt32(16), UInt16(1), UInt16(1), UInt32(sr), UInt32(2sr),
              UInt16(2), UInt16(16), "data", UInt32(2n))
        for s in y
            write(io, round(Int16, clamp(s, -1, 1) * 30000))
        end
    end
    return path
end

end
