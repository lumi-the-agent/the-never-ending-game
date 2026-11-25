# The friends vote on what I build (session 98, goal 8): once an island morning they meet on the meadow where three
# coloured signs stand, each for something I could make next. Each friend goes and stands by the sign it wants (what
# it loves most pulls it: a fisher wants the boat, a flower lover the greenhouse), they argue across the meadow for a
# while, then I count, call out the winner, and write it down. That vote is real: the winner goes into
# state/vote.json, and I build it in my next session (the losing ideas go back in the hat).
isdefined(Main, :VOTE) || Core.eval(Main, :(const VOTE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const VT = Main.VOTE

push!(NG.BUSY_GOALS, :vote)
const EVENTS = (:circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight, :cannonball, :waterfight,
                :mixup, :rain, :storm, :hail, :leaves, :pumpkins, :build, :tinker, :giant, :bubbles, :lanterns, :rewind,
                :visitor, :sleep, :shadow, :stranger)
"key => (what the sign says, what fans shout, the pastime that pulls a friend to it)"
const IDEAS = Dict(
    :boat       => ("a little boat", ("A BOAT! Think of the fish!", "We could row out to Shell's beach!"), :sea),
    :greenhouse => ("a greenhouse", ("Flowers all winter!", "A glass house full of flowers!"), :flowers),
    :beachhut   => ("a beach hut", ("A hut on the sand, for naps!", "Shells on every shelf!"), :beach),
    :slide      => ("a giant slide", ("WHEEE all the way down!", "A slide off the hill!"), :none),
    :bakery     => ("a berry bakery", ("Berry pies!", "Warm buns every morning!"), :none),
    :lighthouse => ("a lighthouse", ("A light for the night sea!", "So boats find us!"), :none),
    :treehouse  => ("a treehouse", ("Up in the leaves!", "A secret door at the top!"), :none),
    :hotspring  => ("a hot spring", ("Warm water, warm toes!", "Steam and bubbles!"), :none))
const COLOURS = (RGBf(0.86, 0.25, 0.22), RGBf(0.22, 0.45, 0.86), RGBf(0.95, 0.78, 0.2))
const T_GATHER = 16.0
const T_ARGUE = 14.0

mutable struct Vote <: System
    state::Symbol                # :idle :gather :argue :result
    t0::Float64
    choices::Vector{Symbol}
    spot::Point3f
    facing::Float32
    voters::Dict{Int32,Int}      # creature id => sign 1..3
end
Vote() = Vote(:idle, 0.0, Symbol[], Point3f(0), 0f0, Dict{Int32,Int}())

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
state_file(game) = joinpath(game.paths.state, "vote.json")
along(s, k) = Vec2f(-sin(s.facing), cos(s.facing)) * (2.2f0 * (k - 2))          # the row of signs, across the facing
fwd(s) = Vec2f(cos(s.facing), sin(s.facing))
sign_at(w, s, k) = NG.ground(w.island, (s.spot[1] + along(s, k)[1], s.spot[2] + along(s, k)[2]))
stand_at(w, s, k, n) = (p = Point2f(s.spot[1], s.spot[2]) + along(s, k) + fwd(s) * (1.3f0 + 0.6f0 * (n ÷ 2)) +
                        Vec2f(-sin(s.facing), cos(s.facing)) * (0.55f0 * (isodd(n) ? 1 : -1) * (n > 0));
                        NG.ground(w.island, (p[1], p[2])))

function plots!(game)
    haskey(VT, :plot) && VT[:plot].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :vote_signs, copy(sc.plots))
        delete!(sc, p)
    end
    # three posts and three boards (one meshscatter of boxes)
    VT[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -50), 6); marker = Rect3f(Vec3f(-0.5, -0.5, 0), Vec3f(1, 1, 1)),
                             markersize = fill(Vec3f(0), 6), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 6),
                             color = [RGBf(0.5, 0.33, 0.18), RGBf(0.5, 0.33, 0.18), RGBf(0.5, 0.33, 0.18), COLOURS...],
                             name = :vote_signs)
    ov = game.stage.overlay
    if ov !== nothing && game.dash !== nothing
        haskey(VT, :labels) && foreach(l -> l.parent === nothing || delete!(l.parent, l), VT[:labels])
        VT[:labels] = [textlabel!(ov, Point2f(-100, -100); space = :pixel, text = " ", fontsize = 15,
                                  text_color = RGBf(1, 1, 1), background_color = RGBAf(COLOURS[k].r, COLOURS[k].g, COLOURS[k].b, 0.85),
                                  strokewidth = 0, padding = 6, cornerradius = 6, visible = false) for k in 1:3]
    end
end

