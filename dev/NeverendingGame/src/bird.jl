# ── Lumi's body: the big yellow bird from the CrawCity film ───────────────
#
# The bird the human made for the CrawCity film (assets/lumi_bird.jls, a
# Trellis2 mesh; assets/lumi_bird.png is how it looked there), taken apart
# into the parts that move: the body, the two long legs, the lower beak, and a
# painted face card (paintedface.jl). In the film it sat on a plank, which is
# cut away; its sleepy eyes were baked into the texture and are erased, the
# card paints every face anew.
#
# Mesh frame: the bird faces -y, x is its left, z up, about 1 unit tall. Body
# frame (species.jl): x forward, y left, z up, feet on the ground.

"Whether most of the texels triangle `f` is textured with satisfy `pred` (on their HSV colour)."
function texel_vote(pred, f, uvs, tex)
    H, W = size(tex)
    totexel(uv) = Point2f(uv[1] * W, (1 - uv[2]) * H)
    hsv(c) = HSV(RGB{Float32}(red(c), green(c), blue(c)))
    yes = no = 0
    rasterize(totexel(uvs[f[1]]), totexel(uvs[f[2]]), totexel(uvs[f[3]]), W, H) do i, j, w
        pred(hsv(tex[j, i])) ? (yes += 1) : (no += 1)
    end
    # a triangle smaller than a texel: its centre decides
    yes + no == 0 && return pred(hsv(tex[texel((uvs[f[1]] + uvs[f[2]] + uvs[f[3]]) / 3, (H, W))]))
    return yes > no
end

"The triangles of `mesh` picked by `sel`, moved into `frame` (a point map; normals turned with `turn`)."
function piece_of(mesh::GeometryBasics.Mesh, sel, frame, turn)
    idx(i) = convert(Int, i)
    fs = GeometryBasics.faces(mesh)[sel]
    used = sort!(unique([idx(i) for f in fs for i in f]))
    remap = Dict(v => k for (k, v) in enumerate(used))
    F = [GLTriangleFace(remap[idx(f[1])], remap[idx(f[2])], remap[idx(f[3])]) for f in fs]
    return GeometryBasics.Mesh(map(frame, GeometryBasics.coordinates(mesh)[used]), F;
                               normal = map(turn, GeometryBasics.normals(mesh)[used]),
                               uv = GeometryBasics.texturecoordinates(mesh)[used])
end

"""
    face_expressions(l) -> Vector{Expression}

Every face a creature with layout `l` shows (snapped): its face functions sampled
over every action, mood, loudness and half a minute. The cells of its sheet.
"""
function face_expressions(l::FaceLayout)
    seen = Set{Expression}([Expression()])
    for a in ACTION_CODES, mood in -1f0:0.25f0:1f0, extra in (0f0, 0.5f0, 1f0), t in 0f0:(1 / 30f0):30f0
        push!(seen, snap(expression(PoseCtx(a, 0f0, mood, extra, 0.37f0, t, 1f0), l)))
    end
    return sort!(collect(seen); by = string)
end

