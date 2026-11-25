# ── Bodies: species are lists of parts that move by dispatch ────────────────
#
# A creature's whole state on screen is six numbers (where it stands, heading,
# gait phase, mood, action, an action specific `extra`), the same six the frame
# log records. Everything else, every ear flop and blink, is a pure function of
# them plus the sim time, computed in the `Herd` recipe. So replays, the live
# view and VideoEditor movies all animate identically from the same numbers.
#
# Body frame: x forward, y left, z up, origin on the ground under the creature.

"Actions a creature can perform. Append only: the index is what the log stores."
const ACTION_CODES = Symbol[:idle, :walk, :run, :eat, :sleep, :talk, :dance, :jump, :sit, :wave, :play, :swim,
                            # feelings (faces.jl): short reactions, see `feel!`
                            :laugh, :cry, :pout, :gasp, :think, :proud, :shy, :yawn, :sigh, :scared, :angry]

action_code(a::Symbol) = UInt8(something(findfirst(==(a), ACTION_CODES), 1))
action_name(code::Integer) = 1 <= code <= length(ACTION_CODES) ? ACTION_CODES[code] : :idle

"Register a new action (plugins). Returns its code."
function register_action!(a::Symbol)
    a in ACTION_CODES || push!(ACTION_CODES, a)
    return action_code(a)
end

const QID = Quaternionf(0, 0, 0, 1)

"Rotation from (roll, pitch, yaw) in radians: yaw ∘ pitch ∘ roll."
euler(v::Vec3f) = qrotation(Vec3f(0, 0, 1), v[3]) * qrotation(Vec3f(0, 1, 0), v[2]) * qrotation(Vec3f(1, 0, 0), v[1])

"The same rotation seen in a mirror at y = 0 (an axial vector flips x and z)."
mirror(q::Quaternionf) = (d = q.data; Quaternionf(-d[1], d[2], -d[3], d[4]))
mirror(v::Vec3f) = Vec3f(v[1], -v[2], v[3])

"What one part sees when it is posed."
struct PoseCtx
    action::Symbol
    phase::Float32    # gait cycle, radians, grows while walking
    mood::Float32     # -1 sad … 1 happy
    extra::Float32    # action specific: jump height, talk loudness, sleep depth
    seed::Float32     # per creature, 0…1, desynchronises idle motion
    t::Float32        # sim time
    side::Float32     # 1, or -1 for the mirrored copy of a part
end

# ── how the whole body moves ────────────────────────────────────────────────

"Body offset (`lift`), squash (> 0 flattens, < 0 stretches) and lean (roll, pitch, yaw)."
struct BodyPose
    lift::Float32
    squash::Float32
    lean::Vec3f
end

breath(c::PoseCtx) = 0.025f0 * sin(1.7f0 * c.t + 6.28f0 * c.seed)

body_pose(::Val, c::PoseCtx) = BodyPose(0.0f0, breath(c), Vec3f(0, 0, 0.06f0 * sin(0.37f0 * c.t + 9c.seed)))
body_pose(::Val{:walk}, c::PoseCtx) =
    BodyPose(0.07f0 * abs(sin(c.phase)), 0.06f0 * cos(2c.phase), Vec3f(0.06f0 * sin(c.phase), 0.06f0, 0))
body_pose(::Val{:run}, c::PoseCtx) =
    BodyPose(0.16f0 * abs(sin(c.phase)), 0.12f0 * cos(2c.phase), Vec3f(0.08f0 * sin(c.phase), 0.18f0, 0))
body_pose(::Val{:sleep}, c::PoseCtx) =
    BodyPose(-0.04f0, 0.14f0 + 0.04f0 * sin(0.9f0 * c.t), Vec3f(0.22f0, 0.05f0, 0))
body_pose(::Val{:eat}, c::PoseCtx) =
    BodyPose(0.0f0, 0.04f0, Vec3f(0, 0.32f0 + 0.08f0 * sin(7c.t), 0))
body_pose(::Val{:talk}, c::PoseCtx) =
    BodyPose(0.02f0 * abs(sin(5c.t)), 0.05f0 * c.extra * sin(11c.t), Vec3f(0, -0.04f0, 0.1f0 * sin(1.3f0 * c.t)))
