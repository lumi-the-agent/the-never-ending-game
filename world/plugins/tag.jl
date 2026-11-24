# Tag (Lumi's wish, s49): now and then, in daylight, three or four critters who are close together
# start a game of tag. One is "it" and runs after the nearest; the others run away, squealing,
# and stay near where the game began. A touch passes "it" on ("Tag! You're it!"). After 40 s
# everyone hops and says it was fun. The camera frames the chase as a group.
const NG = NeverendingGame

isdefined(Main, :TAG_STATE) || Core.eval(Main, :(const TAG_STATE = Dict{Symbol,Any}(:game => nothing, :next => 0.0, :tags => 0)))
const TS = Main.TAG_STATE

const ROUND = 40.0        # s a game lasts
const EVERY = 240.0       # s between two games at most once
const NEAR = 9.0f0        # m: players start within this of each other, and stay within it of the centre
const TOUCH = 0.35f0      # m between the two bodies: a tag
const FREEZE = 1.6        # s the new "it" counts before running
const SQUEALS = ("Eek!", "Can't catch me!", "Nyeh nyeh!", "Too slow!", "Wheee!")

struct Tag <: System end

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
free(c) = c.name != "Lumi" && !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact)
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

"Start a game with `players` (creatures); the first is it."
function start_tag!(w, players)
    for c in players
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:tag, c.pos, :idle, 0.5, w.t + 5, false, 0, true)
    end
    it = first(players)
    centre = sum(c.pos for c in players) / length(players)
    TS[:game] = Dict{Symbol,Any}(:players => [c.id for c in players], :it => it.id, :last => Int32(0), :since => w.t,
                                 :until => w.t + ROUND, :centre => Point3f(centre))
    NG.say!(w, it, "Let's play tag! I'm it!"; duration = 2.5)
    emote(it.id, :hey)
    NG.emit!(w, :tag_start; players = [c.name for c in players])
end

function try_start!(w)
    w.t < TS[:next] && return
    TS[:next] = w.t + 20 + 20rand(w.rng)
    NG.night_factor(w) > 0.3f0 && return
    cs = filter(free, w.creatures)
    for c in cs
        near = [o for o in cs if o.id != c.id && flat(o.pos, c.pos) < NEAR]
        length(near) >= 2 || continue
        TS[:next] = w.t + EVERY
        return start_tag!(w, [c; near[1:min(end, 3)]])
    end
end

function end_tag!(w, g; fun = true)
    for id in g[:players]
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :tag) && continue
        if fun
            c.goal = NG.Goal(:answer, c.pos, :jump, 1.6, w.t + 1.6, true, 0, false); c.action = :jump
            emote(c.id, :heart)
        else
            c.goal = NG.Goal()
        end
    end
    fun && (c = NG.creature(w, g[:it]); c === nothing || NG.say!(w, c, "That was fun! Again tomorrow?"; duration = 2.5))
    TS[:game] = nothing
    NG.emit!(w, :tag_end; tags = TS[:tags])
end

"Where a runner goes: 3.5 m straight away from it, bent back towards the centre when it would leave the field."
function flee_target(w, c, it, centre)
    d = Vec2f(c.pos[1] - it.pos[1], c.pos[2] - it.pos[2]); n = max(hypot(d[1], d[2]), 0.01f0)
    d = d / n
    back = Vec2f(centre[1] - c.pos[1], centre[2] - c.pos[2]); nb = hypot(back[1], back[2])
    nb > 0.6NEAR && (d = d + 1.2f0 * back / nb; d = d / max(hypot(d[1], d[2]), 0.01f0))
    for turn in (0f0, 0.8f0, -0.8f0, 1.6f0, -1.6f0)
        q = Vec2f(cos(turn) * d[1] - sin(turn) * d[2], sin(turn) * d[1] + cos(turn) * d[2])
        p = (c.pos[1] + 3.5f0 * q[1], c.pos[2] + 3.5f0 * q[2])
        NG.on_land(w.island, p[1], p[2]; margin = 0.3f0) && return NG.ground(w.island, p)
    end
    return NG.ground(w.island, (centre[1], centre[2]))
end

