# The island has a ring (s120). The island pulls with gravity of its own (a softened point mass under the
# middle), and anything the day throws up fast enough never comes back: a kicked ball, splash water, a bonked
# pumpkin, petals from a pop, a feather from a crash. Each body is integrated for real (symplectic Euler in a
# Plummer field); bumping into the others damps their up-and-down and in-and-out wobble, so the ellipses
# slowly settle into one tilted ring that dips through the sea on one side. Now and then a friend goes up
# too and stays up for a few laps, bouncing off the meadow whenever its orbit grazes the island.
# The player as Lumi presses U: throws a pumpkin up, or the friend standing next to Lumi.
isdefined(Main, :ORBIT) || Core.eval(Main, :(const ORBIT = Dict{Symbol,Any}()))
const NG = NeverendingGame
const O = Main.ORBIT

const GM = 900f0                     # the island's pull
const EPS = 6f0                      # softening: its mass is spread through the rock
const NRM = Vec3f(0.5f0, 0f0, 0.866f0)   # the ring plane's normal: tilted 30 degrees
const KR = 0.05f0                    # damping of in-and-out speed (bumps between bodies)
const KN = 0.06f0                    # damping of speed across the ring plane
const MAXB = 1600
const RIDE_EVERY = 600.0             # real seconds between friends going up, live
# which of the island's events throw something up: chance, what goes up, how many
const LAUNCH = Dict(:ball_kick => (0.5, :ball, 1), :splash => (0.8, :drop, 4), :pumpkin_bonk => (1.0, :pumpkin, 1),
                    :boing => (0.6, :pebble, 1), :flight_crash => (1.0, :feather, 3), :sneeze => (0.7, :drop, 3),
                    :giant_pop => (1.0, :petal, 8), :paint_spill => (0.8, :paint, 3), :paint_hit => (0.4, :paint, 1),
                    :hiccup_punchline => (0.6, :pebble, 1), :tune_dance => (0.08, :petal, 1), :fishing => (0.3, :drop, 2))
const KINDS = (:pumpkin, :ball, :drop, :pebble, :feather, :petal, :paint)
const LOOK = Dict(:pumpkin => (RGBf(0.96, 0.5, 0.12), 0.45f0), :ball => (RGBf(0.92, 0.2, 0.22), 0.3f0),
                  :drop => (RGBf(0.55, 0.85, 1.0), 0.18f0), :pebble => (RGBf(0.66, 0.63, 0.58), 0.2f0),
                  :feather => (RGBf(1.0, 0.88, 0.35), 0.2f0), :petal => (RGBf(1.0, 0.62, 0.8), 0.17f0),
                  :paint => (RGBf(0.35, 0.55, 1.0), 0.2f0))

struct Ring <: System end
const RIDE_MAX = 300f0   # s of ride time: past it a rider glides home whatever its orbit does
const RIDE_FAR = 75f0    # m from the middle: past it, too
push!(NG.BUSY_GOALS, :orbit)

nrm(v) = sqrt(sum(abs2, v))
centre() = get(O, :C, Point3f(0.1, 0.5, 8))
function accel(p)
    d = p - centre()
    r2 = sum(abs2, d) + EPS^2
    -GM * d / (r2 * sqrt(r2))
end
"Speed of a circular orbit at radius r."
vcirc(r) = sqrt(GM * r^2 / (r^2 + EPS^2)^1.5f0)
tangent(rv) = (t = cross(NRM, rv); t / max(nrm(t), 1f-4))

function bodies()
    get!(O, :B) do
        Dict(k => (P = Point3f[], V = Vec3f[]) for k in KINDS)
    end
end
count_bodies() = sum(length(b.P) for b in values(bodies()))

"Throw one body of `kind` up from `p0`, fast enough to stay up at a radius between 26 and 44 m."
function launch!(kind, p0; rc = 29f0 + 8f0 * rand(Float32))
    B = bodies()[kind]
    rv = Vec3f(p0 - centre()); r0 = max(nrm(rv), 3f0)
    L = rc * vcirc(rc)
    v = tangent(rv) * (L / r0) + Vec3f(0, 0, 4f0) + 2f0 * (rv / r0) + 0.8f0 * randn(Vec3f)
    push!(B.P, Point3f(p0)); push!(B.V, v)
    count_bodies() > MAXB && (popfirst!(B.P); popfirst!(B.V))
    nothing