body_pose(::Val{:dance}, c::PoseCtx) =
    BodyPose(0.1f0 * abs(sin(4c.t)), 0.12f0 * cos(8c.t), Vec3f(0.3f0 * sin(4c.t), 0, 0.5f0 * sin(2c.t)))
function body_pose(::Val{:jump}, c::PoseCtx)
    # extra: height above ground; squash on take off and landing, stretch in the air
    h = c.extra
    return BodyPose(h, h < 0.05f0 ? 0.2f0 : -0.15f0, Vec3f(0, -0.1f0, 0))
end
body_pose(::Val{:sit}, c::PoseCtx) = BodyPose(-0.05f0, 0.12f0 + breath(c), Vec3f(0, -0.15f0, 0))
body_pose(::Val{:wave}, c::PoseCtx) = BodyPose(0.0f0, breath(c), Vec3f(-0.08f0, -0.05f0, 0))
body_pose(::Val{:play}, c::PoseCtx) =
    BodyPose(0.25f0 * abs(sin(c.phase)), 0.15f0 * cos(2c.phase), Vec3f(0, 0.1f0 * sin(c.phase), 0.2f0 * sin(c.phase / 2)))
body_pose(::Val{:swim}, c::PoseCtx) =
    BodyPose(-0.25f0 + 0.04f0 * sin(2c.t), 0.0f0, Vec3f(0.1f0 * sin(c.phase), 0.05f0, 0))
# feelings: the whole body says it too (lean = roll, pitch (+ forward), yaw)
body_pose(::Val{:laugh}, c::PoseCtx) =          # shaking with laughter, leaning back
    BodyPose(0.03f0 * abs(sin(9c.t)), 0.08f0 * cos(18c.t), Vec3f(0.08f0 * sin(9c.t), -0.14f0, 0))
body_pose(::Val{:cry}, c::PoseCtx) =            # hunched, sobbing
    BodyPose(-0.02f0, 0.1f0 + 0.04f0 * abs(sin(7c.t)), Vec3f(0, 0.2f0, 0))
body_pose(::Val{:pout}, c::PoseCtx) =           # turned half away
    BodyPose(0.0f0, 0.06f0 + breath(c), Vec3f(0, 0.04f0, 0.45f0))
body_pose(::Val{:gasp}, c::PoseCtx) =           # pulled up tall, rocked back
    BodyPose(0.04f0, -0.12f0, Vec3f(0, -0.18f0, 0))
body_pose(::Val{:think}, c::PoseCtx) =          # head tilted, a slow sway
    BodyPose(0.0f0, breath(c), Vec3f(0.16f0, 0.02f0, 0.12f0 * sin(0.6f0 * c.t)))
body_pose(::Val{:proud}, c::PoseCtx) =          # chest out, standing tall
    BodyPose(0.02f0, -0.08f0 + breath(c), Vec3f(0, -0.2f0, 0))
body_pose(::Val{:shy}, c::PoseCtx) =            # turned away, swaying a little
    BodyPose(0.0f0, 0.04f0, Vec3f(0.12f0 + 0.05f0 * sin(2c.t), 0.12f0, 0.35f0))
body_pose(::Val{:yawn}, c::PoseCtx) =           # stretches up with the yawn
    (y = yawning(c); BodyPose(0.0f0, -0.12f0y + breath(c), Vec3f(0, -0.22f0y, 0)))
body_pose(::Val{:sigh}, c::PoseCtx) =           # slumped, breathing out slowly
    BodyPose(-0.02f0, 0.12f0 + 0.05f0 * sin(0.8f0 * c.t), Vec3f(0, 0.14f0, 0))
body_pose(::Val{:scared}, c::PoseCtx) =         # shrunk back, trembling
    BodyPose(0.0f0, 0.1f0, Vec3f(0.04f0 * sin(40c.t), -0.12f0, 0))
body_pose(::Val{:angry}, c::PoseCtx) =          # leaning in, huffing
    BodyPose(0.0f0, 0.05f0 + 0.04f0 * abs(sin(10c.t)), Vec3f(0, 0.18f0, 0.03f0 * sin(25c.t)))

