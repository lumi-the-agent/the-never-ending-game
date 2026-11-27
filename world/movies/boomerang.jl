# A boomerang that comes back (s136). The flight is physics/boomerang.jl's blade-element rigid body, stepped before the
# film starts (nothing about its path is drawn by hand): Lumi throws along the north beach, it loops out over the sea
# and comes back. Three shots: the throw beside Lumi, a chase behind the boomerang, Lumi from the sea side for the catch.
#   submit_job(:clip; path, script = "movies/boomerang.jl", call = "boomerang_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics, LinearAlgebra
const NG = NeverendingGame
const BOOM = Module(:BOOM)
Base.include(BOOM, joinpath(@__DIR__, "..", "physics", "boomerang.jl"))

const BM_HIDE = Point3f(0, 0, -50)

"The boomerang's wings as flat slats in its body frame (the same shape the physics flies), around its centre of mass."
function bm_mesh(shape = BOOM.boomerang_shape(); thick = 0.012f0)
    pts = Point3f[]; fs = GLTriangleFace[]
    com = Vec3f(0)   # element positions are already about the centre of mass; rebuild the elbow from the first element
    d1 = Vec3f(shape.s[1]); n = length(shape.p) ÷ 2
    elbow = Vec3f(shape.p[1]) - Float32(shape.ds / 2) * d1
    for (k0, d) in ((1, d1), (n + 1, Vec3f(shape.s[n + 1])))
        c = normalize(cross(Vec3f(0, 0, 1), d)) * Float32(shape.chord / 2)
        L = Float32(shape.arm)
        tipw = 0.75f0
        corners = [elbow - c, elbow + c, elbow + L * d + tipw * c, elbow + L * d - tipw * c]
        base = length(pts)
        for q in corners, z in (-thick / 2, thick / 2)
            push!(pts, Point3f(q + Vec3f(0, 0, z)))
        end
        b(i, top) = base + 2(i - 1) + (top ? 2 : 1)
        push!(fs, GLTriangleFace(b(1, true), b(2, true), b(3, true)), GLTriangleFace(b(1, true), b(3, true), b(4, true)))
        push!(fs, GLTriangleFace(b(1, false), b(3, false), b(2, false)), GLTriangleFace(b(1, false), b(4, false), b(3, false)))
        for i in 1:4
            j = mod1(i + 1, 4)
            push!(fs, GLTriangleFace(b(i, false), b(j, false), b(j, true)), GLTriangleFace(b(i, false), b(j, true), b(i, true)))
        end
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

function bm_quat(R)
    m = R; tr_ = m[1, 1] + m[2, 2] + m[3, 3]
    if tr_ > 0
        s = 2sqrt(tr_ + 1); w = s / 4; x = (m[3, 2] - m[2, 3]) / s; y = (m[1, 3] - m[3, 1]) / s; z = (m[2, 1] - m[1, 2]) / s
    elseif m[1, 1] > m[2, 2] && m[1, 1] > m[3, 3]
        s = 2sqrt(1 + m[1, 1] - m[2, 2] - m[3, 3]); w = (m[3, 2] - m[2, 3]) / s; x = s / 4; y = (m[1, 2] + m[2, 1]) / s; z = (m[1, 3] + m[3, 1]) / s
    elseif m[2, 2] > m[3, 3]
        s = 2sqrt(1 + m[2, 2] - m[1, 1] - m[3, 3]); w = (m[1, 3] - m[3, 1]) / s; x = (m[1, 2] + m[2, 1]) / s; y = s / 4; z = (m[2, 3] + m[3, 2]) / s
    else
        s = 2sqrt(1 + m[3, 3] - m[1, 1] - m[2, 2]); w = (m[2, 1] - m[1, 2]) / s; x = (m[1, 3] + m[3, 1]) / s; y = (m[2, 3] + m[3, 2]) / s; z = s / 4
    end
    Makie.Quaternionf(x, y, z, w)
end

