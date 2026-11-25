# Bubble trouble (session 90, goal 7: soap bubbles with thin film): once a morning Lumi brings out its bubble wand
# on the open meadow and blows giant soap bubbles at its friends. Each bubble swallows a friend whole and carries it
# up over the meadow, paddling and shouting, drifting with the wind, until POP, one after another, and down they
# come with a bump. Lumi's last and biggest one goes wrong: it swallows Lumi itself and floats highest of all.
# Traced, the bubbles are thin soap films (Hikari Glass, thin_wall, a 450 nm film: rainbow swirls); live they are
# pale see-through spheres.
isdefined(Main, :BUBBLES) || Core.eval(Main, :(const BUBBLES = Dict{Symbol,Any}()))
const NG = NeverendingGame
const BB = Main.BUBBLES

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

push!(NG.BUSY_GOALS, :bubbles)
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :cannonball, :waterfight, :mixup, :rain, :storm, :hail, :leaves, :pumpkins, :build, :tinker, :giant)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers, :splash)
const SHOUTS = ("Wheee!", "Get me DOWN!", "I'm a balloon!", "Look, no feet!", "It's so shiny in here!", "Help! ...actually, no, this is great!",
                "I can see my house!", "Wibbly!")
const BUMPS = ("Oof!", "Again! Again!", "Boing.", "That was AMAZING", "My ears are wet")
const NMAX = 8

mutable struct Bubble
    who::Int32                  # the friend inside (0 while it flies to them)
    target::Int32               # whom it flies to
    pos::Point3f
    from::Point3f
    r::Float32                  # radius when full
    born::Float64
    caught::Float64             # when it swallowed `who` (Inf before)
    pop::Float64                # when it pops
    lift::Float32               # how high it floats
    drift::Vec2f
end

mutable struct Bubbles <: System
    state::Symbol               # :idle :gather :blow :after
    t0::Float64
    day::Int
    spot::Point2f
    crew::Vector{Int32}
    bubbles::Vector{Bubble}
    falling::Dict{Int32,Tuple{Point3f,Float64}}   # who falls from where, since when
    next::Int
end
Bubbles() = Bubbles(:idle, 0.0, -1, Point2f(0, 0), Int32[], Bubble[], Dict{Int32,Tuple{Point3f,Float64}}(), 1)

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flatd(a, b) = hypot(a[1] - b[1], a[2] - b[2])
ease(u) = (u = clamp(u, 0f0, 1f0); u * u * (3 - 2u))

"An open meadow spot (furthest from trees, bushes, rocks, actors, the pond and the places plugins drew), kept."
function open_spot(game)
    get!(BB, :spot) do
        w = game.world
        A = game.plugins["areas"].mod
        best = Point2f(0, 0); bd = -99f0
        for x in -16f0:1f0:16f0, y in -16f0:1f0:16f0
            NG.on_land(w.island, x, y; margin = 1f0) || continue
            all(a -> NG.on_land(w.island, x + 6cos(a), y + 6sin(a); margin = 0.4f0), 0:pi/4:2pi) || continue
            m = minimum(p -> p.kind in (:tree, :bush, :rock) ? flatd(p.pos, (x, y)) - (p.kind === :tree ? 2.6f0 : 1f0) * p.scale - 3f0 : 99f0, w.props)
            m = min(m, minimum(a -> a isa NG.AssetActor ? flatd(a.pos, (x, y)) - 2f0 * a.scale - 2f0 : 99f0, w.actors; init = 99f0))
            isdefined(Main, :BOING) && haskey(Main.BOING, :center) && (m = min(m, flatd(Main.BOING[:center], (x, y)) - 8f0))
            m = min(m, flatd((-16f0, 9f0), (x, y)) - 6f0, flatd((-10.5f0, 10f0), (x, y)) - 6.5f0, flatd((-13.5f0, 13.5f0), (x, y)) - 8f0,
                    flatd((6f0, -15f0), (x, y)) - 6f0, flatd(A.POND, (x, y)) - A.POND_R - 4f0)
            m > bd && (bd = m; best = Point2f(x, y))
        end
        best
    end::Point2f
end

