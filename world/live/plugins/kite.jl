# The kite (Lumi's wish: "a kite on windy afternoons over the meadow"): once every afternoon Lumi
# walks out to the open meadow, says the wind is just right and flies a red-and-yellow kite high over
# the trees, its ribbon tail wriggling in the wind. Free friends nearby come to watch, cheer and hop;
# after a while Lumi hands the string to one of them ("your turn!"), and the kite goes on flying.
# Whoever holds the string keeps the kite: a player who jumps into the flyer runs with it, and the
# faster it runs, the higher the kite climbs (it sinks when it stands still).
# Plots: one meshscatter (the kite, one instance, a two-tone diamond), the string and tail (lines),
# the tail's bows (meshscatter). Hidden with `visible` while nobody flies.
isdefined(Main, :KITE) || Core.eval(Main, :(const KITE = Dict{Symbol,Any}()))

const NG = NeverendingGame
const K = Main.KITE
const AFTERNOON = (13.0, 16.5)          # hours the kite may go up (once a day)
const FLIGHT = 420.0                    # sim seconds of one flight (~half an hour of island time)
const HANDOVER = 200.0                  # s until Lumi passes the string on
const STRING_L = 12.0f0                 # m of string
const RED = RGBf(0.92, 0.36, 0.30)
const YELLOW = RGBf(0.99, 0.80, 0.33)
const BLUE = RGBf(0.36, 0.62, 0.92)
const N_BOWS = 7
const KSIZE = 1.6f0                     # a 1.6 m kite: at 12 m of string a 1 m one was a speck
const CHEERS = ("Higher! Higher!", "Wheee!", "It's dancing!", "Look how high!", "Ooh, a loop!")

hour(w) = 24 * NG.daytime(w)
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free_one(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact)
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

"The wind: from the sea in the south-west, veering slowly over the day."
wind_dir(t) = isdefined(Main, :WIND) && haskey(Main.WIND, :now) ? Base.invokelatest(Main.WIND[:now], t)[1] :
              (a = 0.6f0 + 0.5f0 * sin(Float32(t) / 900f0); Vec2f(cos(a), sin(a)))   # the grass's wind (wind.jl) since s73

"The open meadow spot with the most room around it (no tree crowns, rocks, actors, not the pond)."
function kite_spot(game)
    w = game.world
    is = w.island
    pond = haskey(game.plugins, "areas") ? game.plugins["areas"].mod.POND : Point2f(-5.5, 10.5)
    best, bq = -Inf32, nothing
    for x in -24:1:24, y in -24:1:24
        q = (Float32(x), Float32(y))
        NG.on_land(is, q...; margin = 1.5f0) || continue
        flat(pond, q) < 4.5f0 && continue
        d = minimum((flat(p.pos, q) - (p.kind === :tree ? 2.6f0 * p.scale : 0.8f0 * p.scale) for p in w.props); init = 99f0)
        da = minimum((flat(a.pos, q) - a.scale for a in w.actors if a isa NG.AssetActor); init = 99f0)
        m = min(d, da)
        m > best && (best = m; bq = q)
    end
    return NG.ground(is, bq)
end

"The nearest open meadow within 7 m of `p` (2 m from trunks, rocks and actors, well above the sea), or nothing."
function open_near(game, p)
    w = game.world
    best, bq = 7.5f0, nothing
    for dx in -7:1:7, dy in -7:1:7
        q = (Float32(p[1] + dx), Float32(p[2] + dy))
        d = flat(p, q)
        d < best || continue
        NG.on_land(w.island, q...; margin = 1.2f0) || continue
        clear = all(flat(o.pos, q) > (o.kind === :tree ? 2.6f0 * o.scale : 0.8f0 * o.scale) + 0.5f0 for o in w.props) &&
                all(flat(a.pos, q) > a.scale + 0.5f0 for a in w.actors if a isa NG.AssetActor)
        clear && (best = d; bq = q)
    end
    return bq === nothing ? nothing : NG.ground(w.island, bq)
end

"A diamond kite, its face in the local x-z plane, its back towards +y: red left half, yellow right."
function kite_mesh()
    top, bot = Point3f(0, 0, 0.55), Point3f(0, 0, -0.45)
    l, r, c = Point3f(-0.34, 0, 0.12), Point3f(0.34, 0, 0.12), Point3f(0, 0.04, 0.12)
    ps = KSIZE .* Point3f[top, l, c, c, l, bot, top, c, r, c, bot, r]
    fs = [GeometryBasics.TriangleFace(i, i + 1, i + 2) for i in 1:3:12]
    cols = [fill(RED, 6); fill(YELLOW, 6)]
    return GeometryBasics.normal_mesh(ps, fs), cols
