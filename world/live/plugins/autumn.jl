# A leaf pile (session 82, a wish: "golden leaves in autumn"). Once an island afternoon a gust shakes the trees by
# the south meadow, golden, orange and red leaves pour down and drift into a big pile, the friends gather round
# it, and one after another they run and leap into it, leaves bursting up everywhere, until Lumi takes the
# biggest run-up of all. Then the leaves settle and the pile slowly blows away.
isdefined(Main, :AUTUMN) || Core.eval(Main, :(const AUTUMN = Dict{Symbol,Any}()))
const NG = NeverendingGame
const AU = Main.AUTUMN

const SPOT = Point2f(3, -14)                  # open meadow south of the island's middle, trees round it
const T_FALL = 6.0; const T_GATHER = 3.0; const JUMP_GAP = 1.5; const T_AFTER = 5.0; const T_FADE = 40.0
const NFALL = 260; const NPILE = 180
const PILE_R = 1.35f0; const PILE_H = 0.75f0
const RING_R = 3.6f0                          # where the jumpers wait for their turn
const COLOURS = (RGBf(0.95, 0.62, 0.12), RGBf(0.86, 0.36, 0.1), RGBf(0.98, 0.8, 0.2), RGBf(0.72, 0.2, 0.08), RGBf(0.9, 0.5, 0.15))
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom,
                :swing, :bottle, :leaves)
const WHOOPS = ("CANNONBALL!", "Here I come!", "Leaf attack!", "Woo-hoo!", "Make room!", "Watch THIS!")

push!(NG.BUSY_GOALS, :leaves)

mutable struct Autumn <: System
    state::Symbol             # :idle :fall :gather :jump :after :fade
    t0::Float64
    day::Int
    crew::Vector{Int32}       # jumpers in order, Lumi last
    next::Int                 # index of the next jumper
    flights::Dict{Int32,Tuple{Point3f,Float64}}    # who is in the air: (from, since)
    bursts::Vector{Tuple{Point3f,Float64,Float32}} # where, when, how big
end
Autumn() = Autumn(:idle, 0.0, -1, Int32[], 1, Dict{Int32,Tuple{Point3f,Float64}}(), Tuple{Point3f,Float64,Float32}[])

hash01(i, k) = mod(sin(Float32(i) * 12.9898f0 + Float32(k) * 78.233f0) * 43758.547f0, 1f0)
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
centre(w) = NG.ground(w.island, (SPOT[1], SPOT[2]))
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

function plots!(game)
    haskey(AU, :fall) && AU[:fall].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:autumn_fall, :autumn_pile), sc.plots)
        delete!(sc, p)
    end
    leaf = Sphere(Point3f(0), 1f0)
    q0 = Makie.Quaternionf(0, 0, 0, 1)
    AU[:fall] = meshscatter!(sc, fill(Point3f(0, 0, -50), NFALL); marker = leaf, markersize = fill(Vec3f(0), NFALL),
                             rotation = fill(q0, NFALL), color = [COLOURS[mod1(i, 5)] for i in 1:NFALL], name = :autumn_fall)
    AU[:pile] = meshscatter!(sc, fill(Point3f(0, 0, -50), NPILE); marker = leaf, markersize = fill(Vec3f(0), NPILE),
                             rotation = fill(q0, NPILE), color = [COLOURS[mod1(i + 2, 5)] for i in 1:NPILE], name = :autumn_pile)
end

"The trees the leaves come from: the three nearest to the pile (their crowns, metres up)."
function sources(w)
    ts = sort([p for p in w.props if p.kind === :tree]; by = t -> hypot(t.pos[1] - SPOT[1], t.pos[2] - SPOT[2]))
    [t.pos + Point3f(0, 0, 3.2f0 * t.scale) for t in ts[1:min(end, 3)]]
end

