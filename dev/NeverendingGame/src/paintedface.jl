# ── Painted faces: the face drawn onto the head, as in the CrawCity film ────
#
# Ported from CrawCity (tools/faces.jl). A figure made without a face gets a
# face card: the front of its head as a mesh of its own, lying just in front
# of the head, with the face as a flat picture over it. Every face the figure
# can make is painted once into a sheet of cells (`FaceSheet`), and the card
# shows one cell through its `uv_transform`: a blink or a grin changes a 2x3
# matrix and uploads nothing.
#
# Face units: the eyes sit at (±0.5, 0) on the face plane, one unit is the eye
# spacing, y points up. The figure's mesh faces -y, x is the figure's left.

"Call `f(i, j, w)` for every pixel centre `(i, j)` inside triangle `abc` (pixel units), `w` the barycentric weights."
function rasterize(f, a::Point2f, b::Point2f, c::Point2f, W::Integer, H::Integer)
    area = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
    abs(area) < 1f-12 && return
    lo = floor.(Int, min.(a, b, c)); hi = ceil.(Int, max.(a, b, c))
    for j in max(lo[2], 1):min(hi[2], H), i in max(lo[1], 1):min(hi[1], W)
        p = Point2f(i - 0.5f0, j - 0.5f0)
        w1 = ((c[1] - b[1]) * (p[2] - b[2]) - (c[2] - b[2]) * (p[1] - b[1])) / area
        w2 = ((a[1] - c[1]) * (p[2] - c[2]) - (a[2] - c[2]) * (p[1] - c[1])) / area
        w3 = 1f0 - w1 - w2
        min(w1, w2, w3) >= -1f-4 && f(i, j, Vec3f(w1, w2, w3))
    end
end

"""
Where a figure's face is in its mesh: the midpoint between the eyes in `(x, z)`,
the eye spacing in mesh units, and how many face units the mouth is below the
eyes. `lips = false`: no mouth is painted, a beak does the talking; smiles then
push the lower lids up. `eyes`: how big eyes and brows are drawn (1: CrawCity's
people; a cartoon bird reads from afar with bigger ones).
"""
struct FaceLayout
    center::Point2f
    unit::Float32
    mouth::Float32
    lips::Bool
    eyes::Float32
end
FaceLayout(center, unit, mouth; lips = true, eyes = 1) = FaceLayout(Point2f(center), Float32(unit), Float32(mouth), lips, Float32(eyes))

"Texels of the card's picture, each with its face-plane coordinate."
struct FaceMap
    texels::Vector{CartesianIndex{2}}
    q::Vector{Point2f}
end

"""
    bleed!(img, covered; n = 8) -> img

Grow the covered texels `n` texels into the uncovered ones: each uncovered
texel next to a covered one takes its colour, ring by ring. Texture filtering
reads the gaps at every seam; left dark there, they showed as dark lines.
"""
function bleed!(img::AbstractMatrix, covered::AbstractMatrix{Bool}; n = 8)
    covered = copy(covered)
    steps = (CartesianIndex(1, 0), CartesianIndex(-1, 0), CartesianIndex(0, 1), CartesianIndex(0, -1))
    front = [I for I in CartesianIndices(covered) if covered[I] && any(d -> checkbounds(Bool, covered, I + d) && !covered[I + d], steps)]
    for _ in 1:n
        next = CartesianIndex{2}[]
        for I in front, d in steps
            J = I + d
            (checkbounds(Bool, covered, J) && !covered[J]) || continue
            img[J] = img[I]; covered[J] = true
            push!(next, J)
        end
        front = next
    end
    return img
end

"Texel `(row, column)` of an `(H, W)` texture that uv `uv` reads (Trellis2: u = x / W, v = 1 - y / H)."
texel(uv, (H, W)) = CartesianIndex(clamp(ceil(Int, (1 - uv[2]) * H), 1, H), clamp(ceil(Int, uv[1] * W), 1, W))

