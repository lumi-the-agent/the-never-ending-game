# Night shots: while everyone sleeps, the follow camera stops staring at a heap of sleepers
# and shows the island at night like a film would: the cottage in its warm light, a lantern
# and its light pool, the moon over the island (sleeper close-ups: off, see the kinds). A new shot every
# SHOT_TIME seconds, each one drifting slowly sideways. Any moment worth watching (a chat,
# someone awake talking, a dance circle, a race) or a player at the keys takes the camera back.
const NG = NeverendingGame

const SHOT_TIME = 16.0          # seconds per shot
const DRIFT = 0.035f0           # rad/s the eye slides round its subject

mutable struct NightShots <: System
    game::Any
    kinds::Vector{Symbol}       # the shots of the current night, in order
    k::Int                      # current shot
    t0::Float64                 # when it started
    base::Tuple{Point3f,Point3f,Float32,Float32,Float32}   # centre of interest, look-at point, start angle, distance, height
    on::Bool
end
NightShots() = NightShots(nothing, Symbol[], 0, -1e9, (Point3f(0), Point3f(0), 0f0, 0f0, 0f0), false)

const CURRENT = Ref{Any}(nothing)

lumi_sleeps(w) = (c = NG.creature(w, "Lumi"); c !== nothing && (c.action === :sleep || c.goal.kind === :sleep))
"Shots on by day too (the UI test, a trailer)."
const FORCE = Ref(false)
quiet_night(w) = FORCE[] || NG.night_factor(w) > 0.6f0 && lumi_sleeps(w)

lights(game) = (l = get(game.plugins, "lamplight", nothing); l === nothing ? [] : Base.invokelatest(l.mod.light_sources, game))
moon_dir(game, w) = (m = get(game.plugins, "moon", nothing); m === nothing ? Vec3f(0, 0.7, 0.7) : Base.invokelatest(m.mod.moon_dir, w))

"Eye for the shot at drift angle `a` round `c` (distance `d`, height `h`), looking at `look`."
shot_eye(c, a, d, h, w) = (p = NG.ground(w.island, (c[1] + d * cos(a), c[2] + d * sin(a))); Point3f(p[1], p[2], max(p[3], c[3]) + h))

"How much actors, bushes, rocks and creatures fill the view from `eye` to `look` (trees are in `NG.obstruction`); `skip`: the subject."
function clutter(w, eye, look, skip, centre)
    o = 0f0
    for a in w.actors       # the cottage, lanterns, toadstools (the camera sat inside a toadstool)
        a isa NG.AssetActor || continue
        hypot(a.pos[1] - centre[1], a.pos[2] - centre[2]) < 0.3f0 && continue      # the subject itself
        o += max(0f0, 0.7f0 * a.scale + 0.3f0 - NG.segment_distance(eye, look, a.pos + Point3f(0, 0, 0.5f0 * a.scale)))
        o += 2 * max(0f0, a.scale + 0.8f0 - hypot(eye[1] - a.pos[1], eye[2] - a.pos[2]))
    end
    for p in w.props
        # the red ball too: left beside a sleeper it filled a third of the night shot (s44)
        p.kind in (:bush, :rock, :ball) || continue
        r = (p.kind === :bush ? 0.9f0 : p.kind === :ball ? 0.5f0 : 0.6f0) * p.scale + 0.25f0
        o += max(0f0, r - NG.segment_distance(eye, look, p.pos + Point3f(0, 0, p.kind === :ball ? 0f0 : 0.4f0 * p.scale)))
        p.kind === :ball && (o += max(0f0, 1.5f0 - norm(Vec3f(p.pos - eye))))
    end
    for c in w.creatures
        c.id == skip && continue
        r = NG.body_radius(NG.species_of(c)) + 0.3f0
        o += max(0f0, r - NG.segment_distance(eye, look, c.pos + Point3f(0, 0, 0.4f0)))
        o += max(0f0, 2.0f0 - norm(Vec3f(c.pos - eye)))      # nobody's ears in the foreground
    end
    return o
end