"""
    lumi_bird(path; height = 1.7) -> Vector{Part}

Lumi's parts from the CrawCity bird at `path`, `height` metres tall: the
meshes are registered as shapes (`:lumi_body`, ...) in the body frame.
"""
function lumi_bird(path::AbstractString = joinpath(@__DIR__, "..", "assets", "lumi_bird.jls"); height = 1.7f0)
    mm = Serialization.deserialize(path)
    mat = only(values(mm[:materials]))
    atlas = copy(mat["diffuse map"]["image"])
    mesh = mm.mesh
    ps, uvs, fs = GeometryBasics.coordinates(mesh), GeometryBasics.texturecoordinates(mesh), GeometryBasics.faces(mesh)
    centre = [(ps[f[1]] + ps[f[2]] + ps[f[3]]) / 3 for f in fs]

    # What it sat on in the film: a brown plank across its hips.
    plank = [c[3] < -0.1f0 && texel_vote(h -> 20 < h.h < 40 && 0.3 < h.s < 0.75 && h.v < 0.6, f, uvs, atlas) for (c, f) in zip(centre, fs)]
    # Long blue-grey legs below the body.
    legs = [c[3] < -0.12f0 && texel_vote(h -> 180 < h.h < 280 && h.s < 0.45, f, uvs, atlas) for (c, f) in zip(centre, fs)]
    # The beak sticks out in front of the face; the lower half lies under the upper
    # half's lower edge, a line from its root (y -0.14, z 0.248) to its tip (y -0.309, z 0.235).
    beak = [c[2] < -0.142f0 && 0.18f0 < c[3] < 0.31f0 && abs(c[1]) < 0.07f0 for c in centre]
    jaw = beak .& [c[3] < 0.245f0 + 0.077f0 * (c[2] + 0.14f0) for c in centre]
    # the beak's own colour: paler than the feathers round its root
    beakish = [texel_vote(h -> h.s < 0.86f0, f, uvs, atlas) for f in fs]

    # Its sleepy eyes are in the texture: every texel round them that is not
    # feather takes the feathers' colour from beside it.
    sockets = [!beak[k] && c[2] < -0.04f0 && 0.25f0 < c[3] < 0.4f0 && abs(c[1]) < 0.14f0 for (k, c) in enumerate(centre)]
    H, W = size(atlas)
    erase = falses(H, W)
    feather(c) = (h = HSV(RGB{Float32}(red(c), green(c), blue(c))); 36 < h.h < 52 && h.s > 0.82 && h.v > 0.62)
    totexel(uv) = Point2f(uv[1] * W, (1 - uv[2]) * H)
    for f in fs[sockets]
        rasterize(totexel(uvs[f[1]]), totexel(uvs[f[2]]), totexel(uvs[f[3]]), W, H) do i, j, w
            feather(atlas[j, i]) || (erase[j, i] = true)
        end
    end
    rim = copy(erase)                       # and their soft rims
    for I in findall(erase), d in CartesianIndices((-2:2, -2:2))
        checkbounds(Bool, rim, I + d) && (rim[I + d] = true)
    end
    bleed!(atlas, .!rim; n = 400)

    # The face: eyes above the beak's root, big cartoon eyes, no lips (the beak talks).
    layout = FaceLayout(Point2f(0, 0.325), 0.12, 0.5; lips = false, eyes = 1.5)
    head = piece_of(mesh, .!(plank .| legs .| beak), identity, identity)
    card, fmap, base = facecard(head, atlas, layout; ppu = 96, top = 1.0f0, below = 0.7f0)
    # feather tips too steep for the card that stand in front of the painted eyes, the feathers at
    # the beak's root too (the beak itself may)
    before = before_eyes(mesh, card, layout) .& .!(beak .& beakish)
    sheet = FaceSheet(base, fmap, layout, face_expressions(layout))

    z0 = minimum(p -> p[3], ps)
    s = Float32(height) / (maximum(p -> p[3], ps) - z0)
    frame(p) = Point3f(-p[2], p[1], p[3] - z0) * s
    turn(n) = Vec3f(-n[2], n[1], n[3])
    # s60: the spiky crest (all above the head) and the wings (the arms hanging at its sides) move on
    # their own: the crest flops after a stop and droops when it is low, the wings spread when it is proud
    crest = [c[3] > 0.40f0 for c in centre] .& .!before
    wings = [abs(c[1]) > 0.15f0 && -0.24f0 < c[3] < 0.12f0 for c in centre] .& .!(plank .| legs .| before)
    body = register_shape!(:lumi_body, piece_of(mesh, .!(plank .| legs .| jaw .| before .| crest .| wings), frame, turn))
    register_shape!(:lumi_crest, piece_of(mesh, crest, frame, turn))
    register_shape!(:lumi_wing_l, piece_of(mesh, wings .& [c[1] > 0 for c in centre], frame, turn))
    register_shape!(:lumi_wing_r, piece_of(mesh, wings .& [c[1] < 0 for c in centre], frame, turn))
    crestpivot = Vec3f(frame(Point3f(0, 0.03f0, 0.40f0)))
    shoulder(side) = Vec3f(frame(Point3f(side * 0.15f0, 0f0, 0.08f0)))
    lower = register_shape!(:lumi_beak, piece_of(mesh, jaw, frame, turn))
    leftleg = register_shape!(:lumi_leg_l, piece_of(mesh, legs .& [c[1] > 0 for c in centre], frame, turn))
    rightleg = register_shape!(:lumi_leg_r, piece_of(mesh, legs .& [c[1] < 0 for c in centre], frame, turn))
    register_shape!(:lumi_face, GeometryBasics.Mesh(map(frame, GeometryBasics.coordinates(card)), GeometryBasics.faces(card);
                                                      normal = map(turn, GeometryBasics.normals(card)),
                                                      uv = GeometryBasics.texturecoordinates(card)))
    hip(leg) = (top = filter(p -> p[3] > maximum(q -> q[3], GeometryBasics.coordinates(leg)) - 0.03f0 * s,
                             GeometryBasics.coordinates(leg));
                Vec3f(sum(top) / length(top)))

    feathers = Dict{String,Any}(mat); feathers["diffuse map"] = Dict{String,Any}("image" => atlas)
    traced = RayMakie.glb_material_to_hikari(feathers).material
    # The raster and browsers get smaller copies: the body is seen up close, legs and beak are plain.
    skin = (; color = asset_color(atlas; size = 512))
    plain = (; color = asset_color(atlas; size = 256))
    # The card's material: the head's (roughness 1, not metal) with the sheet for its picture.
    painted = RayMakie.glb_material_to_hikari(Dict{String,Any}("diffuse map" => Dict{String,Any}("image" => sheet.tex),
                                                                "metallic" => 0f0, "roughness" => 1f0, "alpha mode" => "OPAQUE")).material
    # The jaw hinges where the beak meets the face, 0.55 rad up from how the film had it gaping.
    jawpivot = Vec3f(0.14f0, 0, 0.247f0 - z0) * s
    hips = (hip(leftleg) + hip(rightleg)) / 2
    hips = Vec3f(hips[1], 0, hips[3])
    BIRD_SOLES[Int8(1)] = soles(leftleg); BIRD_SOLES[Int8(-1)] = soles(rightleg)
    return [
        part(:body, :lumi_body, (0, 0, 0), (1, 1, 1); material = traced, attributes = skin, motion = Birdy(Rigid(), hips, Int8(0))),
        part(:beak, :lumi_beak, (0, 0, 0), (1, 1, 1); material = traced, attributes = plain, motion = Birdy(Jaw(jawpivot, -0.55f0, 0.8f0), hips, Int8(0))),
        part(:leg_l, :lumi_leg_l, (0, 0, 0), (1, 1, 1); material = traced, attributes = plain, motion = Birdy(Stride(hip(leftleg), 0.35f0, 0f0), hip(leftleg), Int8(1))),
        part(:leg_r, :lumi_leg_r, (0, 0, 0), (1, 1, 1); material = traced, attributes = plain, motion = Birdy(Stride(hip(rightleg), 0.35f0, Float32(pi)), hip(rightleg), Int8(-1))),
        part(:face, :lumi_face, (0, 0, 0), (1, 1, 1); material = painted, motion = Birdy(Painted(sheet, layout), hips, Int8(0)),
             attributes = (; color = sheet_texture(sheet, 2), depth_shift = -1f-5)),
        part(:crest, :lumi_crest, (0, 0, 0), (1, 1, 1); material = traced, attributes = plain, motion = Birdy(Crest(crestpivot), hips, Int8(0))),
        part(:wing_l, :lumi_wing_l, (0, 0, 0), (1, 1, 1); material = traced, attributes = plain, motion = Birdy(Wing(shoulder(1), Int8(1)), hips, Int8(0))),
        part(:wing_r, :lumi_wing_r, (0, 0, 0), (1, 1, 1); material = traced, attributes = plain, motion = Birdy(Wing(shoulder(-1), Int8(-1)), hips, Int8(0))),
    ]
