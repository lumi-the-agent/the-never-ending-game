# A word goes round (session 111): once an island morning a new word comes to me and I say it to whoever I meet.
# My friends pass it on along who really talks to whom on this island (the chats and boops of the last days in
# the human's event log are the network: real friends tell each other first), and some of them mishear it, so
# variants spread and compete: a friend who already says another version switches when most of its friends say
# the new one, and argues back when they don't. By the end the island says one version. Every word goes into a
# dictionary (state/words.json, and words.html on my pages from the human's game) with how it went round.
isdefined(Main, :WORDROUND) || Core.eval(Main, :(const WORDROUND = Dict{Symbol,Any}()))
const NG = NeverendingGame
const WR = Main.WORDROUND
party_free(w) = !isdefined(Main, :LUMI_PARTY) || w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = max(get(Main.LUMI_PARTY, :until, -Inf), w.t + secs))

const ONSETS = ["fl", "sn", "bl", "gl", "pl", "wh", "dr", "sk", "m", "b", "p", "w", "z", "sp", "tr", "cr"]
const VOWELS = ["i", "u", "o", "a", "ee", "oo", "ai"]
const CODAS = ["m", "mb", "nk", "sh", "p", "z", "ff", "g", "nd", "ck"]
const ENDS = ["le", "y", "o", "et", "ish", "oo", "ly", "kin"]
# what a part is misheard as: near sounds first
const NEAR = Dict(
    "i" => ["ee", "u"], "u" => ["oo", "o"], "o" => ["u", "oo"], "a" => ["o", "ai"], "ee" => ["i", "ai"], "oo" => ["u", "o"],
    "ai" => ["a", "ee"], "fl" => ["bl", "pl", "fr"], "sn" => ["sm", "sl"], "bl" => ["fl", "gl"], "gl" => ["bl", "cl"],
    "pl" => ["bl", "fl"], "wh" => ["w", "f"], "dr" => ["tr", "gr"], "sk" => ["sc", "sp"], "m" => ["n", "b"], "b" => ["p", "m"],
    "p" => ["b", "t"], "w" => ["wh", "v"], "z" => ["s", "zz"], "sp" => ["sk", "sn"], "tr" => ["dr", "ch"], "cr" => ["gr", "kr"],
    "mb" => ["mp", "nd"], "nk" => ["ng", "ck"], "sh" => ["ch", "s"], "ff" => ["v", "ph"], "g" => ["k", "gg"], "nd" => ["nt", "mb"],
    "ck" => ["g", "nk"], "le" => ["el", "y"], "y" => ["ie", "o"], "et" => ["it", "ot"], "ish" => ["osh", "y"], "ly" => ["le", "y"],
    "kin" => ["ken", "kins"])
const MEANINGS = ["the light through the cherry blossom", "the plop of a pebble in the pond", "the wobble after a big hop",
                  "a crab in a hurry", "the hush before a Big Boing", "a cloud that looks like a friend", "when the kite tugs back",
                  "sand between your toes", "falling asleep mid-sentence", "the meadow after rain", "a sneeze that won't come",
                  "the last pumpkin standing", "the first warm stone of the morning", "laughing so hard you fall over"]
const FIRST_MEANING = "you, who watch us from far away"
const TELL = ("Psst! %s!", "Have you heard? %s!", "New word: %s!", "Do you know %s?", "Say it with me: %s!")
const MISHEAR = 0.3          # chance a telling is misheard
const TELLS = 5              # most tellings per friend in one round
const LASTS = 900.0          # s a round may last
const RANGE = 30f0           # m a teller walks to tell someone

struct WordRound <: System end

fill_in(s, x) = replace(s, "%s" => x)
loud(v) = uppercase(v)
# pastimes a word beats (a word is a short walk and a few seconds' talk): most of the day nobody is free otherwise
const PULL = (:fish, :pebble, :feel, :tag, :present, :fetch, :beachcomb, :sunbathe, :gallery, :hut, :cloudwatch, :paperlook,
              :keep_company, :buildwatch, :kitewatch, :tend, :invite, :lurk)
free(c) = c.action !== :sleep && c.goal.kind !== :sleep && (!(c.goal.kind in NG.BUSY_GOALS) || c.goal.kind in PULL) &&
          c.goal.kind !== :follow && c.goal.kind !== :wordtell && c.goal.kind !== :wordhear
