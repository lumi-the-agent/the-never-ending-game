# How a flame looks (s153, project fire). s152's flames were straight cylinders of one emission at strength 6: in the
# traced film they read as pale yellow planks (media/s153/campfire-in-the-wind-overview.jpg). Here each merged flame
# is a bunch of tongues: curved tubes, wide near the fuel and tapering to a point, bending into the lean as they rise,
# wobbling sideways. Each tongue is cut into three bands drawn as three meshes with their own colour and strength:
# a yellow-white root, an orange body and dark red tips (the soot cooling as it rises), weaker emission so the colour
# survives the tone mapping. Used by movies/fire.jl and plugins/campfire.jl.
using GeometryBasics, LinearAlgebra

"Colour and emission strength of the root, the body and the tips (the s-ranges they cover in FLAME_CUTS)."
const FLAME_BANDS = (((1.0, 0.80, 0.38), 2.2), ((1.0, 0.42, 0.07), 2.2), ((0.85, 0.16, 0.03), 1.3))
const FLAME_CUTS = (0f0, 0.38f0, 0.7f0, 1f0)

"Append one band (s from s0 to s1) of a tongue to the point, normal and face lists."
function tongue_band!(P, N, F, path, radius, s0, s1; rings = 5, sides = 10)
    k0 = length(P)
    for k in 0:rings
        s = s0 + (s1 - s0) * k / rings
        p = path(s)
        tng = normalize(path(min(s + 0.02f0, 1f0)) - path(max(s - 0.02f0, 0f0)))
        ref = abs(tng[1]) < 0.9f0 ? Vec3f(1, 0, 0) : Vec3f(0, 1, 0)
        u = normalize(cross(tng, ref)); v = cross(tng, u)
        r = radius(s)
        for i in 0:sides-1
            th = 2f0 * Float32(pi) * i / sides
            n = cos(th) * u + sin(th) * v
            push!(P, p + r * n); push!(N, n)
        end
    end
    idx(k, i) = k0 + k * sides + mod(i, sides) + 1
    for k in 0:rings-1, i in 0:sides-1     # (a, b, c) and (a, c, d): counter-clockwise from outside, normals outward
        a, b, c, d = idx(k, i), idx(k, i + 1), idx(k + 1, i + 1), idx(k + 1, i)
        push!(F, TriangleFace(a, b, c), TriangleFace(a, c, d))
    end
    return
end

"""
    flame_tongues(flames, t, o, byid) -> (root, body, tips)

The three band meshes of every merged flame `(c, L, Q, ids)` (centre `c` from the origin `o`, height `L`), its
tongues rooted on the fuel bodies `byid[id]` (with `pos` and `size`). `t` (seconds) drives the flicker.
"""
function flame_tongues(flames, t, o, byid)
    bands = [(Point3f[], Vec3f[], TriangleFace{Int}[]) for _ in 1:3]
    for (c, L, Q, ids) in flames
        L < 0.03f0 && continue
        g = [byid[i] for i in ids]
        bx = sum(b -> b.pos[1], g) / length(g); by = sum(b -> b.pos[2], g) / length(g)
        bz = minimum(b -> b.pos[3] + 0.5f0 * b.size[3], g)       # the lowest fuel top: the pile, not a stake top
        base = Point3f(o[1] + bx, o[2] + by, o[3] + bz)
        # along base -> centre, as long as the model's flame (L): 2x base->centre drew a 2 m streak once a 1 m stake
        # burned in the pile's flame (s153 test, media/s153/fire-look-test-overview.jpg)
        F = L * normalize(Vec3f(o[1] + c[1], o[2] + c[2], o[3] + c[3]) - base)
        up = Vec3f(0, 0, F[3]); lean = Vec3f(F[1], F[2], 0)
        side = norm(lean) > 1f-3 ? normalize(cross(Vec3f(0, 0, 1), lean)) : Vec3f(1, 0, 0)
        sp = clamp(0.5f0 * maximum(b -> max(b.size[1], b.size[2]), g), 0.05f0, 0.4f0)
        R = clamp(0.13f0 * L, 0.035f0, 0.15f0)
        for j in 1:7                       # one tall middle tongue, six round it over the fuel
            a = 2f0 * Float32(pi) * j / 7 + 0.4f0 * sin(0.7f0 * t + j)
            off = j == 1 ? Vec3f(0) : Vec3f(0.55f0 * sp * cos(a), 0.55f0 * sp * sin(a), 0)
            h = (j == 1 ? 1f0 : 0.55f0 + 0.08f0 * j) * (1f0 + 0.18f0 * sin(9f0 * t + 2.1f0 * j) + 0.08f0 * sin(23f0 * t + 1.3f0 * j))
            Rj = (j == 1 ? 1f0 : 0.62f0) * R
            ph = 1.7f0 * j
            b0 = base + off - Vec3f(0, 0, 0.03f0)
            path = s -> b0 + h * (s * up + s^1.6f0 * lean) + (0.9f0 * Rj * s * sin(5f0 * s + 8f0 * t + ph)) * side
            radius = s -> Rj * (0.55f0 + 0.45f0 * sin(min(s / 0.3f0, 1f0) * Float32(pi) / 2)) * (1f0 - s)^0.85f0
            for k in 1:3
                tongue_band!(bands[k]..., path, radius, FLAME_CUTS[k], FLAME_CUTS[k+1])
            end
        end
    end
    return map(bands) do (P, N, Fs)
        if isempty(P)         # a speck under the ground where no flame burns (an empty mesh can't be plotted)
            z = Float32(o[3]) - 3f0
            append!(P, (Point3f(o[1], o[2], z), Point3f(o[1] + 0.01f0, o[2], z), Point3f(o[1], o[2] + 0.01f0, z)))
            append!(N, (Vec3f(0, 0, 1), Vec3f(0, 0, 1), Vec3f(0, 0, 1))); push!(Fs, TriangleFace(1, 2, 3))
        end
        GeometryBasics.Mesh(P, Fs; normal = N)
    end
end
