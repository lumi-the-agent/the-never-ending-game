# ── Faces: what a creature feels, readable from a few steps away ────────────
#
# A face is a pure function of the numbers the frame log records (action,
# mood, extra) and the time, like every other part of the body (species.jl),
# so replays and films show the same faces as the live game.
#
# Each action has a `Face`: how much the mouth smiles or frowns and opens, where
# the brows sit, how far the upper lids come down, whether the eyes close into
# happy ^ ^ arcs, blush, tears, a sweat drop and where the pupils look. Plain
# actions (idle, walk, talk, sit, ...) show the creature's mood (-1 sad ...
# 1 happy). The emotional actions (`:laugh`, `:cry`, `:pout`, `:gasp`, `:think`,
# `:proud`, `:shy`, `:yawn`, `:sigh`, `:scared`, `:angry`) are short reactions
# plugins start with `feel!` (behavior.jl), and they move the body and arms too.
#
# The parts: googly eyes with pupils (`Blink`, `Look`), a skin coloured upper lid
# per eye (`Lid`), two ink strokes per eye for the ^ (`JoyStroke`), a brow per eye
# (`Brow`), a mouth line of three strokes that bends into a smile or a frown
# (`MouthLine`), a dark oval for an open mouth (`Mouth`), cheeks (`Blush`), a
# tear per eye (`Tear`) and a sweat drop (`Sweat`). `face_parts` builds them all
# for a species from where its eyes and mouth sit.

"How a face looks: each number 0…1 unless noted."
struct Face
    smile::Float32    # mouth line: -1 frown … 1 big smile
    open::Float32     # mouth open (gasp, laugh, wail)
    brow::Float32     # inner brow ends: -1 up (sad, worried) … 1 down (angry)
    raise::Float32    # brows up (surprise, curiosity)
    lid::Float32      # upper lids down (tired, bored, smug)
    joy::Float32      # eyes closed into ^ ^
    wide::Float32     # eyes bigger, pupils smaller (surprise, fear)
    blush::Float32
    tears::Float32
    sweat::Float32
    gaze::Vec2f       # where the pupils look: (to the creature's left, up), -1…1
end

Face(; smile = 0, open = 0, brow = 0, raise = 0, lid = 0, joy = 0, wide = 0, blush = 0, tears = 0, sweat = 0, gaze = (0, 0)) =
    Face(Float32(smile), Float32(open), Float32(brow), Float32(raise), Float32(lid), Float32(joy), Float32(wide),
         Float32(blush), Float32(tears), Float32(sweat), Vec2f(gaze...))

"The resting face: it shows the mood (-1 sad … 1 happy)."
calm(c::PoseCtx) = Face(smile = 0.1f0 + 0.6f0 * c.mood, brow = min(0.0f0, 1.2f0 * (c.mood + 0.25f0)),
                        lid = c.mood < -0.45f0 ? 0.3f0 : 0.0f0, gaze = (0.35f0 * sin(0.7f0 * c.t + 13c.seed),
                                                                       0.25f0 * sin(1.13f0 * c.t + 7c.seed) + min(0.0f0, 0.5f0 * c.mood)))

face(::Val, c::PoseCtx) = calm(c)
face(::Val{:sleep}, c::PoseCtx) = Face(lid = 1, smile = 0.2)
face(::Val{:dance}, c::PoseCtx) = Face(joy = 1, smile = 1, open = 0.35, blush = 0.5)
face(::Val{:jump}, c::PoseCtx) = Face(joy = 1, smile = 1, open = 0.45)
face(::Val{:wave}, c::PoseCtx) = Face(joy = 1, smile = 0.9)
face(::Val{:play}, c::PoseCtx) = Face(smile = 1, open = 0.35, raise = 0.4)
# `extra` while running: glee (tag players laugh as they run)
face(::Val{:run}, c::PoseCtx) = c.extra > 0.5f0 ? Face(joy = 1, smile = 1, open = 0.5) : calm(c)
face(::Val{:laugh}, c::PoseCtx) = Face(joy = 1, smile = 1, open = 0.75 + 0.2 * abs(sin(9c.t)), blush = 0.4)
face(::Val{:cry}, c::PoseCtx) = Face(smile = -0.9, open = 0.3 + 0.15 * abs(sin(6c.t)), brow = -1, lid = 0.35, tears = 1,
                                     gaze = (0, -0.4))
