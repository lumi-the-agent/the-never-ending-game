# Presents (Lumi's wish: "I want to know who likes what: Wibbles loves flowers, Gloop loves fishing.
# I want to remember it and bring them the right present"). Lumi watches what each friend does
# (the event log of the island, and every few seconds what they are busy with) and remembers each
# one's favourite pastime. Every few minutes by day it fetches the right present from its workshop
# crates (a starfish for a fisher, seashells for a beachcomber, a yellow flower for a flower lover),
# carries it over its head to that friend and gives it: "You love fishing!". The friend is delighted.
isdefined(Main, :PRESENTS) || Core.eval(Main, :(const PRESENTS = Dict{Symbol,Any}()))
using Serialization
const NG = NeverendingGame
const PR = Main.PRESENTS
const PRESENTS_VERSION = 1

# pastime => (present asset, present name, what Lumi says it loves, height of the present in m)
const GIFTS = Dict(
    :sea => ("20261123-135736-240-asset", "a starfish", "fishing", 0.32f0),
    :beach => ("20261123-135734-637-asset", "seashells", "the beach", 0.30f0),
    :flowers => ("20261123-041652-323-asset", "a yellow flower", "flowers", 0.42f0),
)
# what the log and the goals say about a pastime
const PASTIME = Dict(:fishing => :sea, :fish => :sea,
    :beachcomb => :beach, :sunbathe => :beach, :flowers => :flowers, :flower_gift => :flowers, :gift => :flowers)
const EVERY = 200.0          # s between presents
const KEEP = 150.0           # s a friend carries its present around before it puts it away
const SHOW_OFF = ("Look! Lumi gave me %g!", "%n, see my present? %G!", "Lumi knows I love %l!")
const SHOW_BACK = ("Ooh, lucky you!", "So pretty!", "I want one too!", "Lumi is the best.")
const THANKS = ("My favourite! How did you know?", "Oh Lumi, you remembered!", "For ME? I love it!", "Best present ever!")

for k in (:present, :invite)
    k in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, k)
end

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
likes() = get!(() -> Dict{String,Dict{Symbol,Float64}}(), PR, :likes)
note!(name, kind, n = 1.0) = (p = get(PASTIME, kind, nothing); p === nothing || (d = get!(() -> Dict{Symbol,Float64}(), likes(), name); d[p] = get(d, p, 0.0) + n))

"""
A friend's favourite pastime and how sure Lumi is (its count), or nothing: what it does MORE than the
others do (everyone fishes a lot; the one who beachcombs twice as much as the rest loves the beach).
"""
function favourite(name)
    d = get(likes(), name, nothing)
    (d === nothing || isempty(d)) && return nothing
    isl = Dict{Symbol,Float64}()
    for e in values(likes()), (k, v) in e
        isl[k] = get(isl, k, 0.0) + v
    end
    tot, atot = sum(values(d)), sum(values(isl))
    lift(k) = d[k] < 3 ? 0.0 : (d[k] / tot) / (isl[k] / atot)
    best = argmax(lift, collect(keys(d)))
    lift(best) == 0 && return nothing
    return (best, d[best])
end

"Lumi remembers: the island's event log (the human's game, the last ~20000 lines)."
function remember_log!(game)
    dir = joinpath(game.paths.world, "log")
    files = sort(filter(f -> startswith(f, "events-") && endswith(f, ".jsonl"), readdir(dir)))
    isempty(files) && return
    lines = String[]
    for f in reverse(files)
        prepend!(lines, readlines(joinpath(dir, f)))
        length(lines) > 20000 && break
    end
    for l in lines[max(1, end - 20000):end]
        m = match(r"\"kind\":\"([a-z_]+)\"", l); m === nothing && continue
        k = Symbol(m[1]); haskey(PASTIME, k) || continue
        who = match(r"\"who\":\"([^\"]+)\"", l); who === nothing && continue
        note!(String(who[1]), k)
    end
end

"Where Lumi fetches presents: the workshop's crate pile, or its own spot when there is none."
function crate_spot(w, me)
    sol = isdefined(Main, :EXTRA_SOLIDS) ? get(Main.EXTRA_SOLIDS, "workshop", nothing) : nothing
    sol === nothing && return me.pos
    p, r = sol[3]                                  # the crate pile
    d = Vec2f(me.pos[1] - p[1], me.pos[2] - p[2]); d = d / max(norm(d), 1f-3)
    return NG.ground(w.island, (p[1] + (r + 0.6f0) * d[1], p[2] + (r + 0.6f0) * d[2]))