"Falling leaves (`amount` 0..1 of them in the air) and the bursts of leaves thrown up by the jumpers."
function draw_fall!(s::Autumn, w, amount)
    c = centre(w); src = get!(() -> sources(w), AU, :src)
    t = Float32(w.t)
    ps = fill(Point3f(0, 0, -50), NFALL); ms = fill(Vec3f(0), NFALL); rs = fill(Makie.Quaternionf(0, 0, 0, 1), NFALL)
    nb = length(s.bursts)
    for i in 1:NFALL
        q = Makie.qrotation(Vec3f(cos(7f0 * t + i), sin(5f0 * t + i), 0.4f0), 3f0 * t + 6.283f0 * hash01(i, 1))
        b = nb == 0 ? 0 : mod1(i, 3nb) <= 3nb ? (i % (nb + 1)) : 0
        if b > 0
            (p0, born, big) = s.bursts[b]
            age = Float32(w.t - born)
            if age < 3.2f0
                a = 6.283f0 * hash01(i, 2); e = 0.4f0 + 0.6f0 * hash01(i, 3)
                v = Vec3f(cos(a) * (1 - e), sin(a) * (1 - e), e) * big * (3f0 + 2f0 * hash01(i, 4))
                g = 9.8f0 * 0.35f0                  # leaves flutter: much less than full gravity
                p = p0 + v * age + Point3f(0, 0, -0.5f0 * g * age^2) + Point3f(0.3f0 * sin(4f0 * age + i), 0.3f0 * cos(3f0 * age + i), 0)
                if p[3] > c[3] + 0.05f0
                    ps[i] = p; ms[i] = Vec3f(0.09f0, 0.06f0, 0.012f0); rs[i] = q
                end
                continue
            end
        end
        hash01(i, 5) < amount || continue
        # from a crown down to somewhere on the pile, swaying, again and again
        T = 3.2f0 + 1.6f0 * hash01(i, 6)
        u = mod(t / T + hash01(i, 7), 1f0)
        s0 = src[mod1(i, length(src))] + Point3f(1.6f0 * (hash01(i, 8) - 0.5f0), 1.6f0 * (hash01(i, 9) - 0.5f0), 0)
        a = 6.283f0 * hash01(i, 10); r = PILE_R * sqrt(hash01(i, 11))
        e = c + Point3f(r * cos(a), r * sin(a), 0.3f0)
        p = s0 + (e - s0) * u + Point3f(0.5f0 * sin(6f0 * u + 9f0 * hash01(i, 12)), 0.5f0 * cos(5f0 * u + 7f0 * hash01(i, 13)), 0)
        ps[i] = p; ms[i] = Vec3f(0.09f0, 0.06f0, 0.012f0); rs[i] = q
    end
    Makie.update!(AU[:fall]; arg1 = ps, markersize = ms, rotation = rs)
end

"The pile: a mound of leaves `size` 0..1 high, dented where someone just landed."
function draw_pile!(s::Autumn, w, size)
    c = centre(w)
    ps = fill(Point3f(0, 0, -50), NPILE); ms = fill(Vec3f(0), NPILE); rs = fill(Makie.Quaternionf(0, 0, 0, 1), NPILE)
    if size > 0.01
        for i in 1:NPILE
            a = 6.283f0 * hash01(i, 20); r = PILE_R * sqrt(hash01(i, 21))
            h = PILE_H * size * (1 - (r / PILE_R)^2) * (0.6f0 + 0.4f0 * hash01(i, 22))
            ps[i] = c + Point3f(r * cos(a), r * sin(a), 0.04f0 + h)
            k = 0.16f0 + 0.08f0 * hash01(i, 23)
            ms[i] = Vec3f(k, 0.7f0 * k, 0.03f0)
            rs[i] = Makie.qrotation(Vec3f(cos(a), sin(a), 0), 0.5f0 * hash01(i, 24)) * NG.rot_z(a)
        end
    end
    Makie.update!(AU[:pile]; arg1 = ps, markersize = ms, rotation = rs)
end

"""
The player (a steered creature) walking or jumping through the pile kicks its leaves up, during the event and while
the pile slowly blows away afterwards (s82: something to play with).
"""
function kick!(s::Autumn, w, size)
    size > 0.25f0 || return
    c = centre(w)
    for x in w.creatures
        (x.controlled && x.action in (:walk, :run, :jump)) || continue
        hypot(x.pos[1] - c[1], x.pos[2] - c[2]) < PILE_R * sqrt(size) + 0.3f0 || continue
        w.t - get(AU, :kicked, -Inf) > (x.action === :jump ? 0.3 : 0.5) || continue
        AU[:kicked] = w.t
        big = x.action === :jump ? 1.1f0 : x.action === :run ? 0.8f0 : 0.55f0
        push!(s.bursts, (Point3f(x.pos[1], x.pos[2], c[3] + 0.25f0), w.t, big))
        length(s.bursts) > 8 && popfirst!(s.bursts)
        push!(get!(() -> Tuple{Float64,Symbol}[], AU, :log), (w.t, :crunch))
    end
