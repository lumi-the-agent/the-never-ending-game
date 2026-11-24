# Critters build a stone cairn: now and then one wanders off, picks up a pebble, carries it
# over its head to the cairn on the meadow and sets it on top (a little hop and a heart).
# The cairn grows over days (saved in state/cairn.json); once it is a tall stack, new stones
# go round it as a ring. Perfectionist s33: critters leave a trace in the world (#176).
const NG = NeverendingGame

isdefined(Main, :CAIRN_STATE) ||
    Core.eval(Main, :(const CAIRN_STATE = Dict{Symbol,Any}(:n => -1, :site => nothing, :plots => Dict{Symbol,Any}(), :shown => -1)))
const CAIRN = Main.CAIRN_STATE
const STACK = 15          # stones in the stack itself, the rest make the ring
const RING = 24
const RING2 = 32          # then a wider outer ring
const RING3 = 40          # and a third, of small stones (the cairn was full in s40 and the critters stopped carrying)
const EXTRA = 0           # pebbles between the rings past a full cairn: 90 of them (s42) read as a cobbled floor, media/s42-cairn-extra.png; off until a better idea (a second cairn)
const MAX_STONES = STACK + RING + RING2 + RING3 + EXTRA   # stones DRAWN: the count goes on (it was a cap, and a full cairn stopped the critters and the parade, s40 and s42)
cairn_file(game) = joinpath(game.paths.state, "cairn.json")

function load_count!(game)
    f = cairn_file(game)
    CAIRN[:n] = isfile(f) ? Int(NG.JSON.parse(read(f, String))["stones"]) : 3   # three to start: it reads as a cairn
end
save_count(game) = write(cairn_file(game), NG.JSON.json(Dict("stones" => CAIRN[:n])))

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"The most open place on the meadow (a grid search): away from tree crowns, bushes, rocks and assets (cottage, lanterns), off the paths, nearer the middle when it is a tie."
function find_site(w; path = Point2f[], path_width = 1.15f0)
    function room(q)
        r = 3.0f0
        for c in path       # the dirt path (plugins/areas.jl): the outer rings lay across it (s40)
            r = min(r, flat(c, q) - path_width / 2 - 0.15f0)
        end
        for p in w.props
            p.kind in (:tree, :rock, :bush) || continue
            r = min(r, flat(p.pos, q) - (p.kind === :tree ? 2.6f0 : 0.75f0 + 0.3f0) * p.scale)
        end
        for a in w.actors
            a isa NG.AssetActor && (r = min(r, flat(a.pos, q) - 0.6f0 * a.scale - 0.4f0))
        end
        return r
    end
    best, score = nothing, -Inf32
    R = w.island.radius
    for x in -R:0.5f0:R, y in -R:0.5f0:R
        NG.on_land(w.island, x, y; margin = 2.5f0) && NG.walkway_height(x, y) === nothing || continue
        q = Point3f(x, y, 0)
        sc = min(room(q), 2.6f0) - 0.02f0 * hypot(x, y)   # 2.6: the third ring (2.2 m) fits
        sc > score && ((best, score) = (q, sc))
    end
    best === nothing && return NG.ground(w.island, (0.0f0, 0.0f0))
    return NG.ground(w.island, (best[1], best[2]))
end

const SITE_VERSION = 2    # bump when find_site changes: the cairn moves (its stone count stays)
function site(game)
    if CAIRN[:site] === nothing || get(CAIRN, :site_version, 0) != SITE_VERSION
        a = get(game.plugins, "areas", nothing)
        path = a === nothing ? Point2f[] : a.mod.PATH_COARSE
        CAIRN[:site] = find_site(game.world; path)
        CAIRN[:site_version] = SITE_VERSION
        CAIRN[:shown] = -1; CAIRN[:loose_shown] = nothing
    end
    return CAIRN[:site]
end

