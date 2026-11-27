# The scrap crane, first slice (s150, idea "The scrap crane", physics/coilcrane.jl). Lumi holds a cord in its beak
# (NG.beak_tips: the real posed beak); on it hangs a coil wound on an iron peg, current on. Lumi bends down (:eat),
# the coil swings down into a heap of iron pegs on the sand, Lumi straightens, the coil rises. What each peg does is
# the field: the coil's Biot-Savart field, core and pegs solved together as soft iron (physics/softiron.jl), the force
# and torque on each peg, gravity, sand friction. A peg touching the core (or a held peg) rides along while the pull
# along the contact beats its weight. Nothing here moves a peg. Known gap: free pegs do not collide with each other.
#   submit_job(:clip; path, script = "movies/crane.jl", call = "crane_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "coilcrane.jl"))

const CR_L = 0.2; const CR_A = 0.006                     # pegs and core: 20 cm iron, 6 mm radius
const CR_M = 7870.0 * pi * CR_A^2 * CR_L
const CR_MU = 0.5                                        # iron on sand / iron on iron
const CR_WOUND = 0.014 + 0.0028                          # the winding's outer radius (helix R + wire radius, as drawn)

"""One step of a free peg: field force F and torque T, gravity, and the sand. A peg with an end on the sand turns by
its weight about that end (s151: before, a peg the field stood up stayed leaning in the air when the field left)."""
function fall!(q, F, T, gz, m, Iperp; dt = 5e-4)
    e1, e2 = ends(q.p, q.u); lowe = e1[3] < e2[3] ? e1 : e2
    onsand = lowe[3] - CR_A < gz + 1e-3
    Tg = onsand ? vcross(vsub(q.p, lowe), (0.0, 0.0, -9.81 * m)) : (0.0, 0.0, 0.0)
    q.v = vadd(q.v, vmul(dt / m, vadd(F, (0.0, 0.0, -9.81 * m))))
    # about the end on the sand the peg's inertia is m L^2 / 3, four times Iperp about its middle
    q.w = vadd(vmul(0.995, q.w), vadd(vmul(dt / Iperp, T), vmul(dt / (4Iperp), Tg)))
    q.p = vadd(q.p, vmul(dt, q.v))
    q.u = vunit(vadd(q.u, vmul(dt, vcross(q.w, q.u))))
    # the sand: the lowest end stays on it; friction stops a slide the field cannot push
    e1, e2 = ends(q.p, q.u); low = min(e1[3], e2[3]) - CR_A
    if low < gz
        q.p = vadd(q.p, (0.0, 0.0, gz - low))
        Fh = hypot(F[1], F[2]); Nn = max(m * 9.81 - F[3], 0.0)
        q.v = Fh < CR_MU * Nn ? (0.0, 0.0, max(q.v[3], 0.0)) : (q.v[1] * 0.9, q.v[2] * 0.9, max(q.v[3], 0.0))
        # lying flat it stops turning about its long axis' cross (the sand holds it)
        abs(q.u[3]) < 0.02 && (q.w = vmul(0.5, q.w); q.u = vunit((q.u[1], q.u[2], 0.0)))
    end
    return q
end

mutable struct Peg
    p::NTuple{3,Float64}; v::NTuple{3,Float64}; u::NTuple{3,Float64}; w::NTuple{3,Float64}
    held::Bool; rel::NTuple{3,Float64}; urel::NTuple{3,Float64}
end

