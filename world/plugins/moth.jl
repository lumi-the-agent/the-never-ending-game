# Your pointer is a moth (session 101, goal 8): whoever watches the island in a browser has a moth. Wherever the
# mouse pointer is over the 3D view, a pale glowing moth flutters there, a metre above the ground it points at. My
# friends notice it: the nearest ones run after it, leap for it and miss, call to it, and sulk when it is flown out
# over the sea. Leave the pointer still next to me and the moth settles on my crest. You play with the island
# without jumping in, just by moving your mouse.
isdefined(Main, :MOTH) || Core.eval(Main, :(const MOTH = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MO = Main.MOTH

const NEAR = 14f0                # m along the pointer the moth looks for ground, else it flies there in the air
const IDLE = 6.0                 # s without a pointer move before the moth flies off to rest
const CHASE_R = 10f0             # friends this close (on the ground under it) notice it
const MAX_CHASERS = 4
const BORED = 25.0               # s a friend chases before it gives up
const CHASE_LINES = ("A moth!", "I'll get it!", "Come here, little moth!", "Mine! MINE!", "Ooh, shiny!")
const MISS_LINES = ("So close!", "It tickled my nose!", "Hey! Come back!", "Missed!")
const SEA_LINES = ("Come baaack!", "No fair, I can't swim!", "It went out to sea...")
const BODY = RGBf(1.0, 0.97, 0.82)
const WING = RGBf(0.96, 0.92, 1.0)

struct Moth <: System end

"Where the pointer points: the first ground the ray from the camera hits, or a point far along it (sky, sea)."
function pointed(game, sc)
    r = Makie.ray_at_cursor(sc)
    o, d = Point3f(r.origin), Vec3f(r.direction)
    w = game.world
    t = 0f0
    while t < NEAR
        p = o + t * d
        if NG.on_land(w.island, p[1], p[2]; margin = 0f0)
            p[3] <= NG.ground(w.island, (p[1], p[2]))[3] && return (p, true)
        elseif p[3] <= 0.2f0
            return (Point3f(p[1], p[2], 0.2f0), false)                     # over the sea
        end
        t += 0.2f0
    end
    # nothing hit close by (a tree in the way, the far hills, the sky): the moth flutters in the air along the
    # pointer, NEAR metres out, so it stays where you point instead of hiding behind a crown (s101 browser test)
    p = o + NEAR * d
    land = NG.on_land(w.island, p[1], p[2]; margin = 0f0)
    g = land ? NG.ground(w.island, (p[1], p[2]))[3] : 0.2f0
    return (Point3f(p[1], p[2], max(p[3] - 0.9f0, g)), land)
end

"The moth's target this frame: a film or test aim, the browser pointer while it moves, or nothing (resting)."
function aim(game)
    a = get(MO, :aim, nothing)
    a === nothing || return (Point3f(a), true)
    game.dash === nothing && return nothing
    time() - get(MO, :moved, 0.0) < IDLE || return nothing
    p, land = pointed(game, game.dash.view.scene)
    return (p, land)
end

"Pale wings that beat fast, and a glowing body: three instances of one sphere."
function draw!(game, pos, yaw, flap, shown)
    sc = game.stage.scene
    if !haskey(MO, :plot) || MO[:plot].parent === nothing
        MO[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -50), 3); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 3),
                                 rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 3), color = [BODY, WING, WING],
                                 shading = Makie.NoShading, name = :moth)
        # a soft glow round it, so it reads among white flowers in the browser (s101 browser test lost it)
        MO[:halo] = meshscatter!(sc, [Point3f(0, 0, -50)]; marker = Sphere(Point3f(0), 1f0), markersize = 0f0,
                                 color = RGBAf(1.0, 0.88, 0.55, 0.16), transparency = true, shading = Makie.NoShading, name = :moth_halo)
    end
    if !shown
        get(MO, :drawn, true) && (Makie.update!(MO[:plot], fill(Point3f(0, 0, -50), 3); markersize = fill(Vec3f(0), 3));
                                  Makie.update!(MO[:halo], [Point3f(0, 0, -50)]; markersize = 0f0))
        MO[:drawn] = false
        return
    end
    q = Makie.qrotation(Vec3f(0, 0, 1), yaw)
    side = q * Vec3f(0, 1, 0)
    up = Makie.qrotation(Vec3f(1, 0, 0) |> v -> q * v, flap)
    dn = Makie.qrotation(Vec3f(1, 0, 0) |> v -> q * v, -flap)
    # (big enough to see from the follow camera: the first one, 14 cm across, was a white speck, media/s101/moth-1.png)
    ps = [pos, pos + up * (side * 0.31f0), pos + dn * (-side * 0.31f0)]
    rs = [q, up * q, dn * q]
    ms = [Vec3f(0.2, 0.09, 0.09), Vec3f(0.22, 0.34, 0.02), Vec3f(0.22, 0.34, 0.02)]
    Makie.update!(MO[:plot], ps; markersize = ms, rotation = rs)
    Makie.update!(MO[:halo], [pos]; markersize = 0.26f0 + 0.03f0 * sin(6f0 * flap))
    MO[:drawn] = true