end

function build!(game)
    sc = game.stage.scene
    # a reload in the same scene keeps the plots: deleting them failed in RayMakie
    # (delete_trace_handles!: no trace_parts(::RenderObject), s57)
    get(K, :scene, nothing) == objectid(sc) && length(get(K, :plots, Dict())) == 4 && return
    km, cols = kite_mesh()
    far = Point3f(0, 0, -50)
    K[:plots] = Dict{Symbol,Any}(
        :kite => mesh!(sc, km; color = cols, name = :kite, visible = false),
        :string => lines!(sc, fill(far, 24); color = RGBf(0.95, 0.93, 0.88), linewidth = 1.2, name = :kite_string, visible = false),
        :tail => lines!(sc, fill(far, N_BOWS + 1); color = BLUE, linewidth = 2.5, name = :kite_tail, visible = false),
        :bows => meshscatter!(sc, fill(far, N_BOWS); marker = NG.shape(:sphere), markersize = Vec3f(0.14, 0.14, 0.08),
                              color = [isodd(i) ? RED : YELLOW for i in 1:N_BOWS], name = :kite_bows, visible = false))
    K[:scene] = objectid(sc)
    K[:shown] = false
end

function clear!()
    for p in values(get(K, :plots, Dict()))
        p.parent === nothing || delete!(p.parent, p)
    end
    K[:plots] = Dict{Symbol,Any}()
end

show_kite!(on) = (K[:shown] == on || (foreach(p -> p.visible = on, values(K[:plots])); K[:shown] = on))

"The one holding the string (any creature on goal :kite, or a player steering the last flyer)."
function flyer(w)
    id = get(K, :flyer, Int32(0))
    id == 0 && return nothing
    c = NG.creature(w, id)
    c === nothing && return nothing
    # the player let go of Lumi (Stop) with the kite still up: Lumi keeps flying it on its own (s85, todo 435:
    # jump-in leaves an empty goal behind, and the kite was let go the very next frame)
    if !c.controlled && c.goal.kind !== :kite && get(K, :steered, false)
        gone = w.t - get(K, :since, w.t)
        c.goal = NG.Goal(:kite, c.pos, :idle, FLIGHT, w.t + max(20.0, FLIGHT - gone), true, 0, false)
    end
    K[:steered] = c.controlled
    c.controlled || c.goal.kind === :kite || return nothing
    return c
end

watchers(w) = filter(id -> (c = NG.creature(w, id); c !== nothing && !c.controlled && c.goal.kind === :kitewatch), get(K, :watchers, Int32[]))

fly_goal(w, q) = NG.Goal(:kite, q, :idle, FLIGHT, 0.0, false, 0, false)

"Lumi goes out with its kite; up to three free friends near the spot come and watch."
function launch!(game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || !free_one(me)) && return false
    q = K[:spot]
    NG.leave_interactions!(w, me)
    me.goal = fly_goal(w, q)
    K[:flyer] = me.id; K[:since] = w.t; K[:detour] = false; K[:near] = false; K[:tries] = 0; delete!(K, :progress); K[:handed] = false; K[:up] = false
    K[:elev] = 0.15f0; K[:prev] = Point3f(me.pos)
    near = sort([c for c in w.creatures if c !== me && free_one(c) && flat(c.pos, q) < 30]; by = c -> flat(c.pos, q))
    ws = Int32[]
    for (k, c) in enumerate(near[1:min(end, 3)])
        NG.leave_interactions!(w, c)
        a = Float32(2pi * k / 3 + 0.4)
        p = NG.ground(w.island, (q[1] + 2.6f0 * cos(a), q[2] + 2.6f0 * sin(a)))
        c.goal = NG.Goal(:kitewatch, p, :idle, FLIGHT, 0.0, false, me.id, false)
        push!(ws, c.id)
    end
    K[:watchers] = ws
    K[:next_cheer] = w.t + 25.0
    NG.say!(w, me, "The wind is just right! Kite time!"; duration = 3.0)
    NG.emit!(w, :kite_launch; who = join([NG.creature(w, id).name for id in [me.id; ws]], ", "))
    return true
end

