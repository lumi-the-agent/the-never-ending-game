# Tied together (s117): some mornings every friend wakes up tied into one long elastic rope, each to the
# next, Lumi somewhere in the middle. Nobody agrees where to go. Nothing here is scripted: everyone keeps
# walking to wherever they wanted, and a real rope fights them. The rope is a chain of verlet points pinned
# at the friends' waists; it lies on the ground, wraps around tree trunks, and its tension (path length
# past its rest length, so a rope wound round a tree pulls toward the tree) pushes the friends it ties.
# A hard yank throws a friend into the air. Sleepers get dragged along in their sleep.
#   Main.TIED[:force] = true   start now (films, the sandbox)
#   Main.TIED[:sys]            the system (ids, pts, vel)
isdefined(Main, :TIED) || Core.eval(Main, :(const TIED = Dict{Symbol,Any}()))
const NG = NeverendingGame
const T = Main.TIED

const SEG = 3.0f0          # m of rope between two friends once it has reeled in
const SUB = 7              # rope pieces between two friends
const K = 7.0f0            # 1/s² of pull per metre the rope is stretched
const KMAX = 22.0f0        # the pull never exceeds this (m/s²)
const DAMP = 1.3f0         # 1/s, how fast a yank dies down
const VMAX = 4.0f0         # m/s: the fastest the rope drags anyone
const REEL = 18.0          # s the rope takes to reel in from where everyone stood
const LAST = 240.0         # s the friends stay tied
const ROPE_R = 0.07f0
const WAIST = 0.38f0
const ROPE_RED = RGBf(0.86, 0.30, 0.20)
const HOURS = (7.5, 9.5)
const YANKS = ("Hey! Let go!", "Whoa-oa-oa!", "Not that way!", "My bed is THIS way!", "Who's pulling?!",
               "Wheee- ow.", "Stop dragging me!", "Berries are over THERE!")

mutable struct Tied <: System
    on::Bool
    ids::Vector{Int32}
    pts::Vector{Point3f}
    old::Vector{Point3f}
    rest0::Vector{Float32}       # rest length of each piece when the rope appeared
    vel::Dict{Int32,Vec3f}       # what the rope adds to each friend's own walking (xy) and its hop speed (z)
    hop::Dict{Int32,Float32}     # height above the ground of a thrown friend
    said::Dict{Int32,Float64}
    t0::Float64
    day::Int
    wraps::Int
end
Tied() = Tied(false, Int32[], Point3f[], Point3f[], Float32[], Dict(), Dict(), Dict(), 0.0, -1, 0)

node(k) = (k - 1) * SUB + 1
waist(c) = Point3f(c.pos[1], c.pos[2], c.pos[3] + WAIST)

"A short chain through everyone: nearest neighbour from one end, so the rope does not cross the island at first."
function chain(cs)
    left = collect(cs)
    i = argmin([c.pos[1] + c.pos[2] for c in left])
    order = [popat!(left, i)]
    while !isempty(left)
        p = order[end].pos
        j = argmin([hypot(c.pos[1] - p[1], c.pos[2] - p[2]) for c in left])
        push!(order, popat!(left, j))
    end
    return order
end

function tie!(s::Tied, game)
    w = game.world
    cs = [c for c in w.creatures if c.species != "ghost"]
    length(cs) < 3 && return false
    order = chain(cs)
    s.ids = [c.id for c in order]
    s.pts = Point3f[]
    s.rest0 = Float32[]
    for k in 1:length(order)
        a = waist(order[k])
        k == length(order) && (push!(s.pts, a); break)
        b = waist(order[k + 1])
        push!(s.rest0, max(SEG, Float32(norm(b - a)) * 1.05f0))
        for j in 0:(SUB - 1)
            push!(s.pts, a + (b - a) * (j / SUB))
        end
    end
    s.old = copy(s.pts)
    empty!(s.vel); empty!(s.hop); empty!(s.said)
    for id in s.ids
        s.vel[id] = Vec3f(0); s.hop[id] = 0f0
    end
    s.on = true; s.t0 = w.t; s.wraps = 0
    s.day = floor(Int, w.t / w.day_length)
    lumi = findfirst(c -> c.name == "Lumi", order)
    lumi === nothing || NG.say!(w, order[lumi], "Who tied us all together?!"; duration = 3)
    NG.emit!(w, :tied_up; n = length(order), who = join([c.name for c in order], ", "))
    return true
end