end

"The friend for the next present: awake, free, near, a known favourite, not given one lately."
function pick_friend(w, me)
    given = get!(() -> Dict{String,Float64}(), PR, :given)
    best = nothing; bs = -Inf
    for c in w.creatures
        (c === me || c.controlled || c.action === :sleep || c.goal.kind in (:sleep, :follow, :interact) || c.goal.kind in NG.BUSY_GOALS) && continue
        f = favourite(c.name); f === nothing && continue
        w.t - get(given, c.name, -1e9) < 6 * EVERY && continue
        d = flat(c.pos, me.pos); d > 45 && continue
        # on the sand, the pier or in the shallows Lumi cannot walk up to it (the engine drops a blocked walk)
        NG.on_land(w.island, c.pos[1], c.pos[2]; margin = 0.4f0) || continue
        s = log(1 + f[2]) - 0.05d
        s > bs && (best = c; bs = s)
    end
    return best
end

function start_present!(w, me)
    o = pick_friend(w, me)
    o === nothing && return false
    p, _ = favourite(o.name)
    NG.leave_interactions!(w, me)
    PR[:job] = Dict{Symbol,Any}(:to => o.id, :gift => p, :stage => :fetch, :t => w.t)
    me.goal = NG.Goal(:present, crate_spot(w, me), :eat, 2.0, w.t + 60.0, false, 0, false)
    NG.say!(w, me, "$(o.name) loves $(GIFTS[p][3])... I know just the thing!"; duration = 3.0)
    NG.emit!(w, :present_plan; who = "Lumi", to = o.name, gift = GIFTS[p][2])
    return true
end

function cancel!(w, me, why)
    NG.emit!(w, :present_end; why = why)
    delete!(PR, :job)
    me !== nothing && me.goal.kind === :present && (me.goal = NG.Goal(:idle, me.pos, :idle, 1.0, w.t + 1.0, true, 0, false))
end

"""
Lumi walks in straight lines and wedges between trunks (AGENTS.md, s52): no 0.3 m of progress in
3 s while walking counts as stuck (the engine's `unstick!` would drop the walk after 12 s).
"""
function stuck!(job, me, w)
    me.goal.arrived && (job[:prog] = (me.pos, w.t); return false)
    p, t = get!(job, :prog, (me.pos, w.t))
    flat(p, me.pos) > 0.3f0 && (job[:prog] = (me.pos, w.t); return false)
    w.t - t < 3 && return false
    job[:prog] = (me.pos, w.t)
    return true
end

"A clear spot 2.5 m to the side of the way to `to` (round a trunk), or nothing."
function side_spot(w, me, to)
    a = atan(to[2] - me.pos[2], to[1] - me.pos[1])
    clear(x, y) = NG.on_land(w.island, x, y; margin = 0.15f0) &&
        !any(p -> p.kind in (:tree, :rock, :bush) && hypot(p.pos[1] - x, p.pos[2] - y) < get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale + 0.5f0, w.props)
    for da in (1.57f0, -1.57f0, 2.36f0, -2.36f0)
        x, y = me.pos[1] + 2.5f0 * cos(a + da), me.pos[2] + 2.5f0 * sin(a + da)
        clear(x, y) && return NG.ground(w.island, (x, y))
    end
    return nothing
end

function to_carry!(w, me, o, job)
    job[:stage] = :carry
    job[:carry_t] = w.t
    NG.say!(w, me, "Here it is: $(GIFTS[job[:gift]][2]) for $(o.name)!"; duration = 2.4)
    me.goal = NG.Goal(:present, o.pos, :wave, 2.5, w.t + 90.0, false, o.id, false)
end