face(::Val{:pout}, c::PoseCtx) = Face(smile = -0.6, brow = 0.55, lid = 0.25, blush = 0.3, gaze = (0.7, -0.3))
face(::Val{:gasp}, c::PoseCtx) = Face(open = 1, wide = 1, raise = 1)
face(::Val{:think}, c::PoseCtx) = Face(smile = -0.15, raise = 0.55, brow = 0.2, gaze = (0.6 + 0.2 * sin(0.8c.t), 0.85))
face(::Val{:proud}, c::PoseCtx) = Face(smile = 0.85, lid = 0.42, raise = 0.2, blush = 0.25)
face(::Val{:shy}, c::PoseCtx) = Face(smile = 0.45, blush = 1, lid = 0.3, gaze = (0.7, -0.6))
face(::Val{:yawn}, c::PoseCtx) = (y = yawning(c); Face(open = y, lid = 0.4 + 0.5y, raise = 0.4y, smile = -0.1))
face(::Val{:sigh}, c::PoseCtx) = Face(smile = -0.3, brow = -0.35, lid = 0.55, gaze = (0.2, -0.6))
face(::Val{:scared}, c::PoseCtx) = Face(smile = -0.55, open = 0.3, brow = -0.9, raise = 0.8, wide = 1, sweat = 1,
                                        gaze = (0.5 * sin(5c.t), 0))
face(::Val{:angry}, c::PoseCtx) = Face(smile = -0.75, brow = 1, lid = 0.12, blush = 0.7, gaze = (0, -0.1))
face(c::PoseCtx) = face(Val(c.action), c)

"How wide a yawn is at this moment (0…1, one yawn every 4 s)."
yawning(c::PoseCtx) = (f = mod(0.25f0 * c.t + c.seed, 1.0f0); f < 0.6f0 ? sin(Float32(pi) * f / 0.6f0)^2 : 0.0f0)

"How far the mouth is open: the face's own, or talking and chewing."
function mouth_open(c::PoseCtx, f::Face)
    talk = c.action === :talk ? 0.5f0 + 1.6f0 * clamp(c.extra, 0, 1) * abs(sin(13c.t + 5c.seed)) :
           c.action === :eat ? 0.6f0 + 0.8f0 * abs(sin(8c.t)) : 0.0f0
    return max(talk, 2.2f0 * f.open)
end

"Eyes blink every few seconds; they shut in sleep."
function blink(c::PoseCtx)
    c.action === :sleep && return 0.08f0
    f = mod(0.27f0 * c.t + c.seed, 1.0f0)
    return f < 0.035f0 ? 0.1f0 : 1.0f0
end

const NO_PART = (Vec3f(0), QID, Vec3f(0))

# ── the face's parts ────────────────────────────────────────────────────────
# Every motion is written for the left copy (y > 0); `pose_parts!` mirrors the
# right one, so anything that should not mirror (where the pupils look) flips
# with `c.side`.

"A googly eye (radius `r`): blinks, opens wide."
struct Blink <: Motion end
animate(::Blink, c::PoseCtx) = (w = 1 + 0.18f0 * face(c).wide; (Vec3f(0), QID, Vec3f(w, w, w * blink(c))))

"A pupil: looks where the face looks, shrinks with fright."
struct Look <: Motion
    r::Float32
end
function animate(m::Look, c::PoseCtx)
    c.action === :sleep && return NO_PART
    f = face(c)
    k = (1 - 0.35f0 * f.wide) * blink(c)
    return (Vec3f(0, c.side * 0.3f0 * m.r * f.gaze[1], 0.3f0 * m.r * f.gaze[2]), QID, Vec3f(1 - 0.35f0 * f.wide, 1 - 0.35f0 * f.wide, k))
end