"A bubble wand's loop: a pink ring (radius 0.2 m, tube 3.5 cm) standing in the xz plane, 0.5 m up its stick."
function loop_mesh()
    n, m = 32, 10
    pts = Point3f[]; ns = Vec3f[]
    for i in 0:n-1, j in 0:m-1
        a = 2f0 * Float32(pi) * i / n; b = 2f0 * Float32(pi) * j / m
        push!(pts, Point3f((0.2f0 + 0.035f0 * cos(b)) * cos(a), 0.035f0 * sin(b), (0.2f0 + 0.035f0 * cos(b)) * sin(a) + 0.5f0))
        push!(ns, Vec3f(cos(b) * cos(a), sin(b), cos(b) * sin(a)))
    end
    idx(i, j) = mod(i, n) * m + mod(j, m) + 1
    fs = GeometryBasics.GLTriangleFace[]
    for i in 0:n-1, j in 0:m-1
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

const WAND = "20261125-133001-981-asset"     # the generated wand: a pink clay loop on a wooden handle, 1 m tall, loop in xz
const WAND_OK = false                        # true once looked at on the island (until then the hand-made loop)

"Lumi's wand while it gathers the friends and blows: held up beside its beak, the loop facing where it looks."
function draw_wand!(game, s)
    w = game.world; me = lumi_of(w)
    show = s.state in (:gather, :blow) && me !== nothing && !any(b -> b.who == me.id, s.bubbles) && !haskey(s.falling, me.id)
    if !show
        get(BB, :wand_shown, true) && (BB[:loop].visible[] = false; BB[:stick].visible[] = false;
                                       haskey(BB, :wand) && Makie.update!(BB[:wand]; markersize = [Vec3f(0)]))
        BB[:wand_shown] = false
        return
    end
    f = me.yaw + NG.species_of(me).heading
    base = me.pos + Point3f(0.42f0 * cos(f) - 0.18f0 * sin(f), 0.42f0 * sin(f) + 0.18f0 * cos(f), 0.72f0)
    q = Makie.qrotation(Vec3f(0, 0, 1), f - Float32(pi) / 2)
    if haskey(BB, :wand)
        Makie.update!(BB[:wand]; arg1 = [base + Point3f(0, 0, -0.18f0)], rotation = [q], markersize = [Vec3f(0.72f0)])
    else
        Makie.update!(BB[:loop]; arg1 = [base], rotation = [q])
        Makie.update!(BB[:stick]; arg1 = [base])
        BB[:wand_shown] || (BB[:loop].visible[] = true; BB[:stick].visible[] = true)
    end
    BB[:wand_shown] = true
end

function plots!(game)
    haskey(BB, :plot) && BB[:plot].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:bubbles, :bubble_drops, :bubble_wand_loop, :bubble_wand_stick, :bubble_wand), sc.plots)
        delete!(sc, p)
    end
    hide = [Point3f(0, 0, -50)]
    BB[:plot] = if game.dash === nothing
        # a soap film: thin-walled water glass with a 450 nm film (rainbow swirls), the sun let through to whoever is inside
        film = NG.Hikari.Glass(ior = 1.33, thin_wall = true, thin_film_thickness = 450, thin_film_ior = 1.33)
        meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)], color = RGBAf(0.9, 0.95, 1.0, 0.2),
                     material = NG.Hikari.MediumInterface(film; inside = nothing, shadows = 1.1), name = :bubbles)
    else
        meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)], color = RGBAf(0.88, 0.94, 1.0, 0.2),
                     transparency = true, name = :bubbles)
    end
    BB[:drops] = meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)], color = RGBf(0.85, 0.93, 1.0),
                              material = NG.Hikari.Glass(ior = 1.33), name = :bubble_drops)
    BB[:loop] = meshscatter!(sc, hide; marker = loop_mesh(), markersize = [Vec3f(1)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                             color = RGBf(1.0, 0.42, 0.68), visible = false, name = :bubble_wand_loop)
    BB[:stick] = meshscatter!(sc, hide; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 0.32f0), 0.025f0), markersize = [Vec3f(1)],
                              color = RGBf(0.62, 0.4, 0.22), visible = false, name = :bubble_wand_stick)
    delete!(BB, :wand)
    if (WAND_OK || get(BB, :wand_try, false)) && isfile(joinpath(game.paths.world, "assets", WAND, "mesh.jls"))
        BB[:wand] = NG.asset_instances!(sc, NG.lifted_asset(game.paths, WAND), hide; markersize = [Vec3f(0)],
                                        rotation = [Makie.Quaternionf(0, 0, 0, 1)], name = :bubble_wand)
    end
    BB[:wand_shown] = false
    BB[:shown] = true
