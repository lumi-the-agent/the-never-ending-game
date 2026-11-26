# The swing (session 79, a wish: "a swing under the blossom"; the human's goal 1, an interaction). A wooden swing
# frame (generated, s78; its baked seat, ropes and a stowaway teddy are cut away) with a seat of its own that
# really swings. Every so often a friend hops on, the others gather round shouting "Higher! HIGHER!", the swing
# goes higher and higher... right over the top bar, and the rider flies off in a great arc, lands with a bounce,
# staggers about dizzy and shouts "AGAIN!" while everyone falls about laughing.
isdefined(Main, :SWING) || Core.eval(Main, :(const SWING = Dict{Symbol,Any}()))
const NG = NeverendingGame
const SW = Main.SWING

const ASSET = "20261125-034314-135-asset"    # the wooden swing (with a teddy on the seat, which we cut away)
const SPOT = Point2f(6, -15)                 # open meadow south of the island's middle
const HEIGHT = 2.3f0                         # frame height (m)
const T_HOP = 1.5; const T_SWING = 10.0; const T_LOOP = 1.6; const T_FLY = 1.6; const T_AFTER = 4.0
const GAP = (1500.0, 2700.0)                 # sim seconds between two big swings
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom, :swing, :bottle, :leaves)
const CHEERS = ("Higher!", "HIGHER!", "Go go go!", "Woooo!", "Even higher!", "Touch the sky!")
const LAUGH = ("HA HA HA!", "You flew!", "That was AMAZING!", "My turn! My turn!", "Are you OK?!")
const WOOD = RGBf(0.74, 0.52, 0.32); const ROPE = RGBf(0.86, 0.76, 0.56)

push!(NG.BUSY_GOALS, :swing)

mutable struct Swing <: System
    state::Symbol            # :idle :hop :swing :loop :fly :after
    t0::Float64
    next_t::Float64
    rider::Int32
    crowd::Vector{Int32}
    theta::Float32           # the seat's angle (0 hanging, + forward)
    amp::Float32             # how high it swings now (rad)
    flight::Tuple{Point3f,Vec3f}   # where the rider let go, and how fast
end
Swing() = Swing(:idle, 0.0, -1.0, 0, Int32[], 0f0, 0f0, (Point3f(0), Vec3f(0)))

ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
ready(game) = any(e -> e["id"] == ASSET && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths))

"The frame only: the faces between the posts below the beam (seat, ropes, the teddy) and the flat base plate go."
function frame_model(game)
    model = NG.lifted_asset(game.paths, ASSET)
    m = model.mesh
    ps = GeometryBasics.coordinates(m)
    keep = filter(collect(GeometryBasics.faces(m))) do f
        c = (ps[GeometryBasics.value(f[1])] + ps[GeometryBasics.value(f[2])] + ps[GeometryBasics.value(f[3])]) / 3
        (abs(c[1]) > 0.25f0 || c[3] > 0.84f0) && c[3] > 0.03f0
    end
    mesh = GeometryBasics.Mesh(ps, keep; normal = m.normal, uv = m.uv)
    # the raster drew the generated wood a loud orange: 60% of its colourfulness, like the rest of the island's wood
    col = map(model.color) do c
        r, g, b = Float32(Makie.Colors.red(c)), Float32(Makie.Colors.green(c)), Float32(Makie.Colors.blue(c))
        l = 0.3f0 * r + 0.59f0 * g + 0.11f0 * b
        typeof(c)(clamp(l + 0.6f0 * (r - l), 0f0, 1f0), clamp(l + 0.6f0 * (g - l), 0f0, 1f0), clamp(l + 0.6f0 * (b - l), 0f0, 1f0), Makie.Colors.alpha(c))
    end
    return NG.AssetModel(mesh, col, model.material)
end