"Pick the clearest framing of shot `kind`: (centre, look-at, angle, distance, height), or nothing."
function frame_shot(game, kind; need_sleeper = false)
    w = game.world
    ls = lights(game)
    skip = 0
    centre, look, d, h = if kind === :cottage
        i = findfirst(l -> l[4] === :cottage, ls); i === nothing && return nothing
        p, _, s, _ = ls[i]
        p, p + Point3f(0, 0, 0.8f0 * s), 3.2f0 * max(s, 1f0), 1.6f0
    elseif kind === :lantern
        lan = filter(l -> l[4] === :lantern, ls); isempty(lan) && return nothing
        p, _, s, _ = lan[rand(w.rng, 1:length(lan))]
        p, p + Point3f(0, 0, 0.7f0 * s), 4.2f0, 0.9f0
    elseif kind === :pond || kind === :pier
        # the lily pond, and the old pier running out into the moonlit sea (review s31: more places at night)
        ar = get(game.plugins, "areas", nothing); ar === nothing && return nothing
        m = ar.mod
        if kind === :pond
            p = NG.ground(w.island, (m.POND[1], m.POND[2]))
            p, p + Point3f(0, 0, 0.2f0), 5.5f0, 2.8f0      # over the reeds, down onto the lily pads
        else
            mid = m.PIER_START + m.PIER_DIR * (0.6f0 * m.PIER_LEN)
            p = Point3f(mid[1], mid[2], m.PIER_DECK)
            p, p + Point3f(0, 0, 0.6f0), 5.5f0, 1.4f0
        end
    elseif kind === :sleeper
        # a sleeper on its own (a heap of sleepers is no picture)
        alone(c) = all(o -> o === c || hypot(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2]) > 2.5f0, w.creatures)
        sl = [c for c in w.creatures if c.action === :sleep && alone(c) && NG.on_land(w.island, c.pos[1], c.pos[2]; margin = 2f0)]
        isempty(sl) && return nothing
        c = sl[rand(w.rng, 1:length(sl))]
        # framed from its face like the sleepers in front of a place (the clearest of eight
        # directions round the island's middle showed backs)
        f = frame_with_sleeper(w, c, c.pos)
        f === nothing || (LAST_SLEEPER[] = c.id)
        return f
    else   # :moon: from the shore on the far side, across the island towards the moon
        md = moon_dir(game, w)
        back = -normalize(Vec2f(md[1], md[2]) + Vec2f(1f-4))
        r = 0.55f0 * w.island.radius
        c = NG.ground(w.island, (r * back[1], r * back[2]))
        return (c, c + Point3f(40md[1], 40md[2], 40md[3]), Float32(atan(back[2], back[1])), 0.01f0, 1.8f0)
    end
    # a sleeper near the place lies in the front of the picture, the lit place behind it
    # (perfectionist s33: night shots of empty scenery; every frame should hold a creature)
    if kind !== :sleeper
        for sl in sleepers_near(w, centre)
            f = frame_with_sleeper(w, sl, centre)
            f === nothing || (LAST_SLEEPER[] = sl.id; return f)
        end
        need_sleeper && return nothing      # no creature in it: the follow view of a sleeper is better (perfectionist s33)
    end
    # the clearest of eight directions, preferring the island's middle side
    a0 = Float32(atan(-centre[2], -centre[1]))
    best = nothing; bo = Inf32
    for da in (0f0, 0.4f0, -0.4f0, 0.8f0, -0.8f0, 1.2f0, -1.2f0, 1.6f0, -1.6f0, 2.1f0, -2.1f0, 2.6f0, -2.6f0, 3.14f0)
        a = a0 + da
        # the eye drifts during the shot: its start, middle and end must all see the subject
        eyes = [shot_eye(centre, a + DRIFT * Float32(f * SHOT_TIME), d, h, w) for f in (0.0, 0.25, 0.5, 0.75, 1.0)]
        all(e -> NG.on_land(w.island, e[1], e[2]; margin = 0.5f0), eyes) || continue
        o = maximum(e -> NG.obstruction(w, e, look) + clutter(w, e, look, skip, centre), eyes) + 0.05f0 * abs(da)
        o < bo && (best = (centre, look, a, d, h); bo = o)
    end
    return bo < (kind === :sleeper ? 0.3f0 : 0.6f0) ? best : nothing   # a sleeper in a nook of bushes is no picture
end

"The sleeping creatures within `SLEEPER_REACH` m of `place` (on land), closest first."
function sleepers_near(w, place)
    d(c) = hypot(c.pos[1] - place[1], c.pos[2] - place[2])
    cs = [c for c in w.creatures if c.action === :sleep && d(c) < SLEEPER_REACH && NG.on_land(w.island, c.pos[1], c.pos[2]; margin = 1.5f0)]
    return sort!(cs; by = c -> (c.id == LAST_SLEEPER[], d(c)))    # not the one of the last shot again
