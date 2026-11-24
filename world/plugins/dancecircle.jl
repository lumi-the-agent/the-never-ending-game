# Dance circle: every few minutes three or four critters meet by a lantern or the cottage,
# hold a ring and dance round it, singing (notes over their heads, plugins/emotes.jl).
# Walk in as Lumi (Play → Jump in) and they cheer, hearts all round, and dance on longer.
# The dancers talk now and then, so the watching camera turns to them.
const NG = NeverendingGame

const RING_R = 1.7f0
const GAP = (70.0, 140.0)       # sim seconds between circles
const DANCE_TIME = 22.0
const SPIN = 0.55f0             # rad/s round the ring
const SONGS = ("La la laa!", "Round and round!", "Dance with us!", "Hop, hop, turn!", "What a night!", "Tra-la-la!")
const CHEERS = ("Lumi is here!", "Join the ring, Lumi!", "Yay, Lumi!", "More dancers!")
const BYES = ("That was lovely!", "My feet are tired.", "Same time tomorrow?", "Whee, dizzy!")

push!(NG.BUSY_GOALS, :circle)    # a dancer is not pulled away for a chat

mutable struct DanceCircle <: System
    active::Bool
    center::Point3f
    members::Vector{Int32}
    t0::Float64                 # when everyone stood in the ring (0: still gathering)
    started::Float64
    until::Float64
    next_t::Float64
    next_song::Float64
    lumi_joined::Bool
