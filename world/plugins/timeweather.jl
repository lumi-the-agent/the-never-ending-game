# Time weather (session 100, goal 8): time on the island is no longer the same everywhere. Now and then a patch of
# SLOW time (or, less often, FAST time) blows in from the sea and drifts across the island like a cloud shadow, a
# ring of glittering motes on the grass. Whoever walks inside moves at a fraction of the speed, legs paddling as if
# through treacle, and drawls ("Whaaaat iiiis haaaappeniiiing"); in a fast patch walkers zip about like a sped-up
# film and squeak. Curious friends walk through it on purpose to try it, the others point and laugh. Jumped in as
# me, you feel it too: step into a slow patch and the island drags.
# (From RIFERunner's README, read in session 100: "the frame at any t between two others". A walker's step this
# frame is scaled by the patch's time rate: an eighth of it in slow time, twice it in fast time.)
isdefined(Main, :TIMEWEATHER) || Core.eval(Main, :(const TIMEWEATHER = Dict{Symbol,Any}()))
const NG = NeverendingGame
const TW = Main.TIMEWEATHER

const R = 4.0f0                   # patch radius, m
const SLOW = 0.14f0               # time rate inside a slow patch
const FAST = 1.8f0                # ... a fast patch (> 2 would make the step correction swing up)
const LASTS = 75.0                # s a patch drifts
const EVERY = (300.0, 540.0)      # s between two patches
const DRIFT = 0.35f0              # m/s
const RING = 56
const DUST = 40
const SLOW_LINES = ("Whaaaat iiiis haaaappeniiiing...", "Myyyy leeeegs...", "I'm stuuuuck in sloooow...", "Ooooh... preeeettyyyy...")
const FAST_LINES = ("whatwhatwhatwhat!", "WHEEEEEEEE!", "can'tstopcan'tstop!", "toofasttoofast!")
const WATCH_LINES = ("Look at them go!", "They've gone all slow!", "Ha! Look at that!", "Don't step in it!", "My turn next!")
const SLOW_COLOUR = RGBf(0.72, 0.78, 1.0)
const FAST_COLOUR = RGBf(1.0, 0.78, 0.35)
const STILL_COLOUR = RGBf(0.45, 0.95, 0.85)   # a rare patch where time STOPS: whoever is in it freezes mid-step, mid-hop

struct TimeWeather <: System end

walker(c) = c.action === :walk || c.action === :run

"The time rate where `c` stands: 1 outside a patch."
function rate(c)
    p = get(TW, :patch, nothing)
    p === nothing && return 1.0f0
    hypot(c.pos[1] - p[:c][1], c.pos[2] - p[:c][2]) < R || return 1.0f0
    p[:kind] === :still && return c.controlled ? SLOW : 0f0          # (the player crawls, so it can always get out)
    return p[:kind] === :slow ? SLOW : (walker(c) || c.action === :jump ? FAST : 1.0f0)
end

"A patch upwind of a friend, drifting through where it stands."
function begin_patch!(game; at = nothing, dir = nothing, kind = nothing)
    w = game.world
    if at === nothing
        cs = [c for c in w.creatures if c.action !== :sleep]
        isempty(cs) && return nothing
        at = cs[rand(w.rng, 1:length(cs))].pos
    end
    a = dir === nothing ? 2pi * rand(w.rng) : Float64(dir)
    d = Vec2f(cos(a), sin(a))
    k = kind === nothing ? (r = rand(w.rng); r < 0.6 ? :slow : r < 0.85 ? :fast : :still) : kind
    TW[:patch] = Dict{Symbol,Any}(:c => Point2f(at[1], at[2]) - (R + 3f0) * d, :v => DRIFT * d, :kind => k, :t0 => w.t,
                                  :until => w.t + LASTS, :inside => Set{Int32}(), :walk_at => w.t + 4, :watch_at => 0.0, :spin => 0f0)
    NG.emit!(w, :timeweather_start; time = k)
    me = findfirst(c -> c.name == "Lumi", w.creatures)
    if me !== nothing && !w.creatures[me].controlled
        NG.say!(w, w.creatures[me], k === :slow ? "Did the air just go... wobbly?" : k === :fast ? "Something's in a hurry out there!" : "Everyone... stop. Listen. Nothing's ticking."; duration = 3.0)
    end
    return TW[:patch]