"""
    facecard(mesh, atlas, l; ppu = 128, halfwidth = 0.9, top = 0.85, below = 0.8, forward = (0, -1, 0),
             step = 4, radius = 0.35) -> (card, map, base)

The face as a mesh and a picture of its own. The picture shows the front-facing
skin of the head around the features in face units, `ppu` texels to a unit:
`base` is that skin, sampled from `atlas` once from the surface nearest along
`forward` (`forward` along y), and `map` lists the picture's texels for `paint!`.
The card is an even sheet over it (a height field, see the end), its uvs from
the face-plane coordinate, a hair in front of the head. Draw the whole figure
under it, so the card's edge has skin behind it.
"""
function facecard(mesh::GeometryBasics.Mesh, atlas::AbstractMatrix, l::FaceLayout; ppu = 128, halfwidth = 0.9f0,
                  top = 0.85f0, below = 0.8f0, forward = Vec3f(0, -1, 0), step = 4, radius = 0.35f0)
    ps, uvs = GeometryBasics.coordinates(mesh), GeometryBasics.texturecoordinates(mesh)
    fs = GeometryBasics.faces(mesh)
    faceq(p) = Point2f((p[1] - l.center[1]) / l.unit, (p[3] - l.center[2]) / l.unit)
    isface = map(fs) do f
        a, b, c = ps[f[1]], ps[f[2]], ps[f[3]]
        normalize(cross(b - a, c - a)) ⋅ forward > 0.2f0 || return false
        qc = faceq((a + b + c) / 3)
        return abs(qc[1]) < halfwidth && -l.mouth - below < qc[2] < top
    end
    qs = [faceq(ps[i]) for f in fs[isface] for i in f]
    lo, hi = reduce((a, b) -> min.(a, b), qs), reduce((a, b) -> max.(a, b), qs)
    # Whole multiples of 4 texels: a sheet of such cells box-filters down (`shrink`) with every cell where it was.
    pw, ph = 4 .* cld.(ceil.(Int, (hi - lo) .* ppu), 4)
    topix(q) = Point2f((q[1] - lo[1]) * ppu, (hi[2] - q[2]) * ppu)   # x right, y down
    card(q) = (p = topix(q); Vec2f(p[1] / pw, 1 - p[2] / ph))

    HW = size(atlas)
    tone(f) = RGB{Float32}(atlas[texel((uvs[f[1]] + uvs[f[2]] + uvs[f[3]]) / 3, HW)])
    centre(f) = faceq((ps[f[1]] + ps[f[2]] + ps[f[3]]) / 3)
    base = fill(zero(eltype(atlas)), ph, pw)
    covered = falses(ph, pw)
    q = Matrix{Point2f}(undef, ph, pw)
    depth = fill(Inf32, ph, pw)
    # Hair shells have inner sides that face forward too: drawn in whatever
    # order they came, they striped the face. The nearest surface wins.
    function layer!(cands)
        fill!(covered, false); fill!(depth, Inf32)
        for k in findall(cands)
            f = fs[k]
            rasterize(topix(faceq(ps[f[1]])), topix(faceq(ps[f[2]])), topix(faceq(ps[f[3]])), pw, ph) do i, j, w
                p = w[1] * ps[f[1]] + w[2] * ps[f[2]] + w[3] * ps[f[3]]
                d = -(p ⋅ forward)
                d >= depth[j, i] && return
                depth[j, i] = d
                base[j, i] = atlas[texel(w[1] * uvs[f[1]] + w[2] * uvs[f[2]] + w[3] * uvs[f[3]], HW)]
                covered[j, i] = true
                q[j, i] = faceq(p)
            end
        end
    end
    layer!(isface)
    # Only skin is face: hair, a collar or a beard's side keep the atlas (the body
    # is drawn whole under the card). Skin is what the middle of the face shows
    # from the front. Below the eyes in the middle the mouth and the tears are
    # painted, and the eyes and brows are, so there everything stays: a tuft
    # left out was a hole in the card, the head showing through across an eye.
    mid = [RGB{Float32}(base[I]) for I in findall(covered) if abs(q[I][1]) < 0.4f0 && -0.8f0 < q[I][2] < 0.3f0]
    middle(v) = sort!(collect(v))[cld(length(v), 2)]
    skin = RGB{Float32}(middle(c.r for c in mid), middle(c.g for c in mid), middle(c.b for c in mid))
    isskin(c) = abs(c.r - skin.r) + abs(c.g - skin.g) + abs(c.b - skin.b) < 0.35f0
    painted(qc) = abs(qc[1]) < 0.62f0 && qc[2] < -0.16f0
    isface .&= map(f -> painted(centre(f)) || painted_eyes(l, centre(f)) || isskin(tone(f)), fs)
    layer!(isface)
    texels = findall(covered)
    fmap = FaceMap(texels, q[texels])
    # A figure made with features of its own (the bird's baked sleepy eyes, their sockets' shading):
    # under where eyes and brows are painted, what is not skin takes the skin beside it. Left as it
    # was, the old eye showed as a dark smudge wherever a lid or a smile left the skin bare.
    # Stricter than `isskin`: the sockets' shading is still yellow, a darker oval under each eye.
    bare(c) = abs(c.r - skin.r) + abs(c.g - skin.g) + abs(c.b - skin.b) < 0.12f0
    skinlike = copy(covered)
    foreach(I -> painted_eyes(l, q[I]) && !bare(RGB{Float32}(base[I])) && (skinlike[I] = false), texels)
    bleed!(base, skinlike; n = pw + ph)
    # Skin grown over the whole picture, so filtering at the card's edge reads
    # skin and not the empty texture around it (a dark line round the face).
    bleed!(base, covered; n = pw + ph)

    # The card: one even sheet over the face, a height field on a grid of `step` texels at the
    # depth of the nearest surface, hollows narrower than about `2radius` face units closed and
    # tufts as narrow opened. Made of the head's own triangles it followed every tuft and socket:
    # painted eyes sank into the sockets, and from aside a tuft showed cheek across an eye.
    na, nb = cld(pw, step) + 1, cld(ph, step) + 1                  # nodes along x, along y (down)
    node(a, b) = (clamp(1 + (a - 1) * step, 1, pw), clamp(1 + (b - 1) * step, 1, ph))
    front = fill(-Inf32, nb, na)                                   # `p ⋅ forward` of the nearest surface
    h = step ÷ 2
    for b in 1:nb, a in 1:na
        i0, j0 = node(a, b)
        for j in max(j0 - h, 1):min(j0 + h, ph), i in max(i0 - h, 1):min(i0 + h, pw)
            covered[j, i] && (front[b, a] = max(front[b, a], -depth[j, i]))
        end
    end
    # No holes: where no front-facing triangle reached a node inside the face (between two steep
    # ones), the head showed through the card, a streak across an eye. The nodes the outside of
    # the grid cannot reach are face, and a hole takes the depth of its nearest neighbours.
    steps4 = (CartesianIndex(1, 0), CartesianIndex(-1, 0), CartesianIndex(0, 1), CartesianIndex(0, -1))
    outside = falses(nb, na)
    queue = [I for I in CartesianIndices(outside) if !isfinite(front[I]) && (I[1] in (1, nb) || I[2] in (1, na))]
    outside[queue] .= true
    while !isempty(queue)
        I = pop!(queue)
        for d in steps4
            J = I + d
            checkbounds(Bool, outside, J) && !outside[J] && !isfinite(front[J]) || continue
            outside[J] = true
            push!(queue, J)
        end
    end
    has = .!outside
    while any(I -> has[I] && !isfinite(front[I]), CartesianIndices(front))
        front = [has[I] && !isfinite(front[I]) ?
                 maximum((front[I + d] for d in steps4 if checkbounds(Bool, front, I + d)); init = -Inf32) : front[I]
                 for I in CartesianIndices(front)]
    end
    # Past the face the depth goes on as it was at the face's edge: evened with nothing beyond the
    # edge, the closing pulled the edge forward, off the head where it turns away (a stair against
    # the sky from aside), and the opening pushed it back into the head.
    known = copy(has)
    while !all(known)
        grow = [I for I in CartesianIndices(known) if !known[I] && any(d -> checkbounds(Bool, known, I + d) && known[I + d], steps4)]
        for I in grow
            J = I + steps4[findfirst(d -> checkbounds(Bool, known, I + d) && known[I + d], steps4)]
            front[I] = front[J]
        end
        known[grow] .= true
    end
    r = ceil(Int, radius * ppu / step)
    disc = [CartesianIndex(db, da) for db in -r:r, da in -r:r if da^2 + db^2 <= r^2]
    sweep(f, v) = [f(v[I + d] for d in disc if checkbounds(Bool, v, I + d)) for I in CartesianIndices(v)]
    even = sweep(maximum, sweep(minimum, sweep(minimum, sweep(maximum, front))))   # closing, then opening
    # two nodes in from the head's outline: a node on it stepped out past the head, a stair against the sky
    for _ in 1:2
        has = [has[I] && all(d -> checkbounds(Bool, has, I + d) && has[I + d], steps4) for I in CartesianIndices(has)]
    end
    nodeq(a, b) = (ij = node(a, b); Point2f(lo[1] + (ij[1] - 0.5f0) / ppu, hi[2] - (ij[2] - 0.5f0) / ppu))
    vid = zeros(Int, nb, na)
    P = Point3f[]; UV = Vec2f[]
    for b in 1:nb, a in 1:na
        has[b, a] || continue
        qn = nodeq(a, b)
        # a hair in front of the head: in a ray tracer two coplanar surfaces could each win the hit
        push!(P, Point3f(l.center[1] + qn[1] * l.unit, 0, l.center[2] + qn[2] * l.unit) + (even[b, a] + 2f-3 * l.unit) * forward)
        push!(UV, card(qn))
        vid[b, a] = length(P)
    end
    F = GLTriangleFace[]
    for b in 1:(nb - 1), a in 1:(na - 1)
        v1, v2, v3, v4 = vid[b, a], vid[b, a + 1], vid[b + 1, a + 1], vid[b + 1, a]
        all(>(0), (v1, v2, v3, v4)) || continue
        push!(F, GLTriangleFace(v1, v4, v3), GLTriangleFace(v1, v3, v2))   # facing forward
    end
    return GeometryBasics.Mesh(P, F; normal = GeometryBasics.normals(P, F), uv = UV), fmap, base