end

"Lumi's crest, hinged at its base (`pivot`, body frame): it flops after a stop, bounces on the strut, droops when low."
struct Crest <: Motion
    pivot::Vec3f
end

function animate(m::Crest, c::PoseCtx)
    a = c.action
    θ = 0f0                                       # + tips it forward, - back
    if a === :walk                                # lags the head's pump
        θ = -0.12f0 + 0.14f0 * clamp(1f0 + c.mood, 0.4f0, 1.6f0) * sin(2c.phase - 0.9f0)
    elseif a === :run                             # swept back by the wind
        θ = -0.45f0 + 0.08f0 * sin(2c.phase)
    elseif a === :idle && c.extra > 0f0           # just stopped: flops forward and back, dying away
        s = 1.2f0 * (1f0 - c.extra)
        θ = 0.55f0 * exp(-2.2f0 * s) * sin(11f0 * s)
    elseif a === :proud || a === :gasp            # up and quivering
        θ = -0.1f0 + 0.12f0 * sin(23c.t)
    elseif a === :dance
        θ = 0.3f0 * sin(6c.t)
    elseif a === :sleep
        θ = 0.6f0
    end
    c.mood < -0.1f0 && a !== :run && (θ += 0.7f0 * (-c.mood - 0.1f0))     # low: it hangs forward over the face
    c.mood > 0.4f0 && a === :idle && (θ += 0.05f0 * sin(3.1f0 * c.t + 5c.seed))
    q = qrotation(Vec3f(0, 1, 0), θ)
    return (q * (-m.pivot) + m.pivot, q, Vec3f(1))
