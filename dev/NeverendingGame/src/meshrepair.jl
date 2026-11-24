# ── Hollow generated meshes, filled ─────────────────────────────────────────
#
# Trellis2 makes things as thin hollow shells, and tree crowns come out with
# tears in them. Through a tear the path tracer looks into the unlit
# hollow and draws a black hole; the raster shows a dark blotch. `solidified`
# fills such a mesh: a closing of its volume in a grid seals the tears, the
# surface is made anew by marching cubes, and every new triangle reads the
# texture from the nearest old one. The worker's `:asset` jobs fill what they
# make with a `HOLLOW_TAGS` tag; `repair_catalog!` filled the assets made before.

"""
    closest_bary(p, a, b, c) -> (point, barycentrics)

The point of triangle `abc` closest to `p` (Ericson, Real-Time Collision Detection 5.1.5).
"""
function closest_bary(p::Vec3f, a::Vec3f, b::Vec3f, c::Vec3f)
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = ab ⋅ ap, ac ⋅ ap
    (d1 <= 0 && d2 <= 0) && return a, Vec3f(1, 0, 0)
    bp = p - b
    d3, d4 = ab ⋅ bp, ac ⋅ bp
    (d3 >= 0 && d4 <= d3) && return b, Vec3f(0, 1, 0)
    vc = d1 * d4 - d3 * d2
    if vc <= 0 && d1 >= 0 && d3 <= 0
        v = d1 / (d1 - d3)
        return a + v * ab, Vec3f(1 - v, v, 0)
    end
    cp = p - c
    d5, d6 = ab ⋅ cp, ac ⋅ cp
    (d6 >= 0 && d5 <= d6) && return c, Vec3f(0, 0, 1)
    vb = d5 * d2 - d1 * d6
    if vb <= 0 && d2 >= 0 && d6 <= 0
        w = d2 / (d2 - d6)
        return a + w * ac, Vec3f(1 - w, 0, w)
    end
    va = d3 * d6 - d5 * d4
    if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return b + w * (c - b), Vec3f(0, 1 - w, w)
    end
    den = 1 / (va + vb + vc)
    v, w = vb * den, vc * den
    return a + ab * v + ac * w, Vec3f(1 - v - w, v, w)
end

"""
A mesh's triangles bucketed into cubic cells of side `h`, for nearest-triangle queries, with
each triangle's outward normal (from its vertex normals) and texture island (`chart`).
"""
struct TriangleGrid
    ps::Vector{Vec3f}
    fs::Vector{NTuple{3,Int}}
    normals::Vector{Vec3f}
    chart::Vector{Int}
    lo::Vec3f
    h::Float32
    cells::Dict{NTuple{3,Int},Vector{Int}}
end

cell_of(g::TriangleGrid, p) = Tuple(floor.(Int, (p .- g.lo) ./ g.h))

"""
The texture islands of a mesh: triangles sharing a vertex index are on one island (a uv seam
splits the vertices). The island of each triangle.
"""
function charts(fs::Vector{NTuple{3,Int}}, nv::Int)
    parent = collect(1:nv)
    root(x) = (while parent[x] != x; parent[x] = parent[parent[x]]; x = parent[x]; end; x)
    for (a, b, c) in fs
        parent[root(b)] = root(a); parent[root(c)] = root(a)
    end
    return [root(f[1]) for f in fs]
end

function TriangleGrid(mesh::GeometryBasics.Mesh, h::Real)
    ps = Vec3f.(GeometryBasics.coordinates(mesh))
    ns = GeometryBasics.normals(mesh)
    fs = [(convert(Int, f[1]), convert(Int, f[2]), convert(Int, f[3])) for f in GeometryBasics.faces(mesh)]
    lo = reduce((a, b) -> min.(a, b), ps) .- Float32(h)
    g = TriangleGrid(ps, fs, [Vec3f(ns[a] + ns[b] + ns[c]) for (a, b, c) in fs], charts(fs, length(ps)),
                     lo, Float32(h), Dict{NTuple{3,Int},Vector{Int}}())
    for (k, f) in enumerate(fs)
        a, b, c = ps[f[1]], ps[f[2]], ps[f[3]]
        l, u = cell_of(g, min.(a, b, c)), cell_of(g, max.(a, b, c))
        for z in l[3]:u[3], y in l[2]:u[2], x in l[1]:u[1]
            push!(get!(() -> Int[], g.cells, (x, y, z)), k)
        end
    end
    return g
