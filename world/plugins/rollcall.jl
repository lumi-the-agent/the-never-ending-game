# Roll call (session 62): now and then Lumi stops, cups its beak and shouts "HELLOOO, ISLAND!", and one
# after another EVERY creature answers from wherever it is: they turn towards Lumi and wave and shout their
# own hello, the far ones faintly; even the sleepers mumble one in their sleep. Nobody walks anywhere:
# the whole island answers in one wave of voices, nearest first.
const NG = NeverendingGame

const GAP = (360.0, 600.0)
const STAGGER = 0.7                 # s between two answers
const ANSWERS = ("HELLOOO!", "Hi Lumi!", "Here!", "Yoo-hoo!", "Hello hello!", "Present!", "Ahoy!", "Over here!")
const FAR = ("...hellooo...", "(faint) hi!", "...here!")
const SLEEPY = ("zzz... hello... zzz", "mmh... here... zzz")
const SKIP = (:boing, :conga, :freeze, :circle, :hide, :found)

mutable struct RollCall <: System
    queue::Vector{Tuple{Float64,Int32}}   # (time, id) of the answers still to come
    caller::Int32
    next_t::Float64
end
RollCall() = RollCall(Tuple{Float64,Int32}[], Int32(0), -1.0)

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
busy_party() = any(((:BOING, :sys), (:FREEZE, :sys), (:CONGA, :sys))) do (d, k)
    isdefined(Main, d) && haskey(getfield(Main, d), k) && getfield(Main, d)[k].state !== :idle
end

function call!(s::RollCall, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.action === :sleep || me.goal.kind in SKIP) && return false
    others = [c for c in w.creatures if c.id != me.id && c.goal.kind ∉ SKIP && !c.controlled]
    length(others) < 3 && return false
    sort!(others, by = c -> hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]))
    # Lumi stops chatting to shout, and listens while the island answers (its chats overwrote the shout, s62)
    NG.leave_interactions!(w, me)
    me.controlled || NG.feel!(w, me, :wave; seconds = 2.0 + STAGGER * length(others) + 2.0)
    NG.say!(w, me, "HELLOOO, ISLAND!"; duration = 2.5)
    s.caller = me.id
    s.queue = [(w.t + 1.6 + STAGGER * (k - 1), c.id) for (k, c) in enumerate(others)]
    NG.emit!(w, :roll_call; n = length(others), who = join([c.name for c in others], ", "))
    return true
end

function answer!(s::RollCall, w, c)
    me = NG.creature(w, s.caller)
    d = me === nothing ? 0f0 : hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2])
    if c.action === :sleep
        NG.say!(w, c, rand(w.rng, SLEEPY); duration = 2.2)
        return
    end
    NG.say!(w, c, d > 25 ? rand(w.rng, FAR) : rand(w.rng, ANSWERS); duration = 2.0)
    if me !== nothing && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact)
        c.yaw = atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1]) - NG.species_of(c).heading
        NG.feel!(w, c, :wave; seconds = 1.4)
    else
        emote(c.id, :hey)
    end
end

function NG.step!(s::RollCall, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 90.0)
    while !isempty(s.queue) && w.t >= s.queue[1][1]
        _, id = popfirst!(s.queue)
        c = NG.creature(w, id)
        c === nothing || c.goal.kind in SKIP || answer!(s, w, c)
        if isempty(s.queue)
            me = NG.creature(w, s.caller)
            me === nothing || NG.say!(w, me, "Everyone's here! I love this island."; duration = 3)
            NG.emit!(w, :roll_call_end)
        end
    end
    isempty(s.queue) || return
    testing = game.tests !== nothing && NG.running(game.tests)
    busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
    if w.t >= s.next_t && !testing && !busy_game && !busy_party() && 7.5 < 24 * NG.daytime(w) < 21
        call!(s, game) || (s.next_t = w.t + 60)
        isempty(s.queue) || (s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng))
    end
    return
end

register!(RollCall())