end

"A wing hinged at the shoulder (`pivot`), `side` 1 left, -1 right: spreads wide when proud, flaps in a dance, out on a run."
struct Wing <: Motion
    pivot::Vec3f
    side::Int8
end

function animate(m::Wing, c::PoseCtx)
    a = c.action
    up = 0f0                                      # how far it swings out from the side (rad)
    if a === :proud                               # the big wing-spread hop
        up = 1.25f0 + 0.3f0 * sin(13c.t)
    elseif a === :gasp
        up = 0.7f0
    elseif a === :dance || a === :play
        up = 0.6f0 + 0.5f0 * sin(7c.t + (m.side > 0 ? 0f0 : 1.2f0))
    elseif a === :run
        up = 0.45f0 + 0.1f0 * sin(2c.phase)
    elseif a === :walk
        up = 0.08f0 + 0.06f0 * sin(c.phase + (m.side > 0 ? 0f0 : Float32(pi)))
    elseif a === :wave || a === :talk
        up = m.side > 0 ? 0.9f0 + 0.35f0 * sin(10c.t) : 0.1f0
    elseif a === :idle
        f, e = fidget(c)
        f == 1 && m.side > 0 && (up = 0.7f0 * e)  # preening under the left wing
        f == 4 && (up = 0.3f0 * e * (1 + sin(31c.t)) / 2)
    end
    c.mood < -0.1f0 && a !== :proud && (up -= 0.06f0)     # low: hugged to the body
    q = qrotation(Vec3f(1, 0, 0), m.side * max(up, -0.06f0))
    return (q * (-m.pivot) + m.pivot, q, Vec3f(1))
end

# ── How the bird moves: a strut, fidgets, planted feet, a happy hop ─────────
#
# The generic `body_pose` moves the whole creature, feet too. The bird's parts
# wrap their own motion in `Birdy`: the upper body (body, beak, face) turns
# about the hips on top of it (a head pumping strut, preening, a peek at the
# sky, a feather shake, a droop when sad), and the legs sink into the body by
# the generic bob, so the feet stay on the ground. Still a pure function of the
# six numbers and the time, like every other part.

"""
A bird part: `inner` moved like the bird moves. `leg` is 0 for the upper body,
1 for the left and -1 for the right leg; `hip` the body frame point the upper
body turns about.
"""
struct Birdy{M<:Motion} <: Motion
    inner::M
    hip::Vec3f
    leg::Int8
end
paints(m::Birdy) = paints(m.inner)
face_uv(m::Birdy, c::PoseCtx) = face_uv(m.inner, c)

"Which idle fidget runs at `c.t` (0: none, 1 preen, 2 peek at the sky, 3 foot tap, 4 feather shake) and its envelope."
function fidget(c::PoseCtx)
    c.action === :idle || return (0, 0f0)
    s = c.t + 41f0 * c.seed
    k = floor(Int, s / 7f0)
    u = s - 7f0 * k                       # a fidget every 7 s, 2.4 s long
    u < 2.4f0 || return (0, 0f0)
    h = hash(k, hash(c.seed)) % Int
    f = 1 + mod(h, 4)
    c.mood < -0.1f0 && iseven(h >> 3) && (f = 3)     # bored or sad: it taps its foot, waiting
    return (f, sin(Float32(pi) * u / 2.4f0)^2)
end