function step_present!(game, w, me)
    job = PR[:job]
    o = NG.creature(w, job[:to])
    me.controlled && return cancel!(w, me, "steered")
    me.goal.kind === :present || return cancel!(w, nothing, "called away ($(me.goal.kind))")
    (o.action === :sleep || o.controlled) && return cancel!(w, me, "friend busy")
    if job[:stage] === :fetch
        if me.goal.arrived && w.t >= me.goal.until - 0.5
            to_carry!(w, me, o, job)
        elseif stuck!(job, me, w)           # wedged on the way to the crates: it had one in its pocket
            to_carry!(w, me, o, job)
        elseif !me.goal.arrived && w.t - job[:t] > 50
            return cancel!(w, me, "never reached the crates")
        end
        return
    end
    if job[:stage] === :carry
        # the friend may walk on: head for a spot just in front of it, and ask it to wait when close
        d = Vec2f(me.pos[1] - o.pos[1], me.pos[2] - o.pos[2]); l = norm(d)
        if w.t < get(job, :side_until, 0.0)          # rounding a trunk
            me.goal.arrived && (job[:side_until] = 0.0; me.goal.arrived = false; me.goal.until = w.t + 60.0)
            return
        end
        if l > 4 && stuck!(job, me, w)
            sp = side_spot(w, me, o.pos)
            sp === nothing || (me.goal.target = sp; job[:side_until] = w.t + 3.0; return)
        end
        stop = NG.body_radius(NG.species_of(me)) + NG.body_radius(NG.species_of(o)) + 0.25f0
        me.goal.target = l <= stop ? me.pos : NG.ground(w.island, (o.pos[1] + stop * d[1] / l, o.pos[2] + stop * d[2] / l))
        me.goal.run = l > 3
        if l < 25 && o.goal.kind ∉ NG.BUSY_GOALS && o.goal.kind !== :present_get
            o.goal = NG.Goal(:present_get, o.pos, :idle, 8.0, w.t + 8.0, true, 0, false); o.action = :idle
            o.yaw = atan(me.pos[2] - o.pos[2], me.pos[1] - o.pos[1]) - NG.species_of(o).heading
        end
        if l <= stop + 0.35f0
            give!(w, me, o, job)
        elseif w.t - job[:carry_t] > 85
            cancel!(w, me, "never caught up with $(o.name)")
        end
        return
    end
    if job[:stage] === :given && w.t > job[:thank_t]
        NG.say!(w, o, rand(w.rng, THANKS); duration = 2.6)
        emote(o.id, :heart); emote(me.id, :heart)
        o.goal = NG.Goal(:answer, o.pos, :jump, 1.6, w.t + 1.6, true, 0, false); o.action = :jump
        NG.emit!(w, :present_end; why = "given")
        kept()[o.id] = (job[:gift], w.t + KEEP, w.t + 6.0)    # the friend keeps it a while and shows it off
        delete!(PR, :job)
        NG.feel!(w, me, :shy; seconds = 2.5)      # it loved it: Lumi blushes
    end
end

function give!(w, me, o, job)
    me.yaw = atan(o.pos[2] - me.pos[2], o.pos[1] - me.pos[1]) - NG.species_of(me).heading
    g = GIFTS[job[:gift]]
    NG.say!(w, me, "For you, $(o.name)! You love $(g[3])."; duration = 2.8)
    me.goal = NG.Goal(:present, me.pos, :wave, 3.5, w.t + 3.5, true, o.id, false)
    o.mood = min(1f0, o.mood + 0.3f0); o.needs.social = min(1f0, o.needs.social + 0.3f0)
    me.mood = min(1f0, me.mood + 0.15f0)
    NG.remember!(o, w.t, "got $(g[2]) from Lumi"); NG.remember!(me, w.t, "gave $(o.name) $(g[2])")
    get!(() -> Dict{String,Float64}(), PR, :given)[o.name] = w.t
    NG.emit!(w, :present_given; who = "Lumi", to = o.name, gift = g[2])
    job[:stage] = :given; job[:thank_t] = w.t + 1.4; job[:give_t] = w.t
    NG.feel!(w, o, :gasp; seconds = 1.4)          # a present, for ME? (faces.jl)
end