end

"""
The triangle nearest to `p` among those facing the way `facing` does, searched ring by ring
out to `rings` cells; 0 if none is that near. The facing test keeps a shell's inner wall and
the dark undersides of overlapping parts (roof tiles) from lending their texture.
"""
function nearest_triangle(g::TriangleGrid, p::Vec3f, facing::Vec3f; rings = 8)
    c = cell_of(g, p)
    best, bestd = 0, Inf32
    for r in 0:rings
        for z in (c[3] - r):(c[3] + r), y in (c[2] - r):(c[2] + r), x in (c[1] - r):(c[1] + r)
            max(abs(x - c[1]), abs(y - c[2]), abs(z - c[3])) == r || continue
            for k in get(g.cells, (x, y, z), Int[])
                g.normals[k] ⋅ facing > 0 || continue
                f = g.fs[k]
                q, _ = closest_bary(p, g.ps[f[1]], g.ps[f[2]], g.ps[f[3]])
                d = norm(q - p)
                d < bestd && ((best, bestd) = (k, d))
            end
        end
        # a triangle within r cells is nearer than anything in the next ring
        best > 0 && bestd <= r * g.h && break
    end
    return best
end

"One line of the squared distance transform (Felzenszwalb & Huttenlocher): `d[q] = min_p (q - p)^2 + f[p]`."
function distance_line!(d, f, v, z)
    k = 1
    v[1] = 1; z[1] = -Inf; z[2] = Inf
    for q in 2:length(f)
        s = ((f[q] + q^2) - (f[v[k]] + v[k]^2)) / (2q - 2v[k])
        while s <= z[k]
            k -= 1
            s = ((f[q] + q^2) - (f[v[k]] + v[k]^2)) / (2q - 2v[k])
        end
        k += 1
        v[k] = q; z[k] = s; z[k + 1] = Inf
    end
    k = 1
    for q in eachindex(f)
        while z[k + 1] < q
            k += 1
        end
        d[q] = (q - v[k])^2 + f[v[k]]
    end
    return d
end

"The Euclidean distance, in grid steps, from every point of `mask` to its nearest `true`."
function distance_to(mask::AbstractArray{Bool,3})
    D = map(m -> m ? 0.0 : 1e12, mask)
    for dim in 1:3
        others = filter(!=(dim), 1:3)
        n = size(D, dim)
        Threads.@threads for idx in CartesianIndices((size(D, others[1]), size(D, others[2])))
            f = Vector{Float64}(undef, n); d = similar(f); v = Vector{Int}(undef, n); z = Vector{Float64}(undef, n + 1)
            I = Any[0, 0, 0]
            I[dim] = Colon(); I[others[1]] = idx[1]; I[others[2]] = idx[2]
            line = view(D, I...)
            copyto!(f, line)
            line .= distance_line!(d, f, v, z)
        end
    end
    return Float32.(sqrt.(D))
end

"""
    outside_of(mesh; res = 192, close = 5) -> (outside, lo, h)

The grid of `res` steps along `mesh`'s longest side (corner `lo`, step `h`) and which of its
points are outside: points within `close` steps of the surface are wall, the outside is
flood-filled from the grid's border through the rest. Walls `close` thick seal gaps narrower
than `2close` steps.
"""
function outside_of(mesh::GeometryBasics.Mesh; res = 192, close = 5)
    ps = Vec3f.(GeometryBasics.coordinates(mesh))
    fs = [(convert(Int, f[1]), convert(Int, f[2]), convert(Int, f[3])) for f in GeometryBasics.faces(mesh)]
    lo0, hi0 = reduce((a, b) -> min.(a, b), ps), reduce((a, b) -> max.(a, b), ps)
    h = maximum(hi0 - lo0) / res
    pad = close + 2
    lo = lo0 .- pad * h
    dims = Tuple(ceil.(Int, (hi0 - lo0) ./ h) .+ 2pad .+ 1)
    at(i, j, k) = lo + h * Vec3f(i - 1, j - 1, k - 1)
    r = close * h
    wall = zeros(Bool, dims)       # threads only ever set entries, to true
    Threads.@threads for f in fs
        a, b, c = ps[f[1]], ps[f[2]], ps[f[3]]
        l = max.(floor.(Int, (min.(a, b, c) .- r .- lo) ./ h) .+ 1, 1)
        u = min.(ceil.(Int, (max.(a, b, c) .+ r .- lo) ./ h) .+ 1, dims)
        for k in l[3]:u[3], j in l[2]:u[2], i in l[1]:u[1]
            wall[i, j, k] && continue
            p = at(i, j, k)
            q, _ = closest_bary(p, a, b, c)
            norm(q - p) <= r && (wall[i, j, k] = true)
        end
    end
    outside = zeros(Bool, dims)
    outside[1, 1, 1] = true
    queue = [CartesianIndex(1, 1, 1)]
    steps = (CartesianIndex(1, 0, 0), CartesianIndex(-1, 0, 0), CartesianIndex(0, 1, 0),
             CartesianIndex(0, -1, 0), CartesianIndex(0, 0, 1), CartesianIndex(0, 0, -1))
    while !isempty(queue)
        I = pop!(queue)
        for s in steps
            J = I + s
            (checkbounds(Bool, outside, J) && !outside[J] && !wall[J]) || continue
            outside[J] = true
            push!(queue, J)
        end
    end
    return outside, lo, h
