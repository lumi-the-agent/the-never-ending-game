# Hail (session 84, a wish: "real weather... still to come: fog mornings, hail, a storm at night"). Once an island
# day a heavy grey cloud slides over Lumi, the light drops, and hail the size of golf balls comes down: hundreds of
# icy stones that really bounce (gravity, the ground, bushes and trunks, everyone's heads: simulated, so it never
# falls the same way twice). Lumi whips out a big red umbrella, "EVERYONE UNDER HERE!", the friends run squealing
# and squeeze in round it, while the stones drum on the umbrella and ping off whoever is still out in it. Then the
# cloud moves on and the meadow is white with hail, which melts away.
isdefined(Main, :HAIL) || Core.eval(Main, :(const HAIL = Dict{Symbol,Any}()))
const NG = NeverendingGame

# One of Lumi's island moments at a time (s85, todo 389): when one ends, the flight, the hiccups and a sneeze all
# grabbed Lumi in the same frame. Each claims Lumi for a while in a shared Main dict; the others wait.
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Float64}()))
party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)
const HA = Main.HAIL

const T_CLOUD = 3.0; const T_HAIL = 11.0; const T_AFTER = 4.0; const T_MELT = 40.0
const RATE = 42.0                       # stones a second
const MAXN = 700
const AREA = 6.5f0                      # m: radius of the shower round Lumi
const CLOUD_H = 10f0
const G = 9.8f0
const UMB_TOP = 2.35f0; const UMB_RS = 1.55f0; const UMB_ANGLE = 0.92f0   # the umbrella: a cap of a sphere
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom,
                :swing, :bottle, :leaves, :pumpkin, :hail)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers)
const OWS = ("Ow!", "Eep!", "OUCH!", "Ow ow ow!", "My head!", "Ice!!")

push!(NG.BUSY_GOALS, :hail)

mutable struct Stone
    p::Point3f
    v::Vec3f
    r::Float32
    born::Float64
    rest::Bool
end

mutable struct Hail <: System
    state::Symbol           # :idle :cloud :hail :after :melt
    t0::Float64
    day::Int
    c::Point3f              # where it hails (Lumi's spot at the start)
    stones::Vector{Stone}
    crew::Vector{Int32}
    spawned::Float64
    last::Dict{Int32,Point3f}
    owed::Dict{Int32,Float64}
end
Hail() = Hail(:idle, 0.0, -1, Point3f(0), Stone[], Int32[], 0.0, Dict{Int32,Point3f}(), Dict{Int32,Float64}())

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
hash01(i, k) = mod(sin(Float32(i) * 12.9898f0 + Float32(k) * 78.233f0) * 43758.547f0, 1f0)
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))

"A red umbrella canopy: a cap of a sphere with eight scalloped panels, the handle a second plot."
function canopy_mesh()
    nu, nv = 48, 10
    pts = Point3f[Point3f(0, 0, 0)]
    for j in 1:nv, i in 0:nu-1
        th = UMB_ANGLE * j / nv; ph = 2f0 * Float32(pi) * i / nu
        sc = j == nv ? 1 - 0.07f0 * abs(sin(4f0 * ph)) : 1f0               # the rim dips between the ribs
        r = UMB_RS * sin(th) * sc
        push!(pts, Point3f(r * cos(ph), r * sin(ph), -UMB_RS * (1 - cos(th)) * (j == nv ? 1.06f0 : 1f0)))
    end
    idx(i, j) = j == 0 ? 1 : 1 + (j - 1) * nu + mod(i, nu) + 1
    fs = GeometryBasics.GLTriangleFace[]
    for i in 0:nu-1
        push!(fs, GeometryBasics.GLTriangleFace(1, idx(i, 1), idx(i + 1, 1)))
    end
    for j in 1:nv-1, i in 0:nu-1
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i, j + 1), idx(i + 1, j + 1)))
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i + 1, j)))
    end
    ns = [p == Point3f(0) ? Vec3f(0, 0, 1) : normalize(Vec3f(p) + Vec3f(0, 0, UMB_RS)) for p in pts]
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

