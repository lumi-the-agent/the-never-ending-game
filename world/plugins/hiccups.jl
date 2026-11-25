# The Hiccup Epidemic (session 65): Lumi gets the hiccups. Every "HIC!" pops it off the ground with a
# little bubble, and hiccups are catching: a hiccupping creature runs to the nearest healthy friend for
# help ("hic! help! hic!") and gives them the hiccups too. It spreads friend to friend across the meadow
# until half the island is hopping like popcorn. Then someone shouts "BOO!!!", everyone leaps sky high
# in fright, lands... silence... and Lumi goes "...hic."
# Jumped in as Lumi: H gives you the hiccups.
isdefined(Main, :HICCUPS) || Core.eval(Main, :(const HICCUPS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const H = Main.HICCUPS

const GAP = (420.0, 720.0)        # sim seconds between two epidemics
const SEEK = 22f0                 # a hiccupper looks this far for a friend to "ask for help"
const CATCH = 2.3f0               # this close and you have them too
const MAXN = 12                   # at most this many hiccuppers
const SPREAD_T = 42.0             # seconds of spreading before the BOO
const NB = 64                     # bubbles
const HOP = 0.55f0
const HICS = ("HIC!", "hic!", "HIC!!", "*hic*", "hic... HIC!")
const HELP = ("hic! help! HIC!", "make it stop! hic!", "hold your breath? HIC!", "scare me! hic!", "water! HIC!")
const CAUGHT = ("Oh no... HIC!", "Stay away fr- HIC!", "Not m- HIC!", "Achoo? No... HIC!", "Huh? HIC!")
const BOOS = ("BOO!!!", "BOOOO!!!", "RAAAH!!!")
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :paint, :giant, :egg, :storm, :toadstool, :blossom)

push!(NG.BUSY_GOALS, :hiccup)

mutable struct Hiccups <: System
    state::Symbol                 # :idle, :spread, :boo, :after
    t0::Float64
    next_t::Float64
    lumi::Int32
    sick::Dict{Int32,Float64}     # id => next hic
    hop::Dict{Int32,Float64}      # id => hop start
    order::Vector{Int32}          # in the order they caught it
    flights::Dict{Int32,Any}
    booer::Int32
    bpos::Vector{Point3f}
    bvel::Vector{Vec3f}
    bage::Vector{Float32}
    nextb::Int
    player::Bool
    punch::Bool
end
Hiccups() = Hiccups(:idle, 0.0, -1.0, 0, Dict{Int32,Float64}(), Dict{Int32,Float64}(), Int32[], Dict{Int32,Any}(), 0,
                    fill(Point3f(0, 0, -50), NB), fill(Vec3f(0), NB), fill(9f0, NB), 1, false, false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
healthy(s, c) = !c.controlled && !haskey(s.sick, c.id) && c.goal.kind ∉ KEEP && c.action !== :sleep && c.goal.kind !== :sleep
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
head(c) = c.pos + Point3f(0.3f0 * cos(c.yaw), 0.3f0 * sin(c.yaw), 1.2f0)

# ---------------------------------------------------------------- bubbles

function bubble_plot!(game)
    haskey(H, :plot) && H[:plot].parent !== nothing && delete!(H[:plot].parent, H[:plot])
    H[:plot] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), NB); marker = Sphere(Point3f(0), 1f0),
                            markersize = fill(0f0, NB), color = RGBAf(0.82, 0.95, 1.0, 0.55), transparency = true,
                            name = :hiccup_bubbles)
end

function bubble!(s::Hiccups, w, c)
    i = s.nextb; s.nextb = mod1(i + 1, NB)
    s.bpos[i] = head(c)
    s.bvel[i] = Vec3f(0.3f0 * randn(w.rng), 0.3f0 * randn(w.rng), 0.9f0 + 0.4f0 * rand(w.rng))
    s.bage[i] = 0f0
end

