# s182 (project plante): Plante's jar beside the drum's pots, the chemistry of physics/plante.jl replayed. The plates
# were formed for three hours (one reversal each way); the film shows 100 minutes at 13 chemistry minutes a second:
# plate A is the positive and fizzes oxygen because its layer is full; at 2.5 s the leads swap (the cords cross).
# Then A goes quiet while its brown oxide is reduced back to grey spongy lead, and B starts browning with hardly a bubble,
# until A runs out of oxide and fizzes hydrogen. Bubble rates are the solved gas rates (1.5 mm bubbles, rising at their
# terminal 0.18 m/s in real time); the brown patches are the solved PbO2 on each plate.
#   submit_job(:clip; path = ..., script = "movies/plante.jl", call = "plante_film")
using NeverendingGame, Makie, GeometryBasics, LinearAlgebra, Random
const NG = NeverendingGame
include(joinpath(@__DIR__, "..", "physics", "plante.jl"))
include(joinpath(@__DIR__, "..", "physics", "motorlook.jl"))

const PF_JAR = (r = 0.075f0, h = 0.21f0, acid = 0.175f0, wall = 0.004f0)
const PF_PLATE = (w = 0.08f0, h = 0.15f0, t = 0.002f0, gap = 0.032f0, z0 = 0.015f0)
const PF_AREA = 2 * 0.08 * 0.15
const PF_NX, PF_NZ = 8, 12
const PF_BUB = 0.75e-3

function pf_lathe(prof, c; n = 48)
    pts = Point3f[]; fcs = GLTriangleFace[]; m = length(prof)
    for j in 0:n-1, (r, z) in prof
        a = 2pi * j / n
        push!(pts, c + Point3f(r * cos(a), r * sin(a), z))
    end
    for j in 0:n-1, i in 1:m-1
        a = j * m + i; b = mod(j + 1, n) * m + i
        push!(fcs, GLTriangleFace(a, b, b + 1), GLTriangleFace(a, b + 1, a + 1))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fcs))
end

"Oxide reaches the edges first (the current crowds there), then the face, unevenly."
function pf_thresholds(seed)
    rng = MersenneTwister(seed)
    e(i, n) = 1 - 2min(i - 0.5, n + 0.5 - i) / n
    [0.55 * rand(rng) + 0.225 * e(i, PF_NX) + 0.225 * e(k, PF_NZ) for i in 1:PF_NX, k in 1:PF_NZ]
end

function pf_patches(c, thr, share)
    pts = Point3f[]; fcs = GLTriangleFace[]
    W, H, T = PF_PLATE.w, PF_PLATE.h, PF_PLATE.t / 2 + 0.0003f0
    for i in 1:PF_NX, k in 1:PF_NZ
        thr[i, k] < share || continue
        x0 = -W / 2 + W * (i - 1) / PF_NX; x1 = x0 + W / PF_NX
        z0 = H * (k - 1) / PF_NZ; z1 = z0 + H / PF_NZ
        for s in (-1, 1)
            o = length(pts)
            append!(pts, [c + Point3f(x0, s * T, z0), c + Point3f(x1, s * T, z0), c + Point3f(x1, s * T, z1), c + Point3f(x0, s * T, z1)])
            push!(fcs, GLTriangleFace(o + 1, o + 2, o + 3), GLTriangleFace(o + 1, o + 3, o + 4))
        end
    end
    # nothing grown: a 1 mm triangle hidden inside the sheet (the path tracer refuses a mesh without area)
    isempty(pts) && (pts = [c + Point3f(0, 0, 0.05f0), c + Point3f(0.001f0, 0, 0.05f0), c + Point3f(0, 0, 0.051f0)]; fcs = [GLTriangleFace(1, 2, 3)])
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fcs))
end

pf_shares(d, x) = (1 - exp(-d * x / 0.6e-6), 1 - exp(-d * (1 - x) / 0.6e-6))