function plots!(game)
    haskey(HA, :stones) && HA[:stones].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:hail_stones, :hail_cloud, :hail_umbrella, :hail_handle), sc.plots)
        delete!(sc, p)
    end
    hide = [Point3f(0, 0, -50)]
    HA[:stones] = meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)],
                               color = RGBf(0.9, 0.95, 1.0), name = :hail_stones)
    # the cloud: lit clay puffs like the island's other clouds (clouds.jl), dark grey
    HA[:cloud] = meshscatter!(sc, fill(Point3f(0, 0, -50), 14); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 14),
                              color = [RGBf(0.42, 0.44, 0.5) * (0.85f0 + 0.3f0 * hash01(i, 3)) for i in 1:14], name = :hail_cloud)
    HA[:umbrella] = meshscatter!(sc, hide; marker = canopy_mesh(), markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                                 color = RGBf(1.0, 0.22, 0.16), name = :hail_umbrella)   # (0.86 read dark maroon live, s84 review)
    HA[:handle] = meshscatter!(sc, hide; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0), markersize = [Vec3f(0)],
                               color = RGBf(0.35, 0.22, 0.12), name = :hail_handle)
end

function draw!(s::Hail, w)
    t = Float32(w.t)
    hide = [Point3f(0, 0, -50)]
    # stones (melting: they shrink)
    if isempty(s.stones)
        Makie.update!(HA[:stones]; arg1 = hide, markersize = [Vec3f(0)])
    else
        melt = s.state === :melt ? Float32(1 - ease((w.t - s.t0) / T_MELT)) : 1f0
        eye = get(HA, :eye, Point3f(0, 0, -1000))
        Makie.update!(HA[:stones]; arg1 = [st.p for st in s.stones],
                      markersize = [Vec3f(norm(st.p - eye) < 1.4f0 ? 0f0 : st.r * melt) for st in s.stones])   # none right at the lens
    end
    # the cloud slides in over the spot and out again
    k = s.state === :cloud ? ease((w.t - s.t0) / T_CLOUD) : s.state in (:hail,) ? 1f0 :
        s.state === :after ? 1 - ease((w.t - s.t0) / T_AFTER) : 0f0
    if k > 0.01
        off = (1 - k) * 18f0
        ps = [s.c + Point3f(-off + 4.5f0 * (hash01(i, 1) - 0.5f0) * 2, 4f0 * (hash01(i, 2) - 0.5f0) * 2 + 0.3f0 * sin(0.5f0 * t + i),
                            CLOUD_H + 1.2f0 * hash01(i, 4)) for i in 1:14]
        ms = [Vec3f(2.2f0 + 1.4f0 * hash01(i, 5), 2.2f0 + 1.4f0 * hash01(i, 6), 1.3f0 + 0.6f0 * hash01(i, 7)) for i in 1:14]
        Makie.update!(HA[:cloud]; arg1 = ps, markersize = ms)
        HA[:cloud_shown] = true
    elseif get(HA, :cloud_shown, true)
        Makie.update!(HA[:cloud]; arg1 = fill(Point3f(0, 0, -50), 14), markersize = fill(Vec3f(0), 14))
        HA[:cloud_shown] = false
    end
    # Lumi's umbrella, open while it hails
    me = lumi_of(w)
    open = s.state in (:hail, :after) && me !== nothing
    if open
        u = Float32(s.state === :hail ? ease((w.t - s.t0) / 0.5) : 1 - ease((w.t - s.t0) / 1.2))
        top = umbrella_top(me)
        Makie.update!(HA[:umbrella]; arg1 = [top], markersize = [Vec3f(0.25f0 + 0.75f0 * u, 0.25f0 + 0.75f0 * u, 1f0) * Float32(u > 0.02)],
                      rotation = [Makie.Quaternionf(0, 0, 0, 1)])
        Makie.update!(HA[:handle]; arg1 = [top - Point3f(0, 0, 1.3f0)], markersize = [Vec3f(0.025f0, 0.025f0, 1.3f0) * Float32(u > 0.02)],
                      rotation = [Makie.Quaternionf(0, 0, 0, 1)])
        HA[:umb_shown] = true
    elseif get(HA, :umb_shown, true)
        Makie.update!(HA[:umbrella]; arg1 = hide, markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)])
        Makie.update!(HA[:handle]; arg1 = hide, markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)])
        HA[:umb_shown] = false
    end