# Flying (s75, goal 6: Lumi flew upright in its standing pose). Plugins set `:fly` while a creature is in
# the air and `extra` to how hard it works: 1 a takeoff or a landing flare (upright, wings beating, feet
# down), 0 cruising (tipped forward along the flight, feet tucked, beats in bursts and glides between).
register_action!(:fly)
"The wing beat's phase (3.2 beats a second)."
fly_beat(c::PoseCtx) = 2f0 * Float32(pi) * 3.2f0 * c.t + 6.28f0 * c.seed
"How hard the wings beat now (0 a glide … 1): always when it works hard, in bursts when it cruises."
fly_flap(c::PoseCtx) = max(c.extra, clamp(0.5f0 + 1.6f0 * sin(1.8f0 * c.t + 3c.seed), 0f0, 1f0))
# the body rises on each downstroke; tipped forward it sinks about the feet, so it is lifted to match.
# At `extra` 1 it leans back like `:proud` (chest out, -0.2), so a plugin can switch between the two without a snap.
body_pose(::Val{:fly}, c::PoseCtx) =
    BodyPose(0.3f0 * (1f0 - c.extra) - 0.06f0 * fly_flap(c) * sin(fly_beat(c)), 0.03f0 * fly_flap(c) * cos(fly_beat(c)),
             Vec3f(0.05f0 * sin(0.9f0 * c.t + 6c.seed), 0.95f0 - 1.15f0 * c.extra, 0))

# ── how single parts move ───────────────────────────────────────────────────

abstract type Motion end

"Follows the body."
struct Rigid <: Motion end

"""
Swings about a body frame `axis` through `pivot` (relative to the part's
centre). `gait = true` swings with the gait phase instead of time.
"""
struct Swing <: Motion
    axis::Vec3f
    amp::Float32
    freq::Float32
    offset::Float32
    gait::Bool
    pivot::Vec3f
end
Swing(axis, amp, freq; offset = 0, gait = false, pivot = Vec3f(0)) =
    Swing(Vec3f(axis), Float32(amp), Float32(freq), Float32(offset), gait, Vec3f(pivot))

"A foot or leg: lifts and strides with the gait. `offset` is its phase in the cycle."
struct Step <: Motion
    lift::Float32
    stride::Float32
    offset::Float32
end
Step(lift, stride; offset = 0) = Step(Float32(lift), Float32(stride), Float32(offset))

"Wobbles in size: wool puffs, jelly."
struct Jiggle <: Motion
    amp::Float32
    freq::Float32
    offset::Float32
end
Jiggle(amp, freq; offset = 0) = Jiggle(Float32(amp), Float32(freq), Float32(offset))
"An arm or wing: swings when walking, waves, goes up when dancing."
struct Arm <: Motion end

const NOMOVE = (Vec3f(0), QID, Vec3f(1))

swing_gain(::Val) = 1.0f0
swing_gain(::Val{:sleep}) = 0.1f0
swing_gain(::Val{:sit}) = 0.5f0
swing_gain(::Val{:dance}) = 2.2f0
swing_gain(::Val{:run}) = 1.6f0
swing_gain(::Val{:play}) = 1.8f0
swing_gain(::Val{:talk}) = 1.3f0

step_gain(::Val) = 0.0f0
step_gain(::Val{:walk}) = 1.0f0
step_gain(::Val{:run}) = 1.5f0
step_gain(::Val{:play}) = 0.8f0
step_gain(::Val{:swim}) = 0.7f0

"`(Δoffset, Δrotation, Δscale)` of a part in the body frame."
animate(::Rigid, c::PoseCtx) = NOMOVE

function animate(m::Swing, c::PoseCtx)
    clock = m.gait ? c.phase : c.t
    a = swing_gain(Val(c.action)) * m.amp * (1 + 0.4f0 * c.mood) * sin(m.freq * clock + m.offset + 6.28f0 * c.seed)
    q = qrotation(m.axis, a)
    return (q * (-m.pivot) + m.pivot, q, Vec3f(1))
end