"Offset from the site and size of stone `k` (1-based): a stack in shrinking layers, then a ring."
function stone(k)
    h = hash(k)
    j = (h % 1000) / 1000f0
    if k <= STACK
        layers = (5, 4, 3, 2, 1)
        L, i = 1, k
        while L < length(layers) && i > layers[L]
            i -= layers[L]; L += 1
        end
        L == length(layers) && (L += i - 1; i = 1)            # single stones on top
        n = L <= 4 ? layers[L] : 1
        s = 0.2f0 * 0.88f0^(L - 1) * (0.9f0 + 0.2f0j)
        r = n == 1 ? 0.0f0 : (0.26f0 - 0.06f0 * (L - 1))
        a = Float32(2pi * i / n + 0.7L)
        z = sum(0.2f0 * 0.88f0^(l - 1) * 0.95f0 for l in 1:(L - 1); init = 0.0f0) + 0.08f0
        return Point3f(r * cos(a), r * sin(a), z), s
    end
    i = k - STACK
    if i <= RING
        a = Float32(2pi * i / RING)
        return Point3f(1.25f0 * cos(a), 1.25f0 * sin(a), 0.03f0), 0.17f0 * (0.85f0 + 0.3f0j)
    end
    i -= RING
    if i <= RING2
        a = Float32(2pi * (i + 0.5) / RING2)
        return Point3f(1.75f0 * cos(a), 1.75f0 * sin(a), 0.03f0), 0.15f0 * (0.85f0 + 0.3f0j)
    end
    i -= RING2
    if i <= RING3
        a = Float32(2pi * (i + 0.25) / RING3)
        return Point3f(2.2f0 * cos(a), 2.2f0 * sin(a), 0.02f0), 0.13f0 * (0.85f0 + 0.3f0j)
    end
    i -= RING3                     # past the full cairn: little pebbles fill the gaps between the rings (golden angle)
    a = Float32(2.39996 * i)
    r = (0.85f0, 1.5f0, 1.98f0)[mod1(i, 3)] + 0.12f0 * (j - 0.5f0)
    return Point3f(r * cos(a), r * sin(a), 0.02f0), 0.1f0 * (0.85f0 + 0.3f0j)
end

stone_colour(k) = (j = (hash(k + 7) % 1000) / 1000f0; RGBf(0.7f0 + 0.12f0j, 0.67f0 + 0.1f0j, 0.6f0 + 0.08f0j))
const HIDE = Point3f(0, 0, -50)
const MAT = NG.Hikari.Plastic(color = (0.8, 0.77, 0.72), roughness = 0.85)   # the tracer ignores per-stone colours: light enough to read backlit

function plots!(game)
    d = CAIRN[:plots]
    sc = game.stage.scene
    if !haskey(d, :stack)
        d[:stack] = meshscatter!(sc, [HIDE]; marker = NG.shape(:sphere), markersize = [Vec3f(0)], rotation = [Quaternionf(0, 0, 0, 1)],
                                 color = [RGBf(0.6, 0.58, 0.54)], material = MAT, name = :cairn_stones)
        d[:loose] = meshscatter!(sc, [HIDE]; marker = NG.shape(:sphere), markersize = [Vec3f(0)], rotation = [Quaternionf(0, 0, 0, 1)],
                                 color = [RGBf(0.66, 0.63, 0.57)], material = MAT, name = :cairn_loose)
        CAIRN[:loose_shown] = nothing
        d[:carried] = meshscatter!(sc, [HIDE]; marker = NG.shape(:sphere), markersize = [Vec3f(0)],
                                   color = [RGBf(0.6, 0.58, 0.54)], material = MAT, name = :cairn_carried)
        CAIRN[:shown] = -1
    end
    return d
end

function show_stones!(game)
    d = plots!(game)
    n = clamp(CAIRN[:n], 0, MAX_STONES)
    CAIRN[:shown] == n && return
    s0 = site(game)
    pos = Point3f[]; sz = Vec3f[]; rot = Quaternionf[]; col = RGBf[]
    for k in 1:n
        o, s = stone(k)
        base = k <= STACK ? s0 : NG.ground(game.world.island, (s0[1] + o[1], s0[2] + o[2]))
        push!(pos, k <= STACK ? s0 + o : base + Point3f(0, 0, o[3]))
        push!(sz, Vec3f(s, 0.85f0s, 0.55f0s))
        push!(rot, NG.rot_z(Float32(k * 1.7)))
        push!(col, stone_colour(k))
    end
    isempty(pos) && (push!(pos, HIDE); push!(sz, Vec3f(0)); push!(rot, Quaternionf(0, 0, 0, 1)); push!(col, RGBf(0.6, 0.58, 0.54)))
    Makie.update!(d[:stack]; arg1 = pos, markersize = sz, rotation = rot, color = col)
    CAIRN[:shown] = n