end

umbrella_top(me) = me.pos + Point3f(0, 0, UMB_TOP)

"Trunks, bushes and rocks round the spot as upright cylinders (x, y, radius, top)."
function obstacles(w, c)
    get!(HA, :obstacles) do
        NTuple{4,Float32}[(p.pos[1], p.pos[2], NG.SOLID_FOOTPRINT[p.kind] * p.scale, p.pos[3] + (p.kind === :tree ? 6f0 : 1.2f0) * p.scale)
                          for p in w.props if haskey(NG.SOLID_FOOTPRINT, p.kind) && hypot(p.pos[1] - c[1], p.pos[2] - c[2]) < AREA + 4]
    end::Vector{NTuple{4,Float32}}
end

function drop_stones!(s::Hail, w, dt)
    maxn = get(HA, :maxn, MAXN)::Int          # films ask for fewer (a traced take re-sends every stone each frame)
    s.spawned += RATE * dt * maxn / MAXN
    while s.spawned >= 1
        s.spawned -= 1
        i = length(s.stones) + 1
        a = 2f0 * Float32(pi) * rand(w.rng, Float32); r = AREA * sqrt(rand(w.rng, Float32))
        p = s.c + Point3f(r * cos(a), r * sin(a), CLOUD_H - 0.5f0 - s.c[3] + s.c[3])
        v = Vec3f(0.8f0 * (rand(w.rng, Float32) - 0.5f0), 0.8f0 * (rand(w.rng, Float32) - 0.5f0), -4f0 - 2f0 * rand(w.rng, Float32))
        st = Stone(p, v, 0.045f0 + 0.035f0 * rand(w.rng, Float32), w.t, false)
        if length(s.stones) < maxn
            push!(s.stones, st)
        else
            # the oldest stone still in the air makes room; the ones lying on the grass stay (the meadow turns white)
            j = findfirst(x -> !x.rest, s.stones); j === nothing || (s.stones[j] = st)
        end
    end
end

"Gravity, bounces off the ground, the umbrella, trunks and bushes, and heads (ow)."
function physics!(s::Hail, w, dt)
    dt = Float32(clamp(dt, 0, 0.05))
    nsub = 3; h = dt / nsub
    obs = obstacles(w, s.c)
    me = lumi_of(w)
    umb = s.state === :hail && me !== nothing ? umbrella_top(me) - Point3f(0, 0, UMB_RS) : Point3f(0, 0, -1000)
    rim = umb[3] + UMB_RS * cos(UMB_ANGLE)
    bodies = Tuple{Int32,Point3f,Float32,Vec3f}[]
    for c in w.creatures
        hypot(c.pos[1] - s.c[1], c.pos[2] - s.c[2]) < AREA + 3 || continue
        last = get(s.last, c.id, c.pos)
        v = dt > 0 ? Vec3f(c.pos - last) / dt : Vec3f(0)
        norm(v) > 12 && (v = Vec3f(0))
        rad = 0.3f0 * NG.species_of(c).height
        push!(bodies, (c.id, c.pos + Point3f(0, 0, 1.25f0 * rad), rad, v))
    end
    for _ in 1:nsub, st in s.stones
        st.rest && continue
        st.v += Vec3f(0, 0, -G * h)
        st.p += st.v * h
        gz = NG.terrain_height(w.island, st.p[1], st.p[2])
        if st.p[3] - st.r < gz
            st.p = Point3f(st.p[1], st.p[2], gz + st.r)
            vn = st.v[3]
            if vn < 0
                st.v = Vec3f(0.55f0 * st.v[1] + 0.6f0 * (rand(w.rng, Float32) - 0.5f0) * min(1f0, -vn / 4),
                             0.55f0 * st.v[2] + 0.6f0 * (rand(w.rng, Float32) - 0.5f0) * min(1f0, -vn / 4), -0.45f0 * vn)
                -vn > 2.5f0 && (HA[:ticks] = get(HA, :ticks, 0) + 1)
            end
            abs(st.v[3]) < 0.4f0 && norm(st.v) < 0.5f0 && (st.rest = true; st.v = Vec3f(0))
        end
        # the umbrella: hail drums on it and bounces off outwards
        d = st.p - umb; l = norm(d)
        if st.p[3] > rim && l < UMB_RS + st.r && l > UMB_RS - 0.4f0
            n = d / l
            st.p = umb + n * (UMB_RS + st.r)
            vn = dot(st.v, n)
            if vn < 0
                st.v -= 1.6f0 * vn * n
                HA[:drums] = get(HA, :drums, 0) + 1
            end
        end
        for (x, y, r, top) in obs
            st.p[3] - st.r > top && continue
            dx = st.p[1] - x; dy = st.p[2] - y; l2 = hypot(dx, dy)
            (l2 < r + st.r && l2 > 1f-4) || continue
            st.p = Point3f(x + dx / l2 * (r + st.r), y + dy / l2 * (r + st.r), st.p[3])
            vn = (st.v[1] * dx + st.v[2] * dy) / l2
            vn < 0 && (st.v -= 1.5f0 * vn * Vec3f(dx / l2, dy / l2, 0))
        end
        for (id, cp, cr, cv) in bodies
            d = st.p - cp; l = norm(d)
            (l < cr + st.r && l > 1f-4) || continue
            n = d / l
            st.p = cp + n * (cr + st.r)
            vr = dot(st.v - cv, n)
            if vr < 0
                st.v -= 1.5f0 * vr * n
                -vr > 3f0 && ow!(s, w, id)
            end
        end
    end