function animate(m::Step, c::PoseCtx)
    g = step_gain(Val(c.action))
    φ = c.phase + m.offset + (c.side < 0 ? Float32(pi) : 0.0f0)
    g == 0 && c.action === :dance && return (Vec3f(0, 0, 0.05f0 * max(0, sin(8c.t + (c.side < 0 ? 3.14f0 : 0)))), QID, Vec3f(1))
    return (Vec3f(g * m.stride * sin(φ), 0, g * m.lift * max(0, cos(φ))), qrotation(Vec3f(0, 1, 0), -0.4f0 * g * sin(φ)), Vec3f(1))
end

function animate(m::Jiggle, c::PoseCtx)
    k = swing_gain(Val(c.action))
    w = k * m.amp * sin(m.freq * c.t + m.offset + 6.28f0 * c.seed)
    return (Vec3f(0, 0, 0.3f0 * w), QID, Vec3f(1 + w, 1 + w, 1 - w))
end

function animate(::Arm, c::PoseCtx)
    a = c.action
    roll, pitch = if a === :wave && c.side > 0
        (2.3f0 + 0.45f0 * sin(11c.t), 0.0f0)
    elseif a === :dance
        (1.4f0 + 0.6f0 * sin(8c.t + c.side), 0.3f0 * sin(4c.t))
    elseif a === :walk || a === :run || a === :play
        (0.15f0, 0.7f0 * step_gain(Val(a)) * sin(c.phase + (c.side < 0 ? 3.14f0 : 0)))
    elseif a === :sleep
        (-0.1f0, 0.0f0)
    elseif a === :cry || a === :shy                # hands up to the face
        (1.9f0 + 0.1f0 * sin(7c.t), -0.6f0)
    elseif a === :proud                            # hands on the hips
        (0.9f0, 0.6f0)
    elseif a === :scared || a === :gasp            # hands up, trembling
        (2.1f0 + 0.08f0 * sin(40c.t), -0.3f0)
    elseif a === :laugh                            # holding the belly
        (0.7f0 + 0.15f0 * sin(18c.t), -0.7f0)
    elseif a === :think                            # a hand to the chin
        c.side > 0 ? (1.7f0, -1.0f0) : (0.15f0, 0.0f0)
    elseif a === :yawn                             # a big stretch
        (0.6f0 + 2.0f0 * yawning(c), 0.0f0)
    elseif a === :angry                            # stiff arms, shaking fists
        (0.35f0, 0.12f0 * sin(25c.t))
    elseif a === :sigh || a === :pout              # arms hang
        (0.05f0, 0.1f0)
    else
        (0.1f0 + 0.05f0 * sin(1.7f0 * c.t + 6c.seed), 0.0f0)
    end
    q = qrotation(Vec3f(0, 1, 0), pitch) * qrotation(Vec3f(1, 0, 0), roll)
    # arms hinge at the shoulder, the top end of the capsule
    pivot = Vec3f(0, 0, 0.1f0)
    return (q * (-pivot) + pivot, q, Vec3f(1))
end

# ── parts and species ───────────────────────────────────────────────────────

struct Part
    name::Symbol
    shape::Symbol       # a key of `SHAPES`
    material::Any       # a Hikari material
    offset::Vec3f       # body frame, metres
    scale::Vec3f        # of the unit shape
    tilt::Vec3f         # rest rotation (roll, pitch, yaw)
    motion::Motion
    anchor::Symbol      # :body follows bounce/lean/squash, :ground does not (feet)
    mirror::Bool        # a second copy mirrored to -y
    attributes::NamedTuple   # more for its meshscatter: a texture `color` for a mesh shape, a `depth_shift`
end

part(name, shape, offset, scale; material, tilt = Vec3f(0), motion = Rigid(), anchor = :body, mirror = false,
     attributes = (;)) =
    Part(name, shape, material, Vec3f(offset), Vec3f(scale), Vec3f(tilt), motion, anchor, mirror, attributes)

"Number of instances a part contributes per creature."
ncopies(p::Part) = p.mirror ? 2 : 1

struct Species
    name::String
    blurb::String
    parts::Vector{Part}
    height::Float32        # top of the head, for speech bubbles and name tags
    speed::Float32         # walking speed m/s
    stride::Float32        # gait radians per metre
    heading::Float32       # body yaw relative to the walking direction (crabs!)
    sounds::Vector{String} # what it says when it has nothing to say
end

