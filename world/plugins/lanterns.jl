# Lantern float (session 91, goal 7: lights that really light what is around them): once an evening, as the light goes,
# Lumi and its friends gather round the lily pond, and one by one each sets a glowing paper lantern on the water.
# The lanterns drift slowly round the pond, mirrored in it, while everyone makes a wish; then they lift off one after
# another and float up into the night sky. In traced pictures every lantern is a real light (Hikari Emission): it
# lights the water, the lily pads and the faces round the bank. Live, they are warm unlit globes.
isdefined(Main, :LANTERNS) || Core.eval(Main, :(const LANTERNS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const LT = Main.LANTERNS

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

push!(NG.BUSY_GOALS, :lanterns)
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :cannonball, :waterfight, :mixup, :rain, :storm, :hail, :leaves, :pumpkins, :build, :tinker, :giant, :bubbles)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers, :splash)
const WISHES = ("I wish for more berries.", "I wish it was always this pretty.", "Mine's the brightest!", "Ooooh.",
                "I wish for a hat. Another hat.", "Make a wish, everyone!", "Bye bye, little light!", "It's floating!")
const NMAX = 8
const GLOW = RGBf(1.0, 0.66, 0.28)

mutable struct Lantern
    owner::Int32
    from::Point3f
    spot::Point2f            # where it settles on the water
    born::Float64
    rise::Float64            # when it lifts off (Inf until the rise)
end

mutable struct Lanterns <: System
    state::Symbol            # :idle :gather :place :float :rise
    t0::Float64
    day::Int
    crew::Vector{Int32}      # friends, Lumi last
    lanterns::Vector{Lantern}
    next::Int
end
Lanterns() = Lanterns(:idle, 0.0, -1, Int32[], Lantern[], 1)

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
ease(u) = (u = clamp(u, 0f0, 1f0); u * u * (3 - 2u))
pond(game) = game.plugins["areas"].mod.POND
pond_r(game) = game.plugins["areas"].mod.POND_R
level(game) = (Main.AREA_PLOTS[:pond][3])::Float32

function plots!(game)
    haskey(LT, :glow) && LT[:glow].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:lantern_glow, :lantern_base, :lantern_pool), sc.plots)
        delete!(sc, p)
    end
    hide = [Point3f(0, 0, -50)]
    quiet = game.dash === nothing
    # traced: each globe is an area light (the water, the pads and the faces round it light up); live: an unlit warm
    # globe (an Emission mesh is a grey box in the raster's glossy water, s51)
    LT[:glow] = quiet ?
        meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)], color = GLOW, shading = Makie.NoShading,
                     material = NG.Hikari.Emission(color = (1.0, 0.68, 0.32), strength = 9.0), name = :lantern_glow) :
        meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)], color = GLOW, shading = Makie.NoShading,
                     name = :lantern_glow)
    # a little red paper boat under each globe
    LT[:base] = meshscatter!(sc, hide; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0), markersize = [Vec3f(0)],
                             color = RGBf(0.78, 0.16, 0.12), name = :lantern_base)
    # live only: soft warm pools on the water under each lantern (the raster has no light from them; traced copies
    # get the real light): four stacked faint discs per lantern, wider and fainter outwards, like lamplight's pools
    if !quiet
        LT[:pool] = meshscatter!(sc, hide; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 0.002f0), 1f0), markersize = [Vec3f(0)],
                                 color = RGBAf(1.0, 0.72, 0.35, 0.16), shading = Makie.NoShading, transparency = true, name = :lantern_pool)
    end
    LT[:shown] = true
end

function crew_for(w, P, me)
    free(x) = !x.controlled && x.action !== :sleep && x !== me && x.goal.kind ∉ EVENTS && x.goal.kind !== :lanterns &&
              (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL)
    cs = sort([x for x in w.creatures if free(x) && hypot(x.pos[1] - P[1], x.pos[2] - P[2]) < 60];
              by = x -> hypot(x.pos[1] - P[1], x.pos[2] - P[2]))
    return cs[1:min(end, NMAX)]
end

"Where each one stands: round the bank, spread out, the camera's side left open."
function bank_spot(game, i, n)
    P = pond(game); R = pond_r(game)
    eye, _ = lantern_view(game)
    toward = atan(eye[2] - P[2], eye[1] - P[1])
    a = toward + Float32(pi) + Float32(pi) * 1.3f0 * ((i - 1) / max(n - 1, 1) - 0.5f0)
    NG.ground(game.world.island, (P[1] + (R + 0.9f0) * cos(a), P[2] + (R + 0.9f0) * sin(a)))
end