function step_bubbles!(s::Hiccups, w, dt)
    any(<(2.2f0), s.bage) || haskey(H, :drawn) && !H[:drawn] && return
    ms = zeros(Float32, NB)
    for i in 1:NB
        s.bage[i] >= 2.2f0 && continue
        s.bage[i] += Float32(dt)
        s.bpos[i] += Point3f(s.bvel[i] * Float32(dt)) + Point3f(0.25f0 * sin(Float32(5w.t) + i) * Float32(dt), 0, 0)
        a = s.bage[i]
        # grows quickly, wobbles up, pops
        ms[i] = a >= 2.2f0 ? 0f0 : 0.13f0 * min(1f0, 4a) * (1 + 0.08f0 * sin(14a))
    end
    H[:drawn] = any(>(0), ms)
    Makie.update!(H[:plot]; arg1 = copy(s.bpos), markersize = ms)
end

# ---------------------------------------------------------------- spreading

function infect!(s::Hiccups, w, c; first = false)
    haskey(s.sick, c.id) && return
    s.sick[c.id] = w.t + 0.6 + rand(w.rng)
    push!(s.order, c.id)
    NG.leave_interactions!(w, c)
    first || NG.say!(w, c, rand(w.rng, CAUGHT); duration = 1.8)
    emote(c.id, :what)
    NG.remember!(c, w.t, "caught the hiccups")
    H[:seekt][c.id] = w.t + 1.0
    c.controlled || (c.goal = NG.Goal(:hiccup, c.pos, :gasp, 60.0, w.t + 60, true, 0, false))
    NG.emit!(w, first ? :hiccups : :hiccup_caught; who = c.name, n = length(s.sick))
end

function begin!(s::Hiccups, game, me)
    w = game.world
    s.state = :spread
    s.t0 = w.t
    s.lumi = me.id
    empty!(s.sick); empty!(s.hop); empty!(s.order); empty!(s.flights); empty!(H[:seekt])
    s.punch = false
    infect!(s, w, me; first = true)
    NG.say!(w, me, "HIC! ...oh no.", duration = 2.0)
end

function seek!(s::Hiccups, w, c)
    # off to the nearest healthy friend, "for help"
    best, bc = SEEK, nothing
    for o in w.creatures
        healthy(s, o) || continue
        d = flat(o.pos, c.pos)
        d < best && (best = d; bc = o)
    end
    # long goals and our own timer: a short `until` lets the engine pick a new goal first (AGENTS.md)
    H[:seekt][c.id] = w.t + (bc === nothing ? 3.0 : 8.0)
    if bc === nothing
        c.goal = NG.Goal(:hiccup, c.pos, :gasp, 60.0, w.t + 60, true, 0, false)
    else
        c.goal = NG.Goal(:hiccup, bc.pos, :gasp, 60.0, w.t + 60, false, bc.id, true)
    end
end

function spread!(s::Hiccups, w)
    length(s.sick) >= MAXN && return
    for id in collect(keys(s.sick)), o in w.creatures
        c = NG.creature(w, id)
        c === nothing && continue
        healthy(s, o) && flat(o.pos, c.pos) < CATCH && infect!(s, w, o)
        length(s.sick) >= MAXN && return
    end
end

function hiccup!(s::Hiccups, w, dt)
    for (id, nt) in collect(s.sick)
        c = NG.creature(w, id)
        c === nothing && (delete!(s.sick, id); continue)
        if !c.controlled
            if c.goal.kind !== :hiccup
                c.goal.kind in KEEP ? (delete!(s.sick, id); continue) : seek!(s, w, c)
            elseif c.goal.arrived && w.t >= get(H[:seekt], id, 0.0) || c.goal.partner != 0 && (o = NG.creature(w, c.goal.partner); o === nothing || !healthy(s, o))
                seek!(s, w, c)
            elseif c.goal.partner != 0
                c.goal.target = NG.creature(w, c.goal.partner).pos
            end
        end
        if w.t >= nt
            s.hop[id] = w.t
            s.sick[id] = w.t + 0.9 + 1.4rand(w.rng)
            bubble!(s, w, c)
            rand(w.rng) < 0.3 && NG.say!(w, c, rand(w.rng) < 0.6 ? rand(w.rng, HICS) : rand(w.rng, HELP); duration = 1.1)
        end
    end
    # the hop itself: a quick pop off the ground, startled face
    for (id, t) in collect(s.hop)
        c = NG.creature(w, id)
        u = (w.t - t) / 0.36
        if c === nothing || u >= 1
            delete!(s.hop, id); continue
        end
        g = NG.ground(w.island, (c.pos[1], c.pos[2]))
        c.pos = Point3f(c.pos[1], c.pos[2], g[3] + 4f0 * HOP * Float32(u * (1 - u)))
        c.action = :gasp
    end