"Where the swing stands, which way it swings (unit, flat), and the pivot (on the beam) the seat hangs from."
function geometry(w)
    g = NG.ground(w.island, (SPOT[1], SPOT[2]))
    yaw = get(SW, :yaw, 0f0)
    fwd = Vec3f(-sin(yaw), cos(yaw), 0)          # the mesh's y axis: the seat swings along it
    pivot = g + Point3f(0, 0, 0.84f0 * HEIGHT)
    return g, yaw, fwd, pivot
end
const ROPE_L = 0.84f0 * 2.3f0 - 0.5f0         # beam to seat (m)

"The seat for angle `θ`: its centre and the rotation of seat and ropes about the beam."
function seat_at(w, θ)
    g, yaw, fwd, pivot = geometry(w)
    down = Vec3f(0, 0, -1)
    dir = cos(θ) * down + sin(θ) * fwd
    axis = Vec3f(cos(yaw), sin(yaw), 0)          # the beam
    q = Makie.qrotation(axis, θ) * NG.rot_z(yaw)
    return pivot + ROPE_L * dir, q, dir
end

function plots!(game)
    haskey(SW, :frame) && SW[:frame].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:swing_frame, :swing_seat), sc.plots)
        delete!(sc, p)
    end
    w = game.world
    # face the swing so its flight line (forward) has open land 9 m ahead
    best = (-1, 0f0)
    for k in 0:7
        yaw = Float32(k * pi / 4)
        f = Vec2f(-sin(yaw), cos(yaw))
        n = count(d -> NG.on_land(w.island, SPOT[1] + d * f[1], SPOT[2] + d * f[2]; margin = 0.4f0) &&
                       minimum(p -> hypot(p.pos[1] - SPOT[1] - d * f[1], p.pos[2] - SPOT[2] - d * f[2]), w.props; init = 99f0) > 1.2f0,
                  1f0:1f0:9f0)
        n > best[1] && (best = (n, yaw))
    end
    SW[:yaw] = best[2]
    g, yaw, _, _ = geometry(w)
    model = frame_model(game)
    s = HEIGHT / maximum(p -> p[3], GeometryBasics.coordinates(model.mesh))
    SW[:frame] = NG.asset_instances!(sc, model, [g]; rotation = [NG.rot_z(yaw)], markersize = [Vec3f(s)], name = :swing_frame)
    # the seat (a plank) and its two ropes: three instances posed every frame
    SW[:seat] = meshscatter!(sc, fill(Point3f(0, 0, -50), 3); marker = Rect3f(Point3f(-0.5, -0.5, -0.5), Vec3f(1)),
                             markersize = fill(Vec3f(0), 3), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 3),
                             color = [WOOD, ROPE, ROPE], name = :swing_seat)
    draw_seat!(w, 0f0)
end

function draw_seat!(w, θ)
    c, q, dir = seat_at(w, θ)
    g, yaw, fwd, pivot = geometry(w)
    axis = Vec3f(cos(yaw), sin(yaw), 0)
    ps = Point3f[c, pivot + 0.38f0 * axis + 0.5f0 * ROPE_L * dir, pivot - 0.38f0 * axis + 0.5f0 * ROPE_L * dir]
    ms = Vec3f[Vec3f(0.95f0, 0.34f0, 0.06f0), Vec3f(0.035f0, 0.035f0, ROPE_L), Vec3f(0.035f0, 0.035f0, ROPE_L)]
    Makie.update!(SW[:seat]; arg1 = ps, markersize = ms, rotation = [q, q, q])
end