end
DanceCircle() = DanceCircle(false, Point3f(0), Int32[], 0.0, 0.0, 0.0, -1.0, 0.0, false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

"""
The whole ring (and a step round it) on dry land. `on_land`'s `margin` is a HEIGHT above the sea, not a
distance: `margin = RING_R + 0.3` asked for ground 2 m up and left one lantern spot on the island (s45).
"""
ring_on_land(w, p) = all(a -> NG.on_land(w.island, p[1] + (RING_R + 0.5f0) * cos(a), p[2] + (RING_R + 0.5f0) * sin(a)), 0f0:0.5f0:6.2f0)

"Open places next to the lanterns (towards the island's middle) where a ring fits."
function dance_spots(game)
    lamps = get(game.plugins, "lamplight", nothing)
    lamps === nothing && return Point3f[]
    w = game.world
    out = Point3f[]
    clear(p) = all(q -> q.kind ∉ (:tree, :bush, :rock) ||
                        hypot(q.pos[1] - p[1], q.pos[2] - p[2]) > RING_R + (q.kind === :tree ? 1.0f0 : 0.5f0) * q.scale, w.props) &&
               all(a -> !(a isa NG.AssetActor) || hypot(a.pos[1] - p[1], a.pos[2] - p[2]) > RING_R + 0.6f0 * a.scale, w.actors)   # cottage, lanterns, toadstools
    # not by the lily pond: separation.jl keeps everyone out of the water, so a ring point in it is never reached (s40)
    ar = get(game.plugins, "areas", nothing)
    cairn = isdefined(Main, :CAIRN_STATE) ? get(Main.CAIRN_STATE, :site, nothing) : nothing   # nor on the cairn's stone rings
    dry(p) = (ar === nothing || hypot(p[1] - ar.mod.POND[1], p[2] - ar.mod.POND[2]) > ar.mod.POND_R + RING_R + 0.8f0) &&
             (cairn === nothing || hypot(p[1] - cairn[1], p[2] - cairn[2]) > 2.6f0 + RING_R + 0.5f0)
    for (pos, _, _, kind) in Base.invokelatest(lamps.mod.light_sources, game)
        # the first open place round the lantern, starting towards the island's middle
        a0 = atan(-pos[2], -pos[1])
        for r in (2.6f0, 3.4f0, 4.4f0, 5.2f0), da in (0.0f0, 0.8f0, -0.8f0, 1.6f0, -1.6f0, 2.4f0, -2.4f0, 3.14f0)
            p = NG.ground(w.island, (pos[1] + r * cos(a0 + da), pos[2] + r * sin(a0 + da)))
            if clear(p) && ring_on_land(w, p) && dry(p)
                push!(out, p)
                break
            end
        end
    end
    # a second kind of place: the middle of the golden flower field (todo #222), in view of the overview
    f = field_spot(game)
    if f !== nothing
        for r in (0f0, 1f0, 2f0, 3f0), a in 0f0:0.785f0:6.2f0
            q = NG.ground(w.island, (f[1] + r * cos(a), f[2] + r * sin(a)))
            if clear(q) && dry(q) && ring_on_land(w, q)
                push!(out, q); FIELD_RING[] = q
                break
            end
        end
    end
    return out
end

"The golden flower field's middle (plugins/meadow.jl FLOWER_FIELD), or nothing without the meadow."
function field_spot(game)
    me = get(game.plugins, "meadow", nothing)
    me === nothing && return nothing
    c = me.mod.FLOWER_FIELD[1]
    return NG.ground(game.world.island, (c[1], c[2]))
end
const FIELD_RING = Ref{Any}(nothing)   # the ring place found in the field (dance_spots)
in_field(game, p) = (f = FIELD_RING[]; f !== nothing && hypot(p[1] - f[1], p[2] - f[2]) < 0.5f0)
const LANTERN_LINE = "Dance circle by the lantern!"

ring_radius(n) = n <= 4 ? RING_R : RING_R + 0.15f0 * (n - 4)    # a big parade's ring: room for everyone
ring_point(w, s, k, n, t) = (a = Float32(2pi * k / n + SPIN * t); r = ring_radius(n);
    NG.ground(w.island, (s.center[1] + r * cos(a), s.center[2] + r * sin(a))))

can_dance(c) = !c.controlled && !NG.busy(c) && c.goal.kind ∉ (:follow, :answer) && c.species != "Lumi"

"""
Start a ring at `spot` (or a random lantern spot). `dancers`: ids of creatures that dance in it (Lumi's
parade, greetings.jl), else the 4 free ones nearest the spot.
"""
function start_circle!(s::DanceCircle, game; spot = nothing, dancers = nothing, line = LANTERN_LINE)
    w = game.world
    s.active && return false
    spots = dance_spots(game)
    isempty(spots) && return false
    s.center = spot === nothing ? spots[rand(w.rng, 1:length(spots))] : spot
    if dancers === nothing
        near = sort([c for c in w.creatures if can_dance(c) && norm(c.pos - s.center) < 30],
                    by = c -> norm(c.pos - s.center))
        length(near) < 3 && return false
        s.members = [c.id for c in near[1:min(4, end)]]
    else
        length(dancers) < 3 && return false
        s.members = collect(Int32, dancers)
    end
    n = length(s.members)
    for (k, id) in enumerate(s.members)
        c = NG.creature(w, id)
        c.goal = NG.Goal(:circle, ring_point(w, s, k, n, 0.0), :idle, 600.0, 0.0, false, 0, true)
    end
    line == LANTERN_LINE && in_field(game, s.center) && (line = "Dance in the golden flowers!")
    NG.say!(w, NG.creature(w, s.members[1]), line; duration = 3)
    s.active = true; s.t0 = 0.0; s.started = w.t; s.lumi_joined = false
    NG.emit!(w, :dance_circle; who = join([NG.creature(w, id).name for id in s.members], ", "))
    return true
end

function end_circle!(s::DanceCircle, game; why = "done")
    w = game.world
    NG.emit!(w, :dance_circle_end; why, who = join([string(NG.creature(w, id) === nothing ? id : NG.creature(w, id).name) for id in s.members], ", "))
    for id in s.members
        c = NG.creature(w, id)
        c === nothing && continue
        c.goal.kind === :circle || continue
        NG.remember!(c, w.t, "danced in a ring by the lantern")
        c.mood = min(1.0f0, c.mood + 0.15f0)
        NG.choose_goal!(c, w)
    end
    m = isempty(s.members) ? nothing : NG.creature(w, s.members[end])
    m === nothing || NG.say!(w, m, rand(w.rng, BYES); duration = 2.5)
    s.active = false
    s.members = Int32[]
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
end

function NG.step!(s::DanceCircle, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 20.0)
    if !s.active
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        testing = game.tests !== nothing && NG.running(game.tests)   # UI tests move critters about: no ring of our own then
        if w.t >= s.next_t && !busy_game && !testing     # at night too: whoever is awake dances in the lamplight
            start_circle!(s, game) || (s.next_t = w.t + 30.0)
        end
        return
    end
    # someone was taken away (the player, a wave, separation's unstick! on a dancer stuck on its way): the
    # others dance on while three are left (s43: one stuck parade friend broke every parade party after 12 s)
    lost = [(c === nothing ? string(id) : "$(c.name) $(c.goal.kind)") for id in s.members for c in (NG.creature(w, id),) if c === nothing || c.goal.kind !== :circle]
    filter!(id -> (c = NG.creature(w, id); c !== nothing && c.goal.kind === :circle), s.members)
    members = [NG.creature(w, id) for id in s.members]
    if length(members) < 3 || (game.minigame !== nothing && !(game.minigame isa NG.JumpIn))
        return end_circle!(s, game; why = "lost $(lost), minigame $(typeof(game.minigame))")
    end
    n = length(members)
    if s.t0 == 0.0
        # a straggler stuck behind a bush or a sleeper on its spot does not hold the ring up:
        # after 15 s the ones who made it start without it, and it goes back to its own life
        if w.t - s.started > 15 && count(c -> c.goal.arrived, members) >= 3 && !all(c -> c.goal.arrived, members)
            for c in members
                c.goal.arrived && continue
                NG.say!(w, c, "Go on without me!"; duration = 2)
                NG.choose_goal!(c, w)
            end
            filter!(id -> NG.creature(w, id).goal.kind === :circle, s.members)
            members = [NG.creature(w, id) for id in s.members]
        end
        all(c -> c.goal.arrived, members) && (s.t0 = w.t; s.until = w.t + DANCE_TIME; s.next_song = w.t)
        w.t - s.started > 40 && return end_circle!(s, game; why = "could not get there")       # could not get there
        return
    end
    # dance round the ring, facing the middle
    t = w.t - s.t0
    for (k, c) in enumerate(members)
        c.pos = ring_point(w, s, k, n, t)
        c.yaw = atan(s.center[2] - c.pos[2], s.center[1] - c.pos[1]) - NG.species_of(c).heading
        c.action = :dance
        c.goal.action = :dance
        c.goal.until = w.t + 600
    end
    if w.t >= s.next_song
        c = members[rand(w.rng, 1:n)]
        NG.say!(w, c, rand(w.rng, SONGS); duration = 2.2)
        s.next_song = w.t + 3.5 + 2rand(w.rng)
    end
    me = NG.creature(w, "Lumi")
    if me !== nothing && me.controlled && !s.lumi_joined && norm(me.pos - s.center) < ring_radius(length(members)) + 1.5f0
        s.lumi_joined = true
        s.until += 12.0
        for c in members
            emote(c.id, :heart)
        end
        emote(me.id, :heart)
        NG.say!(w, members[1], rand(w.rng, CHEERS); duration = 2.5)
        NG.emit!(w, :dance_join; who = me.name)
    end
    w.t >= s.until && end_circle!(s, game)
    return
end

"The ring's first dancer while the ring dances (the watching camera turns to it)."
const CURRENT = Ref{Any}(nothing)
watch_ring(w) = (s = CURRENT[]; s === nothing || !s.active || s.t0 == 0.0 ? nothing : first(s.members))

"The whole ring in one picture (the camera framed one dancer's back before)."
function ring_group(w)
    id = watch_ring(w)
    id === nothing && return nothing
    ps = [c.pos for c in (NG.creature(w, m) for m in CURRENT[].members) if c !== nothing]
    return id, ps
end

function NG.start!(s::DanceCircle, game)
    CURRENT[] = s
    NG.CAMERA_MOMENTS["dancecircle"] = watch_ring
    isdefined(NG, :CAMERA_GROUPS) && (NG.CAMERA_GROUPS["dancecircle"] = ring_group)
end

function NG.stop!(s::DanceCircle, game)
    delete!(NG.CAMERA_MOMENTS, "dancecircle")
    isdefined(NG, :CAMERA_GROUPS) && delete!(NG.CAMERA_GROUPS, "dancecircle")
    s.active && end_circle!(s, game)
end

register!(DanceCircle())