"Radius of the body footprint: how far apart two creatures stand to talk."
body_radius(sp::Species) = maximum(norm(Vec2f(p.offset[1], p.offset[2])) + maximum(p.scale) * shape_radius(p.shape) for p in sp.parts)

const SPECIES = Dict{String,Species}()

register_species!(s::Species) = (SPECIES[s.name] = s)

"""
    pose_parts!(out, sp, pos, yaw, action, phase, mood, extra, seed, t)

World transforms of all part instances of one creature, appended per part to
`out[j] = (positions, rotations, scales)`. Given a fourth vector, a part that
`paints` (a face card) adds the creature's uv transform to it.
"""
push_uv!(o::NTuple{4,Any}, uv) = push!(o[4], uv)
push_uv!(o, uv) = o                    # the caller asked for transforms only (outfits)

function pose_parts!(out, sp::Species, pos::Point3f, yaw::Float32, action::Symbol, phase::Float32,
                     mood::Float32, extra::Float32, seed::Float32, t::Float32)
    c = PoseCtx(action, phase, mood, extra, seed, t, 1.0f0)
    b = body_pose(Val(action), c)
    qyaw = qrotation(Vec3f(0, 0, 1), yaw + sp.heading)
    qbody = qyaw * euler(b.lean)
    S = Vec3f(1 + b.squash / 2, 1 + b.squash / 2, 1 - b.squash)
    lift = Vec3f(0, 0, b.lift)
    for (j, p) in enumerate(sp.parts)
        ps, rs, ss = out[j]
        for side in (p.mirror ? (1.0f0, -1.0f0) : (1.0f0,))
            cs = PoseCtx(action, phase, mood, extra, seed, t, side)
            paints(p.motion) && push_uv!(out[j], face_uv(p.motion, cs))
            Δo, Δq, Δs = animate(p.motion, cs)
            off = p.offset + Δo
            q = euler(p.tilt) * Δq
            if side < 0
                off = mirror(off); q = mirror(q)
            end
            if p.anchor === :ground
                push!(ps, pos + qyaw * off); push!(rs, qyaw * q); push!(ss, p.scale .* Δs)
            else
                push!(ps, pos + qyaw * lift + qbody * (S .* off)); push!(rs, qbody * q); push!(ss, S .* p.scale .* Δs)
            end
        end
    end
    return out
end

# ── the catalog ─────────────────────────────────────────────────────────────

glossy(c; r = 0.25) = Hikari.Plastic(color = c, roughness = r)
const EYE_WHITE = (0.97, 0.97, 0.96)
# eyes 25-50% bigger in s45 (perfectionist-0043: "the eyes are tiny"; the Fluffkin's vanished on its dark face)
const PUPIL = (0.015, 0.015, 0.02)

"""
Lumi: the big yellow bird from the human's CrawCity film (bird.jl), with a
face painted for every feeling (paintedface.jl).
"""
lumi() = Species("Lumi", "A big shaggy golden bird with a spiky crest and long grey legs. The island's caretaker, builder and chronicler.",
                   lumi_bird(), 1.7f0, 1.1f0, 8.0f0, 0.0f0, ["hm!", "ooh", "tadaa", "*hums*"])

