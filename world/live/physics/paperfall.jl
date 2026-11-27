# A sheet of paper falling through air onto a roof and the ground, simulated (s127).
# PrintSim's sheet solver (VBD shells: stretching, bending, contact with friction, on the GPU through
# Mantle) plus the air drag I added to PrintSim (`air!`, dev/PrintSim/src/dynamics/air.jl).
# Nothing is keyframed: where the sheet goes comes from its mass, its stiffness, the air and the wind.
using PrintSim, LinearAlgebra
import PrintSim as PS
import Mantle
using GeometryBasics: Vec3, Vec3f, Point3f

"A frame axis set rotated by `θ` about y (a roof pitched along x)."
pitched(θ) = (Vec3(cos(θ), 0, sin(θ)), Vec3(0.0, 1, 0), Vec3(-sin(θ), 0, cos(θ)))

"""
    paper_drop(; T, dt, fps, size, spacing, start, tilt, wind, roof) -> (; frames, tris, ms_per_step, ...)

Drops an A4 sheet (80 g/m² office paper) from `start`, tilted `tilt` rad about x, through air with
`wind` (m/s), onto a pitched plank `roof = (center, pitch, half)` and a ground plane at z = 0.
Returns the sheet's vertex positions `fps` times a second, its triangles, and the cost per step.
"""
function paper_drop(; T = 6.0, dt = 1 / 240, fps = 30, size = (0.297, 0.21), spacing = 0.015,
        start = Vec3(-0.35, -0.1, 2.6), tilt = 0.45, wind = Vec3f(0.5, 0.15, 0),
        roof = (Vec3(0.0, 0.0, 1.1), deg2rad(28), (0.55, 0.45, 0.02)), roughness = 1e-4,
        newton = 4, iterations = 12, ground = true, curl = Inf, backend = Mantle.Device())
    b = ModelBuilder()
    if ground
        add_mesh!(b, box_mesh(Vec3(0, 0, -0.05), pitched(0.0), (6.0, 6.0, 0.05)); static = 0.6, kinetic = 0.5)   # grass
        rc, rp, rh = roof
        add_mesh!(b, box_mesh(rc, pitched(rp), rh); static = 0.35, kinetic = 0.3)                                  # a roof plank
    end
    g = SheetGrid(size[1], size[2], spacing)
    c, s = cos(tilt), sin(tilt)
    # a used letter is not flat: curled along its length with radius `curl` (paper curls without stretching)
    shape = isfinite(curl) ? (p -> (φ = (p[1] - size[1] / 2) / curl; Vec3(curl * sin(φ), p[2], curl * (1 - cos(φ))))) :
                             (p -> Vec3(p[1] - size[1] / 2, p[2], 0.0))
    place = p -> start + Vec3(p[1], c * (p[2] - size[2] / 2) - s * p[3], s * (p[2] - size[2] / 2) + c * p[3])
    sheet = add_sheet!(b, g, SheetMaterial(); shape, place)
    solver = SheetSolver(backend, b; roughness, newton, iterations)
    state = State(backend, b)
    air = SheetAir(; wind)
    PS.prime!(solver, state)
    stride = round(Int, 1 / (fps * dt))
    # one film frame of steps (air, then the implicit step), recorded once into a Mantle graph and replayed
    graph = Mantle.Graph(Mantle.todevice(backend))
    Mantle.repeat!(graph, stride) do _
        air!(graph, solver, state, dt, air)
        PS.step!(graph, solver, state, dt)
    end
    plan = Mantle.Plan(graph)
    Mantle.record!(plan)
    frames = Vector{Vector{Point3f}}()
    push!(frames, Point3f.(PS.approximate.(Array(state.x))))
    nf = round(Int, T * fps)
    t0 = time_ns()
    for _ in 1:nf
        Mantle.run!(plan); Mantle.waitfor!(plan)
        push!(frames, Point3f.(PS.approximate.(Array(state.x))))
    end
    ms = (time_ns() - t0) / 1e6 / (nf * stride)
    tris = [Tuple(Int.(t)) for t in b.tris]
    return (; frames, tris, ms_per_step = ms, nu = g.nu, nv = g.nv, dt, fps, roof)
end
