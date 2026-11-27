# Snow on a thing (s140, free time, after W. L. Jacobs' snowed-in watercolor): snow falls straight down onto the
# topmost solid voxel of every column (overhangs shelter what is under them), then slides like sand wherever its
# surface is steeper than `repose`. No cohesion yet: caps stop short of edges instead of bulging over them.
#   include("physics/modes.jl"); include("physics/snow.jl")
#   img, h, lo = Modes.voxelize(coordinates(mesh), faces(mesh), 64)
#   top, d, its = Snow.snowfall(img, 5.0); sm = Snow.snowmesh(top, Snow.smoothsnow(top, d), h, lo)
module Snow
using GeometryBasics

"Fall `D` voxels of snow on `img` (1 = solid) with `pad` cells of ground round it, relax to `repose` degrees.
Returns (top heights in voxels, snow depth in voxels, sweeps; -1 = did not settle)."
function snowfall(img, D; repose = 55.0, pad = 8)
    nx, ny, _ = size(img)
    top = zeros(nx + 2pad, ny + 2pad)
    for i in 1:nx, j in 1:ny
        k = findlast(!iszero, @view img[i, j, :])
        k === nothing || (top[i+pad, j+pad] = k)
    end
    d = fill(Float64(D), size(top))
    t = tand(repose)
    nb = ((1, 0, 1.0), (0, 1, 1.0), (1, 1, sqrt(2)), (1, -1, sqrt(2)))
    for it in 1:20000
        moved = 0.0
        for i in 2:size(top, 1)-1, j in 2:size(top, 2)-1, (a, b, L) in nb
            p, q = (i, j), (i + a, j + b)
            Sp = top[p...] + d[p...]; Sq = top[q...] + d[q...]
            Sp < Sq && ((p, q, Sp, Sq) = (q, p, Sq, Sp))
            ex = Sp - Sq - t * L
            ex > 1e-6 || continue
            m = min(d[p...], ex / 2)
            m > 0 || continue
            d[p...] -= m; d[q...] += m; moved += m
        end
        moved < 1e-4 && return top, d, it
    end
    return top, d, -1
end

"Smooth the snow surface over neighbours within `near` voxels (the same shelf), keeping snow above the stone."
function smoothsnow(top, d; passes = 3, near = 3.0, mind = 0.15)
    S = top .+ d
    for _ in 1:passes
        S2 = copy(S)
        for i in 2:size(S, 1)-1, j in 2:size(S, 2)-1
            d[i, j] > mind || continue
            acc = 0.0; n = 0
            for a in -1:1, b in -1:1
                q = (i + a, j + b)
                (d[q...] > mind && abs(S[q...] - S[i, j]) < near) || continue
                acc += S[q...]; n += 1
            end
            S2[i, j] = max(top[i, j] + mind, acc / n)
        end
        S = S2
    end
    return S .- top
end

"Snow surface triangles in mesh units: a grid square is kept where all four corners carry snow within `jump` voxels
of each other (2 cut real 55-degree slopes into holes, 4.5 keeps them and still drops the walls down to the ground)."
function snowmesh(top, d, h, lo; pad = 8, jump = 4.5, mind = 0.15)
    V = Point3f[]; F = TriangleFace{Int}[]; idx = zeros(Int, size(top))
    for i in axes(top, 1), j in axes(top, 2)
        d[i, j] > mind || continue
        push!(V, Point3f((i - pad - 0.5) * h + lo[1], (j - pad - 0.5) * h + lo[2], (top[i, j] + d[i, j]) * h + lo[3]))
        idx[i, j] = length(V)
    end
    for i in 1:size(top, 1)-1, j in 1:size(top, 2)-1
        c = (idx[i, j], idx[i+1, j], idx[i+1, j+1], idx[i, j+1])
        all(>(0), c) || continue
        zs = [V[k][3] for k in c]
        maximum(zs) - minimum(zs) < jump * h || continue
        push!(F, TriangleFace(c[1], c[2], c[3]), TriangleFace(c[1], c[3], c[4]))
    end
    return GeometryBasics.mesh(V, F; normal = GeometryBasics.normals(V, F))
end

end