function snootle()
    # a piglet on real legs (perfectionist s40: "pink spheres with stub feet"): body raised 0.12 m on
    # four trotters, big floppy ears, a curly tail up high
    pink = glossy((0.98, 0.68, 0.72); r = 0.45)
    hoof = glossy((0.55, 0.32, 0.34); r = 0.4)
    parts = [
        part(:body, :sphere, (0, 0, 0.54), (0.5, 0.34, 0.31); material = pink),
        part(:head, :sphere, (0.44, 0, 0.7), (0.25, 0.24, 0.23); material = pink,
             motion = Swing((0, 1, 0), 0.08, 1.0; gait = true)),
        part(:snoot, :capsule, (0.74, 0, 0.66), (0.07, 0.07, 0.08); material = glossy((0.96, 0.58, 0.64); r = 0.35),
             tilt = (0, 1.75, 0), motion = Swing((0, 0, 1), 0.2, 3.0; pivot = (-0.1, 0, 0))),
        face_parts(eye = (0.6, 0.12, 0.81, 0.1), mouth = (0.65, 0.6, 0.06), brow = (0.58, 0.93),
                   skin = (0.98, 0.68, 0.72), cheek = (0.62, 0.15, 0.66))...,
        part(:ear, :sphere, (0.38, 0.19, 0.93), (0.16, 0.045, 0.12); material = glossy((0.95, 0.52, 0.6); r = 0.5),
             tilt = (0.9, 0.5, 0), motion = Swing((1, 0, 0), 0.45, 1.0; gait = true, pivot = (0, -0.05, -0.08)), mirror = true),
        part(:tail, :torus, (-0.53, 0, 0.7), (0.075, 0.075, 0.075); material = pink, tilt = (0, 1.2, 0),
             motion = Swing((0, 0, 1), 0.8, 6.0)),
        part(:frontleg, :capsule, (0.27, 0.16, 0.16), (0.07, 0.07, 0.13); material = hoof,
             motion = Step(0.09, 0.12), anchor = :ground, mirror = true),
        part(:backleg, :capsule, (-0.27, 0.16, 0.16), (0.07, 0.07, 0.13); material = hoof,
             motion = Step(0.09, 0.12; offset = pi), anchor = :ground, mirror = true),
    ]
    return Species("Snootle", "A piglet with a nose too long for its own good. Sniffs everything, twice.",
                   parts, 1.05f0, 1.3f0, 10.0f0, 0.0f0, ["snrk", "oink?", "*sniff sniff*", "hrmf"])
end

function fluffkin()
    wool = Hikari.DiffuseTransmission(reflectance = (0.96, 0.95, 0.92), transmittance = (0.3, 0.3, 0.28))
    dark = glossy((0.2, 0.16, 0.18); r = 0.55)
    puff(name, o, r, k) = part(name, :sphere, o, (r, r, r); material = wool, motion = Jiggle(0.04, 3.0; offset = k))
    parts = [
        puff(:puff_top, (0, 0, 0.78), 0.3, 0.0),
        puff(:puff_front, (0.2, 0, 0.66), 0.26, 1.0),
        puff(:puff_back, (-0.3, 0, 0.62), 0.27, 2.0),
        part(:puff_side, :sphere, (0.1, 0.2, 0.58), (0.27, 0.27, 0.27); material = wool, motion = Jiggle(0.05, 2.6), mirror = true),
        part(:puff_rear, :sphere, (-0.15, 0.2, 0.6), (0.27, 0.27, 0.27); material = wool, motion = Jiggle(0.05, 3.3), mirror = true),
        part(:belly, :sphere, (0, 0, 0.48), (0.4, 0.3, 0.24); material = wool),
        part(:face, :sphere, (0.4, 0, 0.56), (0.17, 0.15, 0.19); material = dark),
        face_parts(eye = (0.52, 0.085, 0.62, 0.085), mouth = (0.56, 0.5, 0.05), brow = (0.5, 0.73),
                   skin = (0.2, 0.16, 0.18), ink = INK_PALE)...,
        part(:ear, :sphere, (0.35, 0.17, 0.62), (0.09, 0.035, 0.05); material = dark, tilt = (-0.5, 0, 0.3),
             motion = Swing((1, 0, 0), 0.3, 1.0; gait = true, pivot = (0, -0.06, 0)), mirror = true),
        part(:frontleg, :cylinder, (0.18, 0.12, 0), (0.035, 0.035, 0.4); material = dark,
             motion = Step(0.06, 0.06), anchor = :ground, mirror = true),
        part(:backleg, :cylinder, (-0.2, 0.12, 0), (0.035, 0.035, 0.4); material = dark,
             motion = Step(0.06, 0.06; offset = pi), anchor = :ground, mirror = true),
    ]
    return Species("Fluffkin", "A cloud that decided to become a sheep. Very soft, slightly smug.",
                   parts, 1.1f0, 0.9f0, 12.0f0, 0.0f0, ["baa", "mbeh", "*fluffs up*", "bleat."])
end