end

"Whether face-plane point `q` is where `l`'s eyes and brows are painted (with a margin)."
painted_eyes(l::FaceLayout, q) =
    any(s -> abs(q[1] - 0.5f0 * s) < 0.3f0 * l.eyes + 0.1f0, (-1f0, 1f0)) && -0.3f0 * l.eyes - 0.1f0 < q[2] < 0.75f0 + 0.17f0 * l.eyes

"""
    before_eyes(mesh, card, l; forward = (0, -1, 0)) -> BitVector

The triangles of `mesh` (the head `card` was made from) that stand in front of the card where
the eyes and brows are painted: feather tips of a figure made with a face of its own, too
steep to be on the card, that cut across the painted eyes. Leave them out of what is drawn.
"""
function before_eyes(mesh::GeometryBasics.Mesh, card::GeometryBasics.Mesh, l::FaceLayout; forward = Vec3f(0, -1, 0))
    faceq(p) = Point2f((p[1] - l.center[1]) / l.unit, (p[3] - l.center[2]) / l.unit)
    cps = GeometryBasics.coordinates(card)
    cq = map(faceq, cps)
    ps = GeometryBasics.coordinates(mesh)
    # any corner in front: a strand whose middle lay behind the card still crossed an eye
    function ahead(p)
        q = faceq(p)
        painted_eyes(l, q) || return false
        nearest = argmin(i -> norm(cq[i] - q), eachindex(cq))
        return norm(cq[nearest] - q) < 0.15f0 && Vec3f(p) ⋅ forward > Vec3f(cps[nearest]) ⋅ forward
    end
    front = map(ahead, ps)
    return map(f -> front[f[1]] || front[f[2]] || front[f[3]], GeometryBasics.faces(mesh))