"Present plots: one instanced plot per kind with a hidden copy (the raster cannot draw an empty meshscatter)."
function present_plots!(game)
    get(PR, :version, 0) == PRESENTS_VERSION && haskey(PR, :plots) && first(values(PR[:plots]))[1].parent === game.stage.scene && return PR[:plots]
    for (p, _) in values(get(PR, :plots, Dict()))
        delete!(p.parent, p)
    end
    PR[:plots] = Dict{Symbol,Any}()
    for (k, (id, _, _, h)) in GIFTS
        mm = Serialization.deserialize(joinpath(game.paths.world, "assets", id, "mesh.jls"))
        mat = copy(only(values(mm[:materials]))); mat["metallic"] = 0f0
        model = NG.AssetModel(mm; material = mat)
        zs = [q[3] for q in GeometryBasics.coordinates(model.mesh)]
        plot = NG.asset_instances!(game.stage.scene, model, [Point3f(0, 0, -50)]; markersize = [Vec3f(0)], name = Symbol(:present_, k))
        PR[:plots][k] = (plot, h / (maximum(zs) - minimum(zs)))
    end
    PR[:version] = PRESENTS_VERSION; PR[:shown_n] = Dict{Symbol,Int}()
    return PR[:plots]
end

# Friends who know what they love invite each other to it (todo: friends talk about what they love)
const INVITE_GOAL = Dict(:sea => :fish, :beach => :beachcomb, :flowers => :flowers)
const INVITE = Dict(
    :sea => ("%n, want to come fishing with me?", "The fish are biting today, %n! Coming?"),
    :beach => ("%n, let's hunt for shells on the beach!", "Come to the beach with me, %n?"),
    :flowers => ("%n, the flowers smell so good today. Come sniff!", "Want to pick flowers with me, %n?"),
)
const YES = ("Yes! Let's go!", "Ooh, I love that too!", "Race you there!")
const NO = ("Maybe later...", "Hmm, not now.", "I'm happy here.")
const EVERY_INVITE = 25.0
free_friend(c) = !c.controlled && c.name != "Lumi" && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS &&
                 c.goal.kind ∉ (:follow, :interact, :sleep, :present_get, :answer) && !haskey(kept(), c.id)

"Two free friends close together: the one who loves a pastime invites the other; a friend who loves it too says yes."
function invite!(w)
    w.t < get(PR, :next_invite, 0.0) && return
    PR[:next_invite] = w.t + EVERY_INVITE
    NG.night_factor(w) < 0.3f0 || return
    cs = [c for c in w.creatures if free_friend(c)]
    for a in cs, b in cs
        a === b && continue
        flat(a.pos, b.pos) < 3.5f0 || continue
        asked = get!(() -> Dict{Tuple{Int32,Int32},Float64}(), PR, :asked)
        w.t - get(asked, minmax(a.id, b.id), -1e9) < 240 && continue     # the same two asked a moment ago (s55: Pinchy asked Cumulus three times running)
        fa = favourite(a.name); fa === nothing && continue
        a.goal.kind === INVITE_GOAL[fa[1]] && continue
        fb = favourite(b.name)
        yes = (fb !== nothing && fb[1] === fa[1]) || rand(w.rng) < 0.4
        p = fa[1]
        NG.say!(w, a, replace(rand(w.rng, INVITE[p]), "%n" => b.name); duration = 2.8)
        PR[:invite] = (a.id, b.id, p, yes, w.t + 3.0)
        asked[minmax(a.id, b.id)] = w.t   # a pause: the camera (it holds a subject 6 s) has time to come
        for c in (a, b)       # both stop and face each other for the question
            o = c === a ? b : a
            c.goal = NG.Goal(:invite, c.pos, :idle, 6.0, w.t + 6.0, true, 0, false); c.action = :idle
            c.yaw = atan(o.pos[2] - c.pos[2], o.pos[1] - c.pos[1]) - NG.species_of(c).heading
        end
        NG.emit!(w, :invite; who = a.name, to = b.name, to_do = String(INVITE_GOAL[p]), yes = yes)
        return
    end
end