function land!(w, why)
    c = flyer(w)
    if c !== nothing && !c.controlled
        NG.say!(w, c, "Down she comes. That was lovely!"; duration = 2.5)
        c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, w.t + 1.0, true, 0, false); c.action = :idle
    end
    for id in watchers(w)
        o = NG.creature(w, id)
        o.goal = NG.Goal(:idle, o.pos, :idle, 1.0, w.t + 1.0, true, 0, false); o.action = :idle
    end
    NG.emit!(w, :kite_land; why = String(why))
    K[:flyer] = Int32(0); K[:watchers] = Int32[]
end

"""Creatures walk in straight lines and wedge between trunks (separation.jl drops the walk after 12 s):
no 0.3 m closer in 3 s → a clear spot 2.5 m to the side first (as builder.jl `unstuck!`)."""
function unstuck!(game, c)
    w = game.world
    goal = get(K, :detour, false) ? c.goal.target : K[:spot]
    d, t0 = get!(K, :progress, (flat(c.pos, goal), w.t))
    dn = flat(c.pos, goal)
    dn < d - 0.3f0 && (K[:progress] = (dn, w.t); return)
    w.t - t0 < 3 && return
    if get(K, :detour, false) || get(K, :tries, 0) >= 2
        # boxed in twice: the nearest open bit of meadow instead (s58: Lumi flew it on the shore, where
        # a player who jumped in could not walk); with none in reach it goes up right here
        q = get(K, :near, false) ? nothing : open_near(game, c.pos)
        if q !== nothing
            c.goal.target = q; c.goal.arrived = false
            K[:detour] = true; K[:near] = true
            K[:progress] = (flat(c.pos, q), w.t)
            return
        end
        c.goal.target = Point3f(c.pos); c.goal.arrived = true; c.goal.until = w.t + FLIGHT; c.action = :idle
        K[:detour] = false
        return
    end
    K[:tries] = get(K, :tries, 0) + 1
    clear_at = game.plugins["builder"].mod.clear_at
    a = atan(K[:spot][2] - c.pos[2], K[:spot][1] - c.pos[1])
    for da in (1.57f0, -1.57f0, 2.36f0, -2.36f0, 3.14f0), r in (2.5f0, 1.6f0)
        x, y = c.pos[1] + r * cos(a + da), c.pos[2] + r * sin(a + da)
        mx, my = c.pos[1] + 0.5f0r * cos(a + da), c.pos[2] + 0.5f0r * sin(a + da)
        (Base.invokelatest(clear_at, w, x, y) && Base.invokelatest(clear_at, w, mx, my)) || continue
        c.goal.target = NG.ground(w.island, (x, y)); c.goal.arrived = false
        K[:detour] = true
        K[:progress] = (flat(c.pos, (x, y)), w.t)
        return
    end
    K[:progress] = (dn, w.t)
end

"Where the string is held: in front of the flyer, at hand height, towards the kite."
function hand_of(c, kite)
    d = Vec2f(kite[1] - c.pos[1], kite[2] - c.pos[2])
    f = norm(d) < 1f-3 ? Vec2f(1, 0) : normalize(d)
    return Point3f(c.pos) + Vec3f(0.25f0 * f[1], 0.25f0 * f[2], 0.3f0)
end

"Turns the diamond's back (+y) along the string and its top up."
function kite_rotation(n)
    q1 = Makie.rotation_between(Vec3f(0, 1, 0), n)
    r = normalize(cross(n, Vec3f(0, 0, 1)))
    want = cross(r, n)
    got = q1 * Vec3f(0, 0, 1)
    ang = atan(dot(cross(got, want), n), dot(got, want))
    return Makie.qrotation(n, ang) * q1
end