end

"One facial pose, in face units."
Base.@kwdef struct Expression
    eyeopen::Float32 = 1        # 0 shut .. 1 open .. 1.6 wide
    squeeze::Float32 = 0        # > 0.5: shut eyes drawn as > < (crying, straining)
    joy::Float32 = 0            # > 0.5: eyes shut into happy ^ ^ arcs (laughing, dancing)
    pupil::Vec2f = Vec2f(0)     # gaze, in eye radii (x: the figure's left)
    pupilsize::Float32 = 1
    browtilt::Float32 = 0       # + angry (inner ends down), - worried
    browlift::Float32 = 0
    mouthopen::Float32 = 0
    smile::Float32 = 0          # + corners up, - down; without lips the cheeks push the lower lids up
    skew::Float32 = 0           # + the right brow and mouth corner up, the left down: a wry look
    mouthwidth::Float32 = 1
    tears::Float32 = 0          # 0 none .. 1 streams down to the chin
    flow::Float32 = 0           # phase of the tear ripples, advance with time
    # Nichijou's reaction faces, drawn instead of the eyes, brows and mouth above:
    shock::Float32 = 0          # > 0.5: hollow oval eyes, a dark box of a mouth (mouthopen: how tall)
    stare::Float32 = 0          # > 0.5: a blank stare and a mouth hanging open (mouthopen: how far), "eeeh?!"
    sweat::Float32 = 0          # 0 .. 1: a sweat drop at the temple
    blush::Float32 = 0          # 0 .. 1: rosy cheeks
    grey::Float32 = 0           # 0 .. 1: the face drained of colour
end

const FACE_INK = RGB{Float32}(0.09, 0.06, 0.05)
const FACE_EYEWHITE = RGB{Float32}(0.97, 0.97, 0.94)
const FACE_MOUTHIN = RGB{Float32}(0.32, 0.05, 0.05)
const FACE_MOUTHDARK = RGB{Float32}(0.16, 0.05, 0.1)
const FACE_TONGUE = RGB{Float32}(0.86, 0.42, 0.42)
const FACE_TEAR = RGB{Float32}(0.45, 0.78, 1.0)
const FACE_TEARHI = RGB{Float32}(0.9, 0.97, 1.0)
const FACE_HOLLOW = RGB{Float32}(0.86, 0.9, 0.98)
const FACE_SWEAT = RGB{Float32}(0.78, 0.92, 1.0)
const FACE_BLUSH = RGB{Float32}(0.98, 0.45, 0.5)

coverage(d, aa) = clamp(0.5f0 - d / aa, 0f0, 1f0)
blend(a::RGB{Float32}, b::RGB{Float32}, t) = RGB{Float32}(a.r + t * (b.r - a.r), a.g + t * (b.g - a.g), a.b + t * (b.b - a.b))
ellipse(q, c, r) = (norm((q - c) ./ r) - 1) * min(r...)
function capsule(q, a, b, r)
    ab = b - a
    t = clamp(((q - a) ⋅ ab) / (ab ⋅ ab), 0f0, 1f0)
    return norm(q - (a + t * ab)) - r
end