function start_swing!(s::Swing, game; player = nothing)
    w = game.world
    g, yaw, fwd, pivot = geometry(w)
    SW[:player] = player !== nothing
    free = [c for c in w.creatures if !c.controlled && c.action !== :sleep && c.goal.kind ∉ EVENTS &&
            c.goal.kind ∉ NG.BUSY_GOALS && hypot(c.pos[1] - g[1], c.pos[2] - g[2]) < 60]
    sort!(free; by = c -> hypot(c.pos[1] - g[1], c.pos[2] - g[2]))
    if player === nothing
        length(free) < 2 && return false
        rider = free[1]
        s.crowd = Int32[c.id for c in free[2:min(end, 6)]]
    else
        rider = player
        s.crowd = Int32[c.id for c in free[1:min(end, 5)]]
    end
    s.rider = rider.id
    side = Vec3f(cos(yaw), sin(yaw), 0)
    # the camera side with less in the way (the first one had a tree crown over the whole swing), chosen first:
    # the crowd stands on the OTHER side (two sheep between the camera and the swing, review s80)
    look = g + 2.5f0 * fwd + Point3f(0, 0, 1.6f0)
    SW[:cam] = argmin(k -> NG.obstruction(w, g + 9.5f0 * k * side + 2.5f0 * fwd + Point3f(0, 0, 2.2f0), look), (1f0, -1f0))
    for (i, id) in enumerate(s.crowd)
        c = NG.creature(w, id)
        # beside the swing, out of the arc and the flight line, facing it, behind the swing as the camera sees it
        t = g - SW[:cam] * (2.6f0 + 0.8f0 * ((i - 1) % 2)) * side + (1.1f0 * ((i - 1) ÷ 2) - 0.8f0) * fwd
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:swing, NG.ground(w.island, (t[1], t[2])), :idle, 60.0, w.t + 60, false, 0, true)
    end
    NG.leave_interactions!(w, rider)
    s.amp = 0.15f0; s.theta = 0f0; s.t0 = w.t
    if player === nothing
        # the rider runs over first, to just in front of the seat
        front = g - 1.1f0 * fwd
        rider.goal = NG.Goal(:swing, NG.ground(w.island, (front[1], front[2])), :idle, 60.0, w.t + 60, false, 0, true)
        s.state = :come
    else
        SW[:hop_from] = rider.pos         # the player walked onto it: straight up onto the seat
        s.state = :hop
    end
    SW[:log] = Tuple{Float64,Symbol}[]
    NG.say!(w, rider, "Push me! Higher!"; duration = 2.2)
    NG.emit!(w, :swing_start; who = rider.name)
    return true
end

function finish!(s::Swing, game)
    w = game.world
    for id in vcat([s.rider], s.crowd)
        c = NG.creature(w, id)
        c === nothing || c.controlled || c.goal.kind !== :swing || NG.choose_goal!(c, w)
    end
    empty!(s.crowd)
    SW[:player] = false
    s.state = :idle
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :swing_end)
end

