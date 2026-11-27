# Skipping stones (s131). Jumped in as Lumi, stand on the beach facing the sea and press Y: Lumi throws a flat
# stone low and fast. It flies under gravity; each time it meets the sea it skips only if it comes in flat
# (its path under ~35° to the surface; Clanet, Hersen & Bocquet 2004, "Secrets of successful stone-skipping", found
# the best tilt of the stone itself is 20°, which this does not model) and still fast enough; every skip costs it speed, so the hops get shorter and closer until it sinks. Every touch
# leaves a ring that spreads and fades. A throw over land just lands. How many skips depends on where you stand
# and which way you face.
using GeometryBasics, Makie, Random
const NG = NeverendingGame
isdefined(Main, :STONESKIP) || Core.eval(Main, :(const STONESKIP = Dict{Symbol,Any}()))
const SK = Main.STONESKIP

const SK_HIDE = Point3f(0, 0, -50)
const SK_RINGS = 24
const SK_G = 9.81f0
const SK_MAXANGLE = deg2rad(35f0)     # a path steeper than this into the water digs in and sinks
const SK_MINV = 3.0f0                 # m/s along the surface below which it cannot lift off again
const SK_KEEP = 0.82f0                # share of the along-surface speed kept per skip
const SK_REST = 0.55f0                # share of the vertical speed returned per skip
const SK_RING_T = 2.2f0
# s131 first test: thrown from 0.9 m at 6-12° up it came in at ~25° and plopped every time; Lumi now throws
# side-arm from 0.5 m, 1-7° up (people crouch to skip stones).

struct StoneSkip <: System end

function sk_ring_mesh(n = 40)
    pts = Point3f[]; fs = GLTriangleFace[]
    for k in 0:n-1
        a = 2f0 * Float32(pi) * k / n
        push!(pts, Point3f(0.88f0 * cos(a), 0.88f0 * sin(a), 0f0), Point3f(cos(a), sin(a), 0f0))
    end
    for k in 0:n-1
        i = 2k + 1; j = 2mod(k + 1, n) + 1
        push!(fs, GLTriangleFace(i, i + 1, j + 1), GLTriangleFace(i, j + 1, j))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

function sk_build!(game)
    for k in (:stone, :rings)
        haskey(SK, k) && SK[k].parent !== nothing && delete!(SK[k].parent, SK[k])
    end
    sc = game.stage.scene
    SK[:stone] = meshscatter!(sc, [SK_HIDE]; marker = GeometryBasics.Sphere(Point3f(0), 1f0),
        markersize = [Vec3f(0)], color = RGBf(0.55, 0.55, 0.58),
        material = NG.Hikari.Diffuse(color = (0.55, 0.55, 0.58)), name = :stoneskip_stone)
    SK[:rings] = meshscatter!(sc, fill(SK_HIDE, SK_RINGS); marker = sk_ring_mesh(), markersize = fill(Vec3f(0), SK_RINGS),
        color = RGBf(0.92, 0.97, 1.0), material = NG.Hikari.Diffuse(color = (0.92, 0.97, 1.0)), name = :stoneskip_rings)
    SK[:fly] = nothing; SK[:ring] = Tuple{Point3f,Float32}[]; SK[:ydown] = false
end

function sk_throw!(w, me; yaw = me.yaw + NG.species_of(me).heading)
    SK[:who] = me.id
    f = Vec3f(cos(yaw), sin(yaw), 0f0)
    v = 8f0 + 5f0 * rand(Float32)                      # never quite the same throw
    up = deg2rad(1f0 + 6f0 * rand(Float32))
    SK[:fly] = (pos = Point3f(me.pos) + 0.4f0 * f + Point3f(0, 0, 0.5f0), vel = v * (cos(up) * f + Vec3f(0, 0, sin(up))), skips = 0)
    NG.say!(w, me, rand(("Watch this!", "Flat and fast...", "Skip, skip, skip!")); duration = 1.6)
end

function sk_thrower(w)
    i = findfirst(c -> c.id == get(SK, :who, Int32(-1)), w.creatures)
    i === nothing ? nothing : w.creatures[i]
end

sk_say!(w, text) = (c = sk_thrower(w); c === nothing || NG.say!(w, c, text; duration = 2.2))

"Friends near the thrower count along: a big one gets a cheer."
function sk_cheer!(w, skips)
    skips >= 6 || return
    c = sk_thrower(w); c === nothing && return
    for x in w.creatures
        x !== c && hypot(x.pos[1] - c.pos[1], x.pos[2] - c.pos[2]) < 8 &&
            (NG.say!(w, x, rand(("WOW! $(skips)!", "How do you DO that?", "My turn next!", "Count them again!")); duration = 2.0); break)
    end
end

"The nearest shore from a friend: march out in 16 directions until the sea; a spot 1.5 m before it, and the way out."
function sk_shore(w, c)
    best = nothing
    for k in 0:15
        a = Float32(pi) * k / 8
        for d in 1f0:1f0:25f0
            if NG.terrain_height(w.island, c.pos[1] + d * cos(a), c.pos[2] + d * sin(a)) < -0.05f0
                (best === nothing || d < best[1]) && (best = (d, a))
                break
            end
        end
    end
    best === nothing && return nothing
    d, a = best
    p = NG.ground(w.island, (c.pos[1] + (d - 1.5f0) * cos(a), c.pos[2] + (d - 1.5f0) * sin(a)))
    return Point3f(p), a