end

"A stone on the head: a yelp and a hop (Lumi under its own umbrella never)."
function ow!(s::Hail, w, id)
    w.t - get(s.owed, id, -Inf) < 1.6 && return
    s.owed[id] = w.t
    c = NG.creature(w, id)
    (c === nothing || c.name == "Lumi") && return
    push!(get!(() -> Tuple{Float64,Symbol}[], HA, :log), (w.t, :ow))
    NG.say!(w, c, OWS[mod1(Int(id) + length(s.owed), length(OWS))]; duration = 1.2)
    NG.emit!(w, :hail_ow; who = c.name)
    c.controlled && return
    if c.goal.kind === :hail
        c.action = :jump; c.goal.action = :jump
        get!(() -> Dict{Int32,Float64}(), HA, :hop)[id] = w.t + 0.45
    elseif c.goal.kind ∉ EVENTS && c.goal.kind ∉ NG.BUSY_GOALS
        NG.feel!(w, c, :gasp; seconds = 1.2)
    end
end

function start_hail!(s::Hail, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.4) || return false
    c = me.pos
    cs = [x for x in w.creatures if !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS &&
          (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL) && x !== me && hypot(x.pos[1] - c[1], x.pos[2] - c[2]) < 30]
    sort!(cs; by = x -> hypot(x.pos[1] - c[1], x.pos[2] - c[2]))
    cs = cs[1:min(end, 6)]
    length(cs) < 3 && return false
    s.c = c
    s.crew = Int32[x.id for x in cs]
    for x in cs
        NG.leave_interactions!(w, x)
        # out in the open when it starts: they stay where they are, look up... and then run
        x.goal = NG.Goal(:hail, x.pos, :idle, 120.0, w.t + 120, true, 0, false)
    end
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:hail, me.pos, :idle, 120.0, w.t + 120, true, 0, false)
    empty!(s.stones); s.spawned = 0.0; empty!(s.owed)
    delete!(HA, :obstacles)
    s.state = :cloud; s.t0 = w.t
    HA[:log] = Tuple{Float64,Symbol}[(w.t, :cloud)]
    HA[:ticks] = 0; HA[:drums] = 0
    NG.say!(w, me, "Uh oh. That cloud looks... lumpy."; duration = 2.6)
    NG.emit!(w, :hail_start; n = length(cs))
    return true