end

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

# ── the goal: fetch a pebble (partner -1), carry it to the cairn (partner 1) ──
:pebble in NG.GOAL_KINDS || push!(NG.GOAL_KINDS, :pebble)
:pebble in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :pebble)   # a carrier is not pulled into a chat

carriers(w) = count(c -> c.goal.kind === :pebble, w.creatures)
NG.goal_score(::Val{:pebble}, c, w) =
    NG.is_night(w) || c.controlled || c.species == "Lumi" || CAIRN[:site] === nothing ||
    carriers(w) >= 2 ? 0.0 : 0.25 + 0.35c.traits.playfulness

function NG.start_goal(::Val{:pebble}, c, w)
    s = CAIRN[:site]
    s === nothing && return nothing
    for _ in 1:12                       # a pebble a few metres from the cairn, out in the open
        a = 2pi * rand(w.rng); r = 4.0f0 + 4rand(w.rng)
        q = (s[1] + r * cos(a), s[2] + r * sin(a))
        NG.on_land(w.island, q[1], q[2]; margin = 1.0f0) && NG.walkway_height(q[1], q[2]) === nothing || continue
        return NG.Goal(:pebble, NG.ground(w.island, q), :idle, 0.8, w.t + 40, false, -1, false)   # until: give up a walk that is stuck
    end
    return nothing
end

function NG.arrive_goal!(::Val{:pebble}, c, w)
    g = c.goal
    s = CAIRN[:site]
    if g.partner < 0                     # picked it up: off to the cairn, a stone over the head
        a = atan(c.pos[2] - s[2], c.pos[1] - s[1])
        d = (CAIRN[:n] < STACK ? 0.55f0 : CAIRN[:n] < STACK + RING ? 1.25f0 : CAIRN[:n] < STACK + RING + RING2 ? 1.75f0 : 2.2f0) + NG.body_radius(NG.species_of(c))
        g.target = NG.ground(w.island, (s[1] + d * cos(a), s[2] + d * sin(a)))
        g.partner = 1; g.arrived = false; g.duration = 1.6; g.until = w.t + 40
        g.action = :jump
        rand(w.rng) < 0.4 && NG.say!(w, c, rand(w.rng, ["ooh, a nice flat one", "this one's for the pile!", "found one!"]))
    else                                 # at the cairn: set it down
        c.yaw = atan(s[2] - c.pos[2], s[1] - c.pos[1]) - NG.species_of(c).heading
        CAIRN[:n] += 1
        g.partner = 0
        emote(c.id, :heart)
        n = CAIRN[:n]
        rand(w.rng) < 0.5 && NG.say!(w, c, n == STACK ? "the top stone! it's finished!" :
                                         rand(w.rng, ["one more!", "careful... there!", "it's getting tall!", "$(n) stones!"]))
        NG.remember!(c, w.t, "put a stone on the cairn")
        NG.emit!(w, :cairn_stone; who = c.name, stones = n)
        CAIRN[:last_set] = (c.id, w.t); CAIRN[:cheer] = Int32[]
        CAIRN[:dirty] = true
    end
end

"Creatures carrying a pebble right now (on the way back to the cairn)."
carrying(w) = [c for c in w.creatures if c.goal.kind === :pebble && c.goal.partner == 1 && !c.goal.arrived]

# the camera likes a stone being set down, and stays 4 s after it is down
function just_set(w)
    ls = get(CAIRN, :last_set, nothing)
    (ls === nothing || !(0 <= w.t - ls[2] < 4)) && return nothing
    return ls[1]