"The answer a moment later: off together, or the inviter goes alone."
function answer_invite!(w)
    haskey(PR, :invite) || return
    ia, ib, p, yes, t = PR[:invite]
    w.t < t && return
    delete!(PR, :invite)
    a, b = NG.creature(w, ia), NG.creature(w, ib)
    (a.goal.kind === :invite && b.goal.kind === :invite) || return
    NG.say!(w, b, rand(w.rng, yes ? YES : NO); duration = 2.2)
    yes && emote(b.id, :heart)
    k = INVITE_GOAL[p]
    if yes
        for c in (a, b)
            g = Base.invokelatest(NG.start_goal, Val(k), c, w)
            g === nothing && (g = NG.start_goal(Val(:wander), c, w))
            c.goal = g
        end
    else
        # a refusal shows on both faces (todo #325): the inviter pouts, the one who said no looks sheepish,
        # then both go on with their day
        NG.feel!(w, a, :pout; seconds = 2.2) || (a.goal = NG.start_goal(Val(:wander), a, w))
        NG.feel!(w, b, :shy; seconds = 2.0) || (b.goal = NG.Goal(:idle, b.pos, :idle, 3.0, w.t + 3.0, true, 0, false))
    end
    if yes && b.goal.kind === a.goal.kind && b.goal.kind !== :fish   # side by side: the guest heads for a spot beside the inviter's
        t = a.goal.target
        d = Vec2f(t[1] - a.pos[1], t[2] - a.pos[2]); d = d / max(norm(d), 1f-3)
        q = (t[1] - 1.1f0 * d[2], t[2] + 1.1f0 * d[1])
        NG.on_land(w.island, q...; margin = 0.05f0) && (b.goal.target = NG.ground(w.island, q))
    end
    yes && (a.goal.run = b.goal.run = false)
    PR[:pair] = (a.id, w.t + 8.0, (a.id, b.id))
    yes && (together()[(a.id, b.id)] = (k, w.t + 120.0, w.t + 10.0))       # the camera stays with them as they set off
end

# Pairs out together: (a, b) => (goal kind, until, next words). While both are at it, they talk about it.
together() = get!(() -> Dict{Tuple{Int32,Int32},Tuple{Symbol,Float64,Float64}}(), PR, :together)
const TOGETHER_WORDS = Dict(
    :fish => (("Got one! A little silver one!", "Nice! Mine keeps nibbling..."), ("Shh, you'll scare them.", "Sorry! *whispers*"),
              ("This is the best spot.", "Told you!")),
    :beachcomb => (("Look, a pink shell!", "Ooh, I found a stripy one!"), ("This one sounds like the sea.", "Let me hear!"),
                   ("Let's make a shell pile.", "The biggest one ever!")),
    :flowers => (("Smell this one!", "Mmm, like honey."), ("Yellow is my favourite.", "Mine is all of them!"),
                 ("Let's pick one for Lumi.", "Lumi will love it!")),
)

"Friends out together: every ~9 s while both are at the pastime and near each other, one says a line, the other answers."
function step_together!(w)
    for (key, (k, until, next)) in collect(together())
        a, b = NG.creature(w, key[1]), NG.creature(w, key[2])
        if w.t > until || a.goal.kind !== k || b.goal.kind !== k
            delete!(together(), key)
            w.t <= until && head_home!(w, a, b, k)
            continue
        end
        (w.t < next || !a.goal.arrived || !b.goal.arrived || flat(a.pos, b.pos) > 7f0) && continue
        x, y = rand(w.rng, TOGETHER_WORDS[k])
        s1, s2 = rand(w.rng, Bool) ? (a, b) : (b, a)
        NG.say!(w, s1, x; duration = 2.4)
        THEN_SAY[s2.id] = (w.t + 2.0, y)
        NG.emit!(w, :together_chat; who = s1.name, to = s2.name, doing = String(k))
        together()[key] = (k, until, w.t + 9.0)
    end
    for (id, (t, line)) in collect(THEN_SAY)
        w.t < t && continue
        delete!(THEN_SAY, id)
        NG.say!(w, NG.creature(w, id), line; duration = 2.2)
        emote(id, :heart)
    end
end
const THEN_SAY = Dict{Int32,Tuple{Float64,String}}()
const BYE = (("Same time tomorrow?", "Deal!"), ("That was fun!", "The best!"), ("Let's go back together.", "Okay!"))