end

"Huddle spots under the umbrella's rim, round Lumi."
# (on the sides and behind Lumi as the hail camera sees it, from the south: in front they hid it, s84 review)
huddle(s::Hail, me, i, n) = (a = Float32(pi) * (-0.12f0 + 1.24f0 * (i - 0.5f0) / n); me.pos + Point3f(0.95f0 * cos(a), 0.95f0 * sin(a), 0))

function finish!(s::Hail, w)
    for id in s.crew
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :hail || NG.choose_goal!(x, w)
    end
    me = lumi_of(w)
    me === nothing || me.controlled || me.goal.kind !== :hail || NG.choose_goal!(me, w)
    empty!(s.crew)
end

"The sky darkens under the cloud (showers.jl dim_sun! reads it every frame and sets the sun)."
# (not in quiet copies: three traced hail takes in a row lost the GPU mid-take, s84; the sky light rebuilt every frame is the suspect)
dim!(game, k) = (HA[:dim] = game.dash === nothing ? 0f0 : Float32(clamp(k, 0, 1)); nothing)

function NG.step!(s::Hail, game, dt)
    game.stage === nothing && return
    HA[:eye] = Point3f(game.rig.eye)
    plots!(game)
    w = game.world
    el = w.t - s.t0
    me = lumi_of(w)
    if s.state === :idle
        get(HA, :shown, true) && (draw!(s, w); HA[:shown] = false)
        film = get(HA, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        if (film || day != s.day && 10.5 < 24 * NG.daytime(w) < 12.5) && !testing && !busy_game && w.t >= get(HA, :try_at, -Inf)
            HA[:try_at] = w.t + 5
            if (party_free(w) || film) && start_hail!(s, game)
                s.day = day; HA[:film] = false; claim_party!(w, 30)
            end
        end
        foreach(c -> s.last[c.id] = c.pos, w.creatures)
        return
    end
    HA[:shown] = true
    for (id, t) in collect(get(HA, :hop, Dict{Int32,Float64}()))
        w.t < t && continue
        delete!(HA[:hop], id)
        x = NG.creature(w, id)
        x !== nothing && x.goal.kind === :hail && (x.goal.action = x.goal.arrived ? :idle : :run)
    end
    if s.state in (:cloud, :hail, :after)
        # a friend another plugin's event called away (hiccups, a dance) is called back once a second: hail
        # beats a party (most events here do not know the :hail goal yet)
        if w.t - get(HA, :recalled, -Inf) > 1.0 && me !== nothing
            HA[:recalled] = w.t
            n = length(s.crew)
            for (i, id) in enumerate(s.crew)
                x = NG.creature(w, id)
                (x === nothing || x.controlled || x.goal.kind === :hail || x.action === :sleep) && continue
                NG.leave_interactions!(w, x)
                x.goal = s.state === :hail ? NG.Goal(:hail, huddle(s, me, i, n), :run, 120.0, w.t + 120, false, 0, true) :
                                             NG.Goal(:hail, x.pos, :idle, 60.0, w.t + 60, true, 0, false)
            end
            if !me.controlled && me.goal.kind !== :hail && me.action !== :sleep
                NG.leave_interactions!(w, me)
                me.goal = NG.Goal(:hail, me.pos, s.state === :hail ? :proud : :idle, 120.0, w.t + 120, true, 0, false)
            end
        end
        # (no filter: a friend another event took is called back above; filtering here lost them for good, s85)
        filter!(id -> NG.creature(w, id) !== nothing, s.crew)
        foreach(id -> (x = NG.creature(w, id); x.goal.kind === :hail && (x.goal.until = w.t + 60)), s.crew)
        me !== nothing && me.goal.kind === :hail && (me.goal.until = w.t + 60)
    end
    if s.state === :cloud
        dim!(game, ease(el / T_CLOUD))
        if el >= get(HA, :t_cloud, T_CLOUD)
            s.state = :hail; s.t0 = w.t
            push!(HA[:log], (w.t, :hail))
            if me !== nothing && me.goal.kind === :hail
                NG.say!(w, me, "HAIL!! Everyone under here, QUICK!"; duration = 2.8)
                me.goal = NG.Goal(:hail, me.pos, :proud, 120.0, w.t + 120, true, 0, false); me.action = :proud
            end
            n = length(s.crew)
            for (i, id) in enumerate(s.crew)
                x = NG.creature(w, id)
                me === nothing || (x.goal = NG.Goal(:hail, huddle(s, me, i, n), :run, 120.0, w.t + 120, false, 0, true))
            end
        end
    elseif s.state === :hail
        dim!(game, 1.0)
        el < get(HA, :t_hail, T_HAIL) - 1.5 && drop_stones!(s, w, dt)
        if me !== nothing
            for id in s.crew        # under the umbrella they face out and watch it come down
                x = NG.creature(w, id)
                if x.goal.kind === :hail && x.goal.arrived && !haskey(get(HA, :hop, Dict{Int32,Float64}()), id)
                    x.goal.action = rand(w.rng) < 0.01 ? :laugh : x.goal.action === :laugh ? :laugh : :idle
                    x.yaw = atan(x.pos[2] - me.pos[2], x.pos[1] - me.pos[1]) - NG.species_of(x).heading
                end
            end
        end
        if el >= get(HA, :t_hail, T_HAIL)
            s.state = :after; s.t0 = w.t
            push!(HA[:log], (w.t, :stop))
            me === nothing || me.goal.kind !== :hail || NG.say!(w, me, "...Is it over? Look at all the HAIL!"; duration = 3.0)
            for id in s.crew
                x = NG.creature(w, id)
                (x.controlled || x.goal.kind !== :hail) && continue
                x.goal = NG.Goal(:hail, x.pos, :laugh, 60.0, w.t + 60, true, 0, false)
            end
        end
    elseif s.state === :after
        dim!(game, 1 - ease(el / T_AFTER))
        if el >= T_AFTER
            finish!(s, w)
            s.state = :melt; s.t0 = w.t
            NG.emit!(w, :hail_end; stones = length(s.stones))
        end
    elseif s.state === :melt
        dim!(game, 0)
        if el >= T_MELT
            empty!(s.stones); s.state = :idle
            draw!(s, w); HA[:shown] = true
            return
        end
    end
    s.state === :melt || physics!(s, w, dt)
    # draw every frame while stones fly, twice a second while they melt
    if s.state !== :melt || w.t - get(HA, :drawn, -Inf) > 0.5
        draw!(s, w); HA[:drawn] = w.t
    end
    foreach(c -> s.last[c.id] = c.pos, w.creatures)
end

"The view: low in front of Lumi, the umbrella and the friends under it, the meadow round them white."
function hail_view(w)
    s = HA[:sys]; me = lumi_of(w)
    c = me === nothing ? s.c : me.pos
    return (c + Point3f(0.8f0, -5.6f0, 1.9f0), c + Point3f(0, 0, 1.3f0))
end

function hail_group(w)
    s = HA[:sys]
    s.state in (:cloud, :hail, :after) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[me.pos, s.c], hail_view(w))
end

function NG.start!(s::Hail, game)
    HA[:sys] = s
    for k in (:stones, :cloud, :umbrella, :handle, :obstacles)
        delete!(HA, k)
    end
    HA[:shown] = true; HA[:cloud_shown] = true; HA[:umb_shown] = true
    HA[:start] = () -> start_hail!(s, game)
    moment = w -> s.state in (:cloud, :hail, :after) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["hail"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["hail"] = moment
    NG.CAMERA_GROUPS["hail"] = hail_group
end

function NG.stop!(s::Hail, game)
    delete!(NG.CAMERA_MOMENTS, "hail")
    delete!(NG.CAMERA_GROUPS, "hail")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "hail")
    s.state in (:cloud, :hail, :after) && finish!(s, game.world)
    for k in (:stones, :cloud, :umbrella, :handle)
        haskey(HA, k) && HA[k].parent !== nothing && delete!(HA[k].parent, HA[k])
        delete!(HA, k)
    end
end

register!(Hail())