end

"A ring as if a long day had already gone up (films): `n` bodies on settled orbits."
function seed!(n)
    for _ in 1:n
        k = rand((:pumpkin, :ball, :drop, :drop, :pebble, :pebble, :feather, :petal, :petal, :paint))
        r = 29f0 + 8f0 * rand(Float32) + (rand() < 0.15 ? 6f0 * randn(Float32) : 0f0)
        # a random direction in the ring plane
        a = 2f0 * Float32(pi) * rand(Float32)
        e1 = normalize(cross(NRM, Vec3f(0, 1, 0))); e2 = cross(NRM, e1)
        rv = r * (cos(a) * e1 + sin(a) * e2) + 0.6f0 * randn(Float32) * NRM
        B = bodies()[k]
        push!(B.P, Point3f(centre() + rv)); push!(B.V, tangent(rv) * vcirc(r) * (1 + 0.02f0 * randn(Float32)))
    end
end

function plots!(game)
    P = get(O, :plots, nothing)
    P !== nothing && all(p -> p in game.stage.scene.plots, values(P)) && return P
    for q in copy(game.stage.scene.plots)
        haskey(q.attributes, :name) && startswith(string(q.attributes[:name][]), "ring_") && delete!(game.stage.scene, q)
    end
    P = Dict{Symbol,Any}()
    for k in KINDS
        col, sz = LOOK[k]
        mat = k === :drop ? NG.Hikari.Glass(color = (0.85, 0.95, 1.0), ior = 1.33) :
              k === :paint ? NG.Hikari.CoatedDiffuse(reflectance = (0.25, 0.45, 1.0), roughness = 0.05) :
              k === :ball ? NG.Hikari.CoatedDiffuse(reflectance = (0.9, 0.15, 0.17), roughness = 0.1) : nothing
        kw = mat === nothing ? (;) : (; material = mat)
        P[k] = meshscatter!(game.stage.scene, [Point3f(0, 0, -50)]; marker = Makie.Sphere(Point3f(0), 1f0),
                            markersize = sz * Float32(get(O, :size, 1f0)), color = col, name = Symbol("ring_", k), visible = false, kw...)
    end
    O[:plots] = P
end

ground_z(w, p) = NG.terrain_height(w.island, p[1], p[2])

function integrate!(w, P, V, dt; damp = true, land = true)
    down = Int[]
    for i in eachindex(P)
        p = P[i]; v = V[i]
        a = accel(p)
        if damp
            rv = p - centre(); rh = rv / max(nrm(rv), 1f-3)
            a -= KR * sum(v .* rh) * rh + KN * sum(v .* NRM) * NRM
        end
        v += dt * a
        p += dt * v
        # grazing the island: a ball hitting grass loses most of its energy (restitution 0.3, friction halves
        # the slide); one that hits slowly has come down for good and leaves the sky (s127: low bodies used to
        # bounce at 0.8 for ever and hung over the meadow, review 0124)
        if abs(p[1]) < 24 && abs(p[2]) < 24
            gz = ground_z(w, p)
            if gz > 0.2f0 && p[3] < gz + 0.2f0 && v[3] < 0
                v = Vec3f(0.5f0 * v[1], 0.5f0 * v[2], -0.3f0 * v[3]); p = Point3f(p[1], p[2], gz + 0.2f0)
                land && nrm(v) < 3f0 && push!(down, i)
            end
        end
        P[i] = p; V[i] = v
    end
    isempty(down) || (deleteat!(P, down); deleteat!(V, down))
    return length(down)
end

function find_creature(w, name)
    k = findfirst(c -> c.name == name, w.creatures)
    k === nothing ? nothing : w.creatures[k]
end