end

free(c) = !c.controlled && c.action !== :sleep && c.name != "Lumi" &&
          (c.goal.kind === :moth || (c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind !== :follow))

"Friends under the moth run after it, leap when it is just above them, and give up after a while."
function chase!(w, pos, land)
    chasers = get!(() -> Dict{Int32,Float64}(), MO, :chasers)::Dict{Int32,Float64}
    under = NG.ground(w.island, (pos[1], pos[2]))
    for c in w.creatures
        started = get(chasers, c.id, nothing)
        if started !== nothing
            if c.goal.kind !== :moth || w.t - started > BORED      # another plugin took it, or it is tired
                delete!(chasers, c.id)
                c.goal.kind === :moth && (NG.say!(w, c, "Phew!"; duration = 1.5); NG.choose_goal!(c, w))
                continue
            end
            if !land
                NG.say!(w, c, SEA_LINES[rand(w.rng, 1:length(SEA_LINES))]; duration = 2.5)
                NG.emit!(w, :moth_out_to_sea; who = c.name)
                delete!(chasers, c.id); NG.choose_goal!(c, w)
                continue
            end
            d = hypot(c.pos[1] - pos[1], c.pos[2] - pos[2])
            if d < 0.9f0 && w.t >= get(MO, :leap_at, 0.0)                   # just under it: leap for it
                MO[:leap_at] = w.t + 1.2
                c.goal = NG.Goal(:moth, c.pos, :jump, 0.9, w.t + 0.9, true, 0, false)
                rand(w.rng) < 0.5 && NG.say!(w, c, MISS_LINES[rand(w.rng, 1:length(MISS_LINES))]; duration = 1.5)
                NG.emit!(w, :moth_leap; who = c.name)
            elseif !c.goal.arrived || w.t >= c.goal.until
                c.goal = NG.Goal(:moth, under, :idle, 0.5, 0.0, false, 0, true)   # run to under it
            else
                c.goal.target = under
            end
        end
    end
    land || return
    length(chasers) >= MAX_CHASERS && return
    w.t >= get(MO, :notice_at, 0.0) || return
    MO[:notice_at] = w.t + 1.5
    cs = [c for c in w.creatures if free(c) && !haskey(chasers, c.id) && c.goal.kind !== :moth &&
          hypot(c.pos[1] - pos[1], c.pos[2] - pos[2]) < CHASE_R]
    isempty(cs) && return
    c = argmin(c -> hypot(c.pos[1] - pos[1], c.pos[2] - pos[2]), cs)
    NG.leave_interactions!(w, c)
    chasers[c.id] = w.t
    c.goal = NG.Goal(:moth, under, :idle, 0.5, 0.0, false, 0, true)
    NG.say!(w, c, CHASE_LINES[rand(w.rng, 1:length(CHASE_LINES))]; duration = 2.0)
    NG.emit!(w, :moth_chase; who = c.name)
end

function let_go!(w)
    chasers = get(MO, :chasers, nothing)
    chasers === nothing && return
    for (id, _) in chasers
        c = NG.creature(w, id)
        c === nothing || c.goal.kind !== :moth || NG.choose_goal!(c, w)
    end
    empty!(chasers)
end

"Someone opened the page a little while ago and has not touched the pointer: I tell them once (review s101: nobody
would find the moth)."
function hint!(game)
    isdefined(Main, :VISITORS) || return
    log = get(Main.VISITORS, :log, nothing)
    log === nothing && return
    i = findlast(e -> e[2] === :arrive, log)
    i === nothing && return
    ta = log[i][1]
    w = game.world
    (w.t - ta > 8 && w.t - ta < 60 && get(MO, :hinted, -1.0) != ta) || return
    MO[:hinted] = ta
    time() - get(MO, :moved, 0.0) < w.t - ta && return               # they already found it
    me = findfirst(c -> c.name == "Lumi", w.creatures)
    me === nothing || w.creatures[me].controlled || NG.say!(w, w.creatures[me], "Psst... move your mouse over the island!"; duration = 4.0)
    NG.emit!(w, :moth_hint)