"The upper lid over an eye of radius `r`, in skin colour: comes down with `lid` (all the way for ^ ^), slants with the brows."
struct Lid <: Motion
    r::Float32
end
function animate(m::Lid, c::PoseCtx)
    f = face(c)
    shut = f.joy > 0.5f0 ? 1.0f0 : f.lid
    shut < 0.04f0 && return NO_PART
    r = m.r
    bottom = r - 2.1f0 * r * shut                  # where the lid's edge is, from the eye's centre
    top = 1.06f0 * r
    h = (top - bottom) / 2
    q = qrotation(Vec3f(1, 0, 0), 0.18f0 * f.brow)
    return (Vec3f(0.42f0 * r, 0, bottom + h), q, Vec3f(0.74f0 * r, 0.94f0 * r, h))
end

"One stroke of the ^ over a closed happy eye (`outer` or the inner one)."
struct JoyStroke <: Motion
    r::Float32
    outer::Bool
end
function animate(m::JoyStroke, c::PoseCtx)
    face(c).joy > 0.5f0 || return NO_PART
    s = m.outer ? 1.0f0 : -1.0f0
    return (Vec3f(1.13f0 * m.r, s * 0.3f0 * m.r, 0.02f0 * m.r), qrotation(Vec3f(1, 0, 0), s * 0.85f0), Vec3f(0.1f0 * m.r, 0.1f0 * m.r, 0.28f0 * m.r))
end

"A brow (a short capsule lying across the face): up with surprise, slanted by the feeling."
struct Brow <: Motion
    r::Float32
end
function animate(m::Brow, c::PoseCtx)
    f = face(c)
    lift = (0.38f0 * f.raise - 0.1f0 * max(0.0f0, f.brow)) * m.r
    return (Vec3f(0, 0, lift), qrotation(Vec3f(1, 0, 0), Float32(pi / 2) + 0.42f0 * f.brow), Vec3f(1))
end

"""
The mouth line: three overlapping strokes, a middle one and two mirrored sides that bend up
into a smile or down into a frown. `w` is half the mouth's width. It gives way
to the open mouth.
"""
struct MouthLine <: Motion
    w::Float32
    middle::Bool
end
function animate(m::MouthLine, c::PoseCtx)
    f = face(c)
    v = clamp(1 - (mouth_open(c, f) - 0.25f0) / 0.5f0, 0, 1)
    v < 0.05f0 && return NO_PART
    across = qrotation(Vec3f(1, 0, 0), Float32(pi / 2))
    m.middle && return (Vec3f(0), across, Vec3f(v, v, v))
    a = 0.75f0 * f.smile                           # the corners turn up (smile) or down (frown) from the middle's ends
    return (Vec3f(0, 0, 0.32f0 * m.w * sin(a)), qrotation(Vec3f(1, 0, 0), Float32(pi / 2) + a), Vec3f(v, v, v))
end

"The open mouth: a dark oval, wider when smiling (a laugh), hidden when shut."
struct Mouth <: Motion end
function animate(::Mouth, c::PoseCtx)
    f = face(c)
    o = mouth_open(c, f)
    o < 0.15f0 && return NO_PART
    return (Vec3f(0), QID, Vec3f(1, 1 + 0.45f0 * max(0.0f0, f.smile) * min(1.0f0, o), o))
end

"Cheeks: glow with blush. `always`: the species has rosy cheeks even when calm."
struct Blush <: Motion
    always::Bool
end
function animate(m::Blush, c::PoseCtx)
    b = face(c).blush
    m.always || b > 0.15f0 || return NO_PART
    k = m.always ? 0.8f0 + 0.6f0 * b : 0.5f0 + 0.8f0 * b
    return (Vec3f(0), QID, Vec3f(k, k, k))
end

"A tear running down from under an eye of radius `r`."
struct Tear <: Motion
    r::Float32
end
function animate(m::Tear, c::PoseCtx)
    face(c).tears > 0.5f0 || return NO_PART
    k = mod(0.9f0 * c.t + 0.37f0 * c.side + c.seed, 1.0f0)
    return (Vec3f(-0.35f0 * m.r * k, 0, -1.7f0 * m.r * k), QID, Vec3f(1 - 0.4f0 * k))