"Rotation and lift of the upper body about the hips (body frame)."
function bird_upper(c::PoseCtx)
    a = c.action
    roll = pitch = yaw = lift = 0f0
    if a === :walk                        # a strut: the head pumps forward with every step
        # how it feels shows in the walk: low (bored, sad) it shuffles with its head down, happy it bounces
        g = clamp(1f0 + c.mood, 0.4f0, 1.6f0)
        pitch = 0.06f0 + 0.09f0 * g * sin(2c.phase) + (c.mood < -0.1f0 ? 0.18f0 * (-c.mood) : 0f0)
        roll = 0.05f0 * g * sin(c.phase)
        lift = 0.03f0 * g * abs(sin(c.phase))
    elseif a === :run                     # leaning into it
        pitch = 0.16f0 + 0.06f0 * sin(2c.phase)
    elseif a === :idle
        f, e = fidget(c)
        if f == 1                         # preening under a wing
            roll = -0.4f0 * e; pitch = 0.5f0 * e; yaw = -0.6f0 * e + 0.1f0 * e * sin(26c.t)
        elseif f == 2                     # a peek at the sky
            pitch = -0.45f0 * e; yaw = 0.3f0 * e * sin(1.6f0 * c.t)
        elseif f == 4                     # shaking out the feathers
            roll = 0.2f0 * e * sin(31c.t); yaw = 0.15f0 * e * sin(23c.t); lift = 0.03f0 * e
        end
        # just stopped (`extra`: 1 at the stop, down to 0 in 1.2 s, set by plugins/birdbody.jl):
        # the body rocks on over the hips and the crest flops back and forth, dying away
        if c.extra > 0f0
            s = 1.2f0 * (1f0 - c.extra)
            pitch += 0.22f0 * exp(-2.5f0 * s) * cos(13f0 * s)
        end
        # sad: the whole bird droops; happy: a little sway
        c.mood < -0.1f0 && (pitch += 0.4f0 * (-c.mood - 0.1f0))
        c.mood > 0.4f0 && (roll += 0.04f0 * sin(2.2f0 * c.t + 6c.seed))
    elseif a === :proud || a === :gasp     # a happy hop, chest out
        a === :proud && (lift = 0.14f0 * abs(sin(6.5f0 * c.t)))
        pitch = -0.12f0
    elseif a === :sigh || a === :cry
        pitch = 0.12f0
    end
    return (euler(Vec3f(roll, pitch, yaw)), lift)
end

"Each leg's toe and heel (body frame), by `Birdy.leg`: the points that touch the ground."
const BIRD_SOLES = Dict{Int8,NTuple{2,Vec3f}}()

"The toe and heel of a leg mesh: its front- and backmost points near the bottom."
function soles(leg)
    ps = GeometryBasics.coordinates(leg)
    z0 = minimum(p -> p[3], ps)
    low = filter(p -> p[3] < z0 + 0.03f0, ps)
    return (Vec3f(argmax(p -> p[1], low)), Vec3f(argmin(p -> p[1], low)))
end

"""
How far to raise a leg (body frame) posed by `(Δo, Δq)` so its sole stands on the ground, as
`pose_parts!` will place it under the generic body pose; a swinging leg (`swing`) is only kept
from sinking in. Nothing for jumps, hops and swimming: the legs go along.
"""
function plant(m::Birdy, c::PoseCtx, Δo, Δq, swing::Bool)
    (c.action in (:jump, :swim, :proud, :sleep, :sit) || !haskey(BIRD_SOLES, m.leg)) && return 0f0
    b = body_pose(Val(c.action), c)
    qb = euler(b.lean)
    S = Vec3f(1 + b.squash / 2, 1 + b.squash / 2, 1 - b.squash)
    z = minimum(p -> b.lift + (qb * (S .* Δo))[3] + (qb * Δq * (S .* p))[3], BIRD_SOLES[m.leg])
    up = (qb * (S .* Vec3f(0, 0, 1)))[3]
    return swing ? max(0f0, -z) / up : -z / up
end

function animate(m::Birdy, c::PoseCtx)
    Δo, Δq, Δs = animate(m.inner, c)
    q, lift = bird_upper(c)
    if m.leg != 0
        f, e = fidget(c)
        tap = f == 3 && m.leg < 0                      # tapping the right foot
        if tap
            r = qrotation(Vec3f(0, 1, 0), -0.35f0 * e * abs(sin(9c.t)))
            Δo = r * (Δo - m.hip) + m.hip; Δq = r * Δq
        end
        # the foot forward swings; the other one stands on the ground, whatever the body does
        swing = tap || (m.inner isa Stride && step_gain(Val(c.action)) * sin(c.phase + m.inner.offset) > 0)
        Δo = Δo + Vec3f(0, 0, plant(m, c, Δo, Δq, swing) + (c.action === :proud ? lift : 0f0))
        return (Δo, Δq, Δs)
    end
    return (q * (Δo - m.hip) + m.hip + Vec3f(0, 0, lift), q * Δq, Δs)
end