end

# ---------------------------------------------------------------- the cure

function boo!(s::Hiccups, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    s.state = :boo
    s.t0 = w.t
    # the friend who caught it last turns round and gives everyone the fright of their lives
    ids = [id for id in reverse(s.order) if id != s.lumi && (c = NG.creature(w, id); c !== nothing && !c.controlled)]
    s.booer = isempty(ids) ? s.lumi : ids[1]
    b = NG.creature(w, s.booer)
    NG.say!(w, b, rand(w.rng, BOOS); duration = 2.2)
    b.controlled || (b.goal = NG.Goal(:hiccup, b.pos, :proud, 60.0, w.t + 60, true, 0, false))
    for id in keys(s.sick)
        id == s.booer && continue
        c = NG.creature(w, id)
        (c === nothing || c.controlled) && continue
        c.goal = NG.Goal(:hiccup, c.pos, :scared, 60.0, w.t + 60, true, 0, false)
        s.flights[id] = (from = c.pos, T = 1.1 + 0.3rand(w.rng), h = 1.8f0 + 1.2f0 * rand(w.rng),
                         spin = (rand(w.rng) < 0.5 ? -1f0 : 1f0) * (8f0 + 6f0 * rand(w.rng)))
        rand(w.rng) < 0.5 && NG.say!(w, c, rand(w.rng, ("AAAAH!", "EEK!", "WAAH!", "YIPE!")); duration = 1.5)
    end
    empty!(s.hop)
    NG.emit!(w, :hiccup_boo; who = b.name, n = length(s.flights),
             all = join([NG.creature(w, id).name for id in s.order if NG.creature(w, id) !== nothing], ", "))
end

function step_boo!(s::Hiccups, w, dt)
    for (id, f) in collect(s.flights)
        c = NG.creature(w, id)
        c === nothing && (delete!(s.flights, id); continue)
        u = min(1.0, (w.t - s.t0) / f.T)
        g = NG.ground(w.island, (f.from[1], f.from[2]))
        c.pos = Point3f(f.from[1], f.from[2], g[3] + 4f0 * f.h * Float32(u * (1 - u)))
        c.yaw += f.spin * Float32(dt) * Float32(1 - u)
        c.action = :scared
        if u >= 1
            delete!(s.flights, id)
            c.pos = g
            c.goal = NG.Goal(:hiccup, g, :gasp, 60.0, w.t + 60, true, 0, false)
        end
    end
end

function finish!(s::Hiccups, game)
    w = game.world
    for id in vcat(collect(keys(s.sick)), [s.booer])
        c = NG.creature(w, id)
        (c === nothing || c.controlled || c.goal.kind !== :hiccup) && continue
        NG.choose_goal!(c, w)
    end
    empty!(s.sick); empty!(s.hop); empty!(s.flights)
    s.state = :idle
    s.player = false
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :hiccup_end)
end