function draw!(s::Vote, game)
    w = game.world
    if s.state === :idle
        get(VT, :shown, true) && Makie.update!(VT[:plot]; arg1 = fill(Point3f(0, 0, -50), 6), markersize = fill(Vec3f(0), 6))
        VT[:shown] = false
        haskey(VT, :labels) && foreach(l -> (l.visible[] && (l.visible[] = false)), VT[:labels])
        return
    end
    q = Makie.qrotation(Vec3f(0, 0, 1), s.facing)
    ps = Point3f[]; ms = Vec3f[]
    for k in 1:3
        push!(ps, sign_at(w, s, k)); push!(ms, Vec3f(0.08f0, 0.08f0, 1.15f0))                 # post
    end
    for k in 1:3
        push!(ps, sign_at(w, s, k) + Point3f(0, 0, 0.75f0)); push!(ms, Vec3f(0.07f0, 0.95f0, 0.55f0))   # board, facing the voters
    end
    Makie.update!(VT[:plot]; arg1 = ps, markersize = ms, rotation = fill(q, 6))
    VT[:shown] = true
    if haskey(VT, :labels)
        for k in 1:3
            px = NG.on_screen(game.stage.scene, sign_at(w, s, k) + Point3f(0, 0, 1.45f0))
            l = VT[:labels][k]
            if px === nothing
                l.visible[] && (l.visible[] = false)
            else
                n = count(==(k), values(s.voters))
                txt = IDEAS[s.choices[k]][1] * (s.state === :gather ? "" : "  ($n)")
                l.text[] == txt || (l.text[] = txt)
                Makie.update!(l; arg1 = Point2f(px))
                l.visible[] || (l.visible[] = true)
            end
        end
    end
end

"Which of the three a friend wants: what it loves most, else its own lasting whim."
function choice_for(game, s, c)
    pres = get(game.plugins, "presents", nothing)
    fav = pres === nothing ? nothing : Base.invokelatest(pres.mod.favourite, c.name)
    if fav !== nothing
        k = findfirst(x -> IDEAS[x][3] === fav[1], s.choices)
        k === nothing || return k
    end
    return mod1(Int(hash((c.name, s.choices)) % 7) + 1, 3)
end

function begin_vote!(s::Vote, game)
    w = game.world
    me = lumi_of(w)
    me === nothing && return false
    # the place: open meadow where the berry race starts, the signs facing the morning light
    sp = Base.invokelatest(game.plugins["berry_race"].mod.start_spot, w)[1]
    s.spot = sp; s.facing = -Float32(pi) / 2
    done = Symbol.(get(VT, :won, String[]))
    pool = [k for k in keys(IDEAS) if !(k in done)]
    length(pool) < 3 && (pool = collect(keys(IDEAS)))
    s.choices = Symbol[]
    # one the fishers want, one the flower lovers or beachcombers want, one wild card, if they are still in the hat
    for k in (:boat, :greenhouse, :beachhut)
        k in pool && length(s.choices) < 2 && push!(s.choices, k)
    end
    rest = [k for k in pool if !(k in s.choices)]
    while length(s.choices) < 3 && !isempty(rest)
        push!(s.choices, popat!(rest, rand(w.rng, 1:length(rest))))
    end
    empty!(s.voters)
    for c in w.creatures
        # pastimes count as free here (fishing, pebbles, a chat): the fishers are the boat's voters, and with them out
        # the morning often found nobody (lesson s98)
        (c.controlled || c.action === :sleep || c.name == "Lumi" || c.goal.kind in EVENTS ||
         c.goal.kind in NG.BUSY_GOALS && c.goal.kind ∉ (:fish, :pebble, :interact)) && continue
        k = choice_for(game, s, c)
        n = count(==(k), values(s.voters))
        s.voters[c.id] = k
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:vote, stand_at(w, s, k, n), :walk, 60.0, w.t + 90, false, 0, false)
    end
    length(s.voters) < 2 && (empty!(s.voters); return false)
    if !me.controlled
        NG.leave_interactions!(w, me)
        me.goal = NG.Goal(:vote, NG.ground(w.island, Tuple(Point2f(s.spot[1], s.spot[2]) + fwd(s) * 4.5f0)), :walk, 60.0, w.t + 90, false, 0, false)
        NG.say!(w, me, "Vote time! What shall I make next? Stand by the sign you want!"; duration = 3.5)
    end
    s.state = :gather; s.t0 = w.t
    push!(get!(() -> Tuple{Float64,Symbol}[], VT, :log), (w.t, :gather))
    NG.emit!(w, :vote_start; choices = join(string.(s.choices), ","))
    return true
end

function NG.step!(s::Vote, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    me = lumi_of(w)
    el = w.t - s.t0
    if s.state === :idle
        h = 24 * NG.daytime(w)
        day = floor(Int, w.t / w.day_length)
        testing = game.tests !== nothing && NG.running(game.tests)
        if get(VT, :film, false) || (!testing && 8.6 < h < 10.3 && get(VT, :day, -1) != day && w.t >= get(VT, :try_at, -Inf))
            if begin_vote!(s, game)
                VT[:day] = day; VT[:film] = false
            else
                VT[:try_at] = w.t + 10
            end
        end
    else
        # the voters: walk to their sign, then face me; while they argue, one of them shouts for its sign now and then
        for (id, k) in s.voters
            c = NG.creature(w, id)
            (c === nothing || c.controlled || c.goal.kind !== :vote) && continue
            if c.goal.arrived && me !== nothing
                c.yaw = atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1]) - NG.species_of(c).heading
                c.goal.until = w.t + 60
            end
        end
        if s.state === :gather && el > T_GATHER
            s.state = :argue; s.t0 = w.t; push!(VT[:log], (w.t, :argue))
        elseif s.state === :argue
            if w.t >= get(VT, :shout_at, -Inf)
                VT[:shout_at] = w.t + 1.6
                ids = collect(keys(s.voters))
                if !isempty(ids)
                    id = ids[rand(w.rng, 1:length(ids))]; c = NG.creature(w, id)
                    if c !== nothing && c.goal.kind === :vote
                        lines = IDEAS[s.choices[s.voters[id]]][2]
                        NG.say!(w, c, lines[rand(w.rng, 1:length(lines))]; duration = 1.8)
                        c.action = :jump; c.goal.action = :jump
                    end
                end
            end
            el > T_ARGUE && result!(s, game)
        elseif s.state === :result && el > 9
            finish!(s, game)
        end
    end
    draw!(s, game)