end
"For 4 s after a stone is set: the setter, the pile and the critters cheering, framed from the side."
function group(w)
    id = just_set(w)
    id === nothing && return nothing
    s = CAIRN[:site]
    pts = Point3f[s + Point3f(0, 0, 0.6)]
    for c in w.creatures
        (c.id == id || c.id in get(CAIRN, :cheer, Int32[])) && flat(c.pos, s) < 9 && push!(pts, c.pos + Point3f(0, 0, 0.4))
    end
    return (id, pts)
end
moment(w) = (id = just_set(w); id !== nothing ? id : moment_carry(w))
moment_carry(w) = (cs = [c for c in w.creatures if c.goal.kind === :pebble && c.goal.partner >= 0 &&
                    flat(c.pos, CAIRN[:site]) < 4]; isempty(cs) ? nothing : first(cs).id)

# ── the player's part: loose pebbles round the cairn; E by one picks it up, walking to the cairn sets it down ──
const LOOSE = 5
"Where the loose pebbles lie: a ring 3-5 m out, off the paths, on land; `gen` moves a taken one somewhere new."
function loose_spots(w, gen)
    s = CAIRN[:site]
    out = Point3f[]
    for k in 1:LOOSE
        for j in 0:20
            h = hash((k, gen[k], j))
            a = Float32(2pi * (k / LOOSE + 0.15 * ((h % 100) / 100 - 0.5)))
            r = 3.0f0 + 2.0f0 * ((h >> 8) % 100) / 100
            q = (s[1] + r * cos(a), s[2] + r * sin(a))
            NG.on_land(w.island, q[1], q[2]; margin = 1.0f0) && NG.walkway_height(q[1], q[2]) === nothing || continue
            push!(out, NG.ground(w.island, q)); break
        end
    end
    return out
end
pebbles(w) = (get!(CAIRN, :gen, zeros(Int, LOOSE)); get!(() -> loose_spots(w, CAIRN[:gen]), CAIRN, :loose))
lumi_carries() = get(CAIRN, :lumi_stone, false)

function show_loose!(game)
    ps = pebbles(game.world)
    CAIRN[:loose_shown] === ps && return
    pos = [p + Point3f(0, 0, 0.06) for p in ps]
    sz = [Vec3f(0.17f0, 0.14f0, 0.09f0) for _ in ps]
    rot = [NG.rot_z(Float32(k * 2.3)) for k in eachindex(ps)]
    Makie.update!(CAIRN[:plots][:loose]; arg1 = pos, markersize = sz, rotation = rot, color = fill(RGBf(0.66, 0.63, 0.57), length(ps)))
    CAIRN[:loose_shown] = ps
end

near_pebble(w, me) = findfirst(p -> flat(p, me.pos) < 1.1f0, pebbles(w))

"Whether Lumi's E press now is (or was, this frame) a pebble pick, so greetings.jl does not wave too."
uses_e(w, me) = get(CAIRN, :e_used, -1.0) == w.t || (!lumi_carries() && CAIRN[:site] !== nothing && near_pebble(w, me) !== nothing)

function flower_uses_e(game, w, me)
    p = get(game.plugins, "flowergift", nothing)
    (p === nothing || !isdefined(p.mod, :uses_e)) && return false
    return Base.invokelatest(p.mod.uses_e, w, me)
end

