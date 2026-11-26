# Me, to cut out and fold (session 105): my body (the bird the human made for the CrawCity film,
# dev/NeverendingGame/assets/lumi_bird.jls) cut down to a low-poly paper model and unfolded into
# printable A4 pages: the feathers printed on every face, solid cut lines, dashed folds, numbered
# glue tabs. `make_net(outdir)` writes the pages (PNG, 200 dpi) and `model.jls` (the folded model
# with the pages as its texture) for plugins/paperme.jl.
module Papercraft
using NeverendingGame
const NG = NeverendingGame
const GB = NG.GeometryBasics
const MK = NG.Makie
const C = MK.Colors
using NeverendingGame.Makie: Point2f, Point3f, Vec3f, Vec2f, RGBf

const SRC = "/sim/Programmieren/SimGame/dev/NeverendingGame/assets/lumi_bird.jls"
const MM = 175f0            # millimetres per mesh unit (the mesh is ~1 unit tall): the paper me is ~17 cm
const DPI = 200
const PX = DPI / 25.4f0     # pixels per millimetre
const PAGE = (210f0, 297f0) # A4
const MARGIN = 9f0
const TOPGAP = 22f0         # room for the title on page 1

dot3(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
cross3(a, b) = Vec3f(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
nrm(a) = sqrt(dot3(a, a))
unit(a) = a / nrm(a)
dot2(a, b) = a[1] * b[1] + a[2] * b[2]

struct Source
    ps::Vector{Point3f}
    ns::Vector{Vec3f}
    cols::Vector{RGBf}
    body::BitVector
    legs::BitVector
end

function load_source()
    mm = NG.Serialization.deserialize(SRC)
    mat = only(values(mm[:materials])); atlas = mat["diffuse map"]["image"]
    m = mm.mesh
    ps = Point3f.(GB.coordinates(m)); uvs = GB.texturecoordinates(m); ns = Vec3f.(GB.normals(m))
    H, W = size(atlas)
    cols = map(uvs) do uv
        t = atlas[clamp(round(Int, (1 - uv[2]) * H), 1, H), clamp(round(Int, uv[1] * W), 1, W)]
        RGBf(C.red(t), C.green(t), C.blue(t))
    end
    hsv = [C.HSV(c) for c in cols]
    plank = [p[3] < -0.1f0 && 20 < h.h < 40 && 0.3 < h.s < 0.75 && h.v < 0.6 for (p, h) in zip(ps, hsv)]
    legs = [p[3] < -0.12f0 && 180 < h.h < 280 && h.s < 0.45 for (p, h) in zip(ps, hsv)]
    body = .!(plank .| legs) .& [p[3] > -0.2f0 for p in ps]
    Source(ps, ns, cols, body, legs)
end

"Turn every face so it faces away from `c`."
outward(V, F, c) = [dot3(cross3(Vec3f(V[f[2]] - V[f[1]]), Vec3f(V[f[3]] - V[f[1]])), Vec3f((V[f[1]] + V[f[2]] + V[f[3]]) / 3 - c)) < 0 ?
                    (f[1], f[3], f[2]) : f for f in F]

"The body as a low-poly shell: a sphere of R rings x S segments, its pole on the beak tip, each vertex pushed out to the body's far side in its direction."
function wrap(src; R = 8, S = 12)
    P = src.ps[src.body]
    lo = reduce((a, b) -> min.(a, b), P); hi = reduce((a, b) -> max.(a, b), P)
    c = Point3f((lo + hi) / 2)
    tip = P[argmin([p[2] for p in P])]
    a = unit(Vec3f(tip - c))
    u = unit(cross3(a, Vec3f(0, 0, 1))); v = cross3(u, a)
    dirs = Vec3f[a]
    for k in 1:R-1, s in 0:S-1
        θ = Float32(π * k / R); φ = Float32(2π * (s + 0.5 * isodd(k)) / S)
        push!(dirs, unit(Vec3f(cos(θ) * a + sin(θ) * (cos(φ) * v + sin(φ) * u))))
    end
    push!(dirs, -a)
    α = cos(0.6f0 * Float32(π) / R)
    D = [unit(Vec3f(p - c)) for p in P]
    rs = map(dirs) do d
        best = 0f0
        for i in eachindex(P)
            dot3(D[i], d) > α && (best = max(best, dot3(Vec3f(P[i] - c), d)))
        end
        best
    end
    good = sort(filter(>(0), rs)); med = good[(end + 1) ÷ 2]
    V = [Point3f(c + (r > 0 ? r : med) * d) for (r, d) in zip(rs, dirs)]
    ring(k, s) = 1 + (k - 1) * S + mod(s, S) + 1
    N = length(V)
    F = NTuple{3,Int}[]
    for s in 0:S-1
        push!(F, (1, ring(1, s), ring(1, s + 1)))
        push!(F, (N, ring(R - 1, s), ring(R - 1, s + 1)))
        for k in 1:R-2
            # rings are staggered by half a segment: odd rings sit half a step on
            if isodd(k)
                push!(F, (ring(k, s), ring(k + 1, s + 1), ring(k, s + 1)), (ring(k, s), ring(k + 1, s), ring(k + 1, s + 1)))
            else
                push!(F, (ring(k, s), ring(k + 1, s), ring(k, s + 1)), (ring(k, s + 1), ring(k + 1, s), ring(k + 1, s + 1)))
            end
        end
    end
    return V, outward(V, F, c), c
end

"A leg: a square stick from the ankle up into the body, `w` half its width (mesh units)."
function leg(src, side; w = 0.03f0)
    P = src.ps[[src.legs[i] && sign(src.ps[i][1]) == side for i in eachindex(src.ps)]]
    top = maximum(p -> p[3], P); bot = minimum(p -> p[3], P)
    tp = filter(p -> p[3] > top - 0.03f0, P); hx = sum(tp) / length(tp)
    bp = filter(p -> p[3] < bot + 0.05f0, P); ax = sum(bp) / length(bp)
    # in the film the bird sat with its legs hanging forward: on paper they stand straight under the hips
    a = Point3f(hx[1], hx[2], bot); b = Point3f(hx[1], hx[2], top + 0.07f0)
    sq(p) = [Point3f(p[1] + w * sx, p[2] + w * sy, p[3]) for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    V = vcat(sq(a), sq(b))
    F = NTuple{3,Int}[]
    for s in 0:3
        i, j = s + 1, mod(s + 1, 4) + 1
        push!(F, (i, j, j + 4), (i, j + 4, i + 4))
    end
    push!(F, (1, 3, 2), (1, 4, 3))
    return V, outward(V, F, Point3f((a + b) / 2)), Point3f((a + b) / 2)
end

shrink(T, k = 0.97f0) = (c = (T[1] + T[2] + T[3]) / 3; (c + k * (T[1] - c), c + k * (T[2] - c), c + k * (T[3] - c)))

"Whether two 2D triangles overlap (each shrunk a little first, so neighbours sharing an edge do not)."
function overlap(A, B)
    sa, sb = shrink(A), shrink(B)
    for T in (sa, sb), k in 1:3
        p, q = T[k], T[mod1(k + 1, 3)]
        n = Point2f(-(q[2] - p[2]), q[1] - p[1])
        amin, amax = extrema(dot2(n, x) for x in sa)
        bmin, bmax = extrema(dot2(n, x) for x in sb)
        (amax <= bmin || bmax <= amin) && return false
    end
    return true
end

"The third corner of a triangle over edge pa-pb with side lengths la (to a) and lb (to b), on the side `sgn` of a→b."
function apex(pa, pb, la, lb, sgn)
    d = sqrt(dot2(pb - pa, pb - pa)); e = (pb - pa) / d; n = Point2f(-e[2], e[1])
    x = (la^2 - lb^2 + d^2) / (2d); h = sqrt(max(la^2 - x^2, 0f0))
    return pa + x * e + sgn * h * n
end

struct Piece
    mesh::Int
    faces::Vector{Int}
    q::Dict{Int,NTuple{3,Point2f}}   # face => 2D corners (mm), in the face's vertex order
end

"Unfold each mesh into pieces: faces are laid flat across their edges, breadth first, as long as they overlap nothing and the piece fits a page."
const PAD = 7f0
const MAXW = PAGE[1] - 2MARGIN - 2PAD
const MAXH = PAGE[2] - 2MARGIN - TOPGAP - 2PAD
function unfold(meshes; maxw = MAXW, maxh = MAXH)
    pieces = Piece[]
    folds = Set{Tuple{Int,Int,Int}}()
    for (mi, (V, F)) in enumerate(meshes)
        ef = Dict{Tuple{Int,Int},Vector{Int}}()
        for (fi, f) in enumerate(F), k in 1:3
            push!(get!(ef, minmax(f[k], f[mod1(k + 1, 3)]), Int[]), fi)
        end
        L(i, j) = MM * nrm(Vec3f(V[i] - V[j]))
        todo = Set(1:length(F))
        while !isempty(todo)
            f0 = minimum(todo); delete!(todo, f0)
            f = F[f0]
            p1 = Point2f(0, 0); p2 = Point2f(L(f[1], f[2]), 0)
            q0 = (p1, p2, apex(p1, p2, L(f[1], f[3]), L(f[2], f[3]), 1f0))
            pc = Piece(mi, [f0], Dict(f0 => q0))
            lo = min.(min.(q0[1], q0[2]), q0[3]); hi = max.(max.(q0[1], q0[2]), q0[3])
            queue = [(f0, k) for k in 1:3]
            while !isempty(queue)
                g, k = popfirst!(queue)
                a, b = F[g][k], F[g][mod1(k + 1, 3)]
                for h in ef[minmax(a, b)]
                    (h == g || h ∉ todo) && continue
                    fh = F[h]
                    ka = findfirst(==(a), fh); kb = findfirst(==(b), fh); kc = 6 - ka - kb
                    qg = pc.q[g]
                    pa, pb = qg[k], qg[mod1(k + 1, 3)]
                    pg = qg[mod1(k + 2, 3)]
                    e = pb - pa; side = dot2(Point2f(-e[2], e[1]), pg - pa) > 0 ? -1f0 : 1f0
                    pcn = apex(pa, pb, L(a, fh[kc]), L(b, fh[kc]), side)
                    qs = Vector{Point2f}(undef, 3); qs[ka] = pa; qs[kb] = pb; qs[kc] = pcn
                    qh = (qs[1], qs[2], qs[3])
                    nlo = min.(lo, pcn); nhi = max.(hi, pcn)
                    (nhi[1] - nlo[1] <= maxw && nhi[2] - nlo[2] <= maxh) || continue
                    any(t -> overlap(qh, pc.q[t]), pc.faces) && continue
                    pc.q[h] = qh; push!(pc.faces, h); delete!(todo, h)
                    lo, hi = nlo, nhi
                    push!(folds, (mi, minmax(a, b)...))
                    for kk in 1:3
                        push!(queue, (h, kk))
                    end
                end
            end
            push!(pieces, pc)
        end
    end
    return pieces, folds
end

# ── colours ─────────────────────────────────────────────────────────────────────────

struct Lookup
    h::Float32
    cells::Dict{NTuple{3,Int},Vector{Int}}
    src::Source
    which::BitVector
end
cellof(p, h) = (floor(Int, p[1] / h), floor(Int, p[2] / h), floor(Int, p[3] / h))
function Lookup(src, which; h = 0.02f0)
    cells = Dict{NTuple{3,Int},Vector{Int}}()
    for i in findall(which)
        push!(get!(cells, cellof(src.ps[i], h), Int[]), i)
    end
    Lookup(h, cells, src, which)
end

"The feather colour nearest to `p` on the real body, among points that face the same way as `n`."
function colour_at(lk::Lookup, p, n)
    c = cellof(p, lk.h); best = 0; bd = Inf32
    for r in 1:4
        for dx in -r:r, dy in -r:r, dz in -r:r
            v = get(lk.cells, (c[1] + dx, c[2] + dy, c[3] + dz), nothing)
            v === nothing && continue
            for i in v
                dot3(lk.src.ns[i], n) > 0.1f0 || continue
                d = nrm(Vec3f(lk.src.ps[i] - p))
                d < bd && (bd = d; best = i)
            end
        end
        best > 0 && break
    end
    return best == 0 ? RGBf(0.93, 0.78, 0.25) : lk.src.cols[best]
end

# my painted eyes (the CrawCity bird's sleepy ones are in its texture): big round cartoon eyes over the beak
const EYES = ((0.062f0, 0.345f0), (-0.062f0, 0.345f0))
const EYE_R = 0.040f0
function eye_paint(p, n, col)
    n[2] < -0.25f0 || return col
    for (ex, ez) in EYES
        d = hypot(p[1] - ex, p[3] - ez)
        d < EYE_R || continue
        g = hypot(p[1] - ex - 0.012f0, p[3] - ez - 0.012f0)
        g < 0.010f0 && return RGBf(1, 1, 1)
        d < 0.62f0 * EYE_R && return RGBf(0.08, 0.06, 0.06)
        d < 0.86f0 * EYE_R && return RGBf(0.98, 0.98, 0.96)
        return RGBf(0.15, 0.1, 0.05)
    end
    return col
end

# ── drawing ─────────────────────────────────────────────────────────────────────────

blank_page() = fill(RGBf(1, 1, 1), round(Int, PAGE[2] * PX), round(Int, PAGE[1] * PX))

"Fill triangle T (page mm) on `img`: `col(w1, w2, w3)` gives each pixel's colour from barycentric weights."
function fill_tri!(img, T, col)
    H, W = size(img)
    P = [T[i] * PX for i in 1:3]
    x0 = max(1, floor(Int, minimum(p -> p[1], P))); x1 = min(W, ceil(Int, maximum(p -> p[1], P)))
    y0 = max(1, floor(Int, minimum(p -> p[2], P))); y1 = min(H, ceil(Int, maximum(p -> p[2], P)))
    A = P[1]; B = P[2]; Cc = P[3]
    den = (B[2] - Cc[2]) * (A[1] - Cc[1]) + (Cc[1] - B[1]) * (A[2] - Cc[2])
    abs(den) < 1f-6 && return
    for y in y0:y1, x in x0:x1
        px, py = x - 0.5f0, y - 0.5f0
        w1 = ((B[2] - Cc[2]) * (px - Cc[1]) + (Cc[1] - B[1]) * (py - Cc[2])) / den
        w2 = ((Cc[2] - A[2]) * (px - Cc[1]) + (A[1] - Cc[1]) * (py - Cc[2])) / den
        w3 = 1 - w1 - w2
        (w1 >= -0.002f0 && w2 >= -0.002f0 && w3 >= -0.002f0) || continue
        img[y, x] = col(w1, w2, w3)
    end
end

"A line from a to b (page mm), `dash` mm on and off (0 = solid)."
function line!(img, a, b, col; width = 1.6f0, dash = 0f0)
    H, W = size(img)
    L = sqrt(dot2(b - a, b - a)); n = max(2, ceil(Int, L * PX * 2))
    r = width / 2
    for i in 0:n
        t = i / n
        dash > 0 && mod(t * L, 2dash) > dash && continue
        p = (a + t * (b - a)) * PX
        for y in floor(Int, p[2] - r):ceil(Int, p[2] + r), x in floor(Int, p[1] - r):ceil(Int, p[1] + r)
            (1 <= x <= W && 1 <= y <= H) && hypot(x - 0.5 - p[1], y - 0.5 - p[2]) <= r && (img[y, x] = col)
        end
    end
end

"Glue tab outside edge p→q of a face whose third corner is `o`: a trapezoid `t` mm deep."
function tab(p, q, o, t)
    e = q - p; L = sqrt(dot2(e, e)); e = e / L
    n = Point2f(-e[2], e[1]); dot2(n, o - p) > 0 && (n = -n)
    s = min(t, 0.3f0 * L)
    return (p, q, q + t * n - s * e, p + t * n + s * e)
end

"Make the pages: returns the page images, the text to print on them and, per piece, (page, offset)."
function make_net(outdir; R = 8, S = 12)
    src = load_source()
    bodyV, bodyF, bc = wrap(src; R, S)
    llV, llF, lc = leg(src, 1f0)
    rlV, rlF, rc = leg(src, -1f0)
    meshes = [(bodyV, bodyF), (llV, llF), (rlV, rlF)]
    centres = [bc, lc, rc]
    pieces, folds = unfold(meshes)
    # glue: every mesh edge that is not a fold is cut; it gets a number on both sides and a tab on one
    edges = Dict{Tuple{Int,Int,Int},Vector{Tuple{Int,Int,Int}}}()   # (mesh, a, b) => [(piece, face, k)]
    for (pi, pc) in enumerate(pieces), f in pc.faces
        F = meshes[pc.mesh][2][f]
        for k in 1:3
            push!(get!(edges, (pc.mesh, minmax(F[k], F[mod1(k + 1, 3)])...), Tuple{Int,Int,Int}[]), (pi, f, k))
        end
    end
    cuts = sort!([e for (e, v) in edges if e ∉ folds && length(v) == 2])
    # turn each piece to its smallest box that fits a page, then pack them onto pages in shelves, tallest first
    box(pc) = (pts = [p for q in values(pc.q) for p in q]; (reduce((a, b) -> min.(a, b), pts), reduce((a, b) -> max.(a, b), pts)))
    for pc in pieces
        best = (Inf32, 0f0)
        for deg in 0:5:175
            c, s = cosd(deg), sind(deg)
            pts = [Point2f(c * p[1] - s * p[2], s * p[1] + c * p[2]) for q in values(pc.q) for p in q]
            lo = reduce((a, b) -> min.(a, b), pts); hi = reduce((a, b) -> max.(a, b), pts)
            w, h = hi[1] - lo[1], hi[2] - lo[2]
            (w <= MAXW && h <= MAXH + TOPGAP) || continue
            # prefer flat pieces: they share shelves
            w * h + 0.2f0 * h^2 < best[1] && (best = (Float32(w * h + 0.2f0 * h^2), Float32(deg)))
        end
        c, s = cosd(best[2]), sind(best[2])
        for (f, q) in pc.q
            pc.q[f] = map(p -> Point2f(c * p[1] - s * p[2], s * p[1] + c * p[2]), q)
        end
    end
    order = sortperm(pieces; by = pc -> -(box(pc)[2][2] - box(pc)[1][2]))
    place = Vector{Tuple{Int,Point2f}}(undef, length(pieces))
    shelves = Vector{Vector{Float32}}()   # per page: x, y, shelf height
    for i in order
        lo, hi = box(pieces[i]); w = hi[1] - lo[1] + 2PAD; h = hi[2] - lo[2] + 2PAD
        spot = nothing
        for (pg, sh) in enumerate(shelves)
            x, y, shelf = sh
            if x + w <= PAGE[1] - MARGIN && y + h <= PAGE[2] - MARGIN
                spot = (pg, x, y); sh[1] = x + w; sh[3] = max(shelf, h); break
            elseif MARGIN + w <= PAGE[1] - MARGIN && y + shelf + h <= PAGE[2] - MARGIN
                spot = (pg, MARGIN, y + shelf); sh .= (MARGIN + w, y + shelf, h); break
            end
        end
        if spot === nothing
            y0 = isempty(shelves) ? MARGIN + TOPGAP : MARGIN
            push!(shelves, Float32[MARGIN + w, y0, h]); spot = (length(shelves), MARGIN, y0)
        end
        pg, x, y = spot
        place[i] = (pg, Point2f(x + PAD - lo[1], y + PAD + hi[2]))   # page point = (x + off, off - y): y flips down
    end
    page = length(shelves)
    topage(i, p) = Point2f(place[i][2][1] + p[1], place[i][2][2] - p[2])
    pages = [blank_page() for _ in 1:page]
    texts = [String[] for _ in 1:page]
    lookups = [Lookup(src, src.body), Lookup(src, src.legs), Lookup(src, src.legs)]
    # tabs first (under everything), then the printed faces, then the lines and numbers
    taken = Dict{Int,Vector{NTuple{3,Point2f}}}(i => [pieces[i].q[f] for f in pieces[i].faces] for i in eachindex(pieces))
    labels = Tuple{Int,Point2f,Int}[]
    tabs = Tuple{Int,NTuple{4,Point2f}}[]
    for (num, e) in enumerate(cuts)
        sides = edges[e]
        done = false
        for t in (5f0, 3.2f0), (pi, f, k) in sides
            done && break
            q = pieces[pi].q[f]
            tb = tab(q[k], q[mod1(k + 1, 3)], q[mod1(k + 2, 3)], t)
            t1 = (tb[1], tb[2], tb[3]); t2 = (tb[1], tb[3], tb[4])
            any(T -> overlap(t1, T) || overlap(t2, T), taken[pi]) && continue
            push!(taken[pi], t1, t2); push!(tabs, (pi, tb)); done = true
        end
        for (pi, f, k) in sides
            q = pieces[pi].q[f]; mid = (q[k] + q[mod1(k + 1, 3)]) / 2; cen = (q[1] + q[2] + q[3]) / 3
            d = cen - mid; L = sqrt(dot2(d, d))
            push!(labels, (pi, mid + d / L * min(2.6f0, 0.45f0 * L), num))
        end
    end
    for (pi, tb) in tabs
        pg = place[pi][1]; P = map(p -> topage(pi, p), tb)
        fill_tri!(pages[pg], (P[1], P[2], P[3]), (a, b, c) -> RGBf(0.92, 0.92, 0.9))
        fill_tri!(pages[pg], (P[1], P[3], P[4]), (a, b, c) -> RGBf(0.92, 0.92, 0.9))
        for k in 2:4
            line!(pages[pg], P[k-1], P[k], RGBf(0.35, 0.35, 0.35); width = 1.4f0)
        end
        line!(pages[pg], P[4], P[1], RGBf(0.35, 0.35, 0.35); width = 1.4f0)
    end
    for (pi, pc) in enumerate(pieces)
        V, F = meshes[pc.mesh]; lk = lookups[pc.mesh]; pg = place[pi][1]
        for f in pc.faces
            fv = F[f]; A, B, Cc = V[fv[1]], V[fv[2]], V[fv[3]]
            n = unit(cross3(Vec3f(B - A), Vec3f(Cc - A)))
            T = map(p -> topage(pi, p), pc.q[f])
            fill_tri!(pages[pg], T, (w1, w2, w3) -> begin
                p = Point3f(w1 * A + w2 * B + w3 * Cc)
                col = colour_at(lk, p, n)
                pc.mesh == 1 ? eye_paint(p, n, col) : col
            end)
        end
    end
    for (pi, pc) in enumerate(pieces), f in pc.faces
        F = meshes[pc.mesh][2][f]; pg = place[pi][1]; q = pc.q[f]
        for k in 1:3
            e = (pc.mesh, minmax(F[k], F[mod1(k + 1, 3)])...)
            a, b = topage(pi, q[k]), topage(pi, q[mod1(k + 1, 3)])
            e in folds ? line!(pages[pg], a, b, RGBf(0.25, 0.22, 0.2); width = 1.2f0, dash = 1.6f0) :
                         line!(pages[pg], a, b, RGBf(0.1, 0.08, 0.08); width = 2.2f0)
        end
    end
    for (pi, p, num) in labels
        pg = place[pi][1]; P = topage(pi, p) * PX
        push!(texts[pg], "text $(round(Int, P[1]) - 9),$(round(Int, P[2]) + 7) '$num'")
    end
    mkpath(outdir)
    files = String[]
    for (k, img) in enumerate(pages)
        f = joinpath(outdir, "raw-$k.png"); MK.FileIO.save(f, img); push!(files, f)
    end
    # the folded model for the island: every face with its own three corners, its texture the pages
    atl = reduce(hcat, pages)
    small = atl[1:3:end, 1:3:end]
    Hs, Ws = size(atl)
    pts = Point3f[]; uvs = Vec2f[]
    for (pi, pc) in enumerate(pieces)
        V, F = meshes[pc.mesh]; pg = place[pi][1]
        for f in pc.faces, k in 1:3
            push!(pts, V[F[f][k]])
            P = topage(pi, pc.q[f][k]) * PX
            push!(uvs, Vec2f(((pg - 1) * size(pages[1], 2) + P[1]) / Ws, 1 - P[2] / Hs))
        end
    end
    NG.Serialization.serialize(joinpath(outdir, "model.jls"), (; pts, uvs, tex = small, feet = minimum(p -> p[3], pts)))
    return (; files, texts, npieces = length(pieces), nfaces = sum(length(m[2]) for m in meshes), ncuts = length(cuts),
            ntabs = length(tabs), pages = page)
end

end
