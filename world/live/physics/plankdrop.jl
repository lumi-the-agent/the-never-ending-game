# s181 (project planks): oak planks dropped on the island's sand by PrintSim's affine bodies and IPC-style contact.
# The ground is the island's own heightfield under the cart road (physics/data/plank-ground.csv, sampled from
# NG.ground in the sandbox), meshed as triangles; each plank is a closed box mesh of oak (700 kg/m3) released from
# where the player let go of it, and it comes to rest where the contact puts it: on a hump it rocks, over a hollow it
# bridges. Nothing about the resting pose is set by hand.
using PrintSim, Mantle, LinearAlgebra, GeometryBasics
import PrintSim as PS

const PD_DIR = @__DIR__

"The island ground under the road as a mesh, in road coordinates (origin at the sample's corner, z from its lowest point)."
function ground_patch(; file = joinpath(PD_DIR, "data", "plank-ground.csv"), x0 = 2.3, y0 = -15.0, step = 0.04)
    rows = [parse.(Float64, split(l, ",")) for l in eachline(file) if !startswith(l, "#")]
    H = permutedims(reduce(hcat, rows))            # H[i, j]: x index i, y index j
    z0 = minimum(H)
    nx, ny = size(H)
    pts = [Point3{Float64}((i - 1) * step, (j - 1) * step, H[i, j] - z0) for j in 1:ny for i in 1:nx]
    id(i, j) = (j - 1) * nx + i
    fcs = GLTriangleFace[]
    for j in 1:ny-1, i in 1:nx-1
        push!(fcs, GLTriangleFace(id(i, j), id(i + 1, j), id(i + 1, j + 1)), GLTriangleFace(id(i, j), id(i + 1, j + 1), id(i, j + 1)))
    end
    (; mesh = GeometryBasics.Mesh(pts, fcs), H, z0, x0, y0, step)
end

"Height of the patch (road coordinates) under (u, v), bilinear."
function patch_z(g, u, v)
    fi = u / g.step + 1; fj = v / g.step + 1
    i = clamp(floor(Int, fi), 1, size(g.H, 1) - 1); j = clamp(floor(Int, fj), 1, size(g.H, 2) - 1)
    a = fi - i; b = fj - j
    (1 - a) * (1 - b) * g.H[i, j] + a * (1 - b) * g.H[i+1, j] + (1 - a) * b * g.H[i, j+1] + a * b * g.H[i+1, j+1] - g.z0
end

"""
    drop_planks(; planks, seconds, dt, every) -> (; poses, t, g)

`planks`: vector of (u, v, yaw, lift) in road coordinates (m, rad): where the player let go of each plank, `lift` above
the sand under its middle. Steps the bodies until `seconds`; `poses[k]` is a vector of (t, centre, A) every `every` s.
"""
function drop_planks(; planks = [(0.6, 0.28, 0.0, 0.15)], L = 0.6, W = 0.12, T = 0.02, density = 700.0, seconds = 1.0,
                     dt = 1e-3, every = 0.02, mu = 0.6, dev = Mantle.Device())
    g = ground_patch()
    b = ModelBuilder()
    add_mesh!(b, g.mesh; static = mu, kinetic = 0.8mu)
    ids = Int[]
    for (u, v, yaw, lift) in planks
        c = Vec3(u, v, patch_z(g, u, v) + lift + T / 2)
        ax = (Vec3(cos(yaw), sin(yaw), 0.0), Vec3(-sin(yaw), cos(yaw), 0.0), Vec3(0.0, 0, 1))
        push!(ids, add_body!(dev, b, box_mesh(c, ax, (L / 2, W / 2, T / 2)); density, static = mu, kinetic = 0.8mu))
    end
    solver = BodySolver(dev, b); state = AffineState(dev, b)
    PS.prime!(solver, state)
    poses = [Tuple{Float64,Vector{Float64},Matrix{Float64}}[] for _ in ids]
    t = 0.0; next = 0.0
    while t < seconds - 1e-9
        if t >= next - 1e-9
            for (k, id) in enumerate(ids)
                p, A = body_pose(state, b, id)
                push!(poses[k], (t, collect(Float64, p), Matrix{Float64}(A)))
            end
            next += every
        end
        PS.step!(solver, state, dt); t += dt
    end
    (; poses, t, g)
end