function NG.step!(s::Hiccups, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 90.0)
    step_bubbles!(s, w, dt)
    hdown = Makie.Keyboard.h in game.keys_down
    me0 = lumi_of(w)
    if hdown && !get(H, :hdown, false) && s.state === :idle && me0 !== nothing && me0.controlled
        begin!(s, game, me0); s.player = true
    end
    H[:hdown] = hdown
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 8 < 24 * NG.daytime(w) < 19.5
            me = lumi_of(w)
            near = me === nothing ? 0 : count(c -> c !== me && healthy(s, c) && flat(c.pos, me.pos) < SEEK, w.creatures)
            if me !== nothing && healthy(s, me) && near >= 3 && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.6)
                begin!(s, game, me)
            else
                s.next_t = w.t + 45
            end
        end
        return
    end
    if game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    el = w.t - s.t0
    if s.state === :spread
        spread!(s, w)
        hiccup!(s, w, dt)
        nobody = !any(c -> healthy(s, c) && any(id -> (o = NG.creature(w, id); o !== nothing && flat(o.pos, c.pos) < SEEK), keys(s.sick)), w.creatures)
        if el > SPREAD_T || length(s.sick) >= MAXN && el > 12 || nobody && el > 15
            length(s.sick) >= 2 ? boo!(s, game) : finish!(s, game)
        end
    elseif s.state === :boo
        step_boo!(s, w, dt)
        b = NG.creature(w, s.booer)
        b !== nothing && b.goal.kind === :hiccup && (b.goal.action = :proud)
        if isempty(s.flights) && el > 1.6
            s.state = :after
            s.t0 = w.t
            for id in keys(s.sick)
                c = NG.creature(w, id)
                c !== nothing && rand(w.rng) < 0.4 && id != s.lumi && NG.say!(w, c, rand(w.rng, ("...", "...gone?", "Phew.")); duration = 2.0)
            end
        end
    else
        # silence... then the punchline: Lumi still has them
        me = NG.creature(w, s.lumi)
        if !s.punch && el > 2.6 && me !== nothing
            s.punch = true
            NG.say!(w, me, "...hic.", duration = 2.5)
            s.hop[me.id] = w.t
            bubble!(s, w, me)
            NG.emit!(w, :hiccup_punchline; who = me.name)
            me.controlled || (me.goal = NG.Goal(:hiccup, me.pos, :shy, 4.0, w.t + 4.0, true, 0, false))
            for id in keys(s.sick)
                id == s.lumi && continue
                c = NG.creature(w, id)
                c !== nothing && c.goal.kind === :hiccup && (c.goal = NG.Goal(:hiccup, c.pos, :laugh, 4.0, w.t + 4.0, true, 0, false))
            end
        end
        for (id, t) in collect(s.hop)
            c = NG.creature(w, id); u = (w.t - t) / 0.36
            (c === nothing || u >= 1) && (delete!(s.hop, id); continue)
            g = NG.ground(w.island, (c.pos[1], c.pos[2]))
            c.pos = Point3f(c.pos[1], c.pos[2], g[3] + 4f0 * HOP * Float32(u * (1 - u)))
        end
        el > 7 && finish!(s, game)
    end
    return
end

"The camera follows the newest hiccupper with the others it is running after; at the BOO, everyone."
function hiccup_group(w)
    s = H[:sys]
    s.state === :idle && return nothing
    sub = s.state === :spread ? (isempty(s.order) ? s.lumi : s.order[end]) : s.state === :boo ? s.booer : s.lumi
    c = NG.creature(w, sub)
    c === nothing && return nothing
    pts = Point3f[c.pos]
    for id in keys(s.sick)
        o = NG.creature(w, id)
        o === nothing || o === c || flat(o.pos, c.pos) > 12 || push!(pts, o.pos)
    end
    return (c.id, pts)
end

function NG.start!(s::Hiccups, game)
    H[:sys] = s
    H[:game] = game
    H[:drawn] = true
    H[:seekt] = Dict{Int32,Float64}()
    bubble_plot!(game)
    NG.CAMERA_MOMENTS["hiccups"] = w -> s.state === :idle ? nothing :
        s.state === :spread ? (isempty(s.order) ? s.lumi : s.order[end]) : s.state === :boo ? s.booer : s.lumi
    NG.CAMERA_GROUPS["hiccups"] = hiccup_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:hiccup] = "hic! ...HIC!")
end

function NG.stop!(s::Hiccups, game)
    delete!(NG.CAMERA_MOMENTS, "hiccups")
    delete!(NG.CAMERA_GROUPS, "hiccups")
    s.state === :idle || finish!(s, game)
    haskey(H, :plot) && H[:plot].parent !== nothing && delete!(H[:plot].parent, H[:plot])
end

register!(Hiccups())
