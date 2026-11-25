# The Island Choir (session 67): Lumi calls choir practice. Friends nearby gather in a half circle,
# Lumi spreads its wings to conduct, and each friend sings one note of the scale in turn (do, re, mi...).
# Then the whole choir sings one big chord together, hopping... a breath of silence... and one of them
# lets out a dreadful off-key "BWAAARP". Everyone turns to stare, Lumi hides behind a wing, then they all
# fall about laughing. Jumped in as Lumi: C calls choir practice. Every note is logged in `C[:notes]`
# (w.t, kind, midi, who), so a film can lay the real song under its pictures (movies/choir.jl).
isdefined(Main, :CHOIR) || Core.eval(Main, :(const CHOIR = Dict{Symbol,Any}()))
const NG = NeverendingGame
const C = Main.CHOIR

const GAP = (600.0, 900.0)        # sim seconds between two practices
const CALL = 20f0                 # friends this close come to sing
const MAXN = 7                    # singers
const RING = 3.4f0                # half circle radius in front of Lumi
const GATHER_T = 18.0             # at most this long to gather
const BEAT = 0.75                 # seconds between two solo notes
const SCALE = (60, 62, 64, 65, 67, 69, 71)
const SYLL = ("♪ do!", "♪ re!", "♪ mi!", "♪ fa!", "♪ so!", "♪ la!", "♪ ti!")
const KEEP = (:follow, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :giant, :egg, :storm, :toadstool)

push!(NG.BUSY_GOALS, :choir)

mutable struct Choir <: System
    state::Symbol                 # :idle, :gather, :sing
    t0::Float64
    next_t::Float64
    lumi::Int32
    singers::Vector{Int32}
    spots::Vector{Point3f}
    sung::Int                     # solo notes sung so far
    stage::Int                    # 0 solos, 1 chord, 2 silence, 3 bwaarp, 4 stare, 5 laugh
    sour::Int32                   # the off-key one
    hop::Dict{Int32,Tuple{Float64,Float32}}
    player::Bool
end
Choir() = Choir(:idle, 0.0, -1.0, 0, Int32[], Point3f[], 0, 0, 0, Dict{Int32,Tuple{Float64,Float32}}(), false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free(c) = !c.controlled && c.goal.kind ∉ KEEP && c.goal.kind !== :choir && c.action !== :sleep && c.goal.kind !== :sleep
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
hold!(w, c, target, action) = c.controlled || (c.goal = NG.Goal(:choir, target, action, 60.0, w.t + 60, false, 0, false))
pose!(w, c, action) = c.controlled || (c.goal = NG.Goal(:choir, c.pos, action, 60.0, w.t + 60, true, 0, false))
note!(w, kind, midi, c) = (push!(C[:notes], (w.t, kind, midi, c === nothing ? "" : c.name)); NG.emit!(w, :choir_note; kind, midi, who = c === nothing ? "" : c.name))
face!(c, p) = (c.yaw = Float32(atan(p[2] - c.pos[2], p[1] - c.pos[1])))
hop!(s, w, c, h) = (s.hop[c.id] = (w.t, Float32(h)))

function begin!(s::Choir, game, me)
    w = game.world
    cands = sort([c for c in w.creatures if c !== me && free(c) && flat(c.pos, me.pos) < CALL], by = c -> flat(c.pos, me.pos))
    length(cands) < 3 && return false
    s.singers = [c.id for c in cands[1:min(MAXN, end)]]
    s.state = :gather; s.t0 = w.t; s.lumi = me.id; s.sung = 0; s.stage = 0; empty!(s.hop)
    s.sour = s.singers[rand(w.rng, 1:length(s.singers))]
    # the half circle opens towards the side Lumi faces, on land
    f = Vec2f(cos(me.yaw), sin(me.yaw))
    n = length(s.singers)
    s.spots = map(1:n) do k
        a = Float32(-1.1 + 2.2 * (k - 1) / max(n - 1, 1))
        d = Vec2f(f[1] * cos(a) - f[2] * sin(a), f[1] * sin(a) + f[2] * cos(a))
        p = Vec2f(me.pos[1], me.pos[2]) + RING * d
        NG.ground(w.island, (p[1], p[2]))
    end
    NG.say!(w, me, rand(w.rng, ("Choir practice! Gather round!", "Everyone! We're singing today!", "Choir time! Come, come!")); duration = 2.5)
    pose!(w, me, :wave)
    for (k, id) in enumerate(s.singers)
        c = NG.creature(w, id)
        NG.leave_interactions!(w, c)
        hold!(w, c, s.spots[k], :walk)
        rand(w.rng) < 0.4 && NG.say!(w, c, rand(w.rng, ("Ooh, singing!", "Me me me!", "La la?", "I'm a tenor!")); duration = 1.6)
    end
    NG.emit!(w, :choir; who = me.name, n = n)
    return true
end

function finish!(s::Choir, game)
    w = game.world
    for id in vcat(s.singers, [s.lumi])
        c = NG.creature(w, id)
        (c === nothing || c.controlled || c.goal.kind !== :choir) && continue
        NG.choose_goal!(c, w)
    end
    s.state = :idle; s.player = false; empty!(s.hop)
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :choir_end; stage = s.stage)
end