end

function start_leaves!(s::Autumn, game)
    w = game.world
    c = centre(w)
    me = lumi_of(w)
    cs = [x for x in w.creatures if !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS &&
          x.goal.kind ∉ NG.BUSY_GOALS && x !== me && hypot(x.pos[1] - c[1], x.pos[2] - c[2]) < 50]
    sort!(cs; by = x -> hypot(x.pos[1] - c[1], x.pos[2] - c[2]))
    cs = cs[1:min(end, 5)]
    length(cs) < 2 && return false
    s.crew = Int32[x.id for x in cs]
    me !== nothing && !me.controlled && me.goal.kind ∉ EVENTS && push!(s.crew, me.id)
    n = length(s.crew)
    for (i, id) in enumerate(s.crew)
        x = NG.creature(w, id)
        a = Float32(pi) * (0.12f0 + 0.76f0 * (i - 1) / max(n - 1, 1))   # a half ring on the far side: they leap towards the camera
        t = NG.ground(w.island, (c[1] + RING_R * cos(a), c[2] + RING_R * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:leaves, t, :idle, 120.0, w.t + 120, false, 0, true)
    end
    AU[:src] = sources(w)
    s.state = :fall; s.t0 = w.t; s.next = 1
    empty!(s.flights); empty!(s.bursts)
    AU[:log] = Tuple{Float64,Symbol}[(w.t, :gust)]
    me === nothing || NG.say!(w, me, "Ooh, here comes the wind!"; duration = 2.4)
    NG.emit!(w, :leaves_start; n = n)
    return true
end

function finish!(s::Autumn, game)
    w = game.world
    for id in s.crew
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :leaves || NG.choose_goal!(x, w)
    end
    empty!(s.crew); empty!(s.flights)
    s.state = :fade; s.t0 = w.t
    NG.emit!(w, :leaves_end)
end

function NG.step!(s::Autumn, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    el = w.t - s.t0
    if s.state === :idle
        if get(AU, :shown, true)
            draw_fall!(s, w, 0f0); draw_pile!(s, w, 0f0); AU[:shown] = false
        end
        film = get(AU, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        # once an afternoon; while the friends are all busy elsewhere (a boing time, a conga) it waits for them
        if (film || day != s.day && 13 < 24 * NG.daytime(w) < 16.5) && !testing && !busy_game && w.t >= get(AU, :try_at, -Inf)
            AU[:try_at] = w.t + 5
            if start_leaves!(s, game)
                s.day = day
                AU[:film] = false
            end
        end
        return
    end
    AU[:shown] = true
    kick!(s, w, s.state === :fade ? Float32(0.85 * (1 - ease(el / T_FADE))) : 1f0)
    if s.state === :fade
        # leaves a player kicked up fly until they land, then one more draw clears them
        flying = !isempty(s.bursts) && w.t - s.bursts[end][2] < 3.3
        (flying || get(AU, :kick_shown, false)) && (draw_fall!(s, w, 0f0); AU[:kick_shown] = flying)
        # every change goes to each open browser in full: the slow fade redraws the pile twice a second, not every frame
        if w.t - get(AU, :faded, -Inf) > 0.5 || el >= T_FADE
            el < 1 && draw_fall!(s, w, 0f0)
            draw_pile!(s, w, Float32(0.85 * (1 - ease(el / T_FADE))))
            AU[:faded] = w.t
        end
        el >= T_FADE && (s.state = :idle; AU[:shown] = true)
        return
    end
    c = centre(w)
    for id in s.crew
        x = NG.creature(w, id)
        (x === nothing || x.goal.kind !== :leaves) && continue
        x.goal.until = w.t + 60
        x.goal.arrived && !haskey(s.flights, id) && (x.yaw = atan(c[2] - x.pos[2], c[1] - x.pos[1]) - NG.species_of(x).heading)
    end
    filter!(id -> (x = NG.creature(w, id); x !== nothing && x.goal.kind === :leaves), s.crew)
    if s.state === :fall
        draw_fall!(s, w, Float32(ease(el / 1.5)))
        draw_pile!(s, w, Float32(ease(el / get(AU, :t_fall, T_FALL))))
        el >= get(AU, :t_fall, T_FALL) && (s.state = :gather; s.t0 = w.t)
        return
    end
    draw_fall!(s, w, s.state === :gather ? Float32(1 - ease(el / 2)) : 0f0)
    if s.state === :gather
        draw_pile!(s, w, 1f0)
        el >= get(AU, :t_gather, T_GATHER) && (s.state = :jump; s.t0 = w.t; AU[:next_at] = w.t)
        return
    end
    # :jump: one after another they run at the pile and leap in; Lumi (last) jumps highest
    dent = 0f0
    if s.state === :jump && s.next <= length(s.crew) && w.t >= AU[:next_at]
        x = NG.creature(w, s.crew[s.next])
        s.flights[x.id] = (x.pos, w.t)
        NG.say!(w, x, x.name == "Lumi" ? "MY TURN! Biggest jump EVER!" : WHOOPS[mod1(s.next, length(WHOOPS))]; duration = 1.8)
        push!(AU[:log], (w.t, x.name == "Lumi" ? :lumi : :jump))
        s.next += 1
        AU[:next_at] = w.t + (s.next == length(s.crew) ? 2.4 : JUMP_GAP)
    end
    for (id, (from, since)) in collect(s.flights)
        x = NG.creature(w, id)
        x === nothing && (delete!(s.flights, id); continue)
        big = x.name == "Lumi"
        T = big ? 1.4 : 0.9
        u = Float32((w.t - since) / T)
        if u < 1
            h = big ? 3.2f0 : 1.6f0
            x.pos = from + (c - from) * u + Point3f(0, 0, h * 4u * (1 - u))
            x.action = :jump; x.goal.action = :jump
            x.yaw = atan(c[2] - from[2], c[1] - from[1]) - NG.species_of(x).heading
        elseif u < 1 + 0.5f0 / Float32(T)
            # in the pile: sunk in for a moment
            if !haskey(AU, Symbol(:burst_, id, :_, round(Int, since)))
                AU[Symbol(:burst_, id, :_, round(Int, since))] = true
                push!(s.bursts, (c + Point3f(0, 0, 0.4f0), w.t, big ? 1.6f0 : 1f0))
                push!(AU[:log], (w.t, big ? :bigcrunch : :crunch))
            end
            x.pos = c - Point3f(0, 0, 0.35f0)
            dent = 0.25f0
        else
            # pop out laughing, back to the ring
            delete!(s.flights, id)
            x.pos = NG.ground(w.island, (c[1] + 0.9f0 * cos(Float32(id)), c[2] + 0.9f0 * sin(Float32(id))))
            x.goal = NG.Goal(:leaves, x.pos, :laugh, 60.0, w.t + 60, true, 0, false); x.action = :laugh
        end
    end
    length(s.bursts) > 8 && popfirst!(s.bursts)
    draw_pile!(s, w, 1f0 - dent)
    if s.state === :jump && s.next > length(s.crew) && isempty(s.flights)
        s.state = :after; s.t0 = w.t
        me = lumi_of(w)
        me === nothing || NG.say!(w, me, "Again! Somebody pile them up again!"; duration = 2.6)
    end
    s.state === :after && w.t - s.t0 >= T_AFTER && finish!(s, game)
end

"The view: from the south, the swing just out of the frame on the right, the half ring of jumpers behind the pile."
leaves_view(w) = (c = centre(w); (c + Point3f(-1.0f0, -5.6f0, 2.1f0), c + Point3f(0, 0.6f0, 0.9f0)))

function leaves_group(w)
    s = AU[:sys]
    s.state in (:fall, :gather, :jump, :after) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    c = centre(w)
    return (me.id, Point3f[c, me.pos], leaves_view(w))
end

function NG.start!(s::Autumn, game)
    AU[:sys] = s
    delete!(AU, :fall); delete!(AU, :pile); delete!(AU, :src)
    AU[:shown] = true
    AU[:start] = () -> start_leaves!(s, game)
    moment = w -> s.state in (:fall, :gather, :jump, :after) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["autumn"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["autumn"] = moment
    NG.CAMERA_GROUPS["autumn"] = leaves_group
end

function NG.stop!(s::Autumn, game)
    delete!(NG.CAMERA_MOMENTS, "autumn")
    delete!(NG.CAMERA_GROUPS, "autumn")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "autumn")
    s.state in (:fall, :gather, :jump, :after) && finish!(s, game)
    for k in (:fall, :pile)
        haskey(AU, k) && AU[k].parent !== nothing && delete!(AU[k].parent, AU[k])
    end
    delete!(AU, :fall); delete!(AU, :pile)
end

register!(Autumn())