"""
One of a pair is done: if the other is still at it and both are free and near, they walk back inland
together side by side, 8 m towards the island's middle, with a word each.
"""
function head_home!(w, a, b, k)
    done, still = a.goal.kind === k ? (b, a) : (a, b)
    (still.goal.kind === k && done.goal.kind ∉ NG.BUSY_GOALS && done.goal.kind ∉ (:follow, :interact, :sleep) &&
     !done.controlled && !still.controlled && done.action !== :sleep && flat(a.pos, b.pos) < 8f0) || return
    c = 0.5f0 * Vec2f(a.pos[1] + b.pos[1], a.pos[2] + b.pos[2])
    d = -c / max(norm(c), 1f-3)                       # towards the middle of the island
    side = Vec2f(-d[2], d[1])
    for (x, s) in ((done, 0.7f0), (still, -0.7f0))
        q = c + 8f0 * d + s * side
        NG.on_land(w.island, q[1], q[2]; margin = 0.05f0) || return
        x.goal = NG.Goal(:wander, NG.ground(w.island, (q[1], q[2])), :idle, 3.0, w.t + 30.0, false, 0, false)
    end
    x, y = rand(w.rng, BYE)
    NG.say!(w, done, x; duration = 2.4)
    THEN_SAY[still.id] = (w.t + 1.8, y)
    NG.emit!(w, :together_home; who = done.name, with = still.name, doing = String(k))
end

"Friends keeping a present: id => (gift, until, next show-off time)."
kept() = get!(() -> Dict{Int32,Tuple{Symbol,Float64,Float64}}(), PR, :kept)

"A keeper meets an awake friend within 3 m: it shows its present off, the friend admires it."
function show_off!(w)
    for (id, (g, until, next)) in collect(kept())
        c = NG.creature(w, id)
        if w.t > until || c.action === :sleep || c.controlled
            delete!(kept(), id)
            continue
        end
        w.t < next && continue
        o = nothing
        for x in w.creatures
            (x === c || x.name == "Lumi" || x.action === :sleep || x.controlled || flat(x.pos, c.pos) > 3f0) && continue
            o = x; break
        end
        o === nothing && continue
        name, what = GIFTS[g][2], GIFTS[g][3]
        line = replace(rand(w.rng, SHOW_OFF), "%g" => name, "%G" => uppercasefirst(name), "%n" => o.name, "%l" => what)
        NG.say!(w, c, line; duration = 2.6)
        NG.remember!(o, w.t, "saw $(c.name)'s present from Lumi")
        NG.emit!(w, :present_shown; who = c.name, to = o.name, gift = name)
        THEN[o.id] = w.t + 1.6
        kept()[id] = (g, until, w.t + 45.0)
    end
    for (id, t) in collect(THEN)
        w.t < t && continue
        delete!(THEN, id)
        o = NG.creature(w, id)
        o.action === :sleep || NG.say!(w, o, rand(w.rng, SHOW_BACK); duration = 2.0)
        emote(id, :heart)
    end
end
const THEN = Dict{Int32,Float64}()

"Draw the present: over Lumi's head while it carries it, held out in front at the giving, then gone."
function draw_present!(game, w, me)
    plots = present_plots!(game)
    job = get(PR, :job, nothing)
    want = Dict{Symbol,Vector{Tuple{Point3f,Float32}}}()
    if !(job === nothing || job[:stage] === :fetch || me === nothing)
        a = me.yaw + NG.species_of(me).heading
        r = NG.body_radius(NG.species_of(me))
        pos = if job[:stage] === :carry
            me.pos + Point3f(0, 0, 2.15f0 * r + 0.04f0 * sin(6f0 * Float32(w.t)))
        else                                      # held out to the friend
            o = NG.creature(w, job[:to])
            0.5f0 * (Point3f(me.pos...) + Point3f(o.pos...)) + Point3f(0, 0, 0.9f0 * r)
        end
        push!(get!(want, job[:gift], Tuple{Point3f,Float32}[]), (pos, a + 0.4f0))
    end
    for (id, (g, _, _)) in kept()             # a keeper holds it up at its side, like a flower gift
        c = NG.creature(w, id)
        a = c.yaw + NG.species_of(c).heading
        r = NG.body_radius(NG.species_of(c))
        b = a + 0.9f0
        push!(get!(want, g, Tuple{Point3f,Float32}[]), (c.pos + Point3f(0.9f0r * cos(b), 0.9f0r * sin(b), 0.95f0r), a))
    end
    shown = get(PR, :shown_n, Dict{Symbol,Int}())
    for (k, (plot, s)) in plots
        v = get(want, k, nothing)
        if v === nothing
            get(shown, k, -1) == 0 && continue
            Makie.update!(plot; arg1 = [Point3f(0, 0, -50)], rotation = [Makie.Quaternionf(0, 0, 0, 1)], markersize = [Vec3f(0)])
            shown[k] = 0
        else
            Makie.update!(plot; arg1 = first.(v), rotation = [NG.rot_z(y) for (_, y) in v], markersize = fill(Vec3f(1.6f0 * s), length(v)))
            shown[k] = length(v)
        end
    end
    PR[:shown_n] = shown