end

"Who comes: free friends near the spot, nearest first."
function crew_for(w, spot, me)
    free(x) = !x.controlled && x.action !== :sleep && x !== me && x.goal.kind ∉ EVENTS && x.goal.kind !== :bubbles &&
              (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL)
    cs = sort([x for x in w.creatures if free(x) && flatd(x.pos, spot) < 60]; by = x -> flatd(x.pos, spot))
    return cs[1:min(end, NMAX)]
end

function start_bubbles!(s::Bubbles, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    spot = get(BB, :at, open_spot(game))
    cs = crew_for(w, spot, me)
    length(cs) < 3 && return false
    s.spot = Point2f(spot...); s.crew = Int32[x.id for x in cs]
    empty!(s.bubbles); empty!(s.falling); s.next = 1
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:bubbles, NG.ground(w.island, (spot[1], spot[2])), :idle, 120.0, w.t + 120, false, 0, true)
    n = length(cs)
    for (i, x) in enumerate(cs)
        a = 2f0 * Float32(pi) * (i - 0.5f0) / n
        q = NG.ground(w.island, (spot[1] + 3.6f0 * cos(a), spot[2] + 3.6f0 * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:bubbles, q, :idle, 120.0, w.t + 120, false, 0, true)
    end
    s.state = :gather; s.t0 = w.t
    BB[:log] = Tuple{Float64,Symbol}[(w.t, :start)]
    delete!(BB, :view)
    NG.say!(w, me, "Who wants to see my NEW bubble wand?"; duration = 3.0)
    NG.emit!(w, :bubbles_start; n = n)
    return true
end

function finish!(s::Bubbles, w)
    for id in vcat(s.crew, (me = lumi_of(w); me === nothing ? Int32[] : [me.id]))
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :bubbles || NG.choose_goal!(x, w)
    end
    empty!(s.crew); empty!(s.bubbles); empty!(s.falling)
    s.state = :idle
    NG.emit!(w, :bubbles_end)
end

"Lumi's beak: where a new bubble starts."
beak(me) = me.pos + Point3f(0.5f0 * cos(me.yaw + NG.species_of(me).heading), 0.5f0 * sin(me.yaw + NG.species_of(me).heading), 1.25f0)

function blow!(s::Bubbles, w, me, target)
    x = NG.creature(w, target)
    h = NG.species_of(x).height
    r = 0.62f0 * h + 0.25f0
    big = target == me.id
    push!(s.bubbles, Bubble(0, target, beak(me), beak(me), big ? r + 0.25f0 : r, w.t, Inf, Inf,
                            (big ? 4.4f0 : 2.2f0 + 1.4f0 * rand(w.rng, Float32)),
                            Vec2f(0.5f0 * (rand(w.rng, Float32) - 0.5f0), 0.5f0 * (rand(w.rng, Float32) - 0.5f0))))
    push!(BB[:log], (w.t, big ? :blow_big : :blow))
end

function step_bubbles!(s::Bubbles, game, dt)
    w = game.world
    me = lumi_of(w)
    t = w.t
    for b in s.bubbles
        x = NG.creature(w, b.target); x === nothing && continue
        if b.who == 0                           # flying to its friend, growing
            T = b.target == me.id ? 1.4 : 1.2
            u = Float32((t - b.born) / T)
            goal = x.pos + Point3f(0, 0, 0.55f0 * NG.species_of(x).height)
            b.pos = b.from + (goal - b.from) * ease(u) + Point3f(0, 0, 0.6f0 * sin(Float32(pi) * min(u, 1f0)))
            if u >= 1
                b.who = x.id; b.caught = t; b.pop = t + (b.target == me.id ? get(BB, :lumi_pop, 7.5) : get(BB, :pop_min, 5.0) + 3.0 * rand(w.rng))
                b.from = x.pos
                NG.say!(w, x, b.target == me.id ? "Wait... NO... not ME!" : SHOUTS[mod1(Int(x.id) + s.next, length(SHOUTS))]; duration = 2.2)
                push!(BB[:log], (t, :caught))
            end
        else                                    # floating with its friend inside
            el = Float32(t - b.caught)
            up = b.lift * ease(el / 3f0)
            dr = b.drift * min(el, 8f0)
            bob = 0.12f0 * sin(2.1f0 * el + Float32(b.who))
            base = b.from + Point3f(dr[1], dr[2], up + bob)
            x.pos = base
            x.action = el < 0.6f0 ? :scared : :jump; x.goal.action = x.action
            x.goal.arrived = true; x.goal.until = t + 30
            b.pos = base + Point3f(0, 0, 0.5f0 * NG.species_of(x).height)
        end
    end
    # POP
    for b in filter(b -> t >= b.pop, s.bubbles)
        x = NG.creature(w, b.who)
        x === nothing || (s.falling[x.id] = (x.pos, t))
        for _ in 1:22
            a = 2f0 * Float32(pi) * rand(w.rng, Float32); e = rand(w.rng, Float32)
            push!(BB[:spray], (b.pos + b.r * Point3f(cos(a) * (1 - e), sin(a) * (1 - e), 2e - 1),
                               Vec3f(2.2f0 * cos(a), 2.2f0 * sin(a), 1.5f0 * e), t))
        end
        push!(BB[:log], (t, :pop))
    end
    filter!(b -> t < b.pop, s.bubbles)
    # falling friends: down with a bump, then a laugh
    for (id, (from, since)) in collect(s.falling)
        x = NG.creature(w, id); x === nothing && (delete!(s.falling, id); continue)
        g = NG.ground(w.island, (from[1], from[2]))
        el = Float32(t - since)
        z = from[3] - 4.9f0 * el^2
        if z > g[3]
            x.pos = Point3f(from[1], from[2], z); x.action = :scared; x.goal.action = :scared
        else
            delete!(s.falling, id)
            x.pos = g
            x.goal = NG.Goal(:bubbles, g, :laugh, 60.0, t + 60, true, 0, false); x.action = :laugh
            NG.say!(w, x, id == me.id ? "...TA-DAA! (ow)" : BUMPS[mod1(Int(id), length(BUMPS))]; duration = 1.8)
            push!(BB[:log], (t, :bump))
        end
    end
end

function draw!(game)
    s = BB[:sys]; w = game.world; t = w.t
    sp = BB[:spray]::Vector{Tuple{Point3f,Vec3f,Float64}}
    filter!(d -> t - d[3] < 0.7, sp)
    if isempty(s.bubbles)
        get(BB, :shown, true) && Makie.update!(BB[:plot]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)])
    else
        rs = [b.who == 0 ? b.r * (0.25f0 + 0.75f0 * ease(Float32((t - b.born) / 1.2))) : b.r for b in s.bubbles]
        # a soft wobble, like a real bubble
        ms = [Vec3f(r * (1 + 0.04f0 * sin(5f0 * Float32(t) + i)), r * (1 - 0.03f0 * sin(5f0 * Float32(t) + i)), r) for (i, r) in enumerate(rs)]
        Makie.update!(BB[:plot]; arg1 = [b.pos for b in s.bubbles], markersize = ms)
    end
    if isempty(sp)
        get(BB, :shown, true) && Makie.update!(BB[:drops]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)])
    else
        Makie.update!(BB[:drops]; arg1 = [d[1] + Float32(t - d[3]) * d[2] + Point3f(0, 0, -4.9f0 * Float32(t - d[3])^2) for d in sp],
                      markersize = [Vec3f(0.045f0) for _ in sp])
    end
    BB[:shown] = !(isempty(s.bubbles) && isempty(sp))