end

function sk_step!(w, me, dt)
    s = SK[:fly]
    s === nothing && return
    pos, vel, skips = s.pos, s.vel + Vec3f(0, 0, -SK_G * dt), s.skips
    pos = pos + dt * vel
    land = NG.terrain_height(w.island, pos[1], pos[2])
    if land > 0f0 && pos[3] <= land                    # over land: it lands and stays
        SK[:fly] = nothing; SK[:rest] = (Point3f(pos[1], pos[2], land + 0.02f0), time())
        sk_say!(w, skips == 0 ? "That's land, silly." : "$skips skips, then the beach!")
        return
    end
    if pos[3] <= 0f0                                    # the sea
        vh = hypot(vel[1], vel[2])
        β = atan(-vel[3], vh)
        push!(SK[:ring], (Point3f(pos[1], pos[2], 0.012f0), Float32(time())))
        if β < SK_MAXANGLE && vh > SK_MINV
            skips += 1
            keep = SK_KEEP + 0.08f0 * (2rand(Float32) - 1)   # how cleanly it meets the water (wobble, tilt)
            vel = Vec3f(keep * vel[1], keep * vel[2], SK_REST * abs(vel[3]))
            pos = Point3f(pos[1], pos[2], 0.001f0)
        else
            SK[:fly] = nothing
            NG.emit!(w, :stone_skipped; skips)
            sk_say!(w, skips == 0 ? "Plop. Flatter!" : skips == 1 ? "One skip!" : "$skips skips!")
            sk_cheer!(w, skips)
            return
        end
    end
    SK[:fly] = (pos = pos, vel = vel, skips = skips)
end

function NG.step!(::StoneSkip, game, dt)
    game.stage === nothing && return
    (haskey(SK, :rings) && SK[:rings].parent === game.stage.scene) || sk_build!(game)
    NG.path_traced(game) && return
    w = game.world
    me = NG.creature(w, "Lumi")
    me === nothing && return
    ydown = Makie.Keyboard.y in game.keys_down
    ydown && !SK[:ydown] && me.controlled && SK[:fly] === nothing && sk_throw!(w, me)
    # by day, now and then a friend walks down to the nearest shore and skips one
    if SK[:fly] === nothing && get(SK, :walker, nothing) === nothing && time() > get(SK, :auto_next, 0.0) &&
       NG.night_factor(w) < 0.5f0 && (game.minigame === nothing || game.minigame isa NG.JumpIn)
        SK[:auto_next] = time() + 75.0
        cs = [c for c in w.creatures if !c.controlled && c.action !== :sleep && c.name != "Lumi"]
        if !isempty(cs)
            c = rand(cs)
            sh = sk_shore(w, c)
            if sh !== nothing
                c.goal = NG.Goal(:skipstones, sh[1], :idle, 6.0, w.t + 60.0, false, 0, false)
                SK[:walker] = (c.id, sh[2], time())
                NG.say!(w, c, rand(("I'm going to skip stones!", "Bet I can do ten.", "Stone skipping time!")); duration = 2.2)
            end
        end
    end
    wk = get(SK, :walker, nothing)
    if wk !== nothing
        i = findfirst(x -> x.id == wk[1], w.creatures)
        if i === nothing || time() - wk[3] > 45 || w.creatures[i].goal.kind !== :skipstones
            SK[:walker] = nothing
        elseif w.creatures[i].goal.arrived && SK[:fly] === nothing
            c = w.creatures[i]
            c.yaw = wk[2] - NG.species_of(c).heading
            sk_throw!(w, c; yaw = wk[2])
            NG.emit!(w, :stone_throw; who = c.name)
            SK[:walker] = nothing
        end
    end
    SK[:ydown] = ydown
    h = Float32(min(dt, 0.05)) / 4
    for _ in 1:4
        sk_step!(w, me, h)
    end
    fly = SK[:fly]
    rest = get(SK, :rest, nothing)
    sp = fly !== nothing ? fly.pos : (rest !== nothing && time() - rest[2] < 6 ? rest[1] : SK_HIDE)
    Makie.update!(SK[:stone]; arg1 = [sp], markersize = [sp === SK_HIDE ? Vec3f(0) : Vec3f(0.07, 0.07, 0.025)])
    now = Float32(time())
    filter!(r -> now - r[2] < SK_RING_T, SK[:ring])
    pos = fill(SK_HIDE, SK_RINGS); ms = fill(Vec3f(0), SK_RINGS)
    for (k, (p, t0)) in enumerate(Iterators.take(Iterators.reverse(SK[:ring]), SK_RINGS))
        a = (now - t0) / SK_RING_T
        r = 0.15f0 + 1.3f0 * sqrt(a)
        pos[k] = p; ms[k] = Vec3f(r, r, 1f0) * (a < 0.85f0 ? 1f0 : (1f0 - a) / 0.15f0)
    end
    Makie.update!(SK[:rings]; arg1 = pos, markersize = ms)
    return
end

register!(StoneSkip())
