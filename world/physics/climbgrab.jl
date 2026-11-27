# Climb anything, step 2 (s135, projects/climb-anything.md): does a grab hold? Lumi as a PrintSim compound affine
# body (a feathered torso and a claw pad, rigidly one body, 2 kg), thrown at a wall whose top is a lip. Nothing
# decides the outcome but PrintSim's contacts: Cundall-Strack friction capped by Coulomb (static and kinetic) on the
# claw pad and on the torso where it meets the wall. The lip is a block (face at x = 0, top at z = H); `slope` tips
# its top outwards (a rounded or sloped beam), which tips the contact normal and shrinks what friction can hold.
using PrintSim, LinearAlgebra
import PrintSim as PS
import GeometryBasics
using GeometryBasics: Vec3
import Mantle

const GRAB_AXES = (Vec3(1.0, 0, 0), Vec3(0.0, 1, 0), Vec3(0.0, 0, 1))

"""
    grab_trial(dev; speed = 1.0, slope = 0.0, H = 1.2, seconds = 1.2, dt = 1e-3, claw_mu = 0.6, body_mu = 0.25)

Throw Lumi at the lip with horizontal `speed` (m/s, towards the wall) and a small fall (0.6 m/s down), the claw pad
2 cm over the top. Returns `(held, track)`: `held` is true when the claw pad is still on the lip at the end; `track`
is a vector of `(t, center, A)` poses of the body every 10 ms (for films).
"""
function grab_trial(dev; speed = 1.0, slope = 0.0, beam = 0.0, H = 1.2, seconds = 1.2, dt = 1e-3, claw_mu = 0.6,
                    body_mu = 0.25, newton = 8, hinge = false, depth = 0.12, recess = 0.03)
    b = ModelBuilder()
    # the wall: a block with a vertical face at x = 0 up to H - 0.1, and on it a top slab tipped outwards by `slope`
    # about the lip's edge line (x = 0, z = H). s135 first try tipped the whole block, so the face leaned back and Lumi
    # lay on it: every grab held, whatever the slope.
    # s135 second try: a sharp edge held at every slope up to 50 degrees, because the claw pad hooks the corner, where
    # the contact can push in any direction. `beam > 0` makes the lip a round beam of that radius (top at H, its axis
    # over the wall's face), whose normal turns smoothly: there only friction can hold.
    top = beam > 0 ? H - beam : H - 0.1
    # with a beam the block's face sits 3 cm behind the beam's widest point (s135: its top corner at the beam's equator
    # was one more sharp edge, and the sliding pad hooked it)
    back = beam > 0 ? recess : 0.0   # 5 mm was not enough: the pad (half 5 cm) still rested on the corner
    add_mesh!(b, PS.box_mesh(Vec3(-0.4 - back, 0, top / 2), GRAB_AXES, (0.4, 1.0, top / 2)); static = claw_mu, kinetic = 0.8claw_mu)
    if beam > 0
        cyl = GeometryBasics.Cylinder(GeometryBasics.Point3d(-beam, -1, H - beam), GeometryBasics.Point3d(-beam, 1, H - beam), Float64(beam))   # flush with the face (s135: an overhanging beam trapped the torso under it)
        add_mesh!(b, GeometryBasics.mesh(GeometryBasics.Tesselation(cyl, 48); pointtype = GeometryBasics.Point3d,
                                         facetype = GeometryBasics.GLTriangleFace); static = claw_mu, kinetic = 0.8claw_mu)
    else
        s, c = sin(deg2rad(slope)), cos(deg2rad(slope))
        out, along, up = Vec3(c, 0, -s), Vec3(0.0, 1, 0), Vec3(s, 0, c)
        add_mesh!(b, PS.box_mesh(Vec3(0.0, 0, H) - 0.4out - 0.05up, (out, along, up), (0.4, 1.0, 0.05));
                  static = claw_mu, kinetic = 0.8claw_mu)
    end
    add_mesh!(b, PS.box_mesh(Vec3(0.0, 0, -0.05), GRAB_AXES, (3.0, 3.0, 0.05)); static = 0.5, kinetic = 0.4)  # ground
    x0, z0 = 0.06 + beam, 0.02      # start clear of a round beam (it sticks out by its radius)
    torso = PS.box_mesh(Vec3(0.02 + depth + x0, 0, H - 0.36 + z0), GRAB_AXES, (depth, 0.14, 0.30))
    claw = PS.box_mesh(Vec3(-0.03 + x0, 0, H + 0.025 + z0), GRAB_AXES, (0.05, 0.09, 0.015))
    v0 = Vec3(-speed, 0, -0.6)
    if hinge   # s135: a one-piece body wedged between lip and wall and never fell; claws and body hinged at the shoulder
        id = add_body!(dev, b, torso; mass = 1.8, static = body_mu, kinetic = 0.8body_mu, velocity = v0)
        idc = add_body!(dev, b, claw; mass = 0.2, static = claw_mu, kinetic = 0.8claw_mu, velocity = v0)
        add_joint!(b, id, idc; position = Vec3(0.02 + x0, 0, H + z0), axis = Vec3(0.0, 1, 0), kind = :hinge)
    else
        id = add_body!(dev, b, [(; mesh = torso, density = 60.0, static = body_mu, kinetic = 0.8body_mu),
                                (; mesh = claw, density = 400.0, static = claw_mu, kinetic = 0.8claw_mu)];
                       mass = 2.0, velocity = v0)
        idc = id
    end
    solver = BodySolver(dev, b; newton)
    state = AffineState(dev, b)
    PS.prime!(solver, state)
    track = Tuple{Float64, Vec3{Float64}, Any, Vec3{Float64}}[]
    claw0 = Vec3(-0.03 + x0, 0, H + 0.025 + z0)
    clawat() = (q = body_pose(state, b, idc); q[2] * (claw0 - b.bodies[idc].center) + q[1])
    n = round(Int, seconds / dt)
    for k in 1:n
        PS.step!(solver, state, dt)
        k % 10 == 0 && (p = body_pose(state, b, id); push!(track, (k * dt, Vec3{Float64}(p[1]), p[2], Vec3{Float64}(clawat()))))
    end
    clawc = clawat()
    held = clawc[3] > H - 0.02 && clawc[1] < 0.1     # the pad still ON the lip (s135: z > H - 0.15 called a slip a hold)
    return held, track, clawc
end