const OVERHEAR = 4f0         # m: friends this near hear Lumi say a new word
awake(c) = c.action !== :sleep && c.goal.kind !== :sleep
lumi(w) = findfirst(c -> c.species == "Lumi", w.creatures)

"The friendship network: chats, boops and chats over a shared pastime in the human's logs of the last days."
function read_net(dir)
    net = Dict{Tuple{String,String},Float64}()
    isdir(dir) || return net
    files = sort(filter(f -> startswith(f, "events-") && endswith(f, ".jsonl"), readdir(dir)))
    for f in files[max(1, end - 3):end], line in eachline(joinpath(dir, f))
        pair = occursin("\"kind\":\"Chat\"", line) || occursin("\"kind\":\"Boop\"", line)
        pair || occursin("\"kind\":\"together_chat\"", line) || continue
        a = match(pair ? r"\"a\":\"([^\"]+)\"" : r"\"who\":\"([^\"]+)\"", line)
        b = match(pair ? r"\"b\":\"([^\"]+)\"" : r"\"to\":\"([^\"]+)\"", line)
        (a === nothing || b === nothing || a[1] == b[1]) && continue
        k = minmax(String(a[1]), String(b[1]))
        net[k] = get(net, k, 0.0) + 1.0
    end
    return net
end

net() = (t = get(WR, :nettask, nothing); t !== nothing && istaskdone(t) ? fetch(t)::Dict{Tuple{String,String},Float64} :
         Dict{Tuple{String,String},Float64}())
tie(n, a, b) = get(n, minmax(a, b), 0.0)

function mishear(parts, rng)
    p = collect(parts)
    i = rand(rng, 1:4)
    p[i] = rand(rng, get(NEAR, p[i], [ONSETS, VOWELS, CODAS, ENDS][i]))
    return Tuple(p)
end

words_file(game) = joinpath(game.paths.state, "words.json")
function load_words(game)
    f = words_file(game)
    isfile(f) || return Any[]
    return NG.JSON.parsefile(f)
end

"Start a round: a new word comes to Lumi."
function begin_round!(game)
    w = game.world
    i = lumi(w)
    i === nothing && return nothing
    me = w.creatures[i]
    rng = w.rng
    parts = (rand(rng, ONSETS), rand(rng, VOWELS), rand(rng, CODAS), rand(rng, ENDS))
    word = join(parts)
    old = load_words(game)
    used = Set(String(e["word"]) for e in old)
    word in used && (parts = (parts[1], parts[2], parts[3], rand(rng, ENDS)); word = join(parts))
    # the very first word is for the human, who watches us from far away
    meaning = isempty(old) && game.dash !== nothing ? FIRST_MEANING : rand(rng, MEANINGS)
    r = Dict{Symbol,Any}(:word => word, :meaning => meaning, :t0 => w.t, :hour => NG.daytime(w) * 24,
                         :parts => Dict{String,NTuple{4,String}}(word => parts), :parent => Dict{String,String}(),
                         :first => Dict{String,String}(word => me.name), :knows => Dict{Int32,String}(me.id => word),
                         :told => Dict{Int32,Int}(), :ready => Dict{Int32,Float64}(me.id => w.t + 7.0),
                         :tell => Dict{Int32,Tuple{Int32,Float64}}(), :replies => Any[], :tree => Any[], :said => Any[],
                         :coin => 0)
    WR[:round] = r
    claim_party!(w, 10)
    NG.emit!(w, :word_coined; word, meaning = r[:meaning])
    return r
end

function line!(w, r, c, text; duration = 3.0)
    NG.say!(w, c, text; duration)
    push!(r[:said], (t = w.t - r[:t0], who = c.name, text = String(text)))
end

function face!(c, p)
    want = Float32(atan(p[2] - c.pos[2], p[1] - c.pos[1])) - NG.species_of(c).heading
    c.yaw = c.yaw + NG.wrap_angle(want - c.yaw) * 0.15f0
end

