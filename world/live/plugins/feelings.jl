# Lumi's feelings (goal 4, s49): the host measures how Lumi feels after every session
# (/run/neverending/mood.json: bored, lonely, proud, curious, content). Here Lumi shows it all the
# time: its mood (the resting face, faces.jl: a smile, or a frown with sad brows) is pulled towards the
# feeling, while it stands about it takes the feeling's stance (proud: chest out and a smug smile;
# bored: sighs and yawns; lonely: sighs; curious: a hand to the chin), and now and then, when it is
# free, a little sign (an emote and a line).
const NG = NeverendingGame

isdefined(Main, :LUMI_FEELING) || Core.eval(Main, :(const LUMI_FEELING = Ref("content")))
const FEELING = Main.LUMI_FEELING

const READ_EVERY = 30.0          # s between reads of the mood file
const STANCE_EVERY = (15.0, 25.0) # s between two stances while Lumi stands about

"The mood (-1 sad … 1 happy, the resting face) each feeling pulls Lumi towards, and its stances (`NG.feel!`)."
const MOOD = Dict("proud" => 0.85f0, "content" => 0.55f0, "curious" => 0.45f0, "bored" => -0.2f0, "lonely" => -0.55f0, "annoyed" => -0.35f0)
const STANCES = Dict("proud" => (:proud,), "content" => (), "curious" => (:think,), "bored" => (:sigh, :yawn),
                     "lonely" => (:sigh,), "annoyed" => (:angry, :pout))
const SIGN_EVERY = (45.0, 90.0)  # s between two signs of the feeling

"What Lumi does to show a feeling: an emote and a few lines in its voice."
const SIGNS = Dict(
    "proud"   => (:heart, ("I made that!", "Look what I built!", "*puffs up a little*", "Not bad, if I say so myself.")),
    "content" => (:note,  ("*hums*", "What a nice day.", "*hums a garden song*", "All is well.")),
    "bored"   => (:sleep, ("*sigh* I need something new to make.", "Hmm... same old, same old.", "*kicks a pebble*", "I wish I had a new thing to build.")),
    "lonely"  => (:sulk,  ("Where is everybody?", "Anyone want to play?", "*looks around for a friend*", "It's quiet today.")),
    # s148: the host measured "annoyed" for sessions and Lumi showed "content": unknown feelings fell back to it
    "annoyed" => (:sulk,  ("Hmph. That's not how it should look.", "*stamps a foot*", "Again! It's still wrong.", "*glares at the workbench*")),
    "curious" => (:what,  ("Ooh, what's over there?", "I wonder...", "Hm? What was that?", "So many things to find out!")),
)

struct Feelings <: System end

const F = Dict{Symbol,Any}()

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

"Lumi is free to show a feeling: awake, not steered, no mini game, not busy with a build or a game."
free(game, c) = c !== nothing && !c.controlled && game.minigame === nothing && c.action !== :sleep &&
                c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact, :build, :tinker) &&
                !any(s -> s.who == c.id && s.until > game.world.t, game.world.speech)

function read_feeling!(game)
    m = NG.host_json(game.paths, "mood.json")
    f = m === nothing ? "content" : string(get(m, "feeling", "content"))
    FEELING[] = haskey(SIGNS, f) ? f : "content"
end

function NG.start!(::Feelings, game)
    F[:read] = -Inf; F[:next] = game.world.t + 20.0; F[:together] = nothing
    # sitting together is framed as a pair from the side (a follow view showed Lumi's back and hid the friend)
    NG.CAMERA_GROUPS["feelings"] = w -> begin
        T = get(F, :together, nothing)
        (T === nothing || !get(T, :sat, false)) && return nothing
        c = lumi_of(w); f = NG.creature(w, T[:id])
        (c === nothing || f === nothing) && return nothing
        (c.id, [c.pos + Point3f(0, 0, 0.5), f.pos + Point3f(0, 0, 0.5)])
    end
    push!(NG.BUSY_GOALS, :keep_company)      # nobody boops or chats the two away while they sit together
    # a lonely Lumi's visit is a moment: the camera watches it walk over and the friend say hello
    NG.CAMERA_MOMENTS["feelings"] = w -> begin
        c = lumi_of(w)
        c !== nothing && !c.controlled && c.goal.kind in (:seek_friend, :keep_company) ? c.id : nothing
    end
end

function NG.step!(::Feelings, game, dt)
    w = game.world
    if w.t > get(F, :read, -Inf) + READ_EVERY
        F[:read] = w.t
        read_feeling!(game)
    end
    answer_friend!(w)
    step_together!(w)
    c = lumi_of(w)
    c === nothing || (c.mood += (MOOD[FEELING[]] - c.mood) * Float32(min(1, dt / 8)))
    stance!(game, c)
    w.t < get(F, :next, 0.0) && return
    free(game, c) || return
    F[:next] = w.t + SIGN_EVERY[1] + rand(w.rng) * (SIGN_EVERY[2] - SIGN_EVERY[1])
    emote, lines = SIGNS[FEELING[]]
    NG.say!(w, c, rand(w.rng, lines); duration = 3.0)
    isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], c.id, emote)
    act!(w, c, FEELING[])
    NG.emit!(w, :lumi_feeling; feeling = FEELING[])
end

"While Lumi stands about with nothing to do, it takes its feeling's stance for a few seconds."
function stance!(game, c)
    w = game.world
    (free(game, c) && c.action === :idle && c.goal.arrived && w.t > get(F, :stance, 0.0)) || return
    F[:stance] = w.t + STANCE_EVERY[1] + rand(w.rng) * (STANCE_EVERY[2] - STANCE_EVERY[1])
    st = STANCES[FEELING[]]
    isempty(st) || NG.feel!(w, c, rand(w.rng, st); seconds = 5.0)