function step_flight!(game, dt)
    w = game.world
    c = flyer(w)
    t = Float32(w.t)
    if c === nothing
        land!(w, :let_go); show_kite!(false); return
    end
    gone = w.t - K[:since]
    # the player runs with it: speed lifts the kite, standing lets it sink; a critter's kite rides the wind
    v = flat(c.pos, K[:prev]) / max(Float32(dt), 1f-3)
    K[:prev] = Point3f(c.pos)
    if !c.controlled && c.goal.kind === :kite
        if get(K, :detour, false) && c.goal.arrived && get(K, :near, false)   # at the open bit: fly here
            K[:detour] = false; c.goal.until = w.t + FLIGHT; c.action = :idle
        elseif get(K, :detour, false) && c.goal.arrived   # round the obstacle: on to the spot again
            c.goal.target = K[:spot]; c.goal.arrived = false; K[:detour] = false
            K[:progress] = (flat(c.pos, K[:spot]), w.t)
        elseif !c.goal.arrived && flat(c.pos, K[:spot]) < 1.3f0   # close enough: a fern or a friend in the way
            c.goal.arrived = true; c.goal.until = w.t + FLIGHT; c.action = :idle
        elseif !c.goal.arrived
            unstuck!(game, c)
        end
    end
    arrived = c.controlled || (c.goal.arrived && !get(K, :detour, false))
    # a player's kite answers at once: running lifts it fast, standing lets it sink slowly (tester s57:
    # 4 s of running moved it 0.83 → 0.87, nobody could tell)
    target = !arrived ? 0.25f0 : c.controlled ? clamp(0.2f0 + 0.55f0 * v, 0.2f0, 1.1f0) : 0.95f0
    rate = c.controlled ? (target > K[:elev] ? 0.9f0 : 0.25f0) : (target > K[:elev] ? 0.35f0 : 0.12f0)
    K[:elev] += (target - K[:elev]) * min(1.0f0, Float32(dt) * rate)
    e = K[:elev] + 0.06f0 * sin(0.7f0 * t) + 0.03f0 * sin(2.3f0 * t)
    wd = wind_dir(t)
    if c.controlled
        # the player's kite flies ahead of them (smoothed heading), so the chase view behind has it in frame
        a = c.yaw + NG.species_of(c).heading
        f = Vec2f(cos(a), sin(a))
        k0 = get(K, :lead, f)
        ld = k0 + min(1f0, 1.5f0 * Float32(dt)) * (f - k0)
        ld = norm(ld) < 1f-3 ? f : normalize(ld)
        K[:lead] = ld; wd = ld
    else
        delete!(K, :lead)
    end
    side = Vec2f(-wd[2], wd[1])
    sway = 2.2f0 * sin(0.45f0 * t) + 0.8f0 * sin(1.3f0 * t)
    hand = hand_of(c, Point3f(c.pos[1] + wd[1], c.pos[2] + wd[2], 0))
    L = arrived ? STRING_L : 4.0f0
    kite = hand + Vec3f(L * cos(e) * wd[1] + sway * side[1], L * cos(e) * wd[2] + sway * side[2], L * sin(e) + 0.6f0)
    n = normalize(Vec3f(kite - hand))
    q = kite_rotation(n)
    P = K[:plots]
    Makie.rotate!(P[:kite], q); translate!(P[:kite], Vec3f(kite))
    # the string sags a little in the middle
    P[:string][1] = [hand + s * (kite - hand) - Vec3f(0, 0, 0.9f0 * 4s * (1 - s)) for s in range(0f0, 1f0; length = 24)]
    # the tail streams downwind from the kite's bottom tip, wriggling
    bottom = kite + q * Vec3f(0, 0, -0.45f0 * KSIZE)
    s3 = Vec3f(side[1], side[2], 0)
    tail = [bottom + Vec3f(0.42f0 * k * wd[1], 0.42f0 * k * wd[2], -0.26f0 * k) + 0.2f0 * sin(7f0 * t - 1.1f0 * k) * s3 for k in 0:N_BOWS]
    P[:tail][1] = tail
    P[:bows][1] = tail[2:end]
    show_kite!(true)
    if !c.controlled
        # facing the kite, now and then a tug
        c.yaw = atan(wd[2], wd[1]) - NG.species_of(c).heading
        arrived && (c.goal.until = max(c.goal.until, K[:since] + FLIGHT))
        if arrived && !K[:up]
            K[:up] = true
            K[:day] = floor(Int, w.t / w.day_length)     # today's flight is done once the kite is up (a wedged walk retries)
            NG.say!(w, c, "Up, up, up!"; duration = 2.0); emote(c.id, :heart)
        end
    end
    # the watchers look up and cheer
    for id in watchers(w)
        o = NG.creature(w, id)
        o.goal.arrived || continue
        o.goal.until = max(o.goal.until, w.t + 5.0)
        o.yaw = atan(kite[2] - o.pos[2], kite[1] - o.pos[1]) - NG.species_of(o).heading
        o.action = mod(t + 1.7f0 * id, 9f0) < 1.2f0 ? :jump : :idle
    end
    ws = watchers(w)
    if w.t >= K[:next_cheer] && !isempty(ws)
        o = NG.creature(w, rand(w.rng, ws))
        NG.say!(w, o, rand(w.rng, CHEERS); duration = 2.0); emote(o.id, :note)
        K[:next_cheer] = w.t + 18.0 + 10rand(w.rng)
    end
    # Lumi passes the string on to a friend
    if !c.controlled && !K[:handed] && gone > HANDOVER && !isempty(ws)
        o = NG.creature(w, ws[1])
        if o.goal.arrived
            NG.say!(w, c, "Your turn, $(o.name)! Hold tight!"; duration = 2.5)
            o.goal = NG.Goal(:kite, o.pos, :idle, FLIGHT, w.t + FLIGHT - gone, true, 0, false)
            c.goal = NG.Goal(:kitewatch, c.pos, :idle, FLIGHT, w.t + FLIGHT - gone, true, o.id, false)
            K[:watchers] = Int32[filter(!=(o.id), ws); c.id]
            K[:flyer] = o.id; K[:handed] = true
            emote(o.id, :heart)
            NG.emit!(w, :kite_handover; to = o.name)
        end
    end
    meter!(game, c.controlled ? K[:elev] : nothing)
    gone > FLIGHT && !c.controlled && (land!(w, :done); show_kite!(false))
    hour(w) > AFTERNOON[2] + 1.5 && !c.controlled && (land!(w, :evening); show_kite!(false))