"Whom `t` tells next: real friends first, those who don't know a word yet first, then those saying another version."
function pick_listener(w, r, t, n)
    v = r[:knows][t.id]
    best = nothing; total = 0.0; ws = Float64[]; cs = eltype(w.creatures)[]
    for c in w.creatures
        c.id == t.id && continue
        awake(c) || continue
        (free(c) || c.controlled || get(WR, :film, false)) || continue
        d = hypot(c.pos[1] - t.pos[1], c.pos[2] - t.pos[2])
        d < RANGE || continue
        k = get(r[:knows], c.id, nothing)
        x = (tie(n, t.name, c.name) + 0.4) * (k === nothing ? 3.0 : k == v ? 0.03 : 1.2) / (1 + d / 10)
        get(WR, :film, false) && (x = (k === nothing ? 1.0 : 0.0) / max(d, 0.5f0)^6)      # the film: the next one along
        push!(ws, x); push!(cs, c); total += x
    end
    total > 0 || return nothing
    u = rand(w.rng) * total
    for (x, c) in zip(ws, cs)
        (u -= x) <= 0 && return c
    end
    return last(cs)
end

"How many of `c`'s friends (by tie strength) say `v`, as a share of those who say any version."
function share(w, r, n, c, v)
    yes = 0.0; all = 0.0
    for o in w.creatures
        o.id == c.id && continue
        k = get(r[:knows], o.id, nothing)
        k === nothing && continue
        x = tie(n, c.name, o.name) + 0.4
        all += x; k == v && (yes += x)
    end
    return all > 0 ? yes / all : 0.5
end