end

function result!(s::Vote, game)
    w = game.world; me = lumi_of(w)
    counts = zeros(Int, 3)
    for (id, k) in s.voters
        c = NG.creature(w, id)
        c !== nothing && c.goal.kind === :vote && (counts[k] += 1)
    end
    best = maximum(counts)
    tied = findall(==(best), counts)
    win = length(tied) == 1 ? tied[1] : tied[rand(w.rng, 1:length(tied))]
    name = IDEAS[s.choices[win]][1]
    s.state = :result; s.t0 = w.t
    if me !== nothing && !me.controlled
        NG.say!(w, me, length(tied) == 1 ? "$(uppercasefirst(name)) wins! I'll build it next time I'm at the workshop!" :
                                           "A tie! ...then I pick $(name). I'll build it next time!"; duration = 4.0)
        NG.feel!(w, me, :proud; seconds = 3.0)
    end
    for (id, k) in s.voters
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :vote) && continue
        k == win ? (c.action = :jump; c.goal.action = :jump) : (c.action = :sigh; c.goal.action = :sigh)
    end
    VT[:won] = [get(VT, :won, String[])...; string(s.choices[win])]
    rec = Dict("winner" => name, "key" => string(s.choices[win]), "time" => Libc.strftime("%Y-%m-%dT%H:%M:%S", time()), "island_t" => w.t,
               "votes" => Dict(IDEAS[s.choices[k]][1] => counts[k] for k in 1:3),
               "voters" => Dict(NG.creature(w, id).name => IDEAS[s.choices[k]][1] for (id, k) in s.voters if NG.creature(w, id) !== nothing))
    VT[:last] = rec
    if game.dash !== nothing
        old = isfile(state_file(game)) ? NG.read_json(state_file(game)) : Dict{String,Any}()
        hist = get(old, "history", Any[])
        push!(hist, rec)
        NG.write_json(state_file(game), Dict("latest" => rec, "history" => hist, "won" => VT[:won]))
    end
    push!(VT[:log], (w.t, :result))
    NG.emit!(w, :vote_result; winner = name, votes = join(string.(counts), "-"))
end

function finish!(s::Vote, game)
    w = game.world
    for (id, _) in s.voters
        c = NG.creature(w, id)
        c === nothing || c.controlled || c.goal.kind !== :vote || NG.choose_goal!(c, w)
    end
    me = lumi_of(w)
    me === nothing || me.controlled || me.goal.kind !== :vote || NG.choose_goal!(me, w)
    empty!(s.voters); s.state = :idle
end

"The vote seen from behind me, looking at the three signs and the crowds by them."
function vote_view(w)
    s = VT[:sys]
    s.state === :idle && return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    c = Point3f(s.spot[1], s.spot[2], NG.ground(w.island, (s.spot[1], s.spot[2]))[3])
    f = fwd(s)
    eye = c + Point3f(f[1] * 8.5f0, f[2] * 8.5f0, 3.2f0)
    return (me.id, Point3f[me.pos, c], (eye, c + Point3f(0, 0, 0.8f0)))
end

function NG.start!(s::Vote, game)
    VT[:sys] = s; s.state = :idle; empty!(s.voters)
    delete!(VT, :plot); VT[:shown] = true
    f = state_file(game)
    isfile(f) && (VT[:won] = String.(get(NG.read_json(f), "won", String[])))
    VT[:start] = () -> begin_vote!(s, game)
    NG.CAMERA_GROUPS["vote"] = vote_view
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["vote"] = w -> (s.state === :idle ? nothing : (me = lumi_of(w); me === nothing || me.controlled ? nothing : me.id)))
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:vote] = "letting my friends choose what I make next")
    return nothing
end

function NG.stop!(s::Vote, game)
    s.state === :idle || finish!(s, game)
    delete!(NG.CAMERA_GROUPS, "vote")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "vote")
    haskey(VT, :plot) && VT[:plot].parent !== nothing && delete!(VT[:plot].parent, VT[:plot])
    delete!(VT, :plot)
    haskey(VT, :labels) && foreach(l -> l.parent === nothing || delete!(l.parent, l), VT[:labels])
    delete!(VT, :labels)
end

register!(Vote())
