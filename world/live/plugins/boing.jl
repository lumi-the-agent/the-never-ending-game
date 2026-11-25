# The Big Boing (session 62, a bored Lumi's idea): a giant bouncy toadstool in the meadow. Every so
# often Lumi shouts "BOING TIME!" and the WHOLE island gathers round it in a ring; one after another
# each friend hops onto the cap, the cap squashes, and off they fly, spinning, metres up into the sky,
# while the ring cheers. Lumi goes last and highest. In between, friends come for a bounce on their
# own, and a player who jumped in as Lumi launches the nearest friend with E.
isdefined(Main, :BOING) || Core.eval(Main, :(const BOING = Dict{Symbol,Any}()))
const NG = NeverendingGame
const B = Main.BOING

const STEM_H = 1.3f0           # m of stem under the cap (s68: 0.75 under a whole ellipsoid hid it: a red lens on the grass)
const CAP_R = 1.9f0            # cap radius
const CAP_H = 1.0f0            # cap height (a dome on the stem)
const HOP_T = 0.6              # s from the ring onto the cap
const NEXT_T = 1.15            # s between two launches in a party (several in the air at once)
const GAP = (480.0, 720.0)     # sim seconds between parties (daytime)
const SOLO_GAP = (50.0, 110.0) # sim seconds between friends coming for a bounce on their own
const RED = RGBf(0.90, 0.25, 0.22)
const CREAM = RGBf(0.98, 0.92, 0.80)
const WHEES = ("Wheeee!", "BOING!", "Woo-hoo!", "I can see my house!", "Higher!", "Yippee!", "Look at me!", "Aaaaah!")
const OOHS = ("Ooooh!", "So high!", "Wow!", "Again!", "Ha ha ha!", "Go go go!")
const LUMI_CALL = ("I'm sooo bored... EVERYBODY! BOING TIME!", "Boring, boring... BOING! Everyone to the toadstool!")

push!(NG.BUSY_GOALS, :boing)

mutable struct Boing <: System
    state::Symbol                 # :idle, :gather, :bounce
    members::Vector{Int32}
    homes::Dict{Int32,Point3f}    # each one's place in the ring
    queue::Vector{Int32}          # who bounces next
    next_launch::Float64
    started::Float64
    next_t::Float64
    next_solo::Float64
    squash_t::Float64
    flights::Dict{Int32,Any}      # id => (stage, t0, T, from, to, h, spin, solo)
    cheer::Dict{Int32,Float64}    # ring member => jump until
    last_action::Symbol
    subject::Int32
    view::Any
end
Boing() = Boing(:idle, Int32[], Dict{Int32,Point3f}(), Int32[], 0.0, 0.0, -1.0, -1.0, -100.0,
                Dict{Int32,Any}(), Dict{Int32,Float64}(), :idle, Int32(0), nothing)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