"""
    lens(q, c, a, b) -> signed distance

A lens centred at `c`, `a` across and `b` up from the centre (half sizes),
pointed at the two ends of its longer axis: two circle arcs, as Nichijou draws
eyes, rather than an ellipse.
"""
function lens(q, c, a, b)
    p = q - c
    if a >= b
        R = (a^2 + b^2) / (2b)
        return max(norm(p - Vec2f(0, b - R)) - R, norm(p + Vec2f(0, b - R)) - R)
    else
        R = (a^2 + b^2) / (2a)
        return max(norm(p - Vec2f(a - R, 0)) - R, norm(p + Vec2f(a - R, 0)) - R)
    end
end

"Nichijou's shock face: two tall hollow ovals for eyes and, with lips, a dark box for a mouth."
function shockface(e::Expression, l::FaceLayout, q::Point2f, col; aa)
    for s in (-1f0, 1f0)
        d = ellipse(q, Point2f(0.45f0 * s, 0.05f0), l.eyes .* Vec2f(0.23f0, 0.33f0))
        col = blend(col, FACE_HOLLOW, coverage(d, aa))
        col = blend(col, FACE_INK, coverage(abs(d) - 0.03f0, aa))
    end
    l.lips || return col
    h = 0.1f0 + 0.22f0 * e.mouthopen
    c = Point2f(0, -l.mouth + 0.08f0 - h)
    d = max(abs(q[1]) - 0.3f0, abs(q[2] - c[2]) - h)
    return blend(col, FACE_INK, coverage(d, aa))
end

"""
Nichijou's "eeeh?!" face: a blank stare of two solid dark ovals lying flat,
tilting outer ends down as it goes on, and with lips a mouth hung from just
under the nose that grows down and out with `mouthopen`.
"""
function stareface(e::Expression, l::FaceLayout, q::Point2f, col; aa)
    o = e.mouthopen
    for s in (-1f0, 1f0)
        c = Point2f(0.54f0 * s, 0.07f0)
        a_, b_ = 0.29f0 * min(l.eyes, 1.6f0), (0.1f0 + 0.01f0 * o) * l.eyes
        θ = -s * deg2rad(14f0) * clamp((o - 0.4f0) / 0.5f0, 0f0, 1f0)
        sn, cs = sincos(θ)
        p = q - c
        eye = ellipse(Point2f(cs * p[1] + sn * p[2], -sn * p[1] + cs * p[2]), Point2f(0, 0), Vec2f(a_, b_))
        col = blend(col, FACE_INK, coverage(eye, aa))
    end
    l.lips || return col
    top = -l.mouth + 0.2f0
    h = 0.22f0 + 0.28f0 * o
    w = 0.18f0 + 0.15f0 * o
    v = clamp((top - q[2]) / h, 0f0, 1f0)
    half = w * (1 - 0.15f0 * v)
    r = 0.35f0 * min(half, h / 2)
    k = Point2f(abs(q[1]) - (half - r), abs(q[2] - (top - h / 2)) - (h / 2 - r))
    d = norm(max.(k, 0f0)) + min(max(k[1], k[2]), 0f0) - r
    dark = clamp((o - 0.7f0) / 0.3f0, 0f0, 1f0)
    col = blend(col, blend(FACE_MOUTHIN, FACE_MOUTHDARK, dark), coverage(d, aa))
    tongue = max(d, ellipse(q, Point2f(0, top - 0.85f0 * h), Vec2f(0.6f0 * w, 0.35f0 * h)))
    col = blend(col, FACE_TONGUE, (1 - dark) * coverage(tongue, aa))
    return blend(col, FACE_INK, coverage(abs(d) - 0.022f0, aa))
end

"A drop of sweat hanging at `p`: a round bottom drawn up to a point, `size` times the usual."
function sweatdrop(q::Point2f, p::Point2f, col; aa, size = 1f0)
    r = p + (q - p) / size
    d = size * min(norm(r - p) - 0.1f0, capsule(r, p, p + Point2f(0, 0.2f0), 0.015f0 + 0.075f0 * clamp((p[2] + 0.2f0 - r[2]) / 0.2f0, 0f0, 1f0)))
    col = blend(col, FACE_SWEAT, coverage(d, aa))
    return blend(col, FACE_INK, coverage(abs(d) - 0.016f0, aa))
end

"Colour of the face at face-plane point `q` over `base`."
function paint(e::Expression, l::FaceLayout, q::Point2f, base::RGB{Float32}; aa = 0.035f0)
    k = l.eyes
    if e.blush > 0
        # Soft round cheeks under the outer half of the eyes.
        for s in (-1f0, 1f0)
            d = ellipse(q, Point2f((0.5f0 + 0.12f0 * k) * s, -0.17f0 * k - 0.2f0), Vec2f(0.2f0, 0.12f0))
            base = blend(base, FACE_BLUSH, 0.6f0 * e.blush * clamp(0.5f0 - d / 0.08f0, 0f0, 1f0))
        end
    end
    col = if e.shock > 0.5f0
        shockface(e, l, q, base; aa)
    elseif e.stare > 0.5f0
        stareface(e, l, q, base; aa)
    else
        features(e, l, q, base; aa)
    end
    if e.sweat > 0
        # One drop at one temple, bigger with more sweat: a pair looked like a pattern.
        col = sweatdrop(q, Point2f(0.5f0 + 0.2f0 * k, 0.25f0 + 0.17f0 * k), col; aa, size = e.sweat > 0.5f0 ? 1.3f0 : 1f0)
    end
    if e.grey > 0
        y = 0.3f0 * col.r + 0.59f0 * col.g + 0.11f0 * col.b
        col = blend(col, RGB{Float32}(y, y, y), e.grey)
    end
    return col