end

"""The camera: low behind the flyer's shoulder, looking up the string, so flyer and kite are both in
view. The eye is picked among a few spots behind the flyer by `NG.obstruction` plus nightshots'
`clutter` (the first take sat inside a toadstool), once every 2 s so it does not jitter."""
function kite_group(w)
    c = flyer(w)
    c !== nothing && c.controlled && return player_view(w, c)
    (c === nothing || !(c.goal.arrived)) && return nothing
    wd = wind_dir(w.t)
    side = Vec2f(-wd[2], wd[1])
    p = Vec2f(c.pos[1], c.pos[2])
    t2 = p + 4.0f0 * wd
    target = Point3f(t2[1], t2[2], c.pos[3] + 5.0f0)   # flyer low, kite high: 8 m back both fit the 45° view
    pts = Point3f[Point3f(c.pos)]               # [p; ps] would splat the point's coordinates
    append!(pts, [Point3f(NG.creature(w, id).pos) for id in watchers(w)])
    cached = get(K, :view, nothing)
    if cached === nothing || cached[1] != c.id || w.t - cached[2] > 2.0
        clutter = get(K, :clutter, nothing)
        best, eye = Inf32, nothing
        # behind the flyer first; boxed in by crowns (a wedged walk flies the kite where it stands, s58),
        # swing round to the sides and up, so the kite still gets its view
        for turn in (0f0, 0.5f0, -0.5f0, 1.0f0, -1.0f0, 1.6f0, -1.6f0), back in (10.0f0, 12.0f0), up in (2.0f0, 4.5f0)
            a = atan(wd[2], wd[1]) + turn
            bd = Vec2f(cos(a), sin(a))
            e = p - back * bd
            NG.on_land(w.island, e[1], e[2]; margin = 0.1f0) || continue
            ez = max(NG.terrain_height(w.island, e[1], e[2]), c.pos[3]) + up
            E = Point3f(e[1], e[2], ez)
            o = NG.obstruction(w, E, Point3f(c.pos) + Point3f(0, 0, 0.4f0)) + NG.obstruction(w, E, target) +
                (clutter === nothing ? 0f0 : Base.invokelatest(clutter, w, E, Point3f(c.pos), c.id, c.pos)) +
                0.04f0 * abs(turn) + 0.02f0 * (up - 2f0)
            o < best && (best = o; eye = E)
        end
        K[:view] = (c.id, w.t, eye, best)
        cached = K[:view]
    end
    eye = cached[3]
    (eye === nothing || cached[4] > 0.6f0) && return (c.id, pts)      # nothing clear: the usual group view
    # held_subject (render.jl) gives the camera to the group with the most points: a dance ring
    # took it from the kite in the s57 test. The kite flies once a day, so with a clear view of its own
    # it counts as a big moment (the points are not used for that view, only counted).
    while length(pts) < 10
        push!(pts, Point3f(c.pos))
    end
    return (c.id, pts, (eye, target))
end