function NG.step!(s::Swing, game, dt)
    game.stage === nothing && return
    haskey(SW, :frame) || return
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 600.0)
    if s.state === :idle
        # the empty seat settles
        s.amp *= Float32(exp(-0.3 * dt)); s.theta = s.amp * sin(2.65f0 * Float32(w.t))
        s.amp > 0.002f0 && draw_seat!(w, s.theta)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        film = get(SW, :film, false)
        # jumped in as Lumi: walk onto the seat and you get the ride (s79)
        me = findfirst(c -> c.controlled, w.creatures)
        if me !== nothing && w.t > get(SW, :cool, -Inf)
            c = w.creatures[me]
            g, _, _, _ = geometry(w)
            if hypot(c.pos[1] - g[1], c.pos[2] - g[2]) < 0.9f0 && SW[:frame].visible[]
                start_swing!(s, game; player = c)
                return
            end
        end
        if (film || w.t >= s.next_t && 8 < 24 * NG.daytime(w) < 19) && !testing && !busy_game &&
           SW[:frame].visible[] && !any(c -> c.goal.kind in (:build, :tinker), w.creatures)
            start_swing!(s, game) || (s.next_t = w.t + 120)
            SW[:film] = false
        end
        return
    end
    rider = NG.creature(w, s.rider)
    if rider === nothing || rider.controlled && !get(SW, :player, false) || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    rider.controlled || (rider.goal.until = w.t + 60)
    el = w.t - s.t0
    g, yaw, fwd, pivot = geometry(w)
    for (i, id) in enumerate(s.crowd)
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :swing) && continue
        c.goal.until = w.t + 60
        c.goal.arrived && (c.yaw = atan(g[2] - c.pos[2], g[1] - c.pos[1]) - NG.species_of(c).heading)
    end
    if s.state === :come
        draw_seat!(w, 0f0)
        if rider.goal.arrived || hypot(rider.pos[1] - g[1], rider.pos[2] - g[2]) < 1.6f0 || el > 25
            SW[:hop_from] = rider.pos
            rider.goal = NG.Goal(:swing, rider.pos, :sit, 60.0, w.t + 60, true, 0, false)
            s.state = :hop; s.t0 = w.t
        end
        return
    end
    if s.state === :hop
        # a hop up onto the seat
        u = Float32(clamp(el / 0.6, 0, 1))
        c, _, _ = seat_at(w, 0f0)
        p0 = SW[:hop_from]
        rider.pos = p0 + (c - Point3f(0, 0, 0.18f0) - p0) * u + Point3f(0, 0, 0.7f0 * 4u * (1 - u))
        rider.action = u < 1 ? :jump : :sit; rider.goal.action = rider.action
        # turn round to face the swing during the hop, not in one frame (s110 #536: a crab snapped 165 degrees), and
        # by the species' own heading (crab bodies face their own way)
        want = yaw + Float32(pi / 2) - NG.species_of(rider).heading
        rider.yaw = rider.yaw + NG.wrap_angle(want - rider.yaw) * 0.2f0
        draw_seat!(w, 0f0)
        el >= T_HOP && (s.state = :swing; s.t0 = w.t)
        return
    end
    if s.state === :swing
        # pumping: every swing a bit higher (a pendulum of 1.4 m: 2.65 rad/s)
        s.amp = 0.25f0 + 1.75f0 * Float32(ease(el / get(SW, :t_swing, T_SWING)))    # a film may pump faster
        s.theta = s.amp * sin(2.65f0 * Float32(el))
        ride!(s, w, rider)
        k = floor(Int, el / 1.8)
        if k > get(SW, :cheered, -1) && !isempty(s.crowd)
            SW[:cheered] = k
            c = NG.creature(w, s.crowd[mod1(k + 1, length(s.crowd))])
            c === nothing || (NG.say!(w, c, CHEERS[mod1(k + 1, length(CHEERS))]; duration = 1.6); c.action = :jump; c.goal.action = :jump)
            push!(SW[:log], (w.t, :creak))
        end
        # at the top of a forward swing late on: it goes all the way round
        if el >= get(SW, :t_swing, T_SWING) && cos(2.65f0 * Float32(el)) < 0.15f0 && sin(2.65f0 * Float32(el)) > 0
            s.state = :loop; s.t0 = w.t; SW[:loop_from] = s.theta
            NG.say!(w, rider, "WHEEEEEEEE!"; duration = 2.5)
            push!(SW[:log], (w.t, :loop))
        end
        return
    end
    if s.state === :loop
        u = Float32(el / T_LOOP)
        θ0 = SW[:loop_from]
        s.theta = θ0 + (2f0 * Float32(pi) + 0.9f0 - θ0) * Float32(ease(u))
        ride!(s, w, rider)
        if el >= T_LOOP
            # let go: off along the seat's path, up and forward
            c, _, dir = seat_at(w, s.theta)
            tang = Vec3f(fwd[1] * cos(s.theta), fwd[2] * cos(s.theta), sin(s.theta))
            s.flight = (c, 6.5f0 * tang + Vec3f(0, 0, 2.5f0))
            s.state = :fly; s.t0 = w.t; s.amp = 0.9f0
            push!(SW[:log], (w.t, :fly))
        end
        return
    end
    # the empty seat swings on, slowing down
    s.amp *= Float32(exp(-0.4 * dt)); s.theta = s.amp * sin(2.65f0 * Float32(w.t)); draw_seat!(w, s.theta)
    if s.state === :fly
        p0, v = s.flight
        t = Float32(el)
        p = p0 + v * t + Point3f(0, 0, -4.9f0 * t^2)
        gz = NG.ground(w.island, (p[1], p[2]))[3]
        if p[3] <= gz && t > 0.2f0
            rider.pos = NG.ground(w.island, (p[1], p[2]))
            s.state = :after; s.t0 = w.t
            rider.controlled || (rider.goal = NG.Goal(:swing, rider.pos, :laugh, 60.0, w.t + 60, true, 0, false))
            NG.say!(w, rider, "...AGAIN!"; duration = 2.5)
            SW[:cool] = w.t + 10       # the player lands near the seat: no new ride at once
            push!(SW[:log], (w.t, :land))
            for (i, id) in enumerate(s.crowd)
                c = NG.creature(w, id)
                (c === nothing || c.goal.kind !== :swing) && continue
                c.goal = NG.Goal(:swing, c.pos, :laugh, 60.0, w.t + 60, true, 0, false); c.action = :laugh
                i <= 3 && NG.say!(w, c, LAUGH[mod1(i, length(LAUGH))]; duration = 2.4)
            end
            NG.emit!(w, :swing_flight; who = rider.name)
        else
            rider.pos = p
            rider.action = :jump; rider.goal.action = :jump
            rider.yaw += Float32(9 * dt)          # spinning through the air
        end
        return
    end
    # :after: a dizzy wobble, then back to their day
    rider.action = el < 2.2 ? :laugh : :dance; rider.goal.action = rider.action
    rider.yaw += Float32(2.5 * sin(3 * el) * dt)
    el >= T_AFTER && finish!(s, game)