end

"The view: one side of the ring, chosen once from 8 by how clear it is, high enough for the floating bubbles."
function bubble_view(w, s)
    get!(BB, :view) do
        c = Point3f(s.spot[1], s.spot[2], NG.ground(w.island, (s.spot[1], s.spot[2]))[3])
        target = c + Point3f(0, 0, 2.3f0)
        best = (Inf32, c + Point3f(0, -10f0, 3f0))
        for k in 0:7
            a = 2f0 * Float32(pi) * k / 8
            q = (c[1] + 9.5f0 * cos(a), c[2] + 9.5f0 * sin(a))
            NG.on_land(w.island, q[1], q[2]) || continue
            eye = Point3f(q[1], q[2], NG.ground(w.island, q)[3] + 2.6f0)
            o = NG.obstruction(w, eye, target)
            o < best[1] && (best = (o, eye))
        end
        (best[2], target)
    end
end

function bubble_group(w)
    s = BB[:sys]
    s.state === :idle && return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    pts = Point3f[me.pos]
    for id in s.crew
        x = NG.creature(w, id); x === nothing || push!(pts, x.pos)
    end
    return (me.id, pts, bubble_view(w, s))
end

function NG.step!(s::Bubbles, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    me = lumi_of(w)
    el = w.t - s.t0
    if s.state === :idle
        film = get(BB, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        if (film || day != s.day && 8.2 < 24 * NG.daytime(w) < 9.0) && !testing && !busy_game && w.t >= get(BB, :try_at, -Inf)
            BB[:try_at] = w.t + 5
            if (film || party_free(w)) && start_bubbles!(s, game)
                s.day = day; BB[:film] = false; claim_party!(w, 50)
            end
        end
    else
        # keep the crew (another event that took one gets it back once a second)
        if w.t - get(BB, :recalled, -Inf) > 1.0
            BB[:recalled] = w.t
            for id in vcat(s.crew, me === nothing ? Int32[] : [me.id])
                x = NG.creature(w, id)
                (x === nothing || x.controlled || x.goal.kind === :bubbles) && continue
                NG.leave_interactions!(w, x)
                x.goal = NG.Goal(:bubbles, x.pos, :idle, 60.0, w.t + 60, true, 0, false)
            end
        end
        if s.state === :gather
            # the friends turn to Lumi as they arrive
            for id in s.crew
                x = NG.creature(w, id)
                x === nothing || !x.goal.arrived || (x.yaw = atan(me.pos[2] - x.pos[2], me.pos[1] - x.pos[1]) - NG.species_of(x).heading)
            end
            if el >= get(BB, :t_gather, 7.0)
                s.state = :blow; s.t0 = w.t; BB[:next_at] = w.t + 0.8
                me.goal = NG.Goal(:bubbles, me.pos, :idle, 60.0, w.t + 60, true, 0, false)
                NG.say!(w, me, "Ready? Hold very still..."; duration = 2.0)
            end
        elseif s.state === :blow
            if s.next <= length(s.crew) + 1 && w.t >= BB[:next_at]
                target = s.next <= length(s.crew) ? s.crew[s.next] : me.id
                x = NG.creature(w, target)
                if x !== nothing
                    me.yaw = atan(x.pos[2] - me.pos[2], x.pos[1] - me.pos[1]) - NG.species_of(me).heading
                    target == me.id ? (me.yaw += Float32(pi) / 2) : nothing
                    blow!(s, w, me, target)
                    target == me.id && NG.say!(w, me, "And now the BIGGEST one of all..."; duration = 2.0)
                end
                s.next += 1
                BB[:next_at] = w.t + (s.next == length(s.crew) + 1 ? get(BB, :big_gap, 2.2) : get(BB, :gap, 0.75))     # (a film shortens them)
            end
            me.action === :laugh || any(b -> b.who == me.id, s.bubbles) || haskey(s.falling, me.id) || (me.action = :talk; me.goal.action = :talk)
            if s.next > length(s.crew) + 1 && isempty(s.bubbles) && isempty(s.falling)
                s.state = :after; s.t0 = w.t
            end
        elseif s.state === :after
            el >= 3.0 && finish!(s, w)
        end
        step_bubbles!(s, game, dt)
    end
    draw!(game)
    draw_wand!(game, s)
end

function NG.start!(s::Bubbles, game)
    BB[:sys] = s
    BB[:spray] = Tuple{Point3f,Vec3f,Float64}[]
    BB[:start] = () -> start_bubbles!(s, game)
    delete!(BB, :plot); delete!(BB, :drops); delete!(BB, :loop); delete!(BB, :stick); delete!(BB, :spot); delete!(BB, :view); BB[:shown] = true
    NG.CAMERA_GROUPS["bubbles"] = bubble_group
    NG.CAMERA_MOMENTS["bubbles"] = w -> (s.state === :idle ? nothing : (me = lumi_of(w); me === nothing ? nothing : me.id))
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["bubbles"] = NG.CAMERA_MOMENTS["bubbles"])
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:bubbles] = "blowing giant bubbles")
    return nothing
end

function NG.stop!(s::Bubbles, game)
    s.state === :idle || finish!(s, game.world)
    delete!(NG.CAMERA_GROUPS, "bubbles"); delete!(NG.CAMERA_MOMENTS, "bubbles")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "bubbles")
    for k in (:plot, :drops, :loop, :stick, :wand)
        haskey(BB, k) && BB[k].parent !== nothing && delete!(BB[k].parent, BB[k])
        delete!(BB, k)
    end
end

register!(Bubbles())