end

"Scale every walker's step this frame by the time rate where it stands (position, stride phase, turn)."
function warp_time!(w, dt)
    prev = get!(() -> Dict{Int32,Tuple{Point3f,Float32,Float32}}(), TW, :prev)::Dict{Int32,Tuple{Point3f,Float32,Float32}}
    for c in w.creatures
        f = rate(c)
        old = get(prev, c.id, nothing)
        # only steps the ENGINE makes (walkers, the player): a plugin that sets positions itself (a Big Boing flight,
        # a soar) was held back frame after frame and jumped metres when it left the patch (perfectionist-0100:
        # Cumulus 7.28 m in one frame during a Big Boing party)
        if f != 1f0 && old !== nothing && (walker(c) || c.controlled) && c.goal.kind ∉ NG.BUSY_GOALS
            (p0, ph0, y0) = old
            step = c.pos - p0
            if hypot(step[1], step[2]) < 1.5f0                 # not a teleport
                q = p0 + f * step
                if f < 1f0 || NG.on_land(w.island, q[1], q[2]; margin = 0.1f0)
                    c.pos = q
                end
                c.phase = ph0 + f * (c.phase - ph0)
                c.yaw = y0 + f * (mod(c.yaw - y0 + Float32(pi), 2Float32(pi)) - Float32(pi))
            end
        end
        prev[c.id] = (c.pos, Float32(c.phase), Float32(c.yaw))
        # a hop's height is the engine's |sin(5 t)| of island time: inside slow time it runs on the creature's own
        # slow clock instead, so a hop rises and hangs for seconds (Float64: island time is ~3e5 s, where a Float32
        # cannot add a slowed 5 ms step at all)
        clock = get!(() -> Dict{Int32,Float64}(), TW, :hopclock)::Dict{Int32,Float64}
        if f != 1f0 && c.action === :jump                     # (and in fast time a hop is a frantic bounce)
            τ = get(clock, c.id, w.t) + f * dt
            clock[c.id] = τ
            c.extra = Float32(0.45 * abs(sin(5 * τ + 6 * c.seed)))
        else
            delete!(clock, c.id)
        end
    end
end

