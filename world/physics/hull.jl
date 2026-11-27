# Hydrostatics from a hull's own mesh (s145, project log-boat). The submerged part of a closed, outward-facing
# triangle mesh below a flat water plane z = h: its volume and centre of buoyancy, by the divergence theorem.
# Trick: sum signed tetrahedra (o, a, b, c) over the clipped underwater triangle pieces with the apex o ON the water
# plane: the waterplane cap that closes the submerged solid is coplanar with o, so its tetrahedra have zero volume
# and need not be built. Exact for any closed mesh (no voxels, no sampling).
# Looked for an existing one (RomeoDB: buoyancy / hydrostatics / submerged volume): nothing for an arbitrary mesh in a
# game loop; Meshes.jl clips with planes but allocates new meshes per call. This is ~40 lines.
using LinearAlgebra, StaticArrays

const V3 = SVector{3,Float64}

tet6(o, a, b, c) = dot(a - o, cross(b - o, c - o))           # 6 x signed tetra volume

"Clip triangle (a, b, c) to z <= h and add its tetras about `o` into (6V, 24 V*centroid)."
@inline function clip_add(a::V3, b::V3, c::V3, h, o::V3, acc)
    da, db, dc = a[3] - h, b[3] - h, c[3] - h
    cut(p, q, dp, dq) = p + (dp / (dp - dq)) * (q - p)
    add(acc, p, q, r) = (t = tet6(o, p, q, r); (acc[1] + t, acc[2] + t * (o + p + q + r)))
    na = (da <= 0) + (db <= 0) + (dc <= 0)
    na == 0 && return acc
    na == 3 && return add(acc, a, b, c)
    # rotate (keeping the winding) so the lone vertex (the only one below for na == 1, the only one above for na == 2) is `a`
    lone = na == 1 ? (da <= 0, db <= 0, dc <= 0) : (da > 0, db > 0, dc > 0)
    if lone[2]
        a, b, c, da, db, dc = b, c, a, db, dc, da
    elseif lone[3]
        a, b, c, da, db, dc = c, a, b, dc, da, db
    end
    pab = cut(a, b, da, db); pac = cut(a, c, da, dc)
    na == 1 && return add(acc, a, pab, pac)                 # the tip below
    return add(add(acc, pab, b, c), pab, c, pac)            # a above: the quad pab, b, c, pac is below
end

"""
    submerged(verts, faces, h) -> (V, cb)

Volume below the plane z = h of the closed mesh (`verts` points, `faces` index triples, outward winding) and the
centre of that volume (the centre of buoyancy). Buoyancy = rho_water * g * V acting up through `cb`.
"""
function submerged(verts, faces, h)
    o = V3(0.0, 0.0, h)
    acc = (0.0, V3(0.0, 0.0, 0.0))
    for f in faces
        a = V3(verts[f[1]]...); b = V3(verts[f[2]]...); c = V3(verts[f[3]]...)
        acc = clip_add(a, b, c, h, o, acc)
    end
    v6, m = acc
    V = v6 / 6
    return V, (V == 0 ? o : m / (4 * v6))
end

"Vertical force and the torque about `cg` on a floating body: buoyancy up through cb, weight down through cg."
function hydro_wrench(verts, faces, h, mass, cg; rho = 1000.0, g = 9.81)
    V, cb = submerged(verts, faces, h)
    Fb = V3(0, 0, rho * g * V)
    return Fb + V3(0, 0, -mass * g), cross(cb - V3(cg...), Fb)
end
