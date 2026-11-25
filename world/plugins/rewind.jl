# The pocket watch (session 92, goal 8): Lumi found a golden pocket watch that winds the island BACK. The last few
# seconds play again backwards at speed: every friend moonwalks back the way it came, a hop falls up, a chat un-says
# itself in backwards babble ("!ooooheeW"), and then time runs forward again from there, a little differently.
# Jumped in as Lumi, Z winds it back; now and then Lumi does it on its own when nothing big is going on.
isdefined(Main, :REWIND) || Core.eval(Main, :(const REWIND = Dict{Symbol,Any}()))
const NG = NeverendingGame
const RW = Main.REWIND

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

push!(NG.BUSY_GOALS, :rewind)
const KEEP_S = 9.0          # seconds of history kept
const SPEED = 2.5           # how much faster than life it plays back
const EVENTS = (:circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight, :cannonball, :waterfight,
                :mixup, :rain, :storm, :hail, :leaves, :pumpkins, :build, :tinker, :giant, :bubbles, :lanterns, :sleep)
const BABBLE = ("!eeehW", "?tahw ,hO", "...mmmH", "!yeH", "!seirreB", "!ti er'uoY", "!ooH", "?neppah tahw tiaW")

struct Frame
    t::Float64
    ids::Vector{Int32}
    pos::Vector{Point3f}
    yaw::Vector{Float32}
    act::Vector{Symbol}
    phase::Vector{Float32}
    extra::Vector{Float32}
end

mutable struct Rewind <: System
    state::Symbol           # :rec :rewind :land
    t0::Float64
    from::Float64           # the history time the rewind started at
    back::Float64           # how far back it goes (s of history)
    k::Int                  # where in the history it is
    hist::Vector{Frame}
    falling::Dict{Int32,Tuple{Point3f,Float64}}
end
Rewind() = Rewind(:rec, 0.0, 0.0, 0.0, 0, Frame[], Dict{Int32,Tuple{Point3f,Float64}}())

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

function record!(s::Rewind, w)
    !isempty(s.hist) && w.t - s.hist[end].t < 1 / 40 && return
    cs = w.creatures
    push!(s.hist, Frame(w.t, Int32[c.id for c in cs], Point3f[c.pos for c in cs], Float32[c.yaw for c in cs],
                        Symbol[c.action for c in cs], Float32[c.phase for c in cs], Float32[c.extra for c in cs]))
    n = findfirst(f -> w.t - f.t <= KEEP_S, s.hist)
    n === nothing || n <= 1 || deleteat!(s.hist, 1:n-1)
end

"Wind the island back `back` seconds (as much as there is). Returns false when there is too little history."
function wind_back!(s::Rewind, game; back = 6.0)
    w = game.world
    s.state === :rec || return false
    length(s.hist) < 20 && return false
    s.back = min(back, s.hist[end].t - s.hist[1].t)
    s.from = s.hist[end].t; s.k = length(s.hist)
    s.state = :rewind; s.t0 = w.t
    for (i, c) in enumerate(w.creatures)
        c.controlled && continue
        c.goal.kind in EVENTS && continue
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:rewind, c.pos, c.action, 60.0, w.t + 60, true, 0, false)
        c.name == "Lumi" || i % 3 == 0 && NG.say!(w, c, BABBLE[mod1(i + round(Int, w.t), length(BABBLE))]; duration = 1.6)
    end
    me = lumi_of(w)
    me === nothing || NG.say!(w, me, "◀◀ Wait. Let me try that again."; duration = 2.0)
    push!(get!(() -> Tuple{Float64,Symbol}[], RW, :log), (w.t, :rewind))
    # the tape whirr in the browsers that watch (voice.jl plays site/voice/game/*.mp3)
    game.dash !== nothing && haskey(game.plugins, "voice") && Base.invokelatest(game.plugins["voice"].mod.say!, game, "rewind")
    NG.emit!(w, :rewind_start; back = s.back)
    return true
end

function play_back!(s::Rewind, game)
    w = game.world
    τ = s.from - SPEED * (w.t - s.t0)              # where in the history we are now
    while s.k > 1 && s.hist[s.k].t > τ
        s.k -= 1
    end
    f = s.hist[s.k]
    for (j, id) in enumerate(f.ids)
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :rewind && !c.controlled) && continue
        c.pos = f.pos[j]; c.yaw = f.yaw[j]; c.action = f.act[j]; c.phase = f.phase[j]; c.extra = f.extra[j]
        c.goal.kind === :rewind && (c.goal.action = c.action)
    end
    if τ <= s.from - s.back || s.k == 1
        # time runs forward again from here: whoever hangs in the air drops, everyone picks something new
        s.state = :land; s.t0 = w.t
        for c in w.creatures
            (c.goal.kind === :rewind || c.controlled) || continue
            g = NG.ground(w.island, (c.pos[1], c.pos[2]))
            c.pos[3] - g[3] > 0.25f0 && (s.falling[c.id] = (c.pos, w.t))
        end
        me = lumi_of(w)
        me === nothing || me.controlled || NG.say!(w, me, "There. Much better."; duration = 2.0)
        push!(RW[:log], (w.t, :forward))
    end