end

"""
    decimated(ps, fs, target) -> (ps, fs)

A closed mesh with at most `target` faces: GPUMeshing's `simplify` (quadric edge collapses
that keep it closed and two-manifold), on the default Mantle device.
"""
function decimated(ps::Vector{Point3f}, fs::Vector{GLTriangleFace}, target::Int)
    length(fs) <= target && return ps, fs
    dev = Mantle.Device()
    V = Mantle.Buffer(dev, Float32[p[i] for i in 1:3, p in ps])
    F = Mantle.Buffer(dev, Int32[convert(Int, f[i]) for i in 1:3, f in fs])
    V, F = GPUMeshing.simplify(dev, V, F, target)
    v, f = GPUMeshing.download(V), GPUMeshing.download(F)
    foreach(Mantle.free!, (V, F))
    return [Point3f(v[1, i], v[2, i], v[3, i]) for i in axes(v, 2)], [GLTriangleFace(f[1, i], f[2, i], f[3, i]) for i in axes(f, 2)]
end

"""
    closed_surface(mesh; res = 192, close = 5, faces = 40_000) -> GeometryBasics.Mesh

The outer surface of what `mesh` encloses, filled (`outside_of`): the new surface lies where
the distance to the outside is `close` steps again (a closing), `decimated` to at most `faces`
faces; normals point out.
"""
function closed_surface(mesh::GeometryBasics.Mesh; res = 192, close = 5, faces = 40_000)
    outside, lo, h = outside_of(mesh; res, close)
    # positive inside: marching cubes winds the faces towards decreasing values, out
    m = GPUMeshing.marchingcubes(distance_to(outside) .- Float32(close); origin = lo, spacing = Vec3f(h))
    # Points exactly at the level give a vertex per edge at one position and faces of no area:
    # one vertex per position, those faces dropped. Normals from the faces: the field's gradient
    # is zero where the distance is flat, and so were some of marching cubes' normals.
    key = Dict{Point3f,Int}()
    ps = Point3f[]
    id = map(GeometryBasics.coordinates(m)) do p
        get!(key, p) do
            push!(ps, p)
            length(ps)
        end
    end
    fs = GLTriangleFace[]
    for f in GeometryBasics.faces(m)
        a, b, c = id[f[1]], id[f[2]], id[f[3]]
        (a == b || b == c || a == c) && continue
        norm(cross(ps[b] - ps[a], ps[c] - ps[a])) > 0 && push!(fs, GLTriangleFace(a, b, c))
    end
    # Marching cubes made 70 to 210 thousand faces of a tree instanced dozens of times: the
    # island's frame took twice as long.
    ps, fs = decimated(ps, fs, faces)
    ns = GeometryBasics.normals(ps, fs)
    # On a fin of no thickness (the surface folded back onto itself) the faces' normals cancel:
    # such a vertex faces the way one of its faces does.
    for f in fs, i in f
        all(isfinite, ns[i]) || (ns[i] = normalize(cross(ps[f[2]] - ps[f[1]], ps[f[3]] - ps[f[1]])))
    end
    return GeometryBasics.Mesh(ps, fs; normal = ns)
end