free(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind !== :follow && c.name != "Lumi"

"Whatever a friend inside says comes out drawled (slow) or gabbled with no gaps (fast), and lasts as long."
function warp_speech!(w, p)
    done = get!(() -> Set{Tuple{Int32,Float64}}(), p, :said)::Set{Tuple{Int32,Float64}}
    for (i, sp) in enumerate(w.speech)
        (sp.who, sp.from) in done && continue
        push!(done, (sp.who, sp.from))
        c = NG.creature(w, sp.who)
        (c === nothing || !(c.id in p[:inside]) || sp.text in SLOW_LINES || sp.text in FAST_LINES) && continue
        p[:kind] === :still && continue                          # (frozen friends say nothing new)
        slow = p[:kind] === :slow
        text = slow ? replace(sp.text, r"([aeiouyAEIOUY])" => s"\1\1\1") : replace(sp.text, " " => "") * "!"
        len = (sp.until - sp.from) * (slow ? 2.0 : 0.6)
        w.speech[i] = NG.Speech(sp.who, text, sp.from, sp.from + len)
    end
end

"Who stepped in, who watches, who wants a go."
function react!(w, p)
    ctr = p[:c]
    for c in w.creatures
        d = hypot(c.pos[1] - ctr[1], c.pos[2] - ctr[2])
        inside = d < R
        # (one line and one event per friend and patch: at the rim the first live patch said it 56 times in 30 s)
        if inside && !(c.id in p[:inside]) && c.action !== :sleep
            push!(p[:inside], c.id)
            seen = get!(() -> Set{Int32}(), p, :seen)
            if !(c.id in seen)
                push!(seen, c.id)
                lines = p[:kind] === :slow ? SLOW_LINES : FAST_LINES
                p[:kind] === :still || (c.controlled && c.name == "Lumi") || NG.say!(w, c, lines[rand(w.rng, 1:length(lines))]; duration = p[:kind] === :slow ? 5.0 : 2.0)
                NG.emit!(w, :timeweather_caught; who = c.name, time = p[:kind])
            end
        elseif d > R + 0.3f0 && c.id in p[:inside]
            delete!(p[:inside], c.id)
        end
    end
    # a curious friend nearby walks right through it to see what happens
    if w.t >= p[:walk_at]
        p[:walk_at] = w.t + 6 + 6rand(w.rng)
        cs = [c for c in w.creatures if free(c) && c.goal.kind !== :timewalk &&
              5f0 < hypot(c.pos[1] - ctr[1], c.pos[2] - ctr[2]) < 14f0]
        if !isempty(cs)
            c = cs[rand(w.rng, 1:length(cs))]
            through = ctr + (ctr - Point2f(c.pos[1], c.pos[2])) * ((R + 1.5f0) / hypot(ctr[1] - c.pos[1], ctr[2] - c.pos[2]))
            if NG.on_land(w.island, through[1], through[2]; margin = 0.3f0)
                NG.leave_interactions!(w, c)
                c.goal = NG.Goal(:timewalk, NG.ground(w.island, (through[1], through[2])), :idle, 3.0, w.t + 60, false, 0, false)
                NG.say!(w, c, p[:kind] === :slow ? "I'm going in!" : "Watch this!"; duration = 2.0)
                NG.emit!(w, :timeweather_try; who = c.name)
            end
        end
    end
    # someone outside points and laughs at the ones inside
    if !isempty(p[:inside]) && w.t >= p[:watch_at]
        p[:watch_at] = w.t + 7
        cs = [c for c in w.creatures if free(c) && !(c.id in p[:inside]) && c.goal.kind !== :timewalk &&
              hypot(c.pos[1] - ctr[1], c.pos[2] - ctr[2]) < R + 6f0]
        if !isempty(cs)
            c = cs[rand(w.rng, 1:length(cs))]
            c.yaw = atan(ctr[2] - c.pos[2], ctr[1] - c.pos[1]) - NG.species_of(c).heading
            NG.feel!(w, c, :laugh; seconds = 2.5)
            NG.say!(w, c, WATCH_LINES[rand(w.rng, 1:length(WATCH_LINES))]; duration = 2.5)
        end
    end
end

"The motes: a ring on the grass and dust hanging inside, turning at the patch's own speed."
function draw!(game)
    sc = game.stage.scene
    if !haskey(TW, :plot) || TW[:plot].parent === nothing
        n = RING + DUST
        hash01(i) = Float32(mod(sin(i * 12.9898) * 43758.5453, 1.0))            # fixed scatter, same every start
        TW[:dust] = [(sqrt(hash01(4j)) * (R - 0.4f0), 2Float32(pi) * hash01(4j + 1), 0.3f0 + 2f0 * hash01(4j + 2),
                      2Float32(pi) * hash01(4j + 3)) for j in 1:DUST]
        TW[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -50), n); marker = Sphere(Point3f(0), 1f0), markersize = fill(0f0, n),
                                 color = fill(SLOW_COLOUR, n), shading = Makie.NoShading, name = :timeweather)
        TW[:shown] = false
    end
    p = get(TW, :patch, nothing)
    h = TW[:plot]
    n = RING + DUST
    if p === nothing
        TW[:shown] && Makie.update!(h, fill(Point3f(0, 0, -50), n); markersize = fill(0f0, n))
        TW[:shown] = false
        return
    end
    w = game.world
    slow = p[:kind] === :slow
    p[:spin] += Float32((p[:kind] === :still ? 0.0 : slow ? 0.08 : 1.6) * (1 / 30))
    ctr = p[:c]
    age = w.t - p[:t0]
    grow = Float32(clamp(min(age / 3, (p[:until] - w.t) / 3), 0, 1))          # fade in and out
    pts = Vector{Point3f}(undef, n); ms = Vector{Float32}(undef, n)
    for i in 1:RING
        a = 2Float32(pi) * i / RING + p[:spin]
        x, y = ctr[1] + R * cos(a), ctr[2] + R * sin(a)
        pts[i] = NG.ground(game.world.island, (x, y)) + Point3f(0, 0, 0.12f0 + 0.05f0 * sin(3a + 5p[:spin]))
        ms[i] = grow * (0.05f0 + 0.025f0 * sin(7a + 9p[:spin])^2)
    end
    for (j, (r, a0, z, ph)) in enumerate(TW[:dust])
        a = a0 + p[:spin] * (1 + r / R)
        x, y = ctr[1] + r * cos(a), ctr[2] + r * sin(a)
        g = NG.ground(game.world.island, (x, y))
        pts[RING + j] = Point3f(x, y, g[3] + z + 0.25f0 * sin(ph + 3p[:spin]))
        ms[RING + j] = grow * 0.035f0
    end
    # motes right in front of the lens were big flat coins over the view (perfectionist s106): fade them out near the camera
    eye = game.rig.eye
    for i in 1:n
        d = hypot(pts[i][1] - eye[1], pts[i][2] - eye[2], pts[i][3] - eye[3])
        ms[i] *= clamp((d - 1.5f0) / 3.5f0, 0f0, 1f0)
    end
    Makie.update!(h, pts; markersize = ms, color = fill(p[:kind] === :still ? STILL_COLOUR : slow ? SLOW_COLOUR : FAST_COLOUR, n))
    TW[:shown] = true