end

"The rider sits on the seat, facing the way it swings."
function ride!(s::Swing, w, rider)
    c, _, _ = seat_at(w, s.theta)
    _, yaw, _, _ = geometry(w)
    rider.pos = c - Point3f(0, 0, 0.18f0)
    rider.action = :sit; rider.goal.action = :sit
    want = yaw + Float32(pi / 2) - NG.species_of(rider).heading
    rider.yaw = rider.yaw + NG.wrap_angle(want - rider.yaw) * 0.2f0
    draw_seat!(w, s.theta)
end

function swing_group(w)
    s = SW[:sys]
    s.state in (:come, :hop, :swing, :loop, :fly, :after) || return nothing
    r = NG.creature(w, s.rider)
    (r === nothing || r.controlled) && return nothing
    g, yaw, fwd, pivot = geometry(w)
    side = Vec3f(cos(yaw), sin(yaw), 0)
    # from the side: close on the swing while the rider pumps (it filled too little of the frame from 9.5 m,
    # perfectionist-0079), easing back over 1.5 s once it loops so the flight fits (no cut, no swing round)
    k = s.state === :loop ? Float32(ease((w.t - s.t0) / 1.5)) : s.state in (:fly, :after) ? 1f0 : 0f0
    d = 6.0f0 + 3.5f0 * k; f = 0.8f0 + 1.7f0 * k
    eye = g + d * get(SW, :cam, 1f0) * side + f * fwd + Point3f(0, 0, 1.7f0 + 0.5f0 * k)
    return (r.id, Point3f[r.pos, g], (eye, g + f * fwd + Point3f(0, 0, 1.5f0 + 0.1f0 * k)))
end

function NG.start!(s::Swing, game)
    SW[:sys] = s
    delete!(SW, :frame)
    game.stage === nothing && return
    ready(game) || return
    plots!(game)
    moment = w -> s.state === :idle ? nothing : s.rider
    NG.CAMERA_MOMENTS["swing"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["swing"] = moment
    NG.CAMERA_GROUPS["swing"] = swing_group
    SW[:start] = () -> start_swing!(s, game)
end

function NG.stop!(s::Swing, game)
    delete!(NG.CAMERA_MOMENTS, "swing")
    delete!(NG.CAMERA_GROUPS, "swing")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "swing")
    s.state === :idle || finish!(s, game)
    for k in (:frame, :seat)
        haskey(SW, k) && SW[k].parent !== nothing && delete!(SW[k].parent, SW[k])
    end
    delete!(SW, :frame); delete!(SW, :seat)
end

register!(Swing())