free_one(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact, :answer)
# the party calls everyone from their pastimes (fishing, pebbles, sunbathing), but not from another event
const KEEP = (:follow, :interact, :answer, :circle, :rain, :build, :tinker, :kite, :kitewatch, :boing, :boing_walk, :sleep, :paint, :giant, :storm, :toadstool)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch)   # pastimes a BOING TIME! call beats
party_one(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ KEEP && (c.goal.kind ∉ NG.BUSY_GOALS || c.goal.kind in PULL)

"Friends who come free while the party is on join the ring late (a fisher with a fish on the hook)."
function join_late!(s::Boing, game)
    w = game.world
    c0 = B[:center]
    R = ring_r(length(s.members) + 1)
    # Lumi's finale is the last bounce: nobody joins after Lumi went up (Marshmallow did, s62)
    any(id -> NG.creature(w, id).name == "Lumi", s.members) && !any(id -> NG.creature(w, id).name == "Lumi", s.queue) && return
    for c in w.creatures
        (party_one(c) && !(c.id in s.members) && flat(c.pos, c0) < 80) || continue
        a = atan(c.pos[2] - c0[2], c.pos[1] - c0[1])
        home = NG.ground(w.island, (c0[1] + R * cos(a), c0[2] + R * sin(a)))
        NG.leave_interactions!(w, c)
        s.homes[c.id] = home
        push!(s.members, c.id)
        lumi = findfirst(id -> NG.creature(w, id).name == "Lumi", s.queue)
        lumi === nothing ? push!(s.queue, c.id) : insert!(s.queue, lumi, c.id)
        c.goal = NG.Goal(:boing, home, :idle, 600.0, 0.0, false, 0, true)
        NG.say!(w, c, "Wait for me!"; duration = 2)
    end
end
ring_r(n) = max(3.6f0, n * 1.35f0 / Float32(2pi))
hour(w) = 24 * NG.daytime(w)

# ---------------------------------------------------------------- the place

"An open meadow place for the toadstool and a ring of `n` round it, as near the flower field as it gets."
function find_spot(game, n)
    w = game.world
    R = ring_r(n) + 0.8f0
    me = get(game.plugins, "meadow", nothing)
    c0 = me === nothing ? Point2f(0, 0) : Point2f(me.mod.FLOWER_FIELD[1][1], me.mod.FLOWER_FIELD[1][2])
    ar = get(game.plugins, "areas", nothing)
    cairn = isdefined(Main, :CAIRN_STATE) ? get(Main.CAIRN_STATE, :site, nothing) : nothing
    dc = get(game.plugins, "dancecircle", nothing)
    ring_land(p) = all(a -> NG.on_land(w.island, p[1] + R * cos(a), p[2] + R * sin(a); margin = 0.3f0), 0f0:0.4f0:6.2f0)
    function ok(p)
        for q in w.props
            q.kind in (:tree, :bush, :rock) || continue
            flat(q.pos, p) < R + (q.kind === :tree ? 1.4f0 : 0.4f0) * q.scale && return false
        end
        for a in w.actors
            a isa NG.AssetActor && flat(a.pos, p) < R + 0.7f0 * a.scale && return false
        end
        ar !== nothing && flat(ar.mod.POND, p) < ar.mod.POND_R + R + 1 && return false
        cairn !== nothing && flat(cairn, p) < R + 3f0 && return false
        if dc !== nothing && dc.mod.FIELD_RING[] !== nothing
            flat(dc.mod.FIELD_RING[], p) < R + 2f0 && return false
        end
        return ring_land(p)
    end
    best = nothing
    for r in 0f0:1f0:60f0, a in 0f0:0.2f0:6.2f0
        p = Point2f(c0[1] + r * cos(a), c0[2] + r * sin(a))
        ok(p) && (best = p; break)
    end
    best === nothing && return nothing
    return NG.ground(w.island, (best[1], best[2]))
end

# ---------------------------------------------------------------- the toadstool

function clear_plots!()
    for p in values(get(B, :plots, Dict()))
        delete!(p.parent, p)
    end
    B[:plots] = Dict{Symbol,Any}()
end

"A unit half sphere (z ≥ 0), outward normals: the toadstool's cap."
function dome(n = 40, m = 14)
    pts = Point3f[]; fs = GeometryBasics.GLTriangleFace[]
    for j in 0:m, i in 0:n-1
        t = (pi / 2) * j / m; f = 2pi * i / n
        push!(pts, Point3f(sin(t) * cos(f), sin(t) * sin(f), cos(t)))
    end
    for j in 0:m-1, i in 0:n-1
        a = j * n + i + 1; b = j * n + mod(i + 1, n) + 1; c = (j + 1) * n + i + 1; d = (j + 1) * n + mod(i + 1, n) + 1
        push!(fs, GeometryBasics.GLTriangleFace(a, c, b), GeometryBasics.GLTriangleFace(b, c, d))
    end
    return GeometryBasics.Mesh(pts, fs; normal = Vec3f.(pts))
end

"""
Per-vertex colours for the cap (s71, perfectionist-0070: "a flat glossy red dome"): a brighter red on top,
deeper towards the rim, a soft mottle, and a pale lip at the edge where the cap curls under.
"""
function cap_colours(m)
    map(GeometryBasics.coordinates(m)) do p
        z = clamp(p[3], 0f0, 1f0)
        a = atan(p[2], p[1])
        mottle = 0.06f0 * sin(5f0 * a + 7f0 * z) * sin(3f0 * a - 4f0 * z)
        r = 0.62f0 + 0.3f0 * z + mottle
        base = RGBf(r, 0.1f0 + 0.14f0 * z + 0.5f0 * mottle, 0.08f0 + 0.1f0 * z)
        z < 0.1f0 ? RGBf(0.95f0, 0.86f0, 0.72f0) * (1 - z / 0.1f0) + base * (z / 0.1f0) : base
    end
end

function build!(game)
    clear_plots!()
    sc = game.stage.scene
    c = B[:center]
    d = B[:plots]
    stem = Makie.normal_mesh(Cylinder(Point3f(0, 0, -0.3), Point3f(0, 0, STEM_H + 0.1f0), 0.5f0))
    d[:stem] = mesh!(sc, stem; color = CREAM, name = :boing_stem)
    translate!(d[:stem], c)
    # spotted cap: a red dome, a cream underside (the gills), white spots on the dome
    d[:cap] = mesh!(sc, dome(); color = cap_colours(dome()), name = :boing_cap)
    d[:under] = mesh!(sc, Sphere(Point3f(0), 1f0); color = CREAM, name = :boing_under)
    spots = Point3f[]
    for (el, k) in ((0.35f0, 7), (0.8f0, 5), (1.25f0, 1))
        for i in 1:k
            a = Float32(2pi * i / k + el)
            push!(spots, Point3f(sin(1.5f0 - el) * cos(a), sin(1.5f0 - el) * sin(a), cos(1.5f0 - el)) * 1.01f0)
        end
    end
    d[:spots] = meshscatter!(sc, spots; marker = Sphere(Point3f(0), 1f0), markersize = Vec3f(0.17, 0.17, 0.06),
                             rotation = [Makie.rotation_between(Vec3f(0, 0, 1), Vec3f(p)) for p in spots],
                             color = RGBf(1, 0.98, 0.94), name = :boing_spots)
    squash!(0.0)
end

"The cap's wobble after a bounce `t` s ago: 1 at rest, < 1 squashed."
wobble(t) = t < 0 || t > 1.6 ? 1f0 : Float32(1 - 0.38 * exp(-3.2t) * cos(14t))

function squash!(t)
    d = B[:plots]
    c = B[:center]
    s = wobble(t)
    sx = CAP_R * (1 + 0.5f0 * (1 - s))
    z = c[3] + STEM_H
    for k in (:cap, :spots)
        scale!(d[k], sx, sx, CAP_H * s)
        translate!(d[k], c[1], c[2], z)
    end
    scale!(d[:under], sx * 0.96f0, sx * 0.96f0, 0.28f0 * s)
    translate!(d[:under], c[1], c[2], z + 0.02f0)
end

cap_top() = B[:center] + Point3f(0, 0, STEM_H + CAP_H * 0.97f0)

# ---------------------------------------------------------------- flights

"Send `c` up: hop onto the cap, then a flight of `h` metres back to `home`."
function launch!(s::Boing, w, c, home; h = 6f0, solo = false)
    c.goal = NG.Goal(:boing, home, :jump, 600.0, w.t + 600, true, 0, false)
    s.flights[c.id] = (stage = :hop, t0 = w.t, T = HOP_T, from = c.pos, to = cap_top(), h = 1.0f0,
                       home = home, big = h, solo = solo, spin = (rand(w.rng) < 0.5 ? -1f0 : 1f0) * (5f0 + 4f0 * rand(w.rng)))
    s.subject = c.id
end

function step_flights!(s::Boing, game, dt)
    w = game.world
    for (id, f) in collect(s.flights)
        c = NG.creature(w, id)
        if c === nothing || c.controlled || c.goal.kind !== :boing
            delete!(s.flights, id); continue
        end
        u = min(1.0, (w.t - f.t0) / f.T)
        p = f.from + (f.to - f.from) * Float32(u)
        c.pos = Point3f(p[1], p[2], p[3] + 4f0 * f.h * Float32(u * (1 - u)))
        c.action = :jump
        c.goal.action = :jump
        c.goal.until = w.t + 600
        if f.stage === :fly
            c.yaw += f.spin * Float32(dt) * Float32(sin(pi * u))      # spins fastest at the top
            if u >= 0.45 && !get(f, :said, false)
                s.flights[id] = merge(f, (said = true,))
                if f.solo
                    NG.say!(w, c, rand(w.rng, WHEES); duration = 1.6)
                else
                    for m in s.members
                        m == id && continue
                        rand(w.rng) < 0.5 && (s.cheer[m] = w.t + 0.9)
                    end
                    watcher = [m for m in s.members if m != id && !haskey(s.flights, m)]
                    isempty(watcher) || NG.say!(w, NG.creature(w, rand(w.rng, watcher)), rand(w.rng, OOHS); duration = 1.4)
                end
            end
        end
        u < 1 && continue
        if f.stage === :hop
            # on the cap: it squashes, and up we go
            s.squash_t = w.t
            T = 1.1 + 0.32 * sqrt(f.big)
            s.flights[id] = (stage = :fly, t0 = w.t, T = T, from = cap_top(), to = f.home, h = f.big,
                             home = f.home, big = f.big, solo = f.solo, spin = f.spin)
            f.solo || NG.say!(w, c, rand(w.rng, WHEES); duration = 1.6)
            NG.emit!(w, :boing; who = c.name, height = round(f.big; digits = 1))
        else
            delete!(s.flights, id)
            c.pos = NG.ground(w.island, (f.home[1], f.home[2]))
            emote(c.id, :heart)
            c.mood = min(1f0, c.mood + 0.1f0)
            if f.solo
                NG.remember!(c, w.t, "bounced on the big toadstool")
                NG.choose_goal!(c, w)
            else
                c.goal = NG.Goal(:boing, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
                face_center!(c)
            end
        end
    end
end

face_center!(c) = (m = B[:center]; c.yaw = atan(m[2] - c.pos[2], m[1] - c.pos[1]) - NG.species_of(c).heading)

# ---------------------------------------------------------------- the party

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

"Everyone awake and free on the island comes: Lumi calls, the rest run to their place in the ring."
function start_party!(s::Boing, game)
    w = game.world
    s.state === :idle || return false
    cs = [c for c in w.creatures if party_one(c) && flat(c.pos, B[:center]) < 80]
    foreach(c -> NG.leave_interactions!(w, c), cs)
    length(cs) < 3 && return false
    n = length(cs)
    R = ring_r(n)
    c0 = B[:center]
    # each takes the ring place nearest to where it comes from
    angles = [Float32(2pi * k / n) for k in 1:n]
    order = sortperm([atan(c.pos[2] - c0[2], c.pos[1] - c0[1]) for c in cs])
    s.members = Int32[]; empty!(s.homes); empty!(s.cheer)
    a0 = atan(cs[order[1]].pos[2] - c0[2], cs[order[1]].pos[1] - c0[1])
    for (k, i) in enumerate(order)
        c = cs[i]
        a = a0 + angles[k]
        home = NG.ground(w.island, (c0[1] + R * cos(a), c0[2] + R * sin(a)))
        s.homes[c.id] = home
        push!(s.members, c.id)
        c.goal = NG.Goal(:boing, home, :idle, 600.0, 0.0, false, 0, true)
    end
    me = lumi_of(w)
    caller = me !== nothing && me.id in s.members ? me : NG.creature(w, s.members[1])
    NG.say!(w, caller, rand(w.rng, LUMI_CALL); duration = 4)
    # Lumi last (the finale), everyone else in ring order
    s.queue = filter(id -> caller === nothing || id != caller.id || caller.name != "Lumi", copy(s.members))
    caller !== nothing && caller.name == "Lumi" && push!(s.queue, caller.id)
    s.state = :gather; s.started = w.t
    s.view = party_view(game, R)
    NG.emit!(w, :boing_party; n = n, who = join([NG.creature(w, id).name for id in s.members], ", "))
    return true
end

function end_party!(s::Boing, game; why = "done")
    w = game.world
    for id in s.members
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :boing) && continue
        NG.remember!(c, w.t, "everybody bounced on the big toadstool")
        c.mood = min(1f0, c.mood + 0.2f0)
        NG.choose_goal!(c, w)
    end
    NG.emit!(w, :boing_party_end; why)
    s.state = :idle
    s.members = Int32[]; empty!(s.queue)
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
end

"A camera beside the ring, on the sun's side, high enough to see the flyers at the top."
function party_view(game, R)
    w = game.world
    c0 = B[:center]
    sd = NG.sun(w)[1]
    a0 = atan(sd[2], sd[1])
    best = nothing
    for da in (0f0, 0.5f0, -0.5f0, 1f0, -1f0, 1.6f0, -1.6f0, 2.3f0, -2.3f0, 3.1f0)
        a = a0 + da
        eye = NG.ground(w.island, (c0[1] + (R + 12f0) * cos(a), c0[2] + (R + 12f0) * sin(a))) + Point3f(0, 0, 3.2)
        blocked = any(q -> q.kind === :tree && any(t -> flat(q.pos, c0 + (eye - c0) * t) < 2.2f0 * q.scale, 0.35f0:0.1f0:1f0), w.props)
        if !blocked
            best = (eye, c0 + Point3f(0, 0, 4.2))
            break
        end
    end
    best === nothing && (best = (c0 + Point3f(R + 12, 0, 3.2), c0 + Point3f(0, 0, 4.2)))
    return best
end

function step_party!(s::Boing, game, dt)
    w = game.world
    filter!(id -> (c = NG.creature(w, id); c !== nothing && c.goal.kind === :boing), s.members)
    filter!(id -> id in s.members, s.queue)
    if length(s.members) < 2
        return end_party!(s, game; why = "everyone left")
    end
    if !isempty(s.queue) && w.t >= get(B, :join_t, 0.0)
        B[:join_t] = w.t + 2.0
        join_late!(s, game)
    end
    ms = [NG.creature(w, id) for id in s.members]
    if s.state === :gather
        if all(c -> c.goal.arrived, ms) || w.t - s.started > 30
            # stragglers still on the way bounce when they get there
            s.state = :bounce; s.next_launch = w.t + 1.0
        end
        for c in ms
            c.goal.arrived && !haskey(s.flights, c.id) && (c.goal.until = w.t + 600; face_center!(c))
        end
        return
    end
    for c in ms
        haskey(s.flights, c.id) && continue
        c.goal.arrived || continue
        c.goal.until = w.t + 600
        a = get(s.cheer, c.id, 0.0) > w.t ? :jump : :idle
        c.action = a; c.goal.action = a
        face_center!(c)
    end
    if w.t >= s.next_launch && !isempty(s.queue)
        # the next one who stands in the ring
        k = findfirst(id -> (c = NG.creature(w, id); c.goal.arrived && !haskey(s.flights, id)), s.queue)
        # a straggler stuck behind a bush (s62: four of them held a party for minutes): from close by it takes
        # a flying leap onto the cap from where it is, from far it goes back to its day
        if k === nothing && w.t - s.started > 45 && isempty(s.flights)
            id = s.queue[1]
            c = NG.creature(w, id)
            if flat(c.pos, B[:center]) < 9f0
                k = 1
            else
                deleteat!(s.queue, 1); filter!(!=(id), s.members)
                NG.choose_goal!(c, w)
            end
        end
        if k !== nothing
            id = s.queue[k]; deleteat!(s.queue, k)
            c = NG.creature(w, id)
            done = length(s.members) - length(s.queue)
            finale = c.name == "Lumi" && isempty(s.queue)
            h = finale ? 13f0 : 5f0 + 4f0 * Float32(done / length(s.members)) + 1.5f0 * rand(w.rng, Float32)
            launch!(s, w, c, s.homes[id]; h)
            if finale
                NG.say!(w, c, "My turn! Not bored anymore! BOOOING!"; duration = 3)
                for m in s.members
                    m == id || (s.cheer[m] = w.t + 4.5)
                end
            end
            s.next_launch = w.t + (finale ? 5.0 : NEXT_T)
        else
            s.next_launch = w.t + 0.3
        end
    end
    if isempty(s.queue) && isempty(s.flights)
        # everybody hops for joy, then back to their day
        if !haskey(B, :end_at)
            B[:end_at] = w.t + 3.5
            for m in s.members
                s.cheer[m] = w.t + 3.2
                emote(m, :heart)
            end
            NG.say!(w, ms[1], "Again tomorrow!"; duration = 2.5)
        elseif w.t >= B[:end_at]
            delete!(B, :end_at)
            end_party!(s, game)
        end
    end
    w.t - s.started > 240 && end_party!(s, game; why = "took too long")
end

# ---------------------------------------------------------------- bounces in between, and the player

"A free friend near the toadstool now and then walks over for a bounce of its own."
function step_solo!(s::Boing, game)
    w = game.world
    s.next_solo < 0 && (s.next_solo = w.t + 20)
    for c in w.creatures
        c.goal.kind === :boing_walk || continue
        if c.goal.arrived && !haskey(s.flights, c.id)
            launch!(s, w, c, c.goal.target; h = 4f0 + 3f0 * rand(w.rng, Float32), solo = true)
        elseif w.t - get(B, :solo_t, w.t) > 25
            NG.choose_goal!(c, w)
        end
    end
    w.t < s.next_solo && return
    s.next_solo = w.t + SOLO_GAP[1] + (SOLO_GAP[2] - SOLO_GAP[1]) * rand(w.rng)
    c0 = B[:center]
    cs = [c for c in w.creatures if free_one(c) && c.name != "Lumi" && flat(c.pos, c0) < 35]
    isempty(cs) && return
    c = rand(w.rng, cs)
    a = atan(c.pos[2] - c0[2], c.pos[1] - c0[1])
    spot = NG.ground(w.island, (c0[1] + 3.2f0 * cos(a), c0[2] + 3.2f0 * sin(a)))
    c.goal = NG.Goal(:boing_walk, spot, :idle, 30.0, 0.0, false, 0, true)
    B[:solo_t] = w.t
    NG.say!(w, c, "Boing time for me!"; duration = 2)
    NG.emit!(w, :boing_walk; who = c.name)
end

"E as Lumi by the toadstool: the nearest friend gets launched."
function near_launch(w, me)
    flat(me.pos, B[:center]) < CAP_R + 4.5f0 || return nothing
    cs = [c for c in w.creatures if c.id != me.id && !c.controlled && c.action !== :sleep &&
                                    !haskey(B[:sys].flights, c.id) && flat(c.pos, me.pos) < 7f0]
    isempty(cs) && return nothing
    return argmin(c -> flat(c.pos, me.pos), cs)
end
uses_e(w, me) = haskey(B, :center) && haskey(B, :sys) && (get(B, :e_used, -1.0) == w.t || near_launch(w, me) !== nothing)

function step_player!(s::Boing, game)
    w = game.world
    me = lumi_of(w)
    me === nothing && return
    a = me.action
    if me.controlled && a === :wave && s.last_action !== :wave
        c = near_launch(w, me)
        if c !== nothing
            B[:e_used] = w.t
            NG.leave_interactions!(w, c)
            home = c.id in s.members ? s.homes[c.id] : NG.ground(w.island, (c.pos[1], c.pos[2]))
            launch!(s, w, c, home; h = 7f0, solo = !(c.id in s.members))
            NG.say!(w, me, "Up you go, $(c.name)!"; duration = 2)
            NG.emit!(w, :boing_launch; who = c.name, by = me.name)
        end
    end
    s.last_action = a
end

# ---------------------------------------------------------------- camera

function boing_subject(w)
    s = get(B, :sys, nothing)
    (s === nothing || s.state !== :bounce) && return nothing
    return isempty(s.members) ? nothing : first(s.members)     # one subject the whole party: the camera holds the wide view
end

function boing_group(w)
    id = boing_subject(w)
    id === nothing && return nothing
    s = B[:sys]
    ps = [B[:center] + Point3f(0, 0, 8)]
    for m in s.members
        c = NG.creature(w, m); c === nothing || push!(ps, c.pos)
    end
    return s.view === nothing ? (id, ps) : (id, ps, s.view)
end

# ---------------------------------------------------------------- system

function NG.start!(s::Boing, game)
    B[:sys] = s
    delete!(B, :center)
    NG.CAMERA_MOMENTS["boing"] = boing_subject
    NG.CAMERA_GROUPS["boing"] = boing_group
    game.stage === nothing || init!(s, game)
end

function init!(s::Boing, game)
    n = count(c -> c.action !== :sleep, game.world.creatures)
    p = find_spot(game, min(n, 12))
    p === nothing && error("boing: no open place for the toadstool")
    B[:center] = p
    build!(game)
    s.next_t = game.world.t + 25.0          # the first party soon after it appears
end

function NG.step!(s::Boing, game, dt)
    game.stage === nothing && return
    haskey(B, :center) || init!(s, game)
    w = game.world
    squash!(w.t - s.squash_t)
    step_flights!(s, game, dt)
    step_player!(s, game)
    testing = game.tests !== nothing && NG.running(game.tests)
    busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
    if s.state === :idle
        if w.t >= s.next_t && !testing && !busy_game && 7.5 < hour(w) < 19.5
            start_party!(s, game) || (s.next_t = w.t + 40)
        end
        testing || busy_game || step_solo!(s, game)
    else
        # a play test starting mid-party found every critter on the toadstool (s64: tag, ball play)
        busy_game || testing ? end_party!(s, game; why = busy_game ? "mini game" : "test") : step_party!(s, game, dt)
    end
    return
end

function NG.stop!(s::Boing, game)
    delete!(NG.CAMERA_MOMENTS, "boing")
    delete!(NG.CAMERA_GROUPS, "boing")
    w = game.world
    for c in w.creatures
        c.goal.kind in (:boing, :boing_walk) || continue
        c.pos = NG.ground(w.island, (c.pos[1], c.pos[2]))
        NG.choose_goal!(c, w)
    end
    empty!(s.flights)
    s.state = :idle
    clear_plots!()
end

register!(Boing())