end
const LAST_SLEEPER = Ref{Int32}(0)
const FAILED = Ref(-1e9)      # when the last search for a shot found nothing
const SLEEPER_REACH = 60f0      # any sleeper: the closest to the place first (only some have a clear view: crowns over the beds)

"The meadow's grass tufts (plugins/meadow.jl), computed once per world."
function tufts(w)
    g = CURRENT[] === nothing ? nothing : CURRENT[].game
    me = g === nothing ? nothing : get(g.plugins, "meadow", nothing)
    me === nothing && return Point3f[]
    key = (length(w.props), w.island.seed)
    get(TUFTS, :key, nothing) == key && return TUFTS[:spots]
    spots = Base.invokelatest(me.mod.tuft_spots, w; in_the_way = Base.invokelatest(me.mod.area_check, g))
    TUFTS[:spots] = Point3f[sp[1] for sp in spots]; TUFTS[:key] = key
    return TUFTS[:spots]
end
const TUFTS = Dict{Symbol,Any}()

"Grass tufts and flowers between a low eye and a sleeper: a wall of leaves hid Hopscotch (s34)."
function undergrowth(w, eye, look)
    o = 0f0
    for t in tufts(w)
        o += 1.5f0 * max(0f0, 0.3f0 - NG.segment_distance(eye, look, t + Point3f(0, 0, 0.18f0)))
    end
    for p in w.props
        p.kind === :flower || continue
        o += 1.5f0 * max(0f0, 0.35f0 * p.scale + 0.1f0 - NG.segment_distance(eye, look, p.pos + Point3f(0, 0, 0.3f0 * p.scale)))
    end
    return o
end

"""
A low close shot of sleeper `c` with `place` behind it: the eye on the far side of the sleeper,
looking past it towards the place, the sleeper filling a good part of the picture.
"""
function frame_with_sleeper(w, c, place)
    hgt = NG.species_of(c).height
    to = Vec2f(place[1] - c.pos[1], place[2] - c.pos[2])
    # the eye in front of the sleeper's face (a back is no picture), turned a little towards the side away from the place
    face = c.yaw + NG.species_of(c).heading
    away = norm(to) < 0.5f0 ? face : Float32(atan(-to[2], -to[1]))
    a0 = face + 0.35f0 * clamp(Float32(rem2pi(away - face, RoundNearest)), -1f0, 1f0)
    d0 = 2.2f0 + 1.1f0 * clamp(hgt, 0.5f0, 1.5f0)
    # just past the sleeper, within 0.35 m (NG.obstruction does not count the creature at the target as a blocker)
    look_at(a) = (u = Vec2f(-cos(a), -sin(a)); c.pos + Point3f(0.25f0 * u[1], 0.25f0 * u[2], 0.45f0 * hgt))
    best = nothing; bo = Inf32
    # eye level first; higher eyes look down onto the sleeper, and the crowns of the tree it sleeps
    # under leave the top of the picture
    # (a steep eye showed the top of a head, s34 beds-nightshot-4: the higher eyes stand further back, ~20° down at most)
    for (d, h, cost) in ((d0, 0.55f0 + 0.45f0 * hgt, 0f0), (1.2f0 * d0, 1.0f0 + 0.5f0 * hgt, 0.2f0), (1.5f0 * d0, 1.5f0 + 0.5f0 * hgt, 0.35f0)),
        da in (0f0, 0.35f0, -0.35f0, 0.7f0, -0.7f0, 1.1f0, -1.1f0)
        # the face or the side, never the back: a sleeping Fluffkin's back filled a third of the
        # cottage shot for 15 s (review s44, s45 night grid)
        a = a0 + da
        look = look_at(a)
        eyes = [shot_eye(c.pos, a + DRIFT * Float32(f * SHOT_TIME), d, h, w) for f in (0.0, 0.25, 0.5, 0.75, 1.0)]
        all(e -> NG.on_land(w.island, e[1], e[2]; margin = 0.3f0), eyes) || continue
        raw = maximum(e -> NG.obstruction(w, e, look) + clutter(w, e, look, c.id, c.pos) + undergrowth(w, e, look), eyes)
        raw < 0.6f0 || continue                  # as clear as the place shots
        o = raw + 0.12f0 * abs(da) + cost        # the face and eye level preferred
        o < bo && (best = (c.pos, look, a, d, h); bo = o)
    end
    return best