end

"The ordinary face: eyes with pupils, brows, a mouth (with lips), tears."
function features(e::Expression, l::FaceLayout, q::Point2f, base::RGB{Float32}; aa)
    col = base
    k = l.eyes
    line = 0.035f0 * sqrt(k)
    for s in (-1f0, 1f0)
        c = Point2f(0.5f0 * s, 0)
        if e.joy > 0.5f0
            # ^ : the upper part of a ring.
            cc = c - Point2f(0, 0.1f0 * k)
            d = max(abs(norm(q - cc) - 0.2f0 * k) - line, cc[2] + 0.07f0 * k - q[2])
            col = blend(col, FACE_INK, coverage(d, aa))
        elseif e.squeeze > 0.5f0
            # A chevron pointing at the nose: > on the left eye, < on the right.
            tip = c - Point2f(0.14f0 * k * s, 0)
            d = min(capsule(q, c + k * Point2f(0.16f0 * s, 0.13f0), tip, line), capsule(q, c + k * Point2f(0.16f0 * s, -0.13f0), tip, line))
            col = blend(col, FACE_INK, coverage(d, aa))
        elseif e.eyeopen < 0.12f0
            col = blend(col, FACE_INK, coverage(capsule(q, c - Vec2f(0.2k, 0), c + Vec2f(0.2k, 0), 0.03f0 * sqrt(k)), aa))
        else
            # An almond pointed at the corners ("<>"); wide eyes grow taller. Less
            # than open, the lid comes down as a straight line across it.
            rw, rh = 0.21f0 * k, 0.17f0 * k * max(e.eyeopen, 1f0)
            white = lens(q, c, rw, rh)
            lid = c[2] + rh * (2 * min(e.eyeopen, 1f0) - 1)
            d = max(white, q[2] - lid)
            # Without lips a smile shows in the eyes: the cheeks push the lower lid up in an arc.
            cheek = l.lips ? -Inf32 : c[2] - rh + 1.1f0 * rh * max(e.smile, 0f0) * (1 - min(((q[1] - c[1]) / rw)^2, 1f0))
            d = max(d, cheek - q[2])
            col = blend(col, FACE_EYEWHITE, coverage(d, aa))
            pc = c + e.pupil .* Vec2f(rw, rh) .* 0.5f0
            pr = 0.085f0 * k * e.pupilsize
            # A pupil the smile's lower lid cut in half read as a smudge: it sits on top of the lid.
            l.lips || (pc = Point2f(pc[1], max(pc[2], c[2] - rh + 1.1f0 * rh * max(e.smile, 0f0) + 0.8f0 * pr)))
            col = blend(col, FACE_INK, coverage(max(norm(q - pc) - pr, d), aa))
            col = blend(col, FACE_INK, coverage(abs(d) - 0.022f0 * sqrt(k), aa))
            e.eyeopen < 0.95f0 && (col = blend(col, FACE_INK, coverage(max(abs(q[2] - lid) - line, white), aa)))
            l.lips || e.smile <= 0.1f0 || (col = blend(col, FACE_INK, coverage(max(abs(q[2] - cheek) - 0.022f0 * sqrt(k), white), aa)))
        end
        # Brow: the inner end is the one nearer the nose.
        y = 0.4f0 + 0.17f0 * (k - 1) + 0.12f0 * k * max(e.eyeopen - 1, 0) + e.browlift + (s > 0 ? 0.15f0 : -0.06f0) * e.skew
        inner = Point2f((0.5f0 - 0.2f0 * k) * s, y - 0.12f0 * k * e.browtilt)
        outer = Point2f((0.5f0 + 0.2f0 * k) * s, y + 0.12f0 * k * e.browtilt)
        col = blend(col, FACE_INK, coverage(capsule(q, inner, outer, 0.045f0 * sqrt(k)), aa))
    end
    if l.lips
        w = 0.38f0 * e.mouthwidth
        xn = q[1] / w
        if abs(xn) <= 1.15f0
            x = clamp(xn, -1f0, 1f0)
            yc = -l.mouth + 0.2f0 * e.smile * (x^2 - 0.3f0) + 0.08f0 * e.skew * x
            h = max(0.028f0, 0.3f0 * e.mouthopen * sqrt(max(1 - x^2, 0f0)))
            d = max(abs(q[2] - yc) - h, (abs(xn) - 1) * w)
            e.mouthopen > 0.05f0 && (col = blend(col, FACE_MOUTHIN, coverage(d, aa)))
            col = blend(col, FACE_INK, coverage(e.mouthopen > 0.05f0 ? abs(d) - 0.022f0 : d, aa))
        end
    end
    if e.tears > 0
        # Wide streams straight down the cheeks, rippling as they run.
        len = e.tears * (l.mouth + 0.7f0)
        for s in (-1f0, 1f0)
            top = Point2f(0.5f0 * s, -0.16f0 * k)
            wob = 0.02f0 * sin(9f0 * q[2] + e.flow)
            d = capsule(q, top, top - Point2f(0, len), 0.1f0 + wob)
            col = blend(col, FACE_TEAR, 0.9f0 * coverage(d, aa))
            hi = capsule(q, top + Point2f(0.035f0 * s, 0), top + Point2f(0.035f0 * s, -len), 0.018f0)
            col = blend(col, FACE_TEARHI, 0.8f0 * coverage(hi, aa))
        end
    end
    return col