function start_lanterns!(s::Lanterns, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    P = pond(game)
    cs = crew_for(w, P, me)
    length(cs) < 3 && return false
    delete!(LT, :view)
    s.crew = Int32[x.id for x in cs]; push!(s.crew, me.id)
    empty!(s.lanterns); s.next = 1
    n = length(s.crew)
    for (i, id) in enumerate(s.crew)
        x = NG.creature(w, id)
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:lanterns, bank_spot(game, i, n), :idle, 180.0, w.t + 180, false, 0, false)
    end
    s.state = :gather; s.t0 = w.t
    LT[:log] = Tuple{Float64,Symbol}[(w.t, :start)]
    NG.say!(w, me, "Lanterns, everyone! To the pond!"; duration = 3.0)
    NG.emit!(w, :lanterns_start; n = n)
    return true
end

function finish!(s::Lanterns, w)
    for id in s.crew
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :lanterns || NG.choose_goal!(x, w)
    end
    empty!(s.crew); empty!(s.lanterns)
    s.state = :idle
    NG.emit!(w, :lanterns_end)
end

"The pond seen like the cannonball contest (cottage and trees behind it), a little lower: the lanterns, the water and the bank."
function lantern_view(game)
    get!(LT, :view) do
        w = game.world; P = pond(game); lvl = level(game)
        if haskey(game.plugins, "splash")      # its view is chosen clear of the fence and the cherry trees too (s91: from the patch it was all fence)
            e, _ = Base.invokelatest(game.plugins["splash"].mod.contest_view, game)
            return (e + Point3f(0, 0, -0.5f0), Point3f(P[1], P[2], lvl + 0.45f0))
        end
        target = Point3f(P[1], P[2], lvl + 0.5f0)
        best = (Inf32, Point3f(P[1], P[2] - 7f0, lvl + 2f0))
        for k in 0:7
            a = 2f0 * Float32(pi) * k / 8
            q = (P[1] + 6.8f0 * cos(a), P[2] + 6.8f0 * sin(a))
            NG.on_land(w.island, q[1], q[2]) || continue
            eye = Point3f(q[1], q[2], max(lvl, NG.terrain_height(w.island, q[1], q[2])) + 2.0f0)
            o = NG.obstruction(w, eye, target)
            o < best[1] && (best = (o, eye))
        end
        (best[2], target)
    end
end

function lantern_group(w)
    s = LT[:sys]
    s.state === :idle && return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    game = LT[:game]
    return (me.id, Point3f[me.pos], lantern_view(game))
end

"Where a lantern is now."
function lantern_pos(game, l::Lantern, t)
    P = pond(game); lvl = level(game)
    el = Float32(t - l.born)
    # out of the hands and onto the water
    u = ease(el / 1.6f0)
    a0 = atan(l.spot[2] - P[2], l.spot[1] - P[1]); r = hypot(l.spot[1] - P[1], l.spot[2] - P[2])
    a = a0 + 0.06f0 * max(0f0, el - 1.6f0)                        # drifting slowly round the pond
    on = Point3f(P[1] + r * cos(a), P[2] + r * sin(a), lvl + 0.1f0 + 0.015f0 * sin(1.7f0 * el + l.owner))
    p = l.from + (on - l.from) * u + Point3f(0, 0, 0.35f0 * sin(Float32(pi) * u))
    t < l.rise && return p
    # and up into the night
    v = Float32(t - l.rise)
    return p + Point3f(0.25f0 * v * cos(l.owner), 0.25f0 * v * sin(l.owner), 0.35f0 * v^1.5f0)
end

function draw!(game)
    s = LT[:sys]; t = game.world.t
    if isempty(s.lanterns)
        get(LT, :shown, true) && (Makie.update!(LT[:glow]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)]);
                                  Makie.update!(LT[:base]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)]);
                                  haskey(LT, :pool) && Makie.update!(LT[:pool]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)]))
        LT[:shown] = false
        return
    end
    ps = [lantern_pos(game, l, t) for l in s.lanterns]
    Makie.update!(LT[:glow]; arg1 = [p + Point3f(0, 0, 0.13f0) for p in ps], markersize = [Vec3f(0.12f0, 0.12f0, 0.15f0) for _ in ps])
    Makie.update!(LT[:base]; arg1 = ps, markersize = [Vec3f(0.11f0, 0.11f0, 0.04f0) for _ in ps])
    if haskey(LT, :pool)
        lvl = level(game)
        on = [p for p in ps if p[3] < lvl + 0.4f0]          # (not under the ones already flying)
        pp = Point3f[]; pm = Vec3f[]
        for p in on, (k, r) in enumerate((0.3f0, 0.5f0, 0.72f0, 0.95f0))
            push!(pp, Point3f(p[1], p[2], lvl + 0.012f0 + 0.002f0 * k)); push!(pm, Vec3f(r, r, 1))
        end
        isempty(pp) ? Makie.update!(LT[:pool]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)]) :
                      Makie.update!(LT[:pool]; arg1 = pp, markersize = pm)
    end
    LT[:shown] = true
end