function plante_film(path; hour = 15.5, seconds = 7.5, samples = 16, rasterize = false, size = (960, 540), rate = 800.0,
                     spot = (4.62f0, -15.06f0), swap_at = 2.5, eye = (0.25, -0.25, 0.25), target = (0.0, 0.0, 0.10), fade = 0.3, t0 = 0.0)
    # the chemistry: 3 h of forming (A positive at the end), then the film's 90 min with the swap at swap_at
    pre = Plante.form(schedule = [(1.0, 1), (1.0, -1), (1.0, 1)], area = PF_AREA, dt = 10.0)
    A, B = pre.A, pre.B
    film = Plante.form(schedule = [(swap_at * rate / 3600, 1), ((seconds - swap_at) * rate / 3600, -1)], area = PF_AREA,
                       dt = 10.0, plates = (A, B))
    S = (t = film.t, pol = film.pol, O2 = film.O2, H2 = film.H2, dA = film.dA, xA = film.xA, dB = film.dB, xB = film.xB)
    at(t) = clamp(1 + floor(Int, t * rate / 10.0), 1, length(S.t))
    made = Ref(false); P = Ref(Point3f(0)); obs = Dict{Symbol, Any}(); keys_ = Dict{Symbol, Any}()
    bubbles = Tuple{Point3f, Float64}[]; last_t = Ref(-1.0); rng = MersenneTwister(7)
    thr = Dict(:A => pf_thresholds(18), :B => pf_thresholds(59))
    rig = NG.CameraRig(); rig.mode = :fixed
    cords(P, pots, swapped) = begin
        lug(s) = P + Point3f(0, s * PF_PLATE.gap, PF_JAR.h + 0.03f0)
        a, b = swapped ? (pots[2], pots[1]) : (pots[1], pots[2])
        sag(p, q; d = 0.06f0) = [p + t * (q - p) - Point3f(0, 0, d * 4t * (1 - t)) for t in range(0, 1; length = 18)]
        (mtube(sag(lug(-1), a), 0.0018f0; nring = 8), mtube(sag(lug(1), b), 0.0018f0; nring = 8))
    end
    shot = function (g, rig, t)
        sc = g.stage.scene
        if !made[]
            isl = g.world.island
            q = NG.ground(isl, spot); P[] = Point3f(q[1], q[2], q[3] - 0.01f0)
            top(x, y) = (h = NG.ground(isl, (x, y)); Point3f(h[1], h[2], h[3] + 0.25f0))
            obs[:pots] = (top(4.35f0, -14.70f0), top(4.35f0 + 5 * 0.28f0, -14.70f0))
            J = PF_JAR
            jar = [(0.0, 0.0), (J.r, 0.0), (J.r + 0.003, 0.01), (J.r + 0.003, J.h), (J.r - J.wall, J.h), (J.r - J.wall, J.wall), (0.0, J.wall)]
            mesh!(sc, pf_lathe(jar, P[]); color = RGBAf(0.85, 0.93, 0.9, 0.25), name = :plantefilm_jar,
                  material = NG.Hikari.ThinDielectric(ior = 1.5f0))     # thin jar glass: no lens across the jar
            mesh!(sc, pf_lathe([(J.r - J.wall - 0.0005, 0.0), (0.0, 0.0)], P[] + Point3f(0, 0, J.acid)); color = RGBAf(0.9, 0.95, 0.95, 0.3),
                  name = :plantefilm_acid, material = NG.Hikari.ThinDielectric(ior = 1.37f0))
            lead = NG.Hikari.Principled(base_color = (0.56, 0.57, 0.60), metallic = 0.85, roughness = 0.42)
            for (s, L) in ((-1, :A), (1, :B))
                c = P[] + Point3f(0, s * PF_PLATE.gap, PF_PLATE.z0); obs[Symbol("c", L)] = c
                sheet = Rect3f(c + Point3f(-PF_PLATE.w / 2, -PF_PLATE.t / 2, 0), Vec3f(PF_PLATE.w, PF_PLATE.t, PF_PLATE.h))
                lug = Rect3f(c + Point3f(-0.006, -PF_PLATE.t / 2, PF_PLATE.h), Vec3f(0.012, PF_PLATE.t, PF_JAR.h + 0.035f0 - PF_PLATE.h - PF_PLATE.z0))
                mesh!(sc, GeometryBasics.normal_mesh(sheet); color = RGBf(0.56, 0.57, 0.6), material = lead, name = Symbol("plantefilm_lead", L))
                mesh!(sc, GeometryBasics.normal_mesh(lug); color = RGBf(0.56, 0.57, 0.6), material = lead, name = Symbol("plantefilm_lug", L))
                obs[Symbol("ox", L)] = Observable(pf_patches(c, thr[L], 0.0))
                obs[Symbol("sp", L)] = Observable(pf_patches(c, thr[L], 0.0))
                mesh!(sc, obs[Symbol("sp", L)]; color = RGBf(0.3, 0.31, 0.33), name = Symbol("plantefilm_sp", L),
                      material = NG.Hikari.Principled(base_color = (0.30, 0.31, 0.33), metallic = 0.2, roughness = 0.95))
                mesh!(sc, obs[Symbol("ox", L)]; color = RGBf(0.2, 0.1, 0.055), name = Symbol("plantefilm_ox", L),
                      material = NG.Hikari.Principled(base_color = (0.14, 0.075, 0.04), roughness = 0.6))
            end
            obs[:bub] = Observable([P[] + Point3f(0, 0, 0.05f0)])
            meshscatter!(sc, obs[:bub]; markersize = Float32(PF_BUB), color = RGBAf(0.95, 0.98, 1.0, 0.6), name = :plantefilm_bubbles,
                         material = NG.Hikari.Principled(base_color = (0.92, 0.95, 1.0), metallic = 1.0, roughness = 0.08))   # a gas bubble in acid reflects all round (total internal reflection): silver
            c1, c2 = cords(P[], obs[:pots], false)
            obs[:cord1] = Observable(c1); obs[:cord2] = Observable(c2); obs[:swapped] = false
            cu = NG.Hikari.Copper(roughness = 0.25f0)
            mesh!(sc, obs[:cord1]; color = RGBf(0.78, 0.42, 0.22), material = cu, name = :plantefilm_cord1)
            mesh!(sc, obs[:cord2]; color = RGBf(0.78, 0.42, 0.22), material = cu, name = :plantefilm_cord2)
            made[] = true
        end
        t = t + t0
        i = at(max(t, 0.0))
        for (L, d, x) in ((:A, S.dA[i], S.xA[i]), (:B, S.dB[i], S.xB[i]))
            o, s = pf_shares(d, x)
            key = (round(Int, 96o), round(Int, 96s))
            get(keys_, L, nothing) == key && continue
            keys_[L] = key
            obs[Symbol("ox", L)][] = pf_patches(obs[Symbol("c", L)], thr[L], o)
            obs[Symbol("sp", L)][] = pf_patches(obs[Symbol("c", L)], 1 .- thr[L], s * (1 - o))
        end
        sw = S.pol[i] < 0
        if sw != obs[:swapped]
            c1, c2 = cords(P[], obs[:pots], sw); obs[:cord1][] = c1; obs[:cord2][] = c2; obs[:swapped] = sw
        end
        # bubbles at the solved rates; they rise in real time (the chemistry clock only sets how many are born)
        dt = last_t[] < 0 ? 1 / 24 : clamp(t - last_t[], 0.0, 0.2); last_t[] = t
        vb = 4 / 3 * pi * PF_BUB^3
        pos_c, neg_c = S.pol[i] > 0 ? (obs[:cA], obs[:cB]) : (obs[:cB], obs[:cA])
        if isempty(bubbles)          # the first frame: a jar already fizzing, not one that starts
            for _ in 1:round(Int, (S.O2[i] + S.H2[i]) * 0.0245 / vb * 0.9)
                c = rand(rng) < S.O2[i] / (S.O2[i] + S.H2[i]) ? pos_c : neg_c
                push!(bubbles, (c + Point3f((rand(rng) - 0.5f0) * PF_PLATE.w, rand(rng, (-1, 1)) * (PF_PLATE.t / 2 + Float32(PF_BUB)), rand(rng) * (PF_JAR.acid - PF_PLATE.z0 - 0.002f0)), 2pi * rand(rng)))
            end
        end
        for (c, n) in ((pos_c, S.O2[i]), (neg_c, S.H2[i]))
            m = n * 0.0245 / vb * dt
            for _ in 1:(floor(Int, m) + (rand(rng) < m - floor(m) ? 1 : 0))
                push!(bubbles, (c + Point3f((rand(rng) - 0.5f0) * PF_PLATE.w, rand(rng, (-1, 1)) * (PF_PLATE.t / 2 + Float32(PF_BUB)), rand(rng) * PF_PLATE.h), 2pi * rand(rng)))
            end
        end
        topz = P[][3] + PF_JAR.acid - Float32(PF_BUB)
        for k in eachindex(bubbles)
            p, ph = bubbles[k]
            bubbles[k] = (p + Point3f(0.004f0 * cos(ph + 40p[3]) * dt, 0.004f0 * sin(ph + 30p[3]) * dt, 0.18f0 * dt), ph)
        end
        filter!(b -> b[1][3] < topz, bubbles)
        obs[:bub][] = isempty(bubbles) ? [P[] + Point3f(0, 0, 0.05f0)] : first.(bubbles)
        rig.eye = P[] + Point3f(eye...); rig.target = P[] + Point3f(target...)
        nothing
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, fade)
end