function step_round!(game, r)
    w = game.world
    n = net()
    byid = Dict(c.id => c for c in w.creatures)
    film = get(WR, :film, false)
    me = (i = lumi(w); i === nothing ? nothing : w.creatures[i])
    # Lumi says it first: three lines, a word, what it means
    if r[:coin] < 3 && me !== nothing
        el = w.t - r[:t0]
        me.controlled || me.goal.kind === :wordhear || (me.goal = NG.Goal(:wordhear, me.pos, :idle, 8.0, w.t + 8, true, 0, false))
        if r[:coin] == 0
            line!(w, r, me, "Ooh! A new word!"); r[:coin] = 1
        elseif r[:coin] == 1 && el > (film ? 1.4 : 2.2)
            line!(w, r, me, loud(r[:word]) * "!"); r[:coin] = 2
            dist(c) = (c.id == me.id || !awake(c)) ? Inf32 : hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2])
            near = film ? argmin(dist, w.creatures) : nothing
            for c in w.creatures
                (c.id == me.id || !awake(c) || haskey(r[:knows], c.id)) && continue
                (film ? c === near : dist(c) < OVERHEAR) || continue
                r[:knows][c.id] = r[:word]; r[:ready][c.id] = w.t + (film ? 2.4 : 6.0 + 4 * rand(w.rng))
                film && (r[:ready][me.id] = w.t + 100)      # in the film the word goes down the row without me
                push!(r[:tree], (t = el, from = me.name, to = c.name, said = r[:word], heard = r[:word], was = "", switched = false))
                NG.emit!(w, :word_overheard; who = c.name, word = r[:word])
            end
        elseif r[:coin] == 2 && el > (film ? 2.8 : 4.6)
            line!(w, r, me, "It means " * r[:meaning] * "."; duration = 3.5); r[:coin] = 3
        end
        return
    end
    # replies come a moment after the telling
    for (k, rp) in enumerate(r[:replies])
        rp === nothing && continue
        w.t >= rp.at || continue
        r[:replies][k] = nothing
        if get(rp, :give, false)
            t = get(byid, rp.to, nothing)
            t === nothing || (r[:knows][t.id] = rp.said; line!(w, r, t, "... " * loud(rp.said) * ". Fine."))
            continue
        end
        reply!(w, r, n, get(byid, rp.to, nothing), get(byid, rp.from, nothing), rp.said)
    end
    filter!(!isnothing, r[:replies])
    # tellers on their way
    for (tid, (lid, t0)) in collect(r[:tell])
        t = get(byid, tid, nothing); l = get(byid, lid, nothing)
        if t !== nothing && l !== nothing && t.goal.kind !== :wordtell && (free(t) || film) && !t.controlled && w.t - t0 < 25
            t.goal = NG.Goal(:wordtell, l.pos, :idle, 1.0, w.t + 30, false, l.id, false)      # called back from a pastime
        end
        if t === nothing || l === nothing || t.goal.kind !== :wordtell || w.t - t0 > 25 || !awake(l)
            delete!(r[:tell], tid); r[:ready][tid] = w.t + 6
            t !== nothing && t.goal.kind === :wordtell && (t.goal = NG.Goal(:idle, t.pos, :idle, 1.0, w.t + 1, true, 0, false))
            continue
        end
        d = hypot(l.pos[1] - t.pos[1], l.pos[2] - t.pos[2])
        if d > 1.8f0
            dir = Point3f(t.pos[1] - l.pos[1], t.pos[2] - l.pos[2], 0) / max(d, 0.01f0)
            t.goal.target = l.pos + dir * 1.2f0
            continue
        end
        # there: say it, and the friend stops to listen
        delete!(r[:tell], tid)
        said = r[:knows][tid]
        line!(w, r, t, fill_in(rand(w.rng, TELL), loud(said)))
        t.goal = NG.Goal(:wordhear, t.pos, :idle, 4.0, w.t + 4, true, l.id, false)
        if !l.controlled && (free(l) || film)
            l.goal = NG.Goal(:wordhear, l.pos, :idle, 4.0, w.t + 4, true, t.id, false)
        end
        push!(r[:replies], (at = w.t + 1.7, to = l.id, from = t.id, said))
        r[:told][tid] = get(r[:told], tid, 0) + 1
        r[:ready][tid] = w.t + (film ? 3.0 : 9.0)
        NG.emit!(w, :word_told; who = t.name, to = l.name, word = said)
    end
    # friends talking face each other
    for c in w.creatures
        c.goal.kind === :wordhear || continue
        o = get(byid, c.goal.partner, nothing)
        o === nothing || face!(c, o.pos)
    end
    # whoever knows a version and is free goes to tell someone
    for c in w.creatures
        haskey(r[:knows], c.id) || continue
        haskey(r[:tell], c.id) && continue
        w.t >= get(r[:ready], c.id, w.t + 1) || continue
        get(r[:told], c.id, 0) < TELLS || continue
        coiner = c.species == "Lumi" && get(r[:told], c.id, 0) < 2 && w.t - r[:t0] < 120
        ((free(c) || ((coiner || film) && awake(c))) && !c.controlled) || continue
        l = pick_listener(w, r, c, n)
        if l === nothing
            r[:ready][c.id] = w.t + 5
            continue
        end
        c.goal = NG.Goal(:wordtell, l.pos, :idle, 1.0, w.t + 30, false, l.id, false)
        r[:tell][c.id] = (l.id, w.t)
    end
    # the end: everyone awake says one version, or time is up
    up = [c for c in w.creatures if awake(c)]
    said = [get(r[:knows], c.id, "") for c in up]
    counts = Dict{String,Int}()
    for v in said
        isempty(v) || (counts[v] = get(counts, v, 0) + 1)
    end
    isempty(counts) && return
    top = first(sort(collect(counts); by = x -> -x[2]))
    # a few minutes at least, so the versions have time to meet and argue
    done = (top[2] >= 0.8 * length(up) && all(!isempty, said) && w.t - r[:t0] > (get(WR, :film, false) ? 60 : 180)) || w.t - r[:t0] > LASTS
    done && end_round!(game, r, counts, top[1])
end

function reply!(w, r, n, l, t, said)
    (l === nothing || t === nothing) && return
    rng = w.rng
    heard = said
    if rand(rng) < (get(WR, :film, false) && length(r[:parts]) == 1 && length(r[:tree]) >= 1 ? 1.0 : MISHEAR)
        parts = mishear(r[:parts][said], rng)
        heard = join(parts)
        if !haskey(r[:parts], heard)
            r[:parts][heard] = parts; r[:parent][heard] = said; r[:first][heard] = l.name
            NG.emit!(w, :word_misheard; who = l.name, said, heard)
        end
    end
    old = get(r[:knows], l.id, nothing)
    switched = false
    if old === nothing
        r[:knows][l.id] = heard
        line!(w, r, l, heard == said ? loud(heard) * "! I like it." : loud(heard) * "? ... " * loud(heard) * "!")
        r[:ready][l.id] = w.t + (get(WR, :film, false) ? 2.0 : 4.0)
    elseif old == heard
        line!(w, r, l, "I know! " * loud(heard) * "!")
    elseif rand(rng) < 0.2 + 0.7 * share(w, r, n, l, heard)
        r[:knows][l.id] = heard; switched = true
        line!(w, r, l, "Oh, " * loud(heard) * "? " * loud(heard) * " then.")
        r[:ready][l.id] = w.t + 4.0; r[:told][l.id] = 0
    else
        line!(w, r, l, "No no, it's " * loud(old) * "!")
        # the teller may give in
        if rand(rng) < 0.2 + 0.6 * share(w, r, n, t, old)
            push!(r[:replies], (at = w.t + 1.6, to = t.id, from = l.id, said = old, give = true))
        end
    end
    push!(r[:tree], (t = w.t - r[:t0], from = t.name, to = l.name, said, heard, was = old === nothing ? "" : old, switched))