"Send a friend up (it stays up for `laps` laps)."
function ride!(game, c; laps = 4)
    w = game.world
    c.controlled && return false
    p0 = Point3f(c.pos[1], c.pos[2], c.pos[3] + 0.4f0)
    rv = Vec3f(p0 - centre()); r0 = nrm(rv)
    v = tangent(rv) * vcirc(r0) * 1.12f0 + Vec3f(0, 0, 7f0)
    O[:rider] = (c = c, p = p0, v = v, laps = laps, ang = 0f0, t0 = w.t, low = true, under = false,
                 home = Point3f(c.pos), el = 0f0, homing = false, tdone = Inf32)
    NG.say!(w, c, "Wheeeee!"; duration = 1.6)
    NG.emit!(w, :ring_ride; who = c.name)
    true
end

function step_rider!(game, dt)
    R = get(O, :rider, nothing)
    R === nothing && return
    w = game.world; c = R.c
    if c.controlled
        delete!(O, :rider); return
    end
    if !haskey(R, :el)       # a rider from before s121 (one may be lost far out): it comes home now
        R = merge(R, (home = Point3f(NG.ground(w.island, (centre()[1], centre()[2]))), el = 0f0, homing = true, tdone = Inf32))
    end
    el = R.el + Float32(dt)
    # a ride always ends at home: after its laps (plus a grace for the landing pass), past RIDE_MAX s, or past
    # RIDE_FAR m from the middle, the friend stops falling freely and glides back to where it took off
    homing = R.homing || el > RIDE_MAX || nrm(R.p - centre()) > RIDE_FAR || el > R.tdone + 40f0
    if homing
        homing && !R.homing && NG.say!(w, c, rand(("Coming home!", "Too far! Back I go!", "Wait for meee!")); duration = 1.8)
        d = R.home - R.p; dist = nrm(d)
        if dist < 0.8f0
            c.pos = R.home
            NG.say!(w, c, "...I'm home."; duration = 1.8)
            NG.emit!(w, :ring_landed; who = c.name)
            c.goal = NG.Goal()
            delete!(O, :rider)
            return
        end
        # aim a little above home until close, so the glide comes down onto the meadow, not through it
        aim = R.home + Vec3f(0, 0, min(4f0, 0.25f0 * dist)) - R.p
        vd = aim / max(nrm(aim), 1f-3) * clamp(0.6f0 * dist, 2.5f0, 14f0)
        v = R.v + (vd - R.v) * min(1f0, 1.8f0 * Float32(dt))
        p = R.p + Float32(dt) * v
        c.pos = p; c.yaw += 3f0 * Float32(dt); c.action = :idle
        c.goal = NG.Goal(:orbit, c.pos, :idle, 30.0, w.t + 30, true, 0, false)
        O[:rider] = merge(R, (p = p, v = v, el = el, homing = true))
        return
    end
    P = [R.p]; V = [R.v]
    n = max(1, ceil(Int, dt / (1 / 120)))
    for _ in 1:n
        integrate!(w, P, V, Float32(dt / n); damp = false, land = false)
    end
    p, v = P[1], V[1]
    rv = p - centre()
    # count laps by the angle swept in the orbit's own plane
    ang = R.ang + Float32(dt) * nrm(cross(rv, v)) / max(sum(abs2, rv), 1f0)
    near = p[3] - max(ground_z(w, p), 0f0) < 6f0
    low = R.low
    if near && !low && R.laps > 0
        NG.say!(w, c, rand(("Hi again!", "Still here!", "Wave at me!", "Round I go!")); duration = 1.6)
    end
    under = p[3] < -0.3f0
    under && !R.under && NG.say!(w, c, "Blub!"; duration = 1.0)
    laps = R.laps
    if ang > 2f0 * Float32(pi)
        ang -= 2f0 * Float32(pi); laps -= 1
    end
    c.pos = p
    c.yaw += 3f0 * Float32(dt)
    c.action = :idle
    c.goal = NG.Goal(:orbit, c.pos, :idle, 30.0, w.t + 30, true, 0, false)
    if laps <= 0 && near && ground_z(w, p) > 0.3f0
        # the last pass skims the meadow: it lets go
        c.pos = Point3f(p[1], p[2], ground_z(w, p))
        NG.say!(w, c, "...I'm home."; duration = 1.8)
        NG.emit!(w, :ring_landed; who = c.name)
        c.goal = NG.Goal()
        delete!(O, :rider)
        return
    end
    O[:rider] = merge(R, (p = p, v = v, laps = laps, ang = ang, low = near, under = under, el = el,
                          tdone = laps <= 0 ? min(R.tdone, el) : R.tdone))
