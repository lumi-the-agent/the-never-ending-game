# Climb anything (s134, projects/climb-anything.md): grabbable edges read off the island's real meshes.
# Nothing is placed by hand. A column of horizontal probe rays in front of Lumi climbs up a wall; where the wall
# stops (the next probe up finds no wall within reach, or finds it much deeper) a ray cast down just behind the
# wall's face looks for a top. A steep face (normal within 20 degrees of horizontal) under a flat top (normal within
# 30 degrees of up) is a lip a claw can hold. One GPU thread per column (Raycore BVH, KernelAbstractions: CPU or
# Mantle.Device()); the TLAS comes from physics/echo.jl `echo_tlas(solid_triangles(scene), backend)`.
using Raycore, GeometryBasics, LinearAlgebra, StaticArrays, Makie
const CLIMB_KA = Raycore.KernelAbstractions
const CLIMB_Adapt = Raycore.Adapt

const CLIMB_WALL_NZ = 0.342f0    # |n_z| below this: a face steeper than 70 degrees
const CLIMB_TOP_NZ = 0.866f0     # n_z above this: a top flatter than 30 degrees

# out[1:3, m, c] = lip point (on the top, at the wall's face), out[4:6, m, c] = wall normal (outwards),
# out[7, m, c] = top n_z, out[8, m, c] = 1 when column c found its m-th lip (lowest first), else 0.
# s135: a column keeps scanning past a lip (up to size(out, 2) of them); until then the floor lip at 0.28 m of the
# beach hut hid every lip above it (the shelf at 1.2 m was never scanned).
CLIMB_KA.@kernel function climb_edges_kernel!(out, tlas, base, fwd, side, offs, h0, dh, nh, reach)
    c = CLIMB_KA.@index(Global)
    @inbounds begin
        maxlips = size(out, 2)
        for m in 1:maxlips, k in 1:8
            out[k, m, c] = 0f0
        end
        nl = 0
        o0 = base + offs[c] * side
        prev_hit = false; prev_t = 0f0; prev_n = Vec3f(0, 0, 0); prev_x = Point3f(0, 0, 0)
        for j in 0:(nh - 1)
            h = h0 + j * dh
            o = o0 + Vec3f(0, 0, h)
            hit, tri, t, _, _ = Raycore.closest_hit(tlas, Raycore.Ray(; o = o, d = fwd))
            wall = false; n = Vec3f(0, 0, 0)
            if hit && t < reach
                v = tri.vertices
                n = normalize(cross(v[2] - v[1], v[3] - v[1]))
                dot(n, fwd) > 0 && (n = -n)
                wall = abs(n[3]) < CLIMB_WALL_NZ
            end
            # the wall below ended here: nothing within reach, or a step back of more than 0.25 m
            if prev_hit && (!wall || t > prev_t + 0.25f0)
                # look down just behind the wall's face for the top
                p = prev_x - 0.06f0 * prev_n + Vec3f(0, 0, dh + 0.35f0)
                dn = Vec3f(0, 0, -1)
                hit2, tri2, t2, _, _ = Raycore.closest_hit(tlas, Raycore.Ray(; o = p, d = dn))
                if hit2 && t2 < dh + 0.45f0
                    v2 = tri2.vertices
                    n2 = normalize(cross(v2[2] - v2[1], v2[3] - v2[1]))
                    n2[3] < 0 && (n2 = -n2)
                    if n2[3] > CLIMB_TOP_NZ
                        x = p + t2 * dn
                        nl += 1
                        out[1, nl, c] = x[1]; out[2, nl, c] = x[2]; out[3, nl, c] = x[3]
                        out[4, nl, c] = prev_n[1]; out[5, nl, c] = prev_n[2]; out[6, nl, c] = prev_n[3]
                        out[7, nl, c] = n2[3]; out[8, nl, c] = 1f0
                        nl == maxlips && break
                    end
                end
            end
            prev_hit = wall; prev_t = t; prev_n = n; prev_x = o + t * fwd
        end
    end
end

"""
    climb_edges(tlas, backend, feet, facing; width = 1.2, columns = 25, h0 = 0.15, top = 3.0, dh = 0.05, reach = 1.0, maxlips = 4)

The lips Lumi could grab in front of it: a fan of `columns` probe columns over `width` metres across `facing`
(a horizontal direction), each scanning heights `h0:dh:top` above `feet` for a wall within `reach` that ends in a
flat top, keeping up to `maxlips` lips per column. Returns a vector of `(point, wall_normal, top_nz, column_offset)`,
column by column, lowest first within a column.
"""
function climb_edges(tlas, backend, feet, facing; width = 1.2, columns = 25, h0 = 0.15, top = 3.0, dh = 0.05, reach = 1.0,
                     maxlips = 4)
    f = normalize(Vec3f(facing[1], facing[2], 0))
    s = Vec3f(-f[2], f[1], 0)
    offs = collect(Float32, range(-width / 2, width / 2; length = columns))
    st = CLIMB_Adapt.adapt(backend, tlas)
    doffs = CLIMB_KA.allocate(backend, Float32, columns); copyto!(doffs, offs)
    out = CLIMB_KA.zeros(backend, Float32, 8, maxlips, columns)
    nh = floor(Int, (top - h0) / dh) + 1
    climb_edges_kernel!(backend)(out, st, Point3f(feet), f, s, doffs, Float32(h0), Float32(dh), nh, Float32(reach);
                                 ndrange = columns)
    CLIMB_KA.synchronize(backend)
    O = Array(out)
    [(Point3f(O[1, m, c], O[2, m, c], O[3, m, c]), Vec3f(O[4, m, c], O[5, m, c], O[6, m, c]), O[7, m, c], offs[c])
     for c in 1:columns for m in 1:maxlips if O[8, m, c] > 0.5f0]
end