end

function next_shot!(s::NightShots, w)
    game = s.game
    for _ in 1:length(s.kinds)
        s.k = mod1(s.k + 1, length(s.kinds))
        f = frame_shot(game, s.kinds[s.k]; need_sleeper = !FORCE[])
        if f !== nothing
            s.base = f; s.t0 = w.t
            return true
        end
    end
    return false
end

"The follow camera's quiet-night shot (engine `CAMERA_SHOTS`)."
function night_shot(w)
    s = CURRENT[]
    (s === nothing || !s.on) && return nothing
    c, look, a, d, h = s.base
    t = Float32(w.t - s.t0)
    if d < 0.1f0      # the moon shot: a slow crane up
        return c + Point3f(0, 0, h + 0.04f0 * t), look
    end
    return shot_eye(c, a + DRIFT * t, d, h, w), look
end

function NG.step!(s::NightShots, game, dt)
    w = game.world
    was = s.on
    s.on = quiet_night(w)
    s.on || return
    # no sleeper had a clear view a moment ago: the follow view, and look again in a while (not every frame)
    !was && w.t - FAILED[] < SHOT_TIME / 2 && (s.on = false; return)
    if !was || w.t - s.t0 > SHOT_TIME
        was || (s.kinds = [:cottage, :pond, :lantern, :pier, :lantern]; s.k = rand(w.rng, 0:5))   # :moon (an empty sky) is off: every shot holds a sleeper in front of its place
        next_shot!(s, w) || (s.on = false; FAILED[] = w.t)
    end
    return
end

function NG.start!(s::NightShots, game)
    s.game = game
    # the worker (no Revise) runs the engine it started with until its restart: no camera hook there yet,
    # and its traced stills do not need one
    isdefined(NG, :CAMERA_SHOTS) || return
    CURRENT[] = s
    NG.CAMERA_SHOTS["nightshots"] = night_shot
    # every camera (the follow view too) looks past bushes, not through them: a chat behind a
    # bush filled the follow view with leaves (s31 night samples)
    NG.CAMERA_BLOCKERS["bushes"] = (eye, target) -> bush_block(s.game.world, eye, target)
    # toadstools, the cottage, lanterns and rocks too: a red toadstool crown covered a third of
    # a daytime chat shot (review s31)
    NG.CAMERA_BLOCKERS["actors"] = (eye, target) -> actor_block(s.game.world, eye, target)
end

function actor_block(w, eye, target)
    o = 0f0
    for a in w.actors
        a isa NG.AssetActor || continue
        hypot(a.pos[1] - target[1], a.pos[2] - target[2]) < 1.2f0 && continue      # what the shot is about
        o += max(0f0, 0.6f0 * a.scale + 0.2f0 - NG.segment_distance(eye, target, a.pos + Point3f(0, 0, 0.5f0 * a.scale)))
        o += max(0f0, a.scale + 0.5f0 - hypot(eye[1] - a.pos[1], eye[2] - a.pos[2]))    # the eye inside it
    end
    for p in w.props
        p.kind === :rock || continue
        o += max(0f0, 0.6f0 * p.scale + 0.2f0 - NG.segment_distance(eye, target, p.pos + Point3f(0, 0, 0.4f0 * p.scale)))
    end
    return o
end

function bush_block(w, eye, target)
    o = 0f0
    for p in w.props
        p.kind === :bush || continue
        b = p.pos + Point3f(0, 0, 0.4f0 * p.scale)
        o += max(0f0, 0.8f0 * p.scale + 0.15f0 - NG.segment_distance(eye, target, b))
        # a bush beside the lens fills the foreground although the line of sight misses it (s32 day sheet)
        hypot(b[1] - target[1], b[2] - target[2]) > 1.5f0 && (o += max(0f0, 1.1f0 * p.scale + 1.2f0 - norm(Vec3f(eye - b))))
    end
    return o
end

function NG.stop!(s::NightShots, game)
    isdefined(NG, :CAMERA_SHOTS) || return
    delete!(NG.CAMERA_SHOTS, "nightshots")
    delete!(NG.CAMERA_BLOCKERS, "bushes")
    delete!(NG.CAMERA_BLOCKERS, "actors")
    s.on = false
end

register!(NightShots())