"""The player holding the string: from behind and low (WASD stays "forward is away from me"), looking
up between them and the kite, so both are in frame (tester s57: the chase view showed only string)."""
function player_view(w, c)
    ld = get(K, :lead, nothing)
    (ld === nothing || !haskey(K, :plots)) && return nothing
    kite = Point3f(K[:plots][:kite].transformation.translation[])
    p = Point3f(c.pos)
    eye = p - Vec3f(12f0 * ld[1], 12f0 * ld[2], 0) + Vec3f(0, 0, 1.4f0)
    eye = Point3f(eye[1], eye[2], max(eye[3], NG.terrain_height(w.island, eye[1], eye[2]) + 1.2f0))
    # aim half way between the two directions, so Lumi (low) and the kite (high) both fit the 45° view
    target = eye + 5f0 * normalize(normalize(p + Vec3f(0, 0, 0.4f0) - eye) + normalize(kite - eye))
    return (c.id, Point3f[p], (eye, target))
end

const METER = "Kite  "
"The jumped-in flyer's height meter: how high the kite is, and that running lifts it."
function meter!(game, elev)
    ov = game.stage.overlay
    ov === nothing && return
    if !haskey(K, :meter) || K[:meter].parent === nothing
        elev === nothing && return
        K[:meter] = textlabel!(ov, Point2f(0.5, 0.9); space = :relative, text = " ", fontsize = 20,
                               justification = :center, text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.82),
                               strokewidth = 0, padding = 12, cornerradius = 12)
    end
    m = K[:meter]
    on = elev !== nothing
    m.visible[] == on || (m.visible[] = on)
    on || return
    n = clamp(round(Int, 8 * (elev - 0.2f0) / 0.85f0), 0, 8)
    txt = METER * "▮"^n * "▯"^(8 - n) * (n >= 7 ? "   so high! keep running!" : "   run to lift it, stop and it sinks")
    m.text[] == txt || (m.text[] = txt)
end

struct Kite <: System end

function NG.start!(::Kite, game)
    game.stage === nothing && return
    for g in (:kite, :kitewatch)
        g in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, g)
    end
    build!(game)
    K[:spot] = kite_spot(game)
    w = game.world
    # after a reload: someone still holding the string flies on
    i = findfirst(c -> c.goal.kind === :kite, w.creatures)
    K[:flyer] = i === nothing ? Int32(0) : w.creatures[i].id
    K[:watchers] = Int32[c.id for c in w.creatures if c.goal.kind === :kitewatch]
    K[:since] = w.t; K[:handed] = false; K[:up] = false; K[:elev] = 0.5f0; K[:next_cheer] = w.t + 20.0
    K[:prev] = i === nothing ? Point3f(0) : Point3f(w.creatures[i].pos)
    K[:clutter] = haskey(game.plugins, "nightshots") ? game.plugins["nightshots"].mod.clutter : nothing
    delete!(K, :view)
    NG.CAMERA_GROUPS["kite"] = kite_group
    isdefined(Main, :LUMI_DOING) || Core.eval(Main, :(const LUMI_DOING = Dict{Symbol,String}()))
    Main.LUMI_DOING[:kite] = "Flying my kite, wheee!"
    Main.LUMI_DOING[:kitewatch] = "Watching our kite dance"
    return
end

function NG.step!(::Kite, game, dt)
    game.stage === nothing && return
    objectid(game.stage.scene) == get(K, :scene, nothing) || build!(game)
    w = game.world
    if get(K, :flyer, Int32(0)) != 0
        step_flight!(game, dt)
        return
    end
    show_kite!(false)
    haskey(K, :meter) && K[:meter].visible[] && (K[:meter].visible[] = false)
    day = floor(Int, w.t / w.day_length)
    h = hour(w)
    if AFTERNOON[1] <= h < AFTERNOON[2] && get(K, :day, -1) != day && game.minigame === nothing
        w.t >= get(K, :retry, -Inf) && launch!(game) && (K[:retry] = w.t + 60.0)
    end
    return
end

function NG.stop!(::Kite, game)
    delete!(NG.CAMERA_GROUPS, "kite")
    isdefined(Main, :LUMI_DOING) && (delete!(Main.LUMI_DOING, :kite); delete!(Main.LUMI_DOING, :kitewatch))
    game.stage === nothing && return
    w = game.world
    for c in w.creatures
        c.goal.kind in (:kite, :kitewatch) || continue
        c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, w.t + 1.0, true, 0, false); c.action = :idle
    end
    K[:flyer] = Int32(0); K[:watchers] = Int32[]
    foreach(p -> p.visible = false, values(get(K, :plots, Dict())))
    haskey(K, :meter) && (K[:meter].visible[] = false)
    K[:shown] = false
end

register!(Kite())