function blorbo()
    # a gummy jelly, not clear glass: Glass showed the meadow through the body in path tracing and the
    # blorbo read as an empty bubble (host, dance take 9, s50); a glossy mint plastic reads the same in
    # the raster and the tracer
    jelly = glossy((0.45, 0.88, 0.72); r = 0.1)
    parts = [
        part(:body, :sphere, (0, 0, 0.36), (0.4, 0.4, 0.36); material = jelly, motion = Jiggle(0.03, 2.0)),
        part(:core, :sphere, (0, 0, 0.32), (0.12, 0.12, 0.12); material = glossy((1.0, 0.78, 0.25); r = 0.2),
             motion = Jiggle(0.1, 4.0)),
        face_parts(eye = (0.25, 0.14, 0.56, 0.11), mouth = (0.395, 0.32, 0.08), brow = (0.22, 0.7),
                   skin = (0.45, 0.88, 0.72), cheek = (0.32, 0.22, 0.42))...,
        part(:antenna, :cylinder, (0, 0, 0.68), (0.015, 0.015, 0.2); material = glossy((0.4, 0.8, 0.6)),
             motion = Swing((1, 0, 0), 0.3, 2.0)),
        part(:bobble, :sphere, (0, 0, 0.9), (0.05, 0.05, 0.05); material = glossy((1.0, 0.9, 0.3); r = 0.15),
             motion = Swing((1, 0, 0), 0.3, 2.0; pivot = (0, 0, -0.22))),
    ]
    return Species("Blorbo", "A wobbly jelly blob with a glowing yolk. Bounces instead of walking.",
                   parts, 0.95f0, 0.8f0, 14.0f0, 0.0f0, ["blorb", "*wobble*", "bloop!", "glrb"])
end

function crabbit()
    # half crab, half bunny: a shell up on six long jointy legs, big claws, tall bunny ears
    # (perfectionist s40: the creatures read as spheres with stub feet)
    shell = glossy((0.95, 0.42, 0.28); r = 0.2)
    white = glossy((0.97, 0.9, 0.88); r = 0.5)
    parts = [
        part(:body, :sphere, (0, 0, 0.4), (0.3, 0.4, 0.2); material = shell),
        part(:stalk, :cylinder, (0.12, 0.1, 0.5), (0.022, 0.022, 0.16); material = shell, mirror = true),
        face_parts(eye = (0.12, 0.1, 0.72, 0.09), mouth = (0.3, 0.38, 0.07), brow = (0.12, 0.86),
                   skin = (0.95, 0.42, 0.28))...,
        part(:ear, :capsule, (-0.04, 0.09, 0.84), (0.05, 0.028, 0.18); material = white, tilt = (0.3, -0.1, 0),
             motion = Swing((0, 1, 0), 0.3, 1.5; pivot = (0, 0, -0.18)), mirror = true),
        part(:claw, :sphere, (0.36, 0.36, 0.36), (0.14, 0.09, 0.1); material = shell, tilt = (0, 0, 0.4),
             motion = Swing((0, 0, 1), 0.4, 4.0), mirror = true),
        part(:leg1, :capsule, (0.13, 0.44, 0.16), (0.03, 0.03, 0.13); material = shell, tilt = (0.75, 0, 0),
             motion = Step(0.08, 0.08), anchor = :ground, mirror = true),
        part(:leg2, :capsule, (0, 0.47, 0.16), (0.03, 0.03, 0.13); material = shell, tilt = (0.75, 0, 0),
             motion = Step(0.08, 0.08; offset = 2.1), anchor = :ground, mirror = true),
        part(:leg3, :capsule, (-0.13, 0.44, 0.16), (0.03, 0.03, 0.13); material = shell, tilt = (0.75, 0, 0),
             motion = Step(0.08, 0.08; offset = 4.2), anchor = :ground, mirror = true),
        part(:tail, :sphere, (-0.3, 0, 0.42), (0.09, 0.09, 0.09); material = white, motion = Jiggle(0.1, 5.0)),
    ]
    return Species("Crabbit", "Half crab, half bunny, fully confused about which way is forward.",
                   parts, 1.0f0, 1.0f0, 16.0f0, Float32(pi / 2), ["click click", "*hops sideways*", "pinch?", "snip!"])
end

function init_species!()
    for s in (lumi(), snootle(), fluffkin(), blorbo(), crabbit())
        register_species!(s)
    end
    return SPECIES
end