function boomerang_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 6.6,
                        hour = 16.0, spot = (-4f0, 18f0), heading = 0.0, throw_at = 0.6, speed = 22.0, spin = 120.0,
                        layover = 15.0, aim = 2.0, cut1 = 1.3, cut2 = 4.2)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)   # take 2: a beige card stood in Lumi's legs
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world; me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, spot); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        me.yaw = Float32(heading) - NG.species_of(me).heading
        # take 1 (traced): the jelly swallowed a pig on Lumi's spot and a crab and a pig crowded the throw
        for c in w.creatures
            c === me && continue
            if hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 9
                a = atan(c.pos[2] - spot[2], c.pos[1] - spot[1])
                c.pos = NG.ground(w.island, (spot[1] - 10f0 + 2f0 * cos(a), spot[2] - 9f0 + 2f0 * sin(a)))
                c.goal = NG.Goal()
            end
        end
        hand = BOOM.V3(me.pos[1], me.pos[2], me.pos[3] + 1.0)
        track, _ = BOOM.throw_boomerang(; at = hand, heading, speed, spin, layover, aim, seconds = seconds - throw_at,
                                        dt = 1e-3, every = 1 / 240)
        S[:track] = track; S[:hand] = Point3f(hand); S[:caught] = nothing; S[:trail] = Point3f[]; S[:last] = -1.0
        rb = BOOM.boomerang_return(track, hand)        # where it comes back from: the catch is filmed side-on to that
        kb = findfirst(q -> q[1] >= rb.t_back, track); ka = findfirst(q -> q[1] >= rb.t_back - 0.5, track)
        dv = track[kb][2] - track[ka][2]; S[:arrive] = normalize(Vec3f(dv[1], dv[2], 0))
        S[:cam] = nothing
        S[:boom] = meshscatter!(g.stage.scene, [Point3f(hand)]; marker = bm_mesh(), markersize = 1f0,
            rotation = [bm_quat(track[1][3])], color = RGBf(0.55, 0.24, 0.09),
            material = NG.Hikari.Plastic(color = (0.55, 0.24, 0.09), roughness = 0.25), name = :bmfilm_boom)
        S[:trailp] = meshscatter!(g.stage.scene, fill(BM_HIDE, 30); marker = NG.shape(:glowdot), markersize = fill(0f0, 30),
            color = RGBf(1.0, 0.97, 0.9), material = NG.Hikari.Diffuse(color = (1.0, 0.97, 0.9)), name = :bmfilm_trail)
    end
    pose(tf) = (tr = S[:track]; k = clamp(searchsortedfirst(tr, tf; by = q -> q isa Tuple ? q[1] : q), 1, length(tr)); tr[k])
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi"); me.controlled = true
        tf = t - throw_at
        hand = Point3f(me.pos[1], me.pos[2], me.pos[3] + 1.0f0)
        if tf < 0
            bp, R = hand, S[:track][1][3]
        elseif S[:caught] !== nothing
            tc, p0 = S[:caught]; a = Float32(clamp((t - tc) / 0.3, 0, 1))
            side = Point3f(-0.45f0 * S[:arrive][2], 0.45f0 * S[:arrive][1], 0.55f0)   # held up on the camera's side of Lumi (take 2 hid it behind)
            bp, R = (1 - a) * p0 + a * (hand + side), pose(tc - throw_at)[3]
        else
            q = pose(tf); bp, R = Point3f(q[2]), q[3]
            if tf > 3.0 && hypot(bp[1] - hand[1], bp[2] - hand[2]) < 1.1
                S[:caught] = (t, bp)
            end
        end
        me.action = (0 <= tf < 0.4) || (S[:caught] !== nothing && t - S[:caught][1] < 0.6) ? :wave : :idle
        Makie.update!(S[:boom]; arg1 = [bp], rotation = [bm_quat(R)])
        if tf >= 0 && S[:caught] === nothing && t - S[:last] > 1 / 40
            push!(S[:trail], bp); S[:last] = t
            length(S[:trail]) > 30 && popfirst!(S[:trail])
        end
        tp = fill(BM_HIDE, 30); ts = fill(0f0, 30)
        for (k, p) in enumerate(S[:trail])
            tp[k] = p; ts[k] = 0.012f0 * k / length(S[:trail])
        end
        Makie.update!(S[:trailp]; arg1 = tp, markersize = ts)
        x, y, z = me.pos
        f = Vec3f(cos(heading), sin(heading), 0); l = Vec3f(-sin(heading), cos(heading), 0)
        rig.mode = :fixed
        if t < cut1          # in front of Lumi, a little to the side: the throw comes towards the camera
            rig.eye = Point3f(x, y, z) + 2.4f0 * f - 1.4f0 * l + Point3f(0, 0, 1.0f0)
            rig.target = Point3f(x, y, z) + 0.6f0 * l + Point3f(0, 0, 0.9f0)
        elseif t < cut2      # boomerang cam: 2.2 m behind it, along its path over the last 0.15 s (no lag)
            q0 = pose(max(tf - 0.15, 0.0)); v = Vec3f(bp) - Vec3f(q0[2])
            vh = normalize(Vec3f(v[1], v[2], 0) + Vec3f(1f-6, 0, 0))
            rig.eye = bp - 2.2f0 * vh + Point3f(0, 0, 0.55f0)
            rig.target = bp + 1.5f0 * vh
        else                 # side-on to where it comes back from: it crosses the frame into Lumi's wing
            a = S[:arrive]; side = Vec3f(-a[2], a[1], 0)
            rig.eye = Point3f(x, y, z) + 3.4f0 * side - 0.8f0 * a + Point3f(0, 0, 1.3f0)
            rig.target = Point3f(x, y, z) - 0.6f0 * a + Point3f(0, 0, 1.1f0)
        end
        return nothing
    end
    return NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                        rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
end