function lumi_stone!(game, w)
    i = findfirst(c -> c.name == "Lumi", w.creatures)
    i === nothing && return
    me = w.creatures[i]
    a = me.action; pressed = a === :wave && get(CAIRN, :last_action, :idle) !== :wave; CAIRN[:last_action] = a
    if !me.controlled
        CAIRN[:lumi_stone] = false
        return
    end
    s = CAIRN[:site]
    if !lumi_carries()
        pressed || return
        k = near_pebble(w, me)
        (k === nothing || flower_uses_e(game, w, me)) && return
        CAIRN[:e_used] = w.t
        CAIRN[:lumi_stone] = true
        CAIRN[:gen][k] += 1; delete!(CAIRN, :loose)            # a new one turns up somewhere else
        NG.say!(w, me, rand(w.rng, ("A good one for the cairn!", "Heave... got it!", "This one's mine to add!")); duration = 2)
        emote(me.id, :note)
    elseif flat(me.pos, s) < (CAIRN[:n] < STACK ? 1.0f0 : 2.1f0) + NG.body_radius(NG.species_of(me))
        CAIRN[:lumi_stone] = false
        CAIRN[:n] += 1
        CAIRN[:dirty] = true
        emote(me.id, :heart)
        NG.say!(w, me, "$(CAIRN[:n]) stones! I helped!"; duration = 2.5)
        NG.emit!(w, :cairn_stone; who = me.name, stones = CAIRN[:n])
        CAIRN[:last_set] = (me.id, w.t)
        CAIRN[:cheer] = Int32[]
        for o in w.creatures                                  # the critters nearby cheer
            (o === me || o.action === :sleep || flat(o.pos, s) > 9) && continue
            push!(CAIRN[:cheer], o.id)
            emote(o.id, rand(w.rng, (:heart, :note)))
            o.yaw = atan(me.pos[2] - o.pos[2], me.pos[1] - o.pos[1]) - NG.species_of(o).heading
            length(CAIRN[:cheer]) == 1 && NG.say!(w, o, rand(w.rng, ("Yay, Lumi!", "Nice stone!", "It's getting so tall!")); duration = 2)
            NG.remember!(o, w.t, "cheered Lumi's stone on the cairn")
        end
    end
end

# how far the hats in outfits.jl stand above the head: a carried stone rides on top of them
const HAT_LIFT = Dict("Sir Sniffsalot" => 0.3f0, "Pinchy" => 0.3f0, "Cumulus" => 0.14f0, "Truffle" => 0.08f0,
                      "Hopscotch" => 0.08f0, "Gloop" => 0.06f0, "Marshmallow" => 0.05f0)

struct Cairns <: System end

function NG.start!(::Cairns, game)
    CAIRN[:n] < 0 && load_count!(game)
    site(game)
    show_stones!(game)
    NG.CAMERA_MOMENTS["cairns"] = w -> CAIRN[:site] === nothing ? nothing : moment(w)
    NG.CAMERA_GROUPS["cairns"] = w -> CAIRN[:site] === nothing ? nothing : group(w)
end

function NG.step!(::Cairns, game, dt)
    if get(CAIRN, :dirty, false)
        CAIRN[:dirty] = false
        game.dash === nothing || save_count(game)   # copies (traced clips, stills) never write the live count
    end
    show_stones!(game)
    w = game.world
    show_loose!(game)
    lumi_stone!(game, w)
    for c in w.creatures     # stuck behind a bush or trunk on the way: do something else
        c.goal.kind === :pebble && !c.goal.arrived && w.t > c.goal.until && NG.choose_goal!(c, w)
    end
    cs = carrying(w)
    lumi_carries() && (j = findfirst(c -> c.name == "Lumi", w.creatures); j === nothing || push!(cs, w.creatures[j]))
    d = CAIRN[:plots]
    if isempty(cs) && get(CAIRN, :carried_n, 0) == 0
        return
    end
    pos = Point3f[]; sz = Vec3f[]
    for c in cs
        h = NG.species_of(c).height
        lift = get(HAT_LIFT, c.name, 0.0f0)          # on top of the hat, not inside it (the film hid it in Cumulus' beanie)
        push!(pos, c.pos + Point3f(0, 0, 0.9f0h + 0.06f0 + lift + 0.03f0 * sin(Float32(8w.t))))   # on the head, under the name tag
        push!(sz, Vec3f(0.25f0, 0.21f0, 0.13f0))
    end
    isempty(pos) && (push!(pos, HIDE); push!(sz, Vec3f(0)))
    Makie.update!(d[:carried]; arg1 = pos, markersize = sz, color = fill(RGBf(0.62, 0.6, 0.55), length(pos)))
    CAIRN[:carried_n] = length(cs)
end

function NG.stop!(::Cairns, game)
    delete!(NG.CAMERA_MOMENTS, "cairns")
    delete!(NG.CAMERA_GROUPS, "cairns")
    for p in values(CAIRN[:plots])
        delete!(game.stage.scene, p)
    end
    empty!(CAIRN[:plots])
    CAIRN[:shown] = -1
end

register!(Cairns())