v3(x) = (Float64(x[1]), Float64(x[2]), Float64(x[3]))
vadd(a, b) = (a[1] + b[1], a[2] + b[2], a[3] + b[3]); vsub(a, b) = (a[1] - b[1], a[2] - b[2], a[3] - b[3])
vmul(s, a) = (s * a[1], s * a[2], s * a[3]); vdot(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
vcross(a, b) = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
vnorm(a) = sqrt(vdot(a, a)); vunit(a) = vmul(1 / max(vnorm(a), 1e-12), a)

"Closest points between segments p1-q1 and p2-q2 (Ericson), returns (c1, c2)."
function segseg(p1, q1, p2, q2)
    d1 = vsub(q1, p1); d2 = vsub(q2, p2); r = vsub(p1, p2)
    a = vdot(d1, d1); e = vdot(d2, d2); f = vdot(d2, r); c = vdot(d1, r); b = vdot(d1, d2)
    den = a * e - b * b
    s = den > 1e-12 ? clamp((b * f - c * e) / den, 0.0, 1.0) : 0.0
    t = (b * s + f) / e
    if t < 0
        t = 0.0; s = clamp(-c / a, 0.0, 1.0)
    elseif t > 1
        t = 1.0; s = clamp((b - c) / a, 0.0, 1.0)
    end
    return vadd(p1, vmul(s, d1)), vadd(p2, vmul(t, d2))
end
ends(c, u) = (vadd(c, vmul(-CR_L / 2, u)), vadd(c, vmul(CR_L / 2, u)))

"A round tube of radius r along the points `pts` (6 sides): the coil's wound wire."
function tube(pts, r; m = 6)
    vs = Point3f[]; fs = GeometryBasics.TriangleFace{Int}[]
    n = length(pts)
    for i in 1:n
        t = normalize(pts[min(i + 1, n)] - pts[max(i - 1, 1)])
        a = normalize(cross(t, abs(t[3]) < 0.9 ? Vec3f(0, 0, 1) : Vec3f(1, 0, 0))); b = cross(t, a)
        for j in 0:m-1
            push!(vs, pts[i] + r * (cos(2pi * j / m) * a + sin(2pi * j / m) * b))
        end
    end
    for i in 1:n-1, j in 0:m-1
        p = (i - 1) * m; q = i * m; j2 = mod(j + 1, m)
        push!(fs, GeometryBasics.TriangleFace(p + j + 1, q + j + 1, q + j2 + 1), GeometryBasics.TriangleFace(p + j + 1, q + j2 + 1, p + j2 + 1))
    end
    return GeometryBasics.normal_mesh(vs, fs)
end

"The beak point between the two tips, blended across an action switch like the herd blends poses (POSE_BLEND)."
function beakpoint(w, me, act, prev, since, t)
    a0 = me.action
    me.action = act; u, l = NG.beak_tips(w, me); b1 = (u + l) / 2
    me.action = prev; u, l = NG.beak_tips(w, me); b0 = (u + l) / 2
    me.action = a0
    s = clamp((t - since) / Float64(NG.POSE_BLEND), 0.0, 1.0); s = s * s * (3 - 2s)
    return v3(b0 + Float32(s) * (b1 - b0))
end

"""The film's setup and shot. `spot`: where the heap lies (under the beak when Lumi bends). Timeline: hang, bend
(t_bend..t_up), straighten and hold."""
function crane_parts(; spot = (-4.6f0, 18.75f0), N = 1500, I = 3.0, npeg = 9, t_bend = 1.4, t_up = 4.6,
                     cam = (0.1f0, -1.75f0, 0.55f0), dt = 5e-4, seed = 7)
    S = Dict{Symbol,Any}(:t => 0.0)
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :magnetstone_block, :magnetstone_spikes) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot); S[:gz] = Float64(g[3])
        eye = Point3f(spot[1] + cam[1], spot[2] + cam[2], g[3] + cam[3])
        filter!(p -> hypot(p.pos[1] - eye[1], p.pos[2] - eye[2]) > 1.5 && hypot(p.pos[1] - spot[1], p.pos[2] - spot[2]) > 1.2, w.props)
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && c.name != "Lumi" && (c.pos = NG.ground(w.island, (spot[1] + 12f0, spot[2] - 14f0)); c.goal = NG.Goal())
        end
        me = NG.creature(w, "Lumi")
        me.controlled = true; me.yaw = 0f0; me.action = :eat
        me.pos = NG.ground(w.island, (spot[1] - 0.88f0, spot[2]))   # bent, its beak is over the heap
        # the heap: pegs crossing under the beak, in a tight pile (layers by index)
        s = UInt32(seed); rnd() = (s = s * UInt32(1664525) + UInt32(1013904223); s / typemax(UInt32))
        S[:pegs] = map(1:npeg) do k
            r = 0.05 * sqrt(rnd()); ph = 2pi * rnd(); yaw = pi * rnd()
            Peg((spot[1] + r * cos(ph), spot[2] + r * sin(ph), S[:gz] + CR_A), (0.0, 0.0, 0.0), (cos(yaw), sin(yaw), 0.0),
                (0.0, 0.0, 0.0), false, (0.0, 0.0, 0.0), (0.0, 0.0, 1.0))
        end
        # the cord: long enough that, bent, the core's lower end sits 1 cm over the heap's top
        u, l = NG.beak_tips(w, me); b = (u + l) / 2
        S[:cord] = Float64(b[3]) - (S[:gz] + 2.5CR_A + 0.01 + CR_L)
        me.action = :idle                                   # it starts upright: the coil hangs under the upright beak
        u, l = NG.beak_tips(w, me); b = (u + l) / 2
        S[:c] = (Float64(b[1]), Float64(b[2]), Float64(b[3]) - S[:cord] - CR_L / 2); S[:cv] = (0.0, 0.0, 0.0)
        S[:beak] = v3(b)
        # drawing: pegs, the core, the winding, the cord
        a = Float32(CR_A)
        peg = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -CR_L / 2), Point3f(0, 0, CR_L / 2), a))
        iron = NG.Hikari.Diffuse(color = (0.11, 0.11, 0.12), roughness = 0.4f0)
        S[:pegplot] = meshscatter!(gm.stage.scene, fill(Point3f(g), npeg); marker = peg, markersize = 1f0,
                                   rotation = fill(Makie.Quaternionf(0, 0, 0, 1), npeg), color = RGBf(0.11, 0.11, 0.12), material = iron, name = :crane_pegs)
        S[:coreplot] = meshscatter!(gm.stage.scene, [Point3f(g)]; marker = peg, markersize = 1f0, rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                                    color = RGBf(0.11, 0.11, 0.12), material = iron, name = :crane_core)
        # the winding: a copper tube along a helix (fewer, thicker turns drawn than the N the field has)
        nt = 34; per = 16; R = 0.014; rw = 0.0028; len = 0.8CR_L
        pts = [Point3f(R * cos(2pi * k / per), R * sin(2pi * k / per), -len / 2 + len * k / (nt * per)) for k in 0:nt*per]
        S[:coil] = meshscatter!(gm.stage.scene, [Point3f(g)]; marker = tube(pts, Float32(rw)), markersize = 1f0,
                                rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = RGBf(0.85, 0.45, 0.3),
                                material = NG.Hikari.Copper(roughness = 0.18f0), name = :crane_coil)
        # the cord: a unit cylinder stretched from the coil's top to the beak (a meshscatter: mesh! of a Cylinder's
        # normal_mesh has face-view normals the raster cannot take)
        S[:cordplot] = meshscatter!(gm.stage.scene, [Point3f(g)]; marker = GeometryBasics.normal_mesh(Cylinder(Point3f(0), Point3f(0, 0, 1), 0.003f0)),
                                    markersize = [Vec3f(1)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                                    color = RGBf(0.62, 0.52, 0.36), material = NG.Hikari.Diffuse(color = (0.62, 0.52, 0.36), roughness = 0.9f0), name = :crane_cord)
        S[:cc] = nothing
    end
    rot = function (u)                                     # the rotation that turns +z onto u
        d = vunit(u)
        x, y, ww = -d[2], d[1], 1.0 + d[3]
        n = sqrt(x^2 + y^2 + ww^2)
        n < 1e-9 && return Makie.Quaternionf(1, 0, 0, 0)
        return Makie.Quaternionf(Float32(x / n), Float32(y / n), 0f0, Float32(ww / n))
    end
    step! = function (beak)
        c = S[:c]; cv = S[:cv]; gz = S[:gz]; m = CR_M
        # the coil + core on the cord: a damped pendulum from the beak, the cord a stiff link
        cv = vadd(vmul(0.999, cv), (0.0, 0.0, -9.81 * dt))
        # reaction of the held pegs' weight is carried by the cord too: ignored in the swing (pegs ~ the coil's mass)
        c = vadd(c, vmul(dt, cv))
        top = vadd(c, (0.0, 0.0, CR_L / 2)); d = vsub(top, beak); dl = vnorm(d)
        if dl > S[:cord]
            top2 = vadd(beak, vmul(S[:cord] / dl, d)); corr = vsub(top2, top)
            c = vadd(c, corr); cv = vadd(cv, vmul(1 / dt, corr))
        end
        c = (c[1], c[2], max(c[3], gz + CR_L / 2 + 2CR_A))       # the core stops on the heap
        S[:c] = c; S[:cv] = cv
        cu = (0.0, 0.0, 1.0)
        pegs = S[:pegs]
        near = [k for (k, q) in enumerate(pegs) if q.held || vnorm(vsub(q.p, c)) < 0.35]
        # s151: pegs far from the coil still fall (weight torque about the end on the sand); they used to freeze tilted
        Iperp = m * CR_L^2 / 12
        for q in pegs
            (q.held || any(k -> pegs[k] === q, near)) && continue
            fall!(q, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), gz, m, Iperp; dt)
        end
        isempty(near) && return
        cc = CoilCrane.Coil(; N = 60, I = N * I / 60, R = 0.014, len = 0.8CR_L, centre = c, per = 12)   # 60 loops of N/60 turns
        Hext = p -> CoilCrane.Hcoil(cc, p)
        R = CoilCrane.SoftIron.Rods(vcat([c], [pegs[k].p for k in near]), vcat([cu], [pegs[k].u for k in near]); L = CR_L, a = CR_A, K = 8)
        CoilCrane.SoftIron.solve!(R, Hext)
        for (j, k) in enumerate(near)
            q = pegs[k]
            F, T = CoilCrane.SoftIron.force_torque(R, j + 1, Hext)
            if q.held
                # held at the contact while the pull along it beats the weight it has to hold (friction for sideways)
                n = vunit(vsub(c, q.p)); n = (n[1], n[2], n[3])
                pull = vdot(F, n); up = abs(n[3])
                if pull > m * 9.81 * (up + (1 - up) / CR_MU)
                    q.p = vadd(c, q.rel); q.u = q.urel; q.v = cv; q.w = (0.0, 0.0, 0.0)
                    continue
                end
                q.held = false
            end
            fall!(q, F, T, gz, m, Iperp; dt)
            # s151: the winding is solid. Along the wound part (0.8 L) a peg's axis cannot come nearer the core's axis
            # than the winding's outside + the peg's radius; only the core's bare ends let a peg touch the iron. (The
            # s150 film's two held pegs had snapped INSIDE the winding: held, and hidden in the copper.)
            a1, a2 = ends(c, cu); b1, b2 = ends(q.p, q.u)
            x1, x2 = segseg(a1, a2, b1, b2)
            dv = vsub(x2, x1); dd = vnorm(dv)
            onwound = abs(x1[3] - c[3]) < 0.4CR_L
            reach = onwound ? CR_WOUND + CR_A : 2CR_A
            if dd < reach
                n = dd > 1e-9 ? vmul(1 / dd, dv) : (1.0, 0.0, 0.0)
                q.p = vadd(q.p, vmul(reach - dd, n))
                vn = vdot(q.v, n); vn < 0 && (q.v = vsub(q.v, vmul(vn, n)))
                b1, b2 = ends(q.p, q.u); x1, x2 = segseg(a1, a2, b1, b2); dd = vnorm(vsub(x2, x1))
            end
            touch = dd < reach + 0.05CR_A
            if !touch
                for o in pegs
                    (!o.held || o === q) && continue
                    o1, o2 = ends(o.p, o.u); y1, y2 = segseg(o1, o2, b1, b2)
                    vnorm(vsub(y1, y2)) < 2.05CR_A && (touch = true; break)
                end
            end
            if touch
                q.held = true; q.rel = vsub(q.p, c); q.urel = q.u
            end
        end
    end
    shot = function (gm, rig, t)
        w = gm.world
        me = NG.creature(w, "Lumi")
        act = t_bend <= t < t_up ? :eat : :idle
        if act !== get(S, :act, :idle)
            S[:prev] = get(S, :act, :idle); S[:act] = act; S[:since] = t
        end
        me.action = act
        b = beakpoint(w, me, act, get(S, :prev, :idle), get(S, :since, -10.0), t)
        b0 = S[:beak]
        n = max(1, round(Int, (t - S[:t]) / dt))
        for i in 1:n                                       # the beak moves smoothly through the frame's substeps
            step!(vadd(b0, vmul(i / n, vsub(b, b0))))
        end
        S[:t] = t; S[:beak] = b
        c = S[:c]; pegs = S[:pegs]
        Makie.update!(S[:pegplot]; arg1 = [Point3f(q.p...) for q in pegs], rotation = [rot(q.u) for q in pegs])
        Makie.update!(S[:coreplot]; arg1 = [Point3f(c...)])
        Makie.update!(S[:coil]; arg1 = [Point3f(c...)])
        top = Point3f(c[1], c[2], c[3] + CR_L / 2)
        dv = v3(Point3f(b...) - top)
        Makie.update!(S[:cordplot]; arg1 = [top], markersize = [Vec3f(1, 1, vnorm(dv))], rotation = [rot(dv)])
        g = S[:gz]
        rig.mode = :fixed
        # the beach rises inland: the eye stands 0.35 m over the ground UNDER IT (s150's first look had it under the
        # grass, the slope hiding the heap) and looks down at the coil's height
        ex, ey = spot[1] + cam[1], spot[2] + cam[2]
        gze = Float64(NG.ground(w.island, (Float32(ex), Float32(ey)))[3])
        rig.target = Point3f(spot[1] - 0.3f0, spot[2], g + 0.62f0)   # beak to heap in one frame
        rig.eye = Point3f(ex, ey, max(g + cam[3], gze + 0.4))
        return nothing
    end
    setup, shot, S
end

function crane_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 9.0,
                    hour = 16.3, kw...)
    setup, shot, S = crane_parts(; kw...)
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(res, (; path, held = count(q -> q.held, S[:pegs])))
end