function untie!(s::Tied, game)
    w = game.world
    for id in s.ids
        c = NG.creature(w, id)
        c === nothing && continue
        NG.remember!(c, w.t, "was tied to everyone else with one rope all morning")
        c.pos = Point3f(c.pos[1], c.pos[2], floor_at(game, c.pos[1], c.pos[2]))
    end
    isempty(s.ids) || (c = NG.creature(w, s.ids[1]); c === nothing || NG.say!(w, c, "Free!"; duration = 2.5))
    NG.emit!(w, :tied_free; wraps = s.wraps)
    s.on = false; empty!(s.ids)
    T[:force] = false
    show_rope!(s, false)
end

function build!(game)
    sc = game.stage.scene
    get(T, :scene, nothing) == objectid(sc) && haskey(T, :plot) && return
    far = Point3f(0, 0, -60)
    T[:plot] = meshscatter!(sc, fill(far, 2); marker = NG.shape(:cylinder), markersize = Vec3f(ROPE_R, ROPE_R, 0.1),
                            rotation = fill(Vec3f(0, 0, 1), 2), color = ROPE_RED, name = :tied_rope, visible = false)
    T[:scene] = objectid(sc)
end

function show_rope!(s::Tied, on)
    p = get(T, :plot, nothing)
    p === nothing && return
    p.visible[] == on || (p.visible[] = on)
end

function draw_rope!(s::Tied)
    p = get(T, :plot, nothing)
    p === nothing && return
    n = length(s.pts) - 1
    pos = Vector{Point3f}(undef, n); rot = Vector{Vec3f}(undef, n); ms = Vector{Vec3f}(undef, n)
    for i in 1:n
        d = s.pts[i + 1] - s.pts[i]
        l = Float32(norm(d))
        pos[i] = s.pts[i]
        rot[i] = l > 1f-4 ? Vec3f(d / l) : Vec3f(0, 0, 1)
        ms[i] = Vec3f(ROPE_R, ROPE_R, max(l, 1f-3) + ROPE_R)
    end
    Makie.update!(p; arg1 = pos, rotation = rot, markersize = ms)
    show_rope!(s, true)
end

"The ground as it is drawn: the terrain, never under the sea."
function floor_at(game, x, y)
    w = game.world
    z = NG.ground(w.island, (x, y))[3]
    return Float32(z)
end

function trunks(w)
    [(Point2f(p.pos[1], p.pos[2]), 0.2f0 * p.scale + ROPE_R) for p in w.props if p.kind === :tree]
end