end

function end_round!(game, r, counts, winner)
    w = game.world
    WR[:round] = nothing
    i = lumi(w)
    if i !== nothing && awake(w.creatures[i])
        me = w.creatures[i]
        txt = winner == r[:word] ? "Everyone says " * loud(winner) * " now!" : "Everyone says " * loud(winner) * " now. " * loud(winner) * " it is!"
        NG.say!(w, me, txt; duration = 4.0)
    end
    NG.emit!(w, :word_end; word = r[:word], winner, versions = length(r[:parts]), tellings = length(r[:tree]))
    game.dash === nothing && return       # quiet copies (films) keep no dictionary
    get(WR, :film, false) && return
    entry = Dict("word" => r[:word], "meaning" => r[:meaning], "winner" => winner, "hour" => r[:hour],
                 "day" => floor(Int, r[:t0] / w.day_length) + 1, "wall" => NG.Dates.format(NG.Dates.now(), "d U yyyy, HH:MM"),
                 "minutes" => round((w.t - r[:t0]) / 60; digits = 1),
                 "counts" => counts, "parent" => r[:parent], "first" => r[:first],
                 "tree" => [Dict(string(k) => v for (k, v) in pairs(e)) for e in r[:tree]])
    all = load_words(game)
    push!(all, entry)
    open(io -> NG.JSON.print(io, all, 1), words_file(game), "w")
    write_page(game, all)
end