end

function land!(s::Rewind, game)
    w = game.world
    for (id, (from, since)) in collect(s.falling)
        c = NG.creature(w, id); c === nothing && (delete!(s.falling, id); continue)
        g = NG.ground(w.island, (from[1], from[2]))
        z = from[3] - 4.9f0 * Float32(w.t - since)^2
        if z > g[3]
            c.pos = Point3f(from[1], from[2], z)
        else
            c.pos = g; delete!(s.falling, id)
        end
    end
    if isempty(s.falling) && w.t - s.t0 > 0.3
        # time runs on: the friends are not sure what just happened (a gasp, a puzzled think, now and then a deja vu),
        # Lumi is rather pleased with itself; then everyone goes on with the day (feel! hands them back)
        for (i, c) in enumerate(w.creatures)
            (c.goal.kind === :rewind && !c.controlled) || continue
            if c.name == "Lumi"
                NG.feel!(w, c, :proud; seconds = 1.8)
            else
                NG.feel!(w, c, isodd(i) ? :gasp : :think; seconds = 1.2 + 0.8 * rand(w.rng))
                i % 4 == 1 && NG.say!(w, c, "...déjà vu?"; duration = 1.8)
            end
        end
        empty!(s.hist)                          # history starts again from here
        s.state = :rec
        NG.emit!(w, :rewind_end)
    end
end

"Live only (a film draws its own): a << REWIND sign in the corner while time runs back."
function sign!(game, on::Bool)
    (game.stage === nothing || game.dash === nothing) && return
    ov = game.stage.overlay
    if !(haskey(RW, :sign) && RW[:sign].parent === ov)
        # an old-tape look over the whole view: a cool wash and a few faint scan lines
        haskey(RW, :tint) && RW[:tint].parent !== nothing && delete!(RW[:tint].parent, RW[:tint])
        RW[:tint] = poly!(ov, [Rect2f(0, 0, 1, 1); [Rect2f(0, y, 1, 0.006) for y in 0.05:0.11:0.95]]; space = :relative,
                          color = [RGBAf(0.45, 0.6, 0.95, 0.13); [RGBAf(1, 1, 1, 0.1) for _ in 0.05:0.11:0.95]],
                          strokewidth = 0, visible = false)
        RW[:sign] = textlabel!(ov, Point2f(0.14, 0.9); space = :relative, text = "<<  REWIND", fontsize = 30,
                               text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.6),
                               strokewidth = 0, padding = 12, cornerradius = 10, visible = false)
    end
    RW[:sign].visible[] == on || (RW[:sign].visible[] = on; RW[:tint].visible[] = on)
end

function NG.step!(s::Rewind, game, dt)
    w = game.world
    me = lumi_of(w)
    # Z, jumped in as Lumi
    zdown = Makie.Keyboard.z in game.keys_down
    if zdown && !get(RW, :zdown, false) && me !== nothing && me.controlled && s.state === :rec
        wind_back!(s, game)
    end
    RW[:zdown] = zdown
    if s.state === :rec
        record!(s, w)
        # now and then Lumi does it by itself, when nothing big is going on
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= get(RW, :next, w.t + 1) && !testing && !busy_game && me !== nothing && !me.controlled &&
           me.action !== :sleep && me.goal.kind ∉ EVENTS && party_free(w)
            wind_back!(s, game) && claim_party!(w, 8)
            RW[:next] = w.t + 600 + 600 * rand(w.rng)              # every 10-20 minutes
        end
        haskey(RW, :next) || (RW[:next] = w.t + 180 + 180 * rand(w.rng))   # the first a few minutes after a start, so a watcher sees it
    elseif s.state === :rewind
        play_back!(s, game)
    else
        land!(s, game)
    end
    sign!(game, s.state === :rewind)
end

function NG.start!(s::Rewind, game)
    RW[:sys] = s
    get(RW, :next, 0.0) == Inf || delete!(RW, :next)     # (a reload re-times the next one; a film's setup keeps its Inf)
    RW[:start] = (; back = 6.0) -> wind_back!(s, game; back)
    NG.CAMERA_MOMENTS["rewind"] = w -> (s.state === :rec ? nothing : (me = lumi_of(w); me === nothing || me.controlled ? nothing : me.id))
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:rewind] = "winding the island back")
    return nothing
end

function NG.stop!(s::Rewind, game)
    w = game.world
    for c in w.creatures
        c.goal.kind === :rewind && !c.controlled && NG.choose_goal!(c, w)
    end
    s.state = :rec; empty!(s.hist); empty!(s.falling)
    delete!(NG.CAMERA_MOMENTS, "rewind")
    for k in (:sign, :tint)
        haskey(RW, k) && RW[k].parent !== nothing && delete!(RW[k].parent, RW[k])
        delete!(RW, k)
    end
end

register!(Rewind())