function step_tag!(w, g)
    players = [NG.creature(w, id) for id in g[:players]]
    # a player called away (steered, asleep, another plugin's goal) leaves the game
    # the player (steering Lumi) joins by walking up to the game, and plays until they walk off
    me = findfirst(c -> c.controlled, w.creatures)
    if me !== nothing && !(w.creatures[me].id in g[:players]) && flat(w.creatures[me].pos, g[:centre]) < NEAR
        p = w.creatures[me]
        push!(g[:players], p.id); push!(players, p)
        (c = NG.creature(w, g[:it]); c === nothing || NG.say!(w, c, "$(p.name) wants to play too! Run!"; duration = 2.2))
        NG.emit!(w, :tag_join; who = p.name)
    end
    # Lumi itself (nobody steering it) runs over and joins a game near it, once per game
    sp = findfirst(c -> c.name == "Lumi", w.creatures)
    if sp !== nothing && !get(g, :lumi_asked, false)
        c = w.creatures[sp]
        if !c.controlled && c.action !== :sleep && !(c.id in g[:players]) && c.goal.kind ∉ NG.BUSY_GOALS &&
           c.goal.kind ∉ (:follow, :interact, :build, :tinker, :seek_friend, :keep_company) && flat(c.pos, g[:centre]) < 1.5NEAR
            g[:lumi_asked] = true
            NG.leave_interactions!(w, c)
            c.goal = NG.Goal(:tag, g[:centre], :idle, 0.5, w.t + 5, false, 0, true)
            push!(g[:players], c.id); push!(players, c)
            NG.say!(w, c, rand(w.rng, ("Ooh, tag! Me too!", "Wait for me!", "Can I play?")); duration = 2.2)
            NG.emit!(w, :tag_join; who = c.name)
        end
    end
    player(c) = c.controlled && flat(c.pos, g[:centre]) < 1.6NEAR
    keep = [c for c in players if c !== nothing && (player(c) || !c.controlled && c.action !== :sleep && c.goal.kind === :tag)]
    for c in players
        c === nothing || c in keep || (TS[:left] = (c.name, c.goal.kind, c.action, c.controlled); NG.emit!(w, :tag_left; who = c.name, goal = c.goal.kind))
    end
    g[:players] = [c.id for c in keep]
    it = NG.creature(w, g[:it])
    (length(keep) < 2 || it === nothing || !(it in keep)) && return end_tag!(w, g; fun = length(keep) >= 2)
    w.t > g[:until] && return end_tag!(w, g)
    # the chase's targets move all the time: separation's unstick! (no progress for 12 s) would drop a runner
    # whose target keeps its distance, so every few seconds each player gets a fresh goal object
    if w.t > get(g, :renew, 0.0)
        g[:renew] = w.t + 4.0
        foreach(c -> c.controlled || (c.goal = NG.Goal(:tag, c.goal.target, :idle, 0.5, w.t + 5, false, 0, c.goal.run)), keep)
    end
    runners = [c for c in keep if c.id != it.id]
    frozen = w.t - g[:since] < FREEZE
    if frozen                                     # (a player who is it chases with W/A/D; their touch counts the same)
        it.controlled || (it.goal.target = it.pos; it.goal.arrived = false; it.goal.until = w.t + 5)
    else
        # chase the nearest, but not the one who just tagged it (no tag backs)
        cand = [c for c in runners if c.id != g[:last]]
        isempty(cand) && (cand = runners)
        prey = cand[argmin([flat(c.pos, it.pos) for c in cand])]
        it.controlled || (it.goal.target = prey.pos; it.goal.arrived = false; it.goal.until = w.t + 5; it.goal.run = true)
        # bodies never overlap (separation): a touch is the two bodies plus a hand's width apart
        if flat(prey.pos, it.pos) < TOUCH + NG.body_radius(NG.species_of(prey)) + NG.body_radius(NG.species_of(it))
            NG.say!(w, it, "Tag! You're it!"; duration = 2.0); emote(it.id, :note)
            NG.say!(w, prey, rand(w.rng, ("Aww!", "Got me!", "No fair!")); duration = 1.8); emote(prey.id, :what)
            g[:last] = it.id; g[:it] = prey.id; g[:since] = w.t
            TS[:tags] += 1
            NG.emit!(w, :tag_tagged; it = prey.name, by = it.name)
            return
        end
    end
    for c in runners
        c.controlled && continue
        close = flat(c.pos, it.pos) < 2.5f0     # runners dawdle until it is near: it can catch up
        c.goal.target = flee_target(w, c, it, g[:centre]); c.goal.arrived = false; c.goal.until = w.t + 5
        c.goal.run = close
        close && rand(w.rng) < 0.004 && !any(s -> s.who == c.id && s.until > w.t, w.speech) &&
            NG.say!(w, c, rand(w.rng, SQUEALS); duration = 1.5)
    end
end

function NG.start!(::Tag, game)
    push!(NG.BUSY_GOALS, :tag)
    TS[:next] = game.world.t + 60.0
    NG.CAMERA_MOMENTS["tag"] = w -> (g = TS[:game]; g === nothing ? nothing : g[:it])
    NG.CAMERA_GROUPS["tag"] = w -> begin
        g = TS[:game]
        g === nothing && return nothing
        # it and the one it chases: framing every player put the camera far back over the meadow
        it = NG.creature(w, g[:it])
        it === nothing && return nothing
        rs = [c for c in (NG.creature(w, id) for id in g[:players]) if c !== nothing && c.id != it.id]
        isempty(rs) && return nothing
        prey = rs[argmin([flat(c.pos, it.pos) for c in rs])]
        (g[:it], [it.pos, prey.pos])
    end
end

function NG.step!(::Tag, game, dt)
    w = game.world
    for c in w.creatures                        # players laugh as they run (faces.jl: glee in `extra`)
        c.goal.kind === :tag && c.action === :run && (c.extra = 1.0f0)
    end
    g = TS[:game]
    if g === nothing
        game.dash === nothing && return             # no games in quiet copies (clips, stills)
        game.minigame === nothing && try_start!(w)
    else
        step_tag!(w, g)
    end
end

function NG.stop!(::Tag, game)
    TS[:game] === nothing || end_tag!(game.world, TS[:game]; fun = false)
    delete!(NG.CAMERA_MOMENTS, "tag"); delete!(NG.CAMERA_GROUPS, "tag")
end

register!(Tag())