function NG.step!(s::Lanterns, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    me = lumi_of(w)
    el = w.t - s.t0
    if s.state === :idle
        film = get(LT, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        if (film || day != s.day && 19.3 < 24 * NG.daytime(w) < 20.5) && !testing && !busy_game && w.t >= get(LT, :try_at, -Inf)
            LT[:try_at] = w.t + 5
            if (film || party_free(w)) && start_lanterns!(s, game)
                s.day = day; LT[:film] = false; claim_party!(w, 90)
            end
        end
    else
        P = pond(game)
        if w.t - get(LT, :recalled, -Inf) > 1.0          # keep the crew (another event that took one gets it back)
            LT[:recalled] = w.t
            for id in s.crew
                x = NG.creature(w, id)
                (x === nothing || x.controlled || x.goal.kind === :lanterns) && continue
                NG.leave_interactions!(w, x)
                x.goal = NG.Goal(:lanterns, x.pos, :idle, 120.0, w.t + 120, true, 0, false)
            end
        end
        for id in s.crew                                 # everyone faces the water once there
            x = NG.creature(w, id)
            (x === nothing || x.controlled || !x.goal.arrived) && continue
            x.yaw = atan(P[2] - x.pos[2], P[1] - x.pos[1]) - NG.species_of(x).heading
            x.goal.until = w.t + 60
        end
        if s.state === :gather && el >= get(LT, :t_gather, 9.0)
            s.state = :place; s.t0 = w.t; LT[:next_at] = w.t
        elseif s.state === :place
            if s.next <= length(s.crew) && w.t >= LT[:next_at]
                x = NG.creature(w, s.crew[s.next])
                if x !== nothing
                    R = pond_r(game)
                    bank = bank_spot(game, s.next, length(s.crew))      # spread round the pond like the friends on the bank
                    a = atan(bank[2] - P[2], bank[1] - P[1]) + 0.2f0 * (rand(w.rng, Float32) - 0.5f0)
                    r = R * (0.3f0 + 0.45f0 * rand(w.rng, Float32))
                    hand = hypot(x.pos[1] - bank[1], x.pos[2] - bank[2]) < 2f0 ? x.pos : bank   # (a latecomer's lantern starts at its place)
                    push!(s.lanterns, Lantern(x.id, hand + Point3f(0, 0, 0.55f0 * NG.species_of(x).height),
                                              Point2f(P[1] + r * cos(a), P[2] + r * sin(a)), w.t, Inf))
                    x.action = :talk; x.goal.action = :talk
                    x.name == "Lumi" && NG.say!(w, x, "...and mine. Make a wish!"; duration = 2.5)
                    push!(LT[:log], (w.t, :place))
                end
                s.next += 1
                LT[:next_at] = w.t + get(LT, :gap, 0.9)
            end
            if s.next > length(s.crew) && w.t >= LT[:next_at] + 1.5
                s.state = :float; s.t0 = w.t
                for (k, id) in enumerate(s.crew)
                    x = NG.creature(w, id)
                    x === nothing || x.name == "Lumi" || k > 4 || NG.say!(w, x, WISHES[mod1(Int(id) + k, length(WISHES))]; duration = 2.4)
                    x === nothing || (x.action = :idle; x.goal.action = :idle)
                end
            end
        elseif s.state === :float && el >= get(LT, :t_float, 40.0)
            s.state = :rise; s.t0 = w.t
            for (k, l) in enumerate(s.lanterns)
                l.rise = w.t + 0.7 * (k - 1)
            end
            me === nothing || NG.say!(w, me, "Look! They're flying!"; duration = 2.5)
            push!(LT[:log], (w.t, :rise))
        elseif s.state === :rise
            for id in s.crew
                x = NG.creature(w, id)
                (x === nothing || x.controlled) && continue
                x.action = :jump; x.goal.action = :jump
            end
            el >= 0.7 * length(s.lanterns) + 9.0 && finish!(s, w)
        end
    end
    draw!(game)
end

function NG.start!(s::Lanterns, game)
    LT[:sys] = s; LT[:game] = game
    LT[:start] = () -> start_lanterns!(s, game)
    delete!(LT, :glow); delete!(LT, :base); delete!(LT, :pool); delete!(LT, :view); LT[:shown] = true
    NG.CAMERA_GROUPS["lanterns"] = lantern_group
    NG.CAMERA_MOMENTS["lanterns"] = w -> (s.state === :idle ? nothing : (me = lumi_of(w); me === nothing ? nothing : me.id))
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["lanterns"] = NG.CAMERA_MOMENTS["lanterns"])
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:lanterns] = "floating lanterns on the pond")
    return nothing
end

function NG.stop!(s::Lanterns, game)
    s.state === :idle || finish!(s, game.world)
    delete!(NG.CAMERA_GROUPS, "lanterns"); delete!(NG.CAMERA_MOMENTS, "lanterns")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "lanterns")
    for k in (:glow, :base, :pool)
        haskey(LT, k) && LT[k].parent !== nothing && delete!(LT[k].parent, LT[k])
        delete!(LT, k)
    end
end

register!(Lanterns())
