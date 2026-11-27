# The first motor fitted by hand (s154, project motor; physics/motor.jl). Two ferrite stones either side of a wooden
# rotor wound with copper, a split copper ring on its axle, two copper brushes. The rotor's angle every frame comes
# from Motor.spin: torque from I dl x B over every turn in the stones' field, current switched by which ring segment
# each brush touches, back-EMF, friction. Real time. Switched on at 1 s from a quarter turn, it turns 74 deg in 0.8 s
# and sticks short of its dead spot (torque < brush friction there). Lumi stands behind, watching.
#   submit_job(:clip; path, script = "movies/motor.jl", call = "motor_clip")
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motor.jl"))

"A tube mesh along a polyline (radius rad, nring sides)."
function mtube(pts, rad; nring = 10)
    P = [Point3f(p...) for p in pts]
    n = length(P)
    verts = Point3f[]; fcs = GLTriangleFace[]
    for i in 1:n
        t = normalize(i == 1 ? P[2] - P[1] : i == n ? P[n] - P[n-1] : P[i+1] - P[i-1])
        a = abs(t[3]) < 0.9 ? Vec3f(0, 0, 1) : Vec3f(1, 0, 0)
        u = normalize(cross(t, a)); w = cross(t, u)
        for k in 0:nring-1
            ph = 2pi * k / nring
            push!(verts, P[i] + rad * (cos(ph) * u + sin(ph) * w))
        end
    end
    for i in 1:n-1, k in 0:nring-1
        a = (i - 1) * nring + k + 1; b = (i - 1) * nring + mod(k + 1, nring) + 1
        c = i * nring + k + 1; d = i * nring + mod(k + 1, nring) + 1
        push!(fcs, GLTriangleFace(a, c, b)); push!(fcs, GLTriangleFace(b, c, d))
    end
    return GeometryBasics.normal_mesh(GeometryBasics.Mesh(verts, fcs))
end

"The bench motor, three times bench size so it reads next to Lumi (the physics runs on this same build)."
film_build() = Motor.big_bench()      # s154 late: turns sampled along each side (the coarse turn overstated the torque)

const MOTOR_SPOT = (5.6f0, -13.0f0)      # the tops board, open ground (movies/homopolar.jl filmed here)