end

"Paint `e` into `tex`: the card's texels are recomputed from `base`, the rest is left alone."
function paint!(tex::AbstractMatrix, base::AbstractMatrix, fm::FaceMap, l::FaceLayout, e::Expression)
    Threads.@threads for k in eachindex(fm.texels)
        t = fm.texels[k]
        px = base[t]
        c = paint(e, l, fm.q[k], RGB{Float32}(red(px), green(px), blue(px)))
        tex[t] = eltype(tex)(c.r, c.g, c.b, alpha(px))
    end
    return tex
end

"""
    snap(e) -> Expression

`e` on the steps a cartoon face moves in: a quarter of an eye opening, half an
eye radius of gaze, a quarter of a mouth. A live figure's faces all fall on a
few hundred of these, which is what lets them be painted once into a `FaceSheet`.
"""
function snap(e::Expression)
    q(x, s) = Float32(round(x / s) * s) + 0f0       # + 0: no -0.0, a key of its own beside 0.0
    on(x) = x > 0.5f0 ? 1f0 : 0f0
    return Expression(eyeopen = q(e.eyeopen, 0.25), squeeze = on(e.squeeze), joy = on(e.joy),
                      pupil = Vec2f(q(e.pupil[1], 0.5), q(e.pupil[2], 0.5)), pupilsize = q(e.pupilsize, 0.25),
                      browtilt = q(e.browtilt, 0.25), browlift = q(e.browlift, 0.1),
                      mouthopen = q(e.mouthopen, 0.25), smile = q(e.smile, 0.25), skew = q(e.skew, 0.25),
                      mouthwidth = q(e.mouthwidth, 0.25), tears = on(e.tears),
                      flow = e.tears > 0.5f0 ? q(mod(e.flow, 2f0 * π), π / 2) : 0f0,
                      shock = on(e.shock), stare = on(e.stare), sweat = on(e.sweat), blush = q(e.blush, 0.5),
                      grey = q(e.grey, 0.5))
end

"""
    FaceSheet(base, map, layout, expressions; gutter = 16)

Every face a figure makes, painted once into one texture: a grid of cells, one
per (snapped) expression. A face card shows a cell by its `uv_transform`
(`uvtransform`). Each cell has a `gutter` of repeated edge texels, so the mip
levels a small face is drawn from never read the neighbouring cell.
"""
struct FaceSheet
    tex::Matrix{RGBA{Colors.N0f8}}
    cells::Dict{Expression,Int}
    cols::Int
    cell::Tuple{Int,Int}     # (h, w) with the gutter
    gutter::Int
end

function FaceSheet(base::AbstractMatrix, fm::FaceMap, l::FaceLayout, expressions; gutter = 16)
    ph, pw = size(base)
    ch, cw = ph + 2gutter, pw + 2gutter
    n = length(expressions)
    cols = clamp(ceil(Int, sqrt(n * ch / cw)), 1, n)
    rows = cld(n, cols)
    tex = fill(zero(RGBA{Colors.N0f8}), rows * ch, cols * cw)
    face = copy(base)
    cells = Dict{Expression,Int}()
    for (k, e) in enumerate(expressions)
        paint!(face, base, fm, l, e)
        r0, c0 = ((k - 1) ÷ cols) * ch, ((k - 1) % cols) * cw
        for j in 1:cw, i in 1:ch
            tex[r0 + i, c0 + j] = face[clamp(i - gutter, 1, ph), clamp(j - gutter, 1, pw)]
        end
        cells[e] = k
    end
    return FaceSheet(tex, cells, cols, (ch, cw), gutter)
end

"How many steps apart two expressions are; picks a cell for one the sheet was not painted with."
distance(a::Expression, b::Expression) =
    sum(f -> sum(abs2, Float32.(getfield(a, f)) .- Float32.(getfield(b, f))), fieldnames(Expression))