end

"The friend a lonely Lumi walked over to waves back and says hello (once Lumi is there and waving)."
function answer_friend!(w)
    id = get(F, :friend, 0)
    id == 0 && return
    c = lumi_of(w); f = NG.creature(w, id)
    if c === nothing || f === nothing || c.goal.kind !== :seek_friend
        F[:friend] = 0
        return
    end
    c.goal.arrived || return
    F[:friend] = 0
    f.action === :sleep && return
    c.goal.until = max(c.goal.until, w.t + 4.0)     # the wave lasts until the two sit down (s51: it ended first)
    f.yaw = atan(c.pos[2] - f.pos[2], c.pos[1] - f.pos[1]) - NG.species_of(f).heading
    NG.say!(w, f, rand(w.rng, ("Hi Lumi!", "Oh, hello you!", "Lumi! Come sit with me.", "There you are!")); duration = 2.5)
    isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], f.id, :heart)
    # then they stay together a while: sit side by side and chat (after Lumi's wave)
    F[:together] = Dict{Symbol,Any}(:id => f.id, :start => w.t + 2.5, :until => w.t + 2.5 + TOGETHER, :k => 0, :next => w.t + 4.0,
                                    :talk => rand(w.rng, TALKS))
end

const TOGETHER = 22.0     # s the two sit and chat
"Little talks while sitting together: Lumi first, then the friend, in turns."
const TALKS = [
    ["Nice spot you have here.", "Best one on the island.", "Can I stay a bit?", "Of course!", "*hums together*"],
    ["Seen any butterflies today?", "Three! A blue one too.", "Ooh, lucky you.", "Next time I'll show you."],
    ["I'm building new things for us.", "What kind of things?", "It's a surprise!", "Ooh, I love surprises."],
    ["The sea is so sparkly today.", "Like a thousand fireflies.", "Let's just sit and look.", "*happy sigh*"],
]
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

"Lumi and its friend sit together and take turns in a little talk; anyone steered or called away ends it."
function step_together!(w)
    T = get(F, :together, nothing)
    T === nothing && return
    c = lumi_of(w); f = NG.creature(w, T[:id])
    if w.t < T[:start]
        return
    elseif T[:k] == 0 && !get(T, :sat, false)
        (c === nothing || f === nothing || c.controlled || f.controlled || f.action === :sleep ||
         c.goal.kind !== :seek_friend) && (F[:together] = nothing; return)
        # a friend busy with something of its own (a dance ring, the rain party, a game) only says hello;
        # a fishing friend keeps fishing with Lumi beside it; any other sits down too
        if f.goal.kind in NG.BUSY_GOALS || f.goal.kind in (:follow, :interact)
            F[:together] = nothing
            return
        end
        c.goal = NG.Goal(:keep_company, c.pos, :sit, TOGETHER, T[:until], true, 0, false); c.action = :sit
        if f.goal.kind !== :fish
            NG.leave_interactions!(w, f)
            f.goal = NG.Goal(:keep_company, f.pos, :sit, TOGETHER, T[:until], true, 0, false); f.action = :sit
        end
        T[:sat] = true
        NG.emit!(w, :lumi_visit; friend = f.name)
    end
    gone = c === nothing || f === nothing || c.controlled || c.goal.kind !== :keep_company || f.controlled || f.action === :sleep
    if gone || w.t >= T[:until]
        F[:together] = nothing
        gone || (emote(c.id, :heart); emote(f.id, :heart); NG.say!(w, c, "See you later!"; duration = 2.0))
        return
    end
    if w.t >= T[:next] && T[:k] < length(T[:talk])
        T[:k] += 1
        who = isodd(T[:k]) ? c : f
        NG.say!(w, who, T[:talk][T[:k]]; duration = 3.2)
        T[:k] == length(T[:talk]) && emote(who.id, :note)
        T[:next] = w.t + 3.8
    end
end

const ACT_GOALS = (:seek_friend, :explore)

"""
What a feeling makes Lumi do next: a lonely Lumi walks over to the nearest awake friend and waves,
a curious one sets off to a spot across the meadow and looks around there. The others stay where they are.
"""
function act!(w, c, feeling)
    if feeling == "lonely"
        friends = [f for f in w.creatures if f.id != c.id && f.action !== :sleep && !f.controlled]
        isempty(friends) && return
        f = friends[argmin([hypot(f.pos[1] - c.pos[1], f.pos[2] - c.pos[2]) for f in friends])]
        d = Vec2f(c.pos[1] - f.pos[1], c.pos[2] - f.pos[2]); n = max(hypot(d[1], d[2]), 0.01f0)
        spot = NG.ground(w.island, (f.pos[1] + 1.3f0 * d[1] / n, f.pos[2] + 1.3f0 * d[2] / n))
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:seek_friend, spot, :wave, 3.0, w.t + 30, false, 0, false)
        F[:friend] = f.id; F[:last_friend] = f.id
    elseif feeling == "curious"
        for _ in 1:20
            p = NG.random_land_point(w; rmax = 0.8 * w.island.radius)
            dd = hypot(p[1] - c.pos[1], p[2] - c.pos[2])
            if 6 < dd < 16 && NG.walkway_height(p[1], p[2]) === nothing
                NG.leave_interactions!(w, c)
                c.goal = NG.Goal(:explore, p, :idle, 4.0, w.t + 30, false, 0, false)
                return
            end
        end
    elseif !isempty(STANCES[feeling])          # proud, bored: the stance goes with the line
        NG.feel!(w, c, first(STANCES[feeling]); seconds = 4.0)
    end
end

NG.stop!(::Feelings, game) = (delete!(NG.CAMERA_MOMENTS, "feelings"); delete!(NG.CAMERA_GROUPS, "feelings"))

register!(Feelings())