function motor_parts(; seconds = 5.0, hold = 1.0)
    b = film_build()
    run = Motor.spin(b; seconds = seconds - hold + 0.1, θ0 = pi / 2)
    S = Dict{Symbol,Any}()
    copper = NG.Hikari.Copper(roughness = 0.18f0)
    wood = NG.Hikari.Diffuse(color = (0.42, 0.27, 0.15), roughness = 0.8f0)
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world; sc = gm.stage.scene
        g = NG.ground(w.island, MOTOR_SPOT)
        h0 = 0.075f0                                            # axle height over the board
        P = Point3f(g[1], g[2], g[3] + 0.03f0)                  # top of the board
        A = P + Point3f(0, 0, h0)                               # axle centre
        S[:P] = P; S[:A] = A
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(P - Point3f(0.16f0, 0.12f0, 0.03f0), Vec3f(0.36f0, 0.24f0, 0.03f0)));
              color = RGBf(0.42, 0.27, 0.15), name = :mo_board, material = wood)
        # the two stones on wooden blocks, axis along y
        for (k, m) in enumerate(b.magnets)
            y0 = Float32(m.pos[2]); Hs = 0.036f0; Rs = 0.036f0
            c0 = A + Point3f(0, y0, 0); c1 = c0 + Point3f(0, Hs, 0)
            mesh!(sc, GeometryBasics.normal_mesh(Cylinder(c0, c1, Rs)); color = RGBf(0.16, 0.16, 0.17), name = Symbol("mo_stone", k),
                  material = NG.Hikari.Diffuse(color = (0.16, 0.16, 0.17), roughness = 0.55f0))
            mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(A[1] - 0.03f0, c0[2], P[3]), Vec3f(0.06f0, Hs, h0 - Rs)));
                  color = RGBf(0.42, 0.27, 0.15), name = Symbol("mo_block", k), material = wood)
        end
        # axle in two forked sticks
        xa = 0.075f0
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(A - Point3f(xa + 0.01f0, 0, 0), A + Point3f(xa + 0.04f0, 0, 0), 0.0045f0));
              color = RGBf(0.6, 0.6, 0.62), name = :mo_axle_static, material = NG.Hikari.Aluminum(roughness = 0.3f0))
        for (k, x) in enumerate((-xa, xa + 0.03f0))
            mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(A[1] + x, A[2], P[3]), Point3f(A[1] + x, A[2], A[3] + 0.006f0), 0.007f0));
                  color = RGBf(0.42, 0.27, 0.15), name = Symbol("mo_fork", k), material = wood)
        end
        # the rotor (made at the origin in its own frame, turned and moved every frame)
        rot = []
        push!(rot, mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(-0.045f0, -0.008f0, -0.024f0), Vec3f(0.09f0, 0.016f0, 0.048f0)));
                         color = RGBf(0.5, 0.33, 0.18), name = :mo_rotor_wood, material = wood))
        turn = b.turn
        for j in 1:7                                            # the winding: turns side by side across the wood
            dy = (j - 4) * 0.0022f0
            pts = [Point3f(p[1] * 1.02f0, p[2] + dy, p[3] * 1.0f0 + sign(p[3]) * 0.0015f0) for p in turn]
            push!(rot, mesh!(sc, mtube(pts, 0.0016f0); color = RGBf(0.85, 0.45, 0.3), material = copper, name = Symbol("mo_turn", j)))
        end
        # split ring: two copper half rings with gaps, on the axle beyond the fork
        xr = xa + 0.018f0; rr = Float32(b.ring_r); half = (pi - b.gap) / 2
        for (k, c) in enumerate(b.seg_c)
            arc = [Point3f(xr, rr * cos(c + u), rr * sin(c + u)) for u in range(-half, half; length = 16)]
            push!(rot, mesh!(sc, mtube(arc, 0.0035f0); color = RGBf(0.85, 0.45, 0.3), material = copper, name = Symbol("mo_seg", k)))
        end
        # leads from the coil's two ends along the axle to the segments
        push!(rot, mesh!(sc, mtube([Point3f(0.045f0, 0, -0.028f0), Point3f(xr, rr * cos(0.0f0), rr * sin(0.0f0))], 0.0012f0);
                         color = RGBf(0.85, 0.45, 0.3), material = copper, name = :mo_lead1))
        push!(rot, mesh!(sc, mtube([Point3f(0.045f0, 0, 0.028f0), Point3f(xr, -rr, 0.0f0)], 0.0012f0);
                         color = RGBf(0.85, 0.45, 0.3), material = copper, name = :mo_lead2))
        S[:rot] = rot
        # brushes: springy copper strips touching the ring at the top and the bottom, wires off the board
        for (k, β) in enumerate(b.brushes)
            tip = A + Point3f(xr, rr * cos(β) * 1.25f0, rr * sin(β) * 1.25f0)
            base = Point3f(A[1] + xr + 0.05f0, A[2] + (k == 1 ? 0.03f0 : -0.03f0), P[3])
            mesh!(sc, mtube([base, Point3f(base[1], base[2], tip[3]), tip], 0.0016f0); color = RGBf(0.85, 0.45, 0.3),
                  material = copper, name = Symbol("mo_brush", k))
            mesh!(sc, mtube([base, base + Point3f(0.04f0, (k == 1 ? 0.28f0 : 0.22f0), -0.02f0)], 0.0018f0); color = RGBf(0.85, 0.45, 0.3),
                  material = copper, name = Symbol("mo_wire", k))
        end
        for c in w.creatures
            hypot(c.pos[1] - MOTOR_SPOT[1], c.pos[2] - MOTOR_SPOT[2]) < 6 && c.name != "Lumi" &&
                (c.pos = NG.ground(w.island, (MOTOR_SPOT[1] + 14f0, MOTOR_SPOT[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:tops_live_board, :tops_live_top)) && (p.visible[] = false)
        end
        A = S[:A]
        treal = max(t - hold, 0.0)
        k = clamp(searchsortedlast(run.t, treal), 1, length(run.θ))
        θ = Float32(run.θ[k])
        for m in S[:rot]
            Makie.rotate!(m, Makie.qrotation(Vec3f(1, 0, 0), θ))
            Makie.translate!(m, A)
        end
        me = NG.creature(gm.world, "Lumi")
        if me !== nothing                                       # Lumi behind the bench, facing the camera and the motor
            me.pos = NG.ground(gm.world.island, (A[1] - 2.8f0, A[2] + 1.6f0)); me.yaw = -0.53f0
        end
        rig.mode = :fixed
        ex, ey = A[1] + 0.45f0, A[2] - 0.35f0
        ge = NG.ground(gm.world.island, (ex, ey))[3]
        rig.eye = Point3f(ex, ey, max(A[3] + 0.12f0, ge + 0.15f0))
        rig.target = Point3f(A[1] - 1.0f0, A[2] + 0.45f0, A[3] + 0.04f0)   # 3/4 from the ring end: rotor between the stones, Lumi behind
        return nothing
    end
    return setup, shot, S, run
end

function motor_clip(path; samples = 20, width = 960, height = 540, fps = 24, seconds = 5.0, hour = 16.6, rasterize = false)
    setup, shot, S, run = motor_parts(; seconds)
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0)
    return merge(res, (; path, rev_s_end = round(run.rev_s, digits = 2), sparks = length(run.sparks), state = string(run.state)))
end