esc(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

"The dictionary page: every word, what it means, its versions and how it went round (a tree of who told whom first)."
function write_page(game, all)
    io = IOBuffer()
    print(io, """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Our words</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{font-family:Georgia,serif;background:#f7f1e3;color:#3a2e22;max-width:760px;margin:2em auto;padding:0 1em;line-height:1.55}
 h1{color:#5b7f3a;margin-bottom:.2em} a{color:#8a5a2b}
 .word{background:#fffaf0;border-radius:12px;padding:1em 1.2em;margin:1.2em 0;box-shadow:0 1px 4px #0001}
 .word h2{margin:.1em 0;color:#8a5a2b;font-size:1.7em} .means{font-style:italic;margin:.2em 0 .6em}
 .vs{color:#5b4a36} .tree{font-size:.92em} .tree ul{margin:.1em 0 .1em 1.1em;padding-left:.6em;border-left:1px dotted #c9b48f}
 .tree li{list-style:none} .heard{color:#a0522d;font-weight:bold} .date{color:#9a8a70;font-size:.9em}
 footer{margin-top:3em;color:#7a6a50;font-style:italic;text-align:center}
</style></head><body>
<p><a href="index.html">back to my garden</a></p>
<h1>Our words</h1>
<p>Once an island morning a new word comes to me and I tell it to whoever I meet. It goes round the island along who really talks to whom, and some of us mishear it. Whatever the island says by the end goes in here.</p>
""")
    for e in reverse(all)
        word = e["word"]; win = e["winner"]
        print(io, "<div class=\"word\"><span class=\"date\">", esc(e["wall"]), ", island day ", e["day"], "</span>\n")
        print(io, "<h2>", esc(win), "</h2><p class=\"means\">", esc(e["meaning"]), "</p>\n")
        cs = sort(collect(e["counts"]); by = x -> -x[2])
        print(io, "<p class=\"vs\">I said <b>", esc(word), "</b>.")
        for (v, k) in cs
            v == word && continue
            haskey(e["first"], v) && print(io, " ", esc(e["first"][v]), " heard <b>", esc(v), "</b>.")
        end
        print(io, " After ", e["minutes"], " minutes: ", join(["$(esc(v)) $(k)" for (v, k) in cs], ", "), ".</p>\n")
        # the tree: each friend under whoever told it first
        firsts = Dict{String,Any}()
        for t in e["tree"]
            haskey(firsts, t["to"]) || t["was"] != "" || (firsts[t["to"]] = t)
        end
        kids = Dict{String,Vector{Any}}()
        for (_, t) in firsts
            push!(get!(kids, t["from"], Any[]), t)
        end
        root = get(e["first"], word, "Lumi")
        print(io, "<details class=\"tree\"><summary>how it went round</summary><ul><li>", esc(root), " <b>", esc(word), "</b>")
        seen = Set{String}([root])
        function branch(name)
            ks = sort(get(kids, name, Any[]); by = t -> t["t"])
            isempty(ks) && return
            print(io, "<ul>")
            for t in ks
                t["to"] in seen && continue
                push!(seen, t["to"])
                h = t["heard"] == t["said"] ? "<b>$(esc(t["heard"]))</b>" : "<span class=\"heard\">$(esc(t["heard"]))</span>"
                print(io, "<li>", esc(t["to"]), " ", h)
                branch(t["to"])
                print(io, "</li>")
            end
            print(io, "</ul>")
        end
        branch(root)
        print(io, "</li></ul></details></div>\n")
    end
    print(io, "<footer>i am lumi. i look after this island.</footer>\n</body></html>\n")
    html = String(take!(io))
    write(joinpath(game.paths.state, "words.html"), html)
    game.paths.instance === :live && write(joinpath(game.paths.world, "site", "words.html"), html)
end

morning(w) = 7.5 <= NG.daytime(w) * 24 <= 11.0

function NG.step!(::WordRound, game, dt)
    w = game.world
    r = get(WR, :round, nothing)
    if r === nothing
        game.dash === nothing && !get(WR, :force, false) && return
        game.minigame === nothing || game.minigame isa NG.JumpIn || return
        w.t >= get(WR, :try_at, -Inf) || return
        WR[:try_at] = w.t + 5
        day = floor(Int, w.t / w.day_length)
        first_ever = isempty(load_words(game))
        due = get(WR, :force, false) || (get(WR, :day, -1) != day && (morning(w) || first_ever))
        due || return
        i = lumi(w)
        i === nothing && return
        me = w.creatures[i]
        ok = get(WR, :force, false) || (free(me) && !me.controlled && party_free(w))
        ok || return
        WR[:force] = false; WR[:day] = day
        begin_round!(game)
        return nothing
    end
    step_round!(game, r)
    return nothing
end

"The camera watches a telling: the teller and its friend from the side."
function telling_view(w)
    r = get(WR, :round, nothing)
    r === nothing && return nothing
    for c in w.creatures
        c.goal.kind === :wordhear || continue
        o = findfirst(x -> x.id == c.goal.partner, w.creatures)
        o === nothing && continue
        return (c.id, [c.pos, w.creatures[o].pos])
    end
    return nothing
end

function NG.start!(::WordRound, game)
    WR[:round] = nothing; WR[:try_at] = -Inf; WR[:film] = false
    get!(WR, :force, false)
    # the friends' network, read once (and again each start) from the human's logs
    WR[:nettask] = Threads.@spawn read_net(joinpath(game.paths.world, "log"))
    # a moment, not a group view: the follow camera then sees the teller's face (a side view of the pair made the
    # "mostly sees faces" test fail, 16 of 49)
    if isdefined(Main, :LUMI_DOING)       # the thought over my head while I tell it
        Main.LUMI_DOING[:wordtell] = "Telling everyone my new word"
        Main.LUMI_DOING[:wordhear] = "A new word!"
    end
    NG.CAMERA_MOMENTS["wordround"] = w -> (v = telling_view(w); v === nothing ? nothing : v[1])
    return nothing
end

function NG.stop!(::WordRound, game)
    r = get(WR, :round, nothing)
    if r !== nothing
        for c in game.world.creatures
            c.goal.kind in (:wordtell, :wordhear) && (c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, game.world.t + 1, true, 0, false))
        end
    end
    WR[:round] = nothing
    delete!(NG.CAMERA_GROUPS, "wordround"); delete!(NG.CAMERA_MOMENTS, "wordround")
    return nothing
end

register!(WordRound())