function NG.step!(s::Tied, game, dt)
    w = game.world
    game.stage === nothing || objectid(game.stage.scene) == get(T, :scene, nothing) || build!(game)
    T[:sys] = s
    if !s.on
        h = 24 * NG.daytime(w)
        day = floor(Int, w.t / w.day_length)
        want = get(T, :force, false) ||
               (HOURS[1] <= h < HOURS[2] && day != s.day && game.minigame === nothing &&
                isdefined(Main, :LUMI_PARTY) && w.t >= get(Main.LUMI_PARTY, :until, -Inf))
        want && tie!(s, game) && isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + LAST)
        s.on || return
    end
    if w.t - s.t0 > LAST && !get(T, :force, false) || any(id -> NG.creature(w, id) === nothing, s.ids)
        untie!(s, game); return
    end
    dt = Float32(clamp(dt, 0.0, 0.05))
    dt <= 0 && return
    cs = [NG.creature(w, id) for id in s.ids]
    # 1. what the rope did to everyone last frame carries on (on top of their own walking this frame)
    for c in cs
        v = s.vel[c.id]
        x0 = c.pos[1]; y0 = c.pos[2]
        x = x0 + v[1] * dt; y = y0 + v[2] * dt
        fl = floor_at(game, x, y)
        h = s.hop[c.id] + v[3] * dt
        vz = v[3] - 9.8f0 * dt
        if h <= 0f0
            h = 0f0
            vz = 0f0
        end
        s.vel[c.id] = Vec3f(v[1], v[2], vz)
        # in the air: the rope's throw decides the height. On the ground: only the slope under the drag
        # changes it, so whatever else lifts a friend (a swing, a toadstool, Lumi's wings) keeps doing so
        z = h > 0f0 || s.hop[c.id] > 0f0 ? fl + h : c.pos[3] + (fl - floor_at(game, x0, y0))
        s.hop[c.id] = h
        c.pos = Point3f(x, y, z)
    end
    # 2. the rope: verlet points, pinned at the waists, lying on the ground, wound round trunks
    pinned = Set(node(k) for k in eachindex(cs))
    for (k, c) in enumerate(cs)
        s.pts[node(k)] = waist(c)
    end
    for i in eachindex(s.pts)
        i in pinned && continue
        p = s.pts[i]; o = s.old[i]
        s.old[i] = p
        s.pts[i] = p + (p - o) * 0.96f0 + Vec3f(0, 0, -9.8f0 * dt * dt)
    end
    reel = clamp(Float32((w.t - s.t0) / REEL), 0f0, 1f0)
    rest = [(r + (SEG - r) * reel) / SUB for r in s.rest0]
    tr = trunks(w)
    touching = 0
    for _ in 1:10
        for i in 1:(length(s.pts) - 1)
            a = s.pts[i]; b = s.pts[i + 1]
            d = b - a; l = norm(d)
            r0 = rest[(i - 1) ÷ SUB + 1]
            l <= r0 && continue
            corr = d * Float32((l - r0) / l)
            pa = i in pinned; pb = (i + 1) in pinned
            if pa && pb
                continue
            elseif pa
                s.pts[i + 1] = b - corr
            elseif pb
                s.pts[i] = a + corr
            else
                s.pts[i] = a + corr / 2; s.pts[i + 1] = b - corr / 2
            end
        end
        for i in eachindex(s.pts)
            i in pinned && continue
            p = s.pts[i]
            for (t, r) in tr
                dx = p[1] - t[1]; dy = p[2] - t[2]
                d2 = dx * dx + dy * dy
                if d2 < r * r && d2 > 1f-8
                    f = r / sqrt(d2)
                    p = Point3f(t[1] + dx * f, t[2] + dy * f, p[3])
                    touching += 1
                end
            end
            g = floor_at(game, p[1], p[2]) + ROPE_R
            p[3] < g && (p = Point3f(p[1], p[2], g))
            s.pts[i] = p
        end
    end
    touching > 0 && w.t - get(T, :wrap_t, -Inf) > 20 && (s.wraps += 1; T[:wrap_t] = w.t; NG.emit!(w, :tied_wrap))
    # 3. the pull: how much longer each piece of rope is than its rest length, toward the next rope point
    for (k, c) in enumerate(cs)
        F = Vec2f(0)
        for side in (-1, 1)
            (k + side < 1 || k + side > length(cs)) && continue
            piece = side < 0 ? k - 1 : k
            lo = node(piece); hi = node(piece + 1)
            len = sum(norm(s.pts[i + 1] - s.pts[i]) for i in lo:(hi - 1))
            stretch = len - rest[piece] * SUB
            stretch <= 0 && continue
            q = side < 0 ? s.pts[node(k) - 1] : s.pts[node(k) + 1]
            d = Vec2f(q[1] - c.pos[1], q[2] - c.pos[2])
            nd = norm(d)
            nd < 1f-4 && continue
            F += d / nd * min(K * stretch, KMAX)
        end
        # tied friends bump, they do not sink into each other
        for o in cs
            o === c && continue
            d = Vec2f(c.pos[1] - o.pos[1], c.pos[2] - o.pos[2])
            nd = norm(d)
            (nd < 1f-4 || nd > 1.0f0) && continue
            F += d / nd * 14f0 * (1.0f0 - nd)
        end
        v = s.vel[c.id]
        vxy = (Vec2f(v[1], v[2]) + F * dt) * exp(-DAMP * dt)
        vz = v[3]
        speed = norm(vxy)
        if speed > VMAX                       # a yank, not a teleport: the eye has to follow it (host motion measure)
            vxy = vxy * (VMAX / speed); speed = VMAX
        end
        # a hard yank throws a friend off its feet
        thrown = get!(() -> Dict{Int32,Float64}(), T, :thrown)
        if speed > 2.8f0 && s.hop[c.id] == 0f0 && w.t - get(thrown, c.id, -Inf) > 3.5
            vz = min(0.9f0 * speed, 5.5f0)
            s.hop[c.id] = 0.01f0
            thrown[c.id] = w.t
            NG.emit!(w, :tied_yank; who = c.name, speed = round(speed; digits = 1))
        end
        s.vel[c.id] = Vec3f(vxy[1], vxy[2], vz)
        if speed > 2.2f0 && w.t - get(s.said, c.id, -Inf) > 12
            NG.say!(w, c, YANKS[rand(w.rng, 1:length(YANKS))]; duration = 2)
            s.said[c.id] = w.t
        end
    end
    for (k, c) in enumerate(cs)
        s.pts[node(k)] = waist(c)
    end
    game.stage === nothing || draw_rope!(s)
    return
end

function NG.stop!(s::Tied, game)
    s.on && untie!(s, game)
end

register!(Tied())