"""
    uvtransform(sheet, e) -> Mat{2,3,Float32}

The `uv_transform` that shows the cell of `e` (snapped; the nearest cell if the
sheet has none for it). Makie's convention: the first component runs down the
rows of the texture, the second along its columns, and the card's uvs run over
the card (u right, v up).
"""
function uvtransform(sheet::FaceSheet, e::Expression)
    k = get(sheet.cells, e, 0)
    k == 0 && (k = sheet.cells[argmin(c -> distance(c, e), collect(keys(sheet.cells)))])
    H, W = size(sheet.tex)
    ch, cw = sheet.cell
    g = sheet.gutter
    r0, c0 = ((k - 1) ÷ sheet.cols) * ch, ((k - 1) % sheet.cols) * cw
    ih, iw = ch - 2g, cw - 2g
    return Mat{2,3,Float32}(0, iw / W, -ih / H, 0, (r0 + g + ih) / H, (c0 + g) / W)
end

"""
    sheet_texture(sheet, k) -> Matrix

The sheet box-filtered down by `k` (2 or 4: its cells are whole multiples of 4
texels), every cell where it was, so the same uv transforms read it. For the
raster and for browsers, which get every texture as float colours; the tracer
reads the full sheet from the material.
"""
function sheet_texture(sheet::FaceSheet, k::Integer)
    all(iszero, size(sheet.tex) .% k) || error("a $(size(sheet.tex)) sheet does not shrink by $k")
    return asset_color(sheet.tex; size = maximum(size(sheet.tex)) ÷ k)
end

# ── a creature's painted face ───────────────────────────────────────────────

"""
    expression(c, layout) -> Expression

What a creature's face shows (`face`, `blink`, `mouth_open` in faces.jl, the
same numbers the 3D faces of the other species read) as a painted expression.
Without lips the beak shows the mouth, so the painted one stays shut.
"""
expression(c::PoseCtx, l::FaceLayout) = expression(Val(c.action), c, l)

function expression(::Val, c::PoseCtx, l::FaceLayout)
    f = face(c)
    shut = blink(c) < 0.5f0 || f.lid > 0.95f0
    return Expression(eyeopen = shut ? 0f0 : (1 - f.lid) * (1 + 0.5f0 * f.wide), joy = f.joy, pupil = f.gaze,
                      pupilsize = 1 - 0.45f0 * f.wide, browtilt = f.brow, browlift = 0.15f0 * f.raise,
                      mouthopen = l.lips ? clamp(mouth_open(c, f) / 2.2f0, 0f0, 1f0) : 0f0,
                      smile = l.lips ? f.smile : max(f.smile, 0f0), tears = f.tears, flow = 4c.t,
                      sweat = f.sweat, blush = f.blush)
end

"A gasp is Nichijou's shock: hollow eyes, a sweat drop."
expression(::Val{:gasp}, c::PoseCtx, l::FaceLayout) = Expression(shock = 1, mouthopen = 0.8, sweat = 1)

"""
A face card: rigid on the head, showing the creature's expression through its
uv transform (`face_uv`), one cell of `sheet`.
"""
struct Painted <: Motion
    sheet::FaceSheet
    layout::FaceLayout
end
animate(::Painted, c::PoseCtx) = NOMOVE

"Whether a part's texture is read through a per-creature uv transform (`face_uv`)."
paints(::Motion) = false
paints(::Painted) = true

face_uv(m::Painted, c::PoseCtx) = uvtransform(m.sheet, snap(expression(c, m.layout)))

"""
A lower beak or jaw hinged at `pivot` (body frame): shut at `rest` radians about
the body's y axis (+ opens), opened up to `open` further as the creature talks,
laughs or gasps.
"""
struct Jaw <: Motion
    pivot::Vec3f
    rest::Float32
    open::Float32
end
function animate(m::Jaw, c::PoseCtx)
    o = clamp(mouth_open(c, face(c)) / 1.6f0, 0f0, 1f0)
    q = qrotation(Vec3f(0, 1, 0), m.rest + m.open * o)
    return (q * (-m.pivot) + m.pivot, q, Vec3f(1))
end

"""
A long leg hinged at the hip (`pivot`, body frame): swings back and forth with
the gait, `offset` its phase (π for the other leg).
"""
struct Stride <: Motion
    pivot::Vec3f
    amp::Float32
    offset::Float32
end
function animate(m::Stride, c::PoseCtx)
    a = step_gain(Val(c.action)) * m.amp * sin(c.phase + m.offset)
    c.action === :dance && (a = 0.25f0 * m.amp * sin(8c.t + m.offset))
    q = qrotation(Vec3f(0, 1, 0), -a)               # + a: the foot forward
    return (q * (-m.pivot) + m.pivot, q, Vec3f(1))
end