"""
    with_uvs(new, old; cell) -> GeometryBasics.Mesh

`new` textured like `old`. Each corner of a triangle reads the texture at its closest point on
the nearest triangle of `old` that faces its way; where the three corners land on different
islands of the texture, the triangle reads all three from the one triangle nearest its centre
instead, so it never spans an island seam (a smear across the atlas). Corners are not shared
(their uvs differ across islands); the normals stay `new`'s.
"""
function with_uvs(new::GeometryBasics.Mesh, old::GeometryBasics.Mesh; cell::Real)
    g = TriangleGrid(old, cell)
    ouv = GeometryBasics.texturecoordinates(old)
    nps, nns, nfs = GeometryBasics.coordinates(new), GeometryBasics.normals(new), GeometryBasics.faces(new)
    function landing(p::Vec3f, n::Vec3f)
        k = nearest_triangle(g, p, n)
        # the new surface lies within `close` grid steps of the old: a few cells out at most
        k == 0 && error("with_uvs: no triangle of the old mesh near $p facing $n")
        o = g.fs[k]
        _, w = closest_bary(p, g.ps[o[1]], g.ps[o[2]], g.ps[o[3]])
        return k, w[1] * ouv[o[1]] + w[2] * ouv[o[2]] + w[3] * ouv[o[3]]
    end
    nf = length(nfs)
    P = Vector{Point3f}(undef, 3nf); N = Vector{Vec3f}(undef, 3nf); UV = Vector{Vec2f}(undef, 3nf)
    Threads.@threads for t in 1:nf
        f = nfs[t]
        idx = (convert(Int, f[1]), convert(Int, f[2]), convert(Int, f[3]))
        corners = map(i -> landing(Vec3f(nps[i]), Vec3f(nns[i])), idx)
        if !allequal(g.chart[k] for (k, _) in corners)
            n = Vec3f(nns[idx[1]] + nns[idx[2]] + nns[idx[3]])
            k, _ = landing(Vec3f((nps[idx[1]] + nps[idx[2]] + nps[idx[3]]) / 3), n)
            o = g.fs[k]
            corners = map(idx) do i
                _, w = closest_bary(Vec3f(nps[i]), g.ps[o[1]], g.ps[o[2]], g.ps[o[3]])
                (k, w[1] * ouv[o[1]] + w[2] * ouv[o[2]] + w[3] * ouv[o[3]])
            end
        end
        for (c, i) in enumerate(idx)
            j = 3(t - 1) + c
            P[j] = nps[i]; N[j] = nns[i]; UV[j] = corners[c][2]
        end
    end
    return GeometryBasics.Mesh(P, [GLTriangleFace(3t - 2, 3t - 1, 3t) for t in 1:nf]; normal = N, uv = UV)
end

"""
    solidified(mm; res = 192, close = 5) -> MetaMesh

`mm` filled: its closed surface (`closed_surface`), textured by `with_uvs`, same materials.
"""
function solidified(mm::GeometryBasics.MetaMesh; res = 192, close = 5)
    mesh = mm.mesh
    bb = Rect3f(GeometryBasics.coordinates(mesh))
    shut = closed_surface(mesh; res, close, faces = length(GeometryBasics.faces(mesh)))    # no heavier than it was
    filled = with_uvs(shut, mesh; cell = maximum(GeometryBasics.widths(bb)) / res * 2)
    return GeometryBasics.MetaMesh(filled, mm.meta)
end

"""
Catalog tags of what Trellis2 makes as a torn shell that shows black holes (tree crowns).
Only these are filled: on made things (a bench, a roof of tiles) the remade surface reads its
texture less cleanly and fills real crevices, and a hedge lost the shadows between its leaves.
"""
const HOLLOW_TAGS = ("tree",)

"""
    fill_hollow!(path) -> path

The mesh at `path` replaced by its `solidified` self; the original is kept beside it as
`mesh_raw.jls` (and filled again from there when this runs twice).
"""
function fill_hollow!(path::AbstractString)
    raw = joinpath(dirname(path), "mesh_raw.jls")
    isfile(raw) || cp(path, raw)
    Serialization.serialize(path, solidified(Serialization.deserialize(raw)))
    return path
end

"""
    repair_catalog!(paths) -> ids

Fills every catalog asset tagged with one of `HOLLOW_TAGS` that has not been filled yet (no
`mesh_raw.jls`). New ones are filled by the worker's `:asset` job.
"""
function repair_catalog!(p::GamePaths)
    todo = filter(load_catalog(p)) do e
        any(in(HOLLOW_TAGS), get(e, "tags", String[])) && !isfile(joinpath(dirname(e["mesh"]), "mesh_raw.jls"))
    end
    foreach(e -> fill_hollow!(e["mesh"]), todo)
    return [e["id"] for e in todo]
end