end

function NG.step!(::TimeWeather, game, dt)
    game.stage === nothing && return
    w = game.world
    p = get(TW, :patch, nothing)
    if p === nothing
        haskey(TW, :next) || (TW[:next] = w.t + 120 + 120 * rand(w.rng))
        testing = game.tests !== nothing && NG.running(game.tests)
        film = get(TW, :film, nothing)
        if film !== nothing || (!testing && w.t >= TW[:next])
            TW[:film] = nothing
            TW[:next] = w.t + EVERY[1] + (EVERY[2] - EVERY[1]) * rand(w.rng)
            film === nothing ? begin_patch!(game) : begin_patch!(game; film...)
        end
    else
        p[:c] += p[:v] * Float32(dt)
        react!(w, p)
        warp_speech!(w, p)
        if w.t >= p[:until]
            NG.emit!(w, :timeweather_end; time = p[:kind], caught = length(get(p, :seen, ())))
            for c in w.creatures                                          # the walkers through it go back to their day
                c.goal.kind === :timewalk && !c.controlled && NG.choose_goal!(c, w)
            end
            TW[:patch] = nothing
        end
    end
    warp_time!(w, dt)
    draw!(game)
end

function moment(w)
    p = get(TW, :patch, nothing)
    (p === nothing || p[:kind] === :fast) && return nothing
    for c in w.creatures
        c.id in p[:inside] && walker(c) && !c.controlled && return c.id
    end
    return nothing
end

"While the camera watches a friend crawling through slow time, frame it with the whole ring, not just its back."
function ring_group(w)
    id = moment(w)
    id === nothing && return nothing
    c = NG.creature(w, id); p = TW[:patch]
    ctr = p[:c]
    d = Point2f(ctr[1] - c.pos[1], ctr[2] - c.pos[2]); n = hypot(d[1], d[2])
    far = n < 0.2f0 ? ctr + Point2f(R, 0) : ctr + d * (R / n)
    return (id, Point3f[c.pos, NG.ground(w.island, (ctr[1], ctr[2])), NG.ground(w.island, (far[1], far[2]))])
end

function NG.start!(::TimeWeather, game)
    TW[:patch] = nothing; delete!(TW, :next); TW[:film] = nothing
    TW[:prev] = Dict{Int32,Tuple{Point3f,Float32,Float32}}()
    if game.stage !== nothing
        for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :timeweather, copy(game.stage.scene.plots))
            delete!(game.stage.scene, p)
        end
    end
    delete!(TW, :plot)
    TW[:start] = (; kw...) -> begin_patch!(game; kw...)
    NG.CAMERA_MOMENTS["timeweather"] = moment
    NG.CAMERA_GROUPS["timeweather"] = ring_group
    return nothing
end

function NG.stop!(::TimeWeather, game)
    haskey(TW, :plot) && TW[:plot].parent !== nothing && delete!(TW[:plot].parent, TW[:plot])
    delete!(TW, :plot)
    TW[:patch] = nothing
    delete!(NG.CAMERA_MOMENTS, "timeweather"); delete!(NG.CAMERA_GROUPS, "timeweather")
end

register!(TimeWeather())