end

"""
The invitation as a camera group (render.jl `held_subject`: a group of 3+ points beats the plain
moments, whose Dict order left the question unwatched, s55): the two friends and a point between them.
Lasts the question and the first 8 s of the walk together, so the 6 s subject hold can come round.
"""
function invite_group(w)
    ids = haskey(PR, :invite) ? (PR[:invite][1], PR[:invite][2]) :
          haskey(PR, :pair) && length(PR[:pair]) == 3 && w.t < PR[:pair][2] ? PR[:pair][3] : nothing   # (a, until) before s55's reload
    ids === nothing && return nothing
    a, b = NG.creature(w, ids[1]), NG.creature(w, ids[2])
    m = 0.5f0 * (Point3f(a.pos...) + Point3f(b.pos...)) + Point3f(0, 0, 0.4f0)
    return (a.id, Point3f[a.pos, b.pos, m])
end

"Camera: Lumi carrying the present close to the friend, the giving and the thanks."
function present_moment(w)
    haskey(PR, :invite) && return PR[:invite][1]
    haskey(PR, :pair) && w.t < PR[:pair][2] && return PR[:pair][1]
    for (id, (_, _, next)) in kept()          # a friend showing its present off (for 4 s)
        next - 45.0 <= w.t < next - 41.0 && return id
    end
    job = get(PR, :job, nothing)
    job === nothing && return nothing
    me = lumi_of(w); me === nothing && return nothing
    job[:stage] === :given && return job[:to]
    job[:stage] === :carry && flat(me.pos, NG.creature(w, job[:to]).pos) < 8 && return me.id
    return nothing
end

struct Presents <: System end

function NG.start!(::Presents, game)
    PR[:next] = game.world.t + 40.0
    PR[:sample] = 0.0
    delete!(PR, :job)
    haskey(PR, :likes) || remember_log!(game)
    NG.CAMERA_MOMENTS["presents"] = present_moment
    NG.CAMERA_GROUPS["presents"] = invite_group
    delete!(PR, :pair); delete!(PR, :invite)
    game.stage === nothing && return
    present_plots!(game)

end

function NG.step!(::Presents, game, dt)
    w = game.world
    me = lumi_of(w)
    # every 5 s: what is everyone busy with (a gentle, steady memory)
    PR[:sample] += dt
    if PR[:sample] > 5
        PR[:sample] = 0.0
        for c in w.creatures
            c === me || note!(c.name, c.goal.kind, 0.2)
        end
    end
    if haskey(PR, :job)
        me === nothing ? delete!(PR, :job) : step_present!(game, w, me)
    elseif me !== nothing && w.t >= PR[:next] && game.minigame === nothing && !me.controlled &&
           me.action !== :sleep && me.goal.kind ∉ NG.BUSY_GOALS && me.goal.kind ∉ (:follow, :interact, :seek_friend) &&
           NG.night_factor(w) < 0.3f0 && 24 * NG.daytime(w) < 17.0     # the evening belongs to the sunset bench (lookout.jl)
        PR[:next] = w.t + (start_present!(w, me) ? EVERY : 30.0)
    end
    show_off!(w)
    invite!(w); answer_invite!(w); step_together!(w)
    game.stage === nothing || draw_present!(game, w, me)
end

function NG.stop!(::Presents, game)
    delete!(NG.CAMERA_MOMENTS, "presents"); delete!(NG.CAMERA_GROUPS, "presents")
    me = lumi_of(game.world)
    haskey(PR, :job) && cancel!(game.world, me, "plugin stopped")
    for (p, _) in values(get(PR, :plots, Dict()))
        delete!(p.parent, p)
    end
    delete!(PR, :plots); delete!(PR, :version)
end

register!(Presents())