end

function NG.step!(::Moth, game, dt)
    game.stage === nothing && return
    w = game.world
    game.dash === nothing || hint!(game)
    a = aim(game)
    if a === nothing
        get(MO, :active, false) && (let_go!(w); NG.emit!(w, :moth_rest))
        MO[:active] = false
        draw!(game, Point3f(0), 0f0, 0f0, false)
        return
    end
    target, land = a
    hover = land ? target + Point3f(0, 0, 0.9f0) : target + Point3f(0, 0, 0.6f0)
    if !get(MO, :active, false)
        MO[:active] = true; MO[:pos] = hover; MO[:t0] = w.t
        NG.emit!(w, :moth_appear)
    end
    # Lumi: a moth left still next to me lands on my crest
    me = findfirst(c -> c.name == "Lumi", w.creatures)
    still = get(MO, :aim, nothing) === nothing && time() - get(MO, :moved, 0.0) > 2.0
    if me !== nothing && still && hypot(w.creatures[me].pos[1] - target[1], w.creatures[me].pos[2] - target[2]) < 2f0
        L = w.creatures[me]
        hover = L.pos + Point3f(0, 0, 1.75f0)
        if !get(MO, :on_crest, false)
            MO[:on_crest] = true
            L.controlled || NG.say!(w, L, "Look! It likes me!"; duration = 3.0)
            NG.emit!(w, :moth_on_crest)
        end
    else
        MO[:on_crest] = false
    end
    p = MO[:pos]::Point3f
    k = Float32(1 - exp(-5 * dt))
    tt = Float32(w.t)
    flutter = Point3f(0.12f0 * sin(7.3f0 * tt), 0.12f0 * sin(5.1f0 * tt + 1), 0.15f0 * sin(9.7f0 * tt + 2))
    np = p + (hover - p) * k
    MO[:pos] = np
    v = np - p
    yaw = hypot(v[1], v[2]) > 1f-3 ? atan(v[2], v[1]) : get(MO, :yaw, 0f0)
    MO[:yaw] = yaw
    flap = get(MO, :on_crest, false) ? 0.6f0 + 0.5f0 * sin(3f0 * tt) : 0.9f0 * sin(38f0 * tt)
    draw!(game, np + (get(MO, :on_crest, false) ? Point3f(0) : flutter), yaw, flap, true)
    get(MO, :on_crest, false) ? let_go!(w) : chase!(w, np, land)
end

function NG.start!(::Moth, game)
    # (timers too: a quiet copy starts from the same snapshot time, and the preview's notice_at, kept in Main, made the
    # friends in the next take ignore the moth for its whole length)
    MO[:active] = false; MO[:on_crest] = false; MO[:drawn] = true; MO[:notice_at] = 0.0; MO[:leap_at] = 0.0
    haskey(MO, :aim) || (MO[:aim] = nothing)
    MO[:chasers] = Dict{Int32,Float64}()
    if game.stage !== nothing
        for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:moth, :moth_halo), copy(game.stage.scene.plots))
            delete!(game.stage.scene, p)
        end
    end
    delete!(MO, :plot)
    foreach(Makie.off, get(MO, :obs, Any[]))
    MO[:obs] = Any[]
    if game.dash !== nothing
        sc = game.dash.view.scene
        e = Makie.events(sc)
        push!(MO[:obs], on(e.mouseposition; priority = 100) do mp
            Makie.is_mouseinside(sc) && (MO[:moved] = time())
            return
        end)
    end
    return nothing
end

function NG.stop!(::Moth, game)
    foreach(Makie.off, get(MO, :obs, Any[])); MO[:obs] = Any[]
    let_go!(game.world)
    haskey(MO, :plot) && MO[:plot].parent !== nothing && delete!(MO[:plot].parent, MO[:plot])
    haskey(MO, :halo) && MO[:halo].parent !== nothing && delete!(MO[:halo].parent, MO[:halo])
    delete!(MO, :plot)
end

register!(Moth())