end

"A sweat drop sliding down the side of the head."
struct Sweat <: Motion
    r::Float32
end
function animate(m::Sweat, c::PoseCtx)
    face(c).sweat > 0.5f0 || return NO_PART
    k = mod(0.7f0 * c.t + c.seed, 1.0f0)
    return (Vec3f(0, 0, -0.9f0 * m.r * k), QID, Vec3f(1))
end

const INK = (0.06, 0.025, 0.025)               # near black: lighting barely shows on it, so strokes read as lines
const INK_PALE = (0.97, 0.92, 0.82)
const TEAR = (0.55, 0.82, 1.0)

"""
    face_parts(; eye, mouth, skin, ink = INK, brow, cheek = nothing, rosy = false, pupil = 0.5)

All parts of a face. `eye = (x, y, z, r)`: the left eye's centre and radius;
`mouth = (x, z, w)`: the middle of the mouth and half its width; `brow = (x, z)`:
the left brow's centre (it has to sit on the head, which curves away above the
eyes); `skin`: the colour round the eyes, for the lids; `ink`: brows, mouth line
and the ^ strokes (pale on a dark face); `cheek = (x, y, z)`: where the left cheek
glows (`rosy`: always a little).
"""
function face_parts(; eye, mouth, skin, brow, ink = INK, cheek = nothing, rosy = false, pupil = 0.5)
    x, y, z, r = eye
    mx, mz, w = mouth
    t = 0.19f0 * w                                  # stroke thickness
    inkm = glossy(ink; r = 0.9)                     # matte: a glossy stroke shows a highlight and reads as beads
    parts = [
        part(:eye, :sphere, (x, y, z), (0.8r, 0.9r, r); material = glossy(EYE_WHITE; r = 0.05), motion = Blink(), mirror = true),
        part(:pupil, :sphere, (x + 0.78r, y, z + 0.05r), (0.35r, pupil * r, 1.1pupil * r);
             material = glossy(PUPIL; r = 0.02), motion = Look(r), mirror = true),
        part(:lid, :sphere, (x, y, z), (1, 1, 1); material = glossy(skin; r = 0.4), motion = Lid(r), mirror = true),
        part(:joy_outer, :capsule, (x, y, z), (1, 1, 1); material = inkm, motion = JoyStroke(r, true), mirror = true),
        part(:joy_inner, :capsule, (x, y, z), (1, 1, 1); material = inkm, motion = JoyStroke(r, false), mirror = true),
        part(:brow, :capsule, (brow[1], y, brow[2]), (0.17r, 0.17r, 0.33r); material = inkm, motion = Brow(r), mirror = true),
        # long thin ellipsoids, like brush strokes (short capsules shade like two beads)
        part(:mouth_line, :sphere, (mx, 0, mz), (t, t, 0.45w); material = inkm, motion = MouthLine(w, true)),
        part(:mouth_corner, :sphere, (mx - 0.01w, 0.62w, mz), (t, t, 0.34w); material = inkm, motion = MouthLine(w, false), mirror = true),
        part(:mouth, :sphere, (mx, 0, mz - 0.2w), (0.35w, 0.75w, 0.32w); material = glossy((0.3, 0.06, 0.1)), motion = Mouth()),
        part(:tear, :sphere, (x + 1.0r, y + 0.25r, z - 0.75r), (0.34r, 0.34r, 0.48r); material = glossy(TEAR; r = 0.05),
             motion = Tear(r), mirror = true),
        part(:sweat, :sphere, (x - 0.4r, y + 1.55r, z + 0.8r), (0.26r, 0.26r, 0.38r); material = glossy(TEAR; r = 0.05),
             motion = Sweat(r)),
    ]
    cheek === nothing || push!(parts, part(:cheek, :sphere, cheek, (0.4r, 0.64r, 0.36r); material = glossy((0.98, 0.5, 0.58); r = 0.6),
                                           tilt = (0, 0, 0.6), motion = Blush(rosy), mirror = true))
    return parts
end