function step_gather!(s::Choir, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    arrived = 0
    for (k, id) in enumerate(s.singers)
        c = NG.creature(w, id)
        c === nothing && continue
        if c.goal.kind !== :choir && !c.controlled
            hold!(w, c, s.spots[k], :walk)
        end
        # a passer-by's chat must not hold a singer back (Marshmallow sang "do!" from 6 m away, s67)
        c.controlled || c.action !== :talk || NG.leave_interactions!(w, c)
        if flat(c.pos, s.spots[k]) < 1.5
            arrived += 1
            c.goal.kind === :choir && (c.goal.arrived || pose!(w, c, :idle))
            face!(c, me.pos)
        end
    end
    if arrived >= length(s.singers) || w.t - s.t0 > GATHER_T
        s.state = :sing; s.t0 = w.t
        me.controlled || (face!(me, sum(s.spots) / length(s.spots)); pose!(w, me, :proud))
        NG.say!(w, me, "And a one... and a two...", duration = 1.6)
        NG.emit!(w, :choir_sing; n = arrived)
    end
end

function step_sing!(s::Choir, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    el = w.t - s.t0
    ids = s.singers
    n = length(ids)
    # the conductor's wings: proud (spread) on every beat
    me.controlled || (me.goal.action = s.stage <= 1 ? (isodd(floor(Int, el / BEAT)) ? :proud : :wave) : me.goal.action)
    for id in ids
        c = NG.creature(w, id)
        c !== nothing && s.stage <= 2 && c.goal.kind === :choir && face!(c, me.pos)
    end
    if s.stage == 0
        k = floor(Int, (el - 1.8) / BEAT) + 1
        if k > s.sung && k <= n
            s.sung = k
            c = NG.creature(w, ids[k])
            if c !== nothing
                NG.say!(w, c, SYLL[k]; duration = 0.9)
                pose!(w, c, :talk); hop!(s, w, c, 0.25)
                emote(c.id, :note)
                note!(w, :solo, SCALE[k], c)
            end
        elseif k > n
            s.stage = 1; s.t0 = w.t
            for id in ids
                c = NG.creature(w, id)
                c === nothing && continue
                NG.say!(w, c, "♪ LAAAAA!"; duration = 2.0)
                pose!(w, c, :dance); hop!(s, w, c, 0.5)
                emote(c.id, :note)
            end
            NG.say!(w, me, "♪ HOOOO!", duration = 2.0)
            note!(w, :chord, 72, me)
        end
    elseif s.stage == 1 && el > 2.2
        s.stage = 2; s.t0 = w.t
        for id in ids
            c = NG.creature(w, id); c === nothing || pose!(w, c, :proud)
        end
        pose!(w, me, :proud)
        note!(w, :silence, 0, nothing)
    elseif s.stage == 2 && el > 1.3
        s.stage = 3; s.t0 = w.t
        s.sour in ids || (s.sour = ids[rand(w.rng, 1:n)])
        c = NG.creature(w, s.sour)
        if c !== nothing
            NG.say!(w, c, "♪ BWAAAAARP!"; duration = 2.0)
            pose!(w, c, :proud); hop!(s, w, c, 0.35)
            note!(w, :sour, 41, c)
            NG.emit!(w, :choir_sour; who = c.name)
        end
    elseif s.stage == 3 && el > 1.4
        s.stage = 4; s.t0 = w.t
        sc = NG.creature(w, s.sour)
        for id in ids
            id == s.sour && continue
            c = NG.creature(w, id)
            (c === nothing || sc === nothing) && continue
            face!(c, sc.pos); pose!(w, c, :gasp); emote(c.id, :what)
        end
        sc === nothing || NG.say!(w, sc, "...what?", duration = 1.8)
        pose!(w, me, :shy)
        NG.say!(w, me, "...from the top?", duration = 2.0)
    elseif s.stage == 4 && el > 2.2
        s.stage = 5; s.t0 = w.t
        for id in ids
            c = NG.creature(w, id); c === nothing && continue
            pose!(w, c, :laugh)
            rand(w.rng) < 0.5 && NG.say!(w, c, rand(w.rng, ("HAHAHA!", "Hee hee!", "Bwaarp!", "Again! Again!")); duration = 1.8)
        end
        pose!(w, me, :laugh)
        note!(w, :laugh, 0, me)
    elseif s.stage == 5 && el > 3.0
        finish!(s, game)
    end
end

function step_hops!(s::Choir, w)
    for (id, (t, h)) in collect(s.hop)
        c = NG.creature(w, id); u = (w.t - t) / 0.4
        (c === nothing || u >= 1) && (delete!(s.hop, id); continue)
        g = NG.ground(w.island, (c.pos[1], c.pos[2]))
        c.pos = Point3f(c.pos[1], c.pos[2], g[3] + 4f0 * h * Float32(u * (1 - u)))
    end
end

function NG.step!(s::Choir, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 240.0)
    cdown = Makie.Keyboard.c in game.keys_down
    me0 = lumi_of(w)
    if cdown && !get(C, :cdown, false) && s.state === :idle && me0 !== nothing && me0.controlled
        begin!(s, game, me0) ? (s.player = true) : NG.say!(w, me0, "Nobody here to sing with...", duration = 2.0)
    end
    C[:cdown] = cdown
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 9 < 24 * NG.daytime(w) < 19.5
            me = lumi_of(w)
            ok = me !== nothing && free(me) && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.6) && begin!(s, game, me)
            ok || (s.next_t = w.t + 45)
        end
        return
    end
    if game.minigame !== nothing && !(game.minigame isa NG.JumpIn) || NG.creature(w, s.lumi) === nothing
        return finish!(s, game)
    end
    # a singer an event took (a race, a dance ring) is gone; one the engine sent off to an everyday goal comes back
    filter!(id -> (c = NG.creature(w, id); c !== nothing && (c.controlled || c.goal.kind === :choir ||
                   c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ KEEP && c.goal.kind ∉ (:interact, :sleep))), s.singers)
    for id in s.singers
        c = NG.creature(w, id)
        c.controlled || c.goal.kind === :choir || (NG.leave_interactions!(w, c); s.state === :gather ? hold!(w, c, s.spots[something(findfirst(==(id), s.singers), 1)], :walk) : pose!(w, c, :idle))
    end
    s.state === :gather ? step_gather!(s, game) : step_sing!(s, game)
    s.state === :idle || step_hops!(s, w)
    s.state === :idle || length(s.singers) >= 2 || finish!(s, game)
    return
end

"The whole choir and its conductor, seen from the side."
function choir_group(w)
    s = C[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    pts = Point3f[me.pos]
    for id in s.singers
        c = NG.creature(w, id); c === nothing || push!(pts, c.pos)
    end
    return (me.id, pts)
end

function NG.start!(s::Choir, game)
    C[:sys] = s
    C[:game] = game
    C[:notes] = Tuple{Float64,Symbol,Int,String}[]
    NG.CAMERA_MOMENTS["choir"] = w -> s.state === :idle ? nothing : s.state === :sing && s.stage in (3, 4) ? s.sour : s.lumi
    NG.CAMERA_GROUPS["choir"] = choir_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:choir] = "conducting the choir")
end

function NG.stop!(s::Choir, game)
    delete!(NG.CAMERA_MOMENTS, "choir")
    delete!(NG.CAMERA_GROUPS, "choir")
    s.state === :idle || finish!(s, game)
end

register!(Choir())