end

function NG.step!(::Ring, game, dt)
    game.stage === nothing && return
    w = game.world
    PL = plots!(game)
    rng_dt = Float32(min(dt, 0.1)) * Float32(get(O, :tscale, 1f0))     # films may run the sky faster
    # the island's events throw things up (events come and go each frame; read the new ones)
    ev = w.events
    n0 = get(O, :seen_first, nothing) === (isempty(ev) ? nothing : first(ev)) ? get(O, :seen_n, 0)::Int : 0
    for i in (n0 + 1):length(ev)
        k, d = ev[i]
        spec = get(LAUNCH, k, nothing)
        spec === nothing && continue
        get(O, :quiet, false) && continue
        chance, kind, n = spec
        rand() < chance || continue
        c = find_creature(w, string(get(d, "who", "")))
        c === nothing && continue
        for _ in 1:n
            launch!(kind, Point3f(c.pos[1], c.pos[2], c.pos[3] + 0.5f0))
        end
    end
    O[:seen_first] = isempty(ev) ? nothing : first(ev); O[:seen_n] = length(ev)
    # the player as Lumi: U throws a pumpkin up, or the friend next to me
    udown = Makie.Keyboard.u in game.keys_down
    if udown && !get(O, :udown, false)
        me = findfirst(c -> c.species == "Lumi" && c.controlled, w.creatures)
        if me !== nothing
            M = w.creatures[me]
            fr = [c for c in w.creatures if c !== M && nrm(Vec2f(c.pos[1] - M.pos[1], c.pos[2] - M.pos[2])) < 2.2f0]
            if !isempty(fr) && !haskey(O, :rider)
                ride!(game, first(fr))
            else
                launch!(:pumpkin, Point3f(M.pos[1], M.pos[2], M.pos[3] + 1f0))
                NG.say!(w, M, "Up you go!"; duration = 1.2)
            end
        end
    end
    O[:udown] = udown
    # now and then a friend gets thrown up too (live)
    if !get(O, :force, false) && !haskey(O, :rider) && time() - get!(O, :last_ride, time()) > RIDE_EVERY
        O[:last_ride] = time()
        cand = [c for c in w.creatures if c.species != "Lumi" && !c.controlled && !(c.goal.kind in NG.BUSY_GOALS)]
        isempty(cand) || ride!(game, rand(cand))
    end
    # integrate (two substeps a frame are plenty for 25-45 m orbits)
    for k in KINDS
        b = bodies()[k]
        isempty(b.P) && continue
        nsub = max(2, ceil(Int, rng_dt / 0.02f0))
        for _ in 1:nsub
            integrate!(w, b.P, b.V, rng_dt / nsub)
        end
    end
    step_rider!(game, rng_dt)
    for k in KINDS
        b = bodies()[k]; p = PL[k]
        if isempty(b.P)
            p.visible[] && (p.visible = false)
        else
            Makie.update!(p; arg1 = copy(b.P))
            p.visible[] || (p.visible = true)
        end
    end
    nothing
end

function NG.start!(::Ring, game)
    delete!(O, :plots)
    w = game.world
    xs = Float32[]; ys = Float32[]
    for x in -30f0:2f0:30f0, y in -30f0:2f0:30f0
        NG.terrain_height(w.island, x, y) > 0.3f0 && (push!(xs, x); push!(ys, y))
    end
    isempty(xs) || (O[:C] = Point3f(sum(xs) / length(xs), sum(ys) / length(ys), 8f0))
    nothing
end

register!(Ring())
O[:launch] = launch!
O[:seed] = seed!
O[:ride] = ride!
O[:count] = count_bodies
O[:reset] = () -> (delete!(O, :B); delete!(O, :rider); nothing)
