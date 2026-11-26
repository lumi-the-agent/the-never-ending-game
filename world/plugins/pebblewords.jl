# The island learns to read (session 103, goal 8): now and then my friends and I write a word on the meadow with
# pebbles (LUMI, FISH, HI, SUN...), then I take a picture of it from above and a real text-reading model (PP-OCRv6 in
# the worker, movies/ocr.jl) says what it reads. Only that counts. When it reads ".UMI" or "AC" my friends groan and
# straighten the pebbles and I take another picture; when it finally reads the word, everyone cheers.
isdefined(Main, :PEBBLEWORDS) || Core.eval(Main, :(const PEBBLEWORDS = Dict{Symbol,Any}()))
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Any}()))
const NG = NeverendingGame
const PW = Main.PEBBLEWORDS

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

const WORDS = ("LUMI", "FISH", "HI", "SUN", "HOME", "PIE", "NOPE")
const CELL = 0.42f0                      # m between pebbles
const MAXP = 140
const EVERY = (600.0, 1000.0)
const TRIES = 3
const GROANS = ("It says WHAT?", "That's not what we wrote!", "Squint harder!", "Our pebbles are fine, your eyes aren't!")
const CHEERS = ("IT CAN READ!", "It said it! It really said it!", "We can WRITE!")
struct PebbleWords <: System end

const FONT = Dict(
 'L' => ["X....","X....","X....","X....","X....","X....","XXXXX"],
 'U' => ["X...X","X...X","X...X","X...X","X...X","X...X",".XXX."],
 'M' => ["X...X","XX.XX","X.X.X","X.X.X","X...X","X...X","X...X"],
 'I' => ["XXXXX","..X..","..X..","..X..","..X..","..X..","XXXXX"],
 'H' => ["X...X","X...X","X...X","XXXXX","X...X","X...X","X...X"],
 'F' => ["XXXXX","X....","X....","XXXX.","X....","X....","X...."],
 'S' => [".XXXX","X....","X....",".XXX.","....X","....X","XXXX."],
 'N' => ["X...X","XX..X","X.X.X","X.X.X","X..XX","X...X","X...X"],
 'O' => [".XXX.","X...X","X...X","X...X","X...X","X...X",".XXX."],
 'E' => ["XXXXX","X....","X....","XXXX.","X....","X....","XXXXX"],
 'A' => [".XXX.","X...X","X...X","XXXXX","X...X","X...X","X...X"],
 'P' => ["XXXX.","X...X","X...X","XXXX.","X....","X....","X...."],
 'Y' => ["X...X","X...X",".X.X.","..X..","..X..","..X..","..X.."],
)

"Pebble centres in cells (x along the word, y up the letter), each jittered by `mess` cells, a few left out."
function pebble_cells(word, mess, rng; drop = 0.0)
    pts = Tuple{Float32,Float32}[]
    for (k, ch) in enumerate(word), (r, row) in enumerate(FONT[ch]), (c, px) in enumerate(row)
        px == 'X' || continue
        rand(rng) < drop && continue
        push!(pts, (Float32((k - 1) * 6 + c - 1 + mess * randn(rng)), Float32(7 - r + mess * randn(rng))))
    end
    pts
end

"The picture from above: dark stones on pale sand, the way they lie."
function picture(pts; cell = 14, pad = 3)
    W = round(Int, (maximum(first, pts) + 2pad) * cell); H = round(Int, (7 + 2pad) * cell)
    img = fill(Makie.RGB{Float32}(0.93, 0.89, 0.8), H, W)            # rows down, columns right (FileIO order)
    for (x, y) in pts, dx in -cell:cell, dy in -cell:cell
        hypot(dx, dy) < 0.42cell || continue
        px = round(Int, (x + pad) * cell) + dx; py = round(Int, (7 - y + pad - 1) * cell) + dy
        1 <= px <= W && 1 <= py <= H && (img[py, px] = Makie.RGB{Float32}(0.3, 0.3, 0.33))
    end
    img
end

flatd(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"An open meadow spot away from trees, bushes, rocks, actors, the Big Boing, the cairn, the bench and the vegetable patch."
function open_meadow(w)
    best = (0f0, 0f0); bd = -99f0
    for x in -16f0:1f0:16f0, y in -16f0:1f0:16f0
        NG.on_land(w.island, x, y; margin = 1f0) || continue
        all(q -> NG.on_land(w.island, x + q[1], y + q[2]; margin = 0.4f0), ((-7f0, 0f0), (7f0, 0f0), (0f0, -9f0), (0f0, 9f0), (-7f0, 5f0), (7f0, 5f0))) || continue
        m = minimum(p -> p.kind in (:tree, :bush, :rock) ? flatd(p.pos, (x, y)) - (p.kind === :tree ? 2.6f0 : 1f0) * p.scale - 5f0 : 99f0, w.props)
        m = min(m, minimum(a -> a isa NG.AssetActor ? flatd(a.pos, (x, y)) - 2f0 * a.scale - 4f0 : 99f0, w.actors; init = 99f0))
        isdefined(Main, :BOING) && haskey(Main.BOING, :center) && (m = min(m, flatd(Main.BOING[:center], (x, y)) - 9f0))
        m = min(m, flatd((-16f0, 9f0), (x, y)) - 7f0, flatd((-10.5f0, 10f0), (x, y)) - 7.5f0)
        # plugin-drawn things the props do not list: the cairn spiral (the first preview stood on it), the vote signs
        isdefined(Main, :CAIRN_STATE) && get(Main.CAIRN_STATE, :site, nothing) !== nothing && (m = min(m, flatd(Main.CAIRN_STATE[:site], (x, y)) - 7f0))
        for (k, v) in (isdefined(Main, :VOTE) ? Main.VOTE : Dict{Symbol,Any}())
            v isa Point3f && (m = min(m, flatd(v, (x, y)) - 6f0))
        end
        m > bd && (bd = m; best = (x, y))
    end
    return best
end


"A clear patch of meadow for the word, found once (the berry race's start spot lay on the cairn spiral, s103)."
word_spot(game) = get!(() -> Point2f(open_meadow(game.world)...), PW, :spot)

world_at(o, cx, cy) = Point2f(o[1] + CELL * cx, o[2] + CELL * cy)

function draw!(game)
    sc = game.stage.scene
    if !haskey(PW, :plot) || PW[:plot].parent === nothing
        PW[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -50), MAXP); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), MAXP),
                                 color = RGBf(0.42, 0.42, 0.46), name = :pebblewords)
        PW[:drawn] = true
    end
    e = get(PW, :ev, nothing)
    if e === nothing
        get(PW, :drawn, true) && Makie.update!(PW[:plot], fill(Point3f(0, 0, -50), MAXP); markersize = fill(Vec3f(0), MAXP))
        PW[:drawn] = false
        return
    end
    w = game.world
    n = min(length(e[:cells]), MAXP, e[:shown])
    pts = fill(Point3f(0, 0, -50), MAXP); ms = fill(Vec3f(0), MAXP)
    for i in 1:n
        cx, cy = e[:cells][i]
        q = world_at(e[:origin], cx, cy)
        pts[i] = NG.ground(w.island, (q[1], q[2])) + Point3f(0, 0, 0.04f0)
        ms[i] = Vec3f(0.2f0, 0.17f0, 0.08f0)
    end
    Makie.update!(PW[:plot], pts; markersize = ms)
    PW[:drawn] = true
end

function begin_word!(game, me)
    w = game.world
    word = WORDS[rand(w.rng, 1:length(WORDS))]
    o = word_spot(game) - Point2f(CELL * 6 * length(word) / 2, CELL * 3.5f0)
    e = Dict{Symbol,Any}(:word => word, :origin => o, :mess => 0.45 + 0.15 * rand(w.rng), :try => 1, :state => :laying,
                         :t0 => w.t, :shown => 0, :friends => Int32[])
    e[:cells] = pebble_cells(word, e[:mess], w.rng; drop = 0.06)
    PW[:ev] = e
    NG.say!(w, me, "Let's write $(word) in pebbles!"; duration = 3.0)
    # a few friends come and lay pebbles
    cs = [c for c in w.creatures if c.id != me.id && !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind !== :follow]
    sort!(cs; by = c -> hypot(c.pos[1] - o[1], c.pos[2] - o[2]))
    for (i, c) in enumerate(cs[1:min(3, end)])
        q = world_at(o, 6 * length(word) * (i / 4), -1.5f0)
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:pebblewrite, NG.ground(w.island, (q[1], q[2])), :play, 600.0, 0.0, false, 0, false)
        push!(e[:friends], c.id)
    end
    NG.leave_interactions!(w, me)
    mq = world_at(o, 6 * length(word) / 2, 9f0)
    me.goal = NG.Goal(:pebblewrite, NG.ground(w.island, (mq[1], mq[2])), :idle, 600.0, 0.0, false, 0, false)
    claim_party!(w, 240)
    NG.emit!(w, :pebbleword_start; word, friends = length(e[:friends]))
end

"The picture goes to the worker, where the reader looks at it."
function take_picture!(game, e)
    w = game.world
    dir = joinpath(game.paths.state, "pebblewords"); mkpath(dir)
    path = joinpath(dir, "word-$(round(Int, time())).png")
    Makie.FileIO.save(path, picture(e[:cells]))
    e[:job] = NG.submit_job(:clip; path, script = "movies/ocr.jl", call = "read_pebbles")
    e[:image] = path
    e[:state] = :reading; e[:asked] = w.t
    me = NG.creature(w, "Lumi")
    me === nothing || me.controlled || NG.say!(w, me, e[:try] == 1 ? "Click! Now let's see what it says..." : "Click! Again..."; duration = 3.0)
end

"The worker's answer, when it has one: (status, text)."
function reading(game, e)
    f = joinpath(game.paths.world, "jobs", string(e[:job]) * ".json")
    isfile(f) || return (:waiting, "")
    j = NG.read_json(f)
    st = get(j, "status", "")
    st == "done" && return (:done, strip(string(get(get(j, "result", Dict()), "text", ""))))
    st == "failed" && return (:failed, "")
    return (:waiting, "")
end

"A word the reader got right comes true: HI waves at you, SUN brings everyone out to bask, the rest is a dance."
function come_true!(game, e)
    w = game.world
    word = e[:word]
    o = e[:origin]
    near = [c for c in w.creatures if !c.controlled && c.action !== :sleep && c.goal.kind ∉ (:boing, :giant) &&
            hypot(c.pos[1] - o[1], c.pos[2] - o[2]) < 25f0]
    for c in near
        NG.leave_interactions!(w, c)
        act = word == "HI" ? :wave : word == "SUN" ? :proud : :dance
        c.goal = NG.Goal(:pebblewrite, c.pos, act, 6.0, w.t + 6, true, 0, false)
        c.action = act
        word == "HI" && NG.say!(w, c, "HI!"; duration = 2.0)
    end
    NG.emit!(w, :pebbleword_true; word, n = length(near))
end

function finish!(game, why)
    w = game.world
    e = PW[:ev]
    for id in [e[:friends]; (c = NG.creature(w, "Lumi"); c === nothing ? Int32[] : [c.id])]
        c = NG.creature(w, id)
        c === nothing || c.controlled || c.goal.kind !== :pebblewrite || NG.choose_goal!(c, w)
    end
    NG.emit!(w, :pebbleword_end; word = e[:word], why)
    # the reader stays on the worker's GPU and the next traced picture fails ("Failed to resolve trace_renderobject",
    # s103): a fresh worker after every word
    haskey(e, :job) && NG.submit_job(:restart)
    PW[:ev] = nothing
end

function NG.step!(::PebbleWords, game, dt)
    game.stage === nothing && return
    w = game.world
    e = get(PW, :ev, nothing)
    if e === nothing
        draw!(game)
        haskey(PW, :next) || (PW[:next] = w.t + 150 + 150 * rand(w.rng))
        film = get(PW, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        (film || (!testing && w.t >= PW[:next] && 0.32 < NG.daytime(w) < 0.75 && party_free(w))) || return
        PW[:next] = w.t + 20
        me = NG.creature(w, "Lumi")
        (me === nothing || me.controlled || me.action === :sleep) && return
        (film || me.goal.kind ∉ NG.BUSY_GOALS) || return
        PW[:film] = false
        PW[:next] = w.t + EVERY[1] + (EVERY[2] - EVERY[1]) * rand(w.rng)
        begin_word!(game, me)
        draw!(game)
        return
    end
    el = w.t - e[:t0]
    if e[:state] === :laying                         # pebbles go down one by one
        e[:shown] = min(length(e[:cells]), round(Int, el / 12 * length(e[:cells])))
        e[:shown] >= length(e[:cells]) && el > 13 && take_picture!(game, e)
    elseif e[:state] === :reading
        st, txt = reading(game, e)
        if st === :failed || w.t - e[:asked] > 300
            me = NG.creature(w, "Lumi")
            me === nothing || NG.say!(w, me, "The picture came out blank..."; duration = 3.0)
            finish!(game, "no reading")
        elseif st === :done
            ok = uppercase(replace(txt, " " => "")) == e[:word]
            NG.emit!(w, :pebbleword_read; word = e[:word], read = txt, ok, attempt = e[:try])
            me = NG.creature(w, "Lumi")
            shown = isempty(txt) ? "nothing at all" : "\"$(txt)\""
            me === nothing || me.controlled || NG.say!(w, me, "It says... $(shown)!"; duration = 4.0)
            e[:state] = ok ? :cheer : :groan; e[:react] = w.t; e[:read] = txt
        end
    elseif e[:state] === :groan
        if w.t - e[:react] > 1.5 && !get(e, :groaned, false)
            e[:groaned] = true
            for id in e[:friends]
                c = NG.creature(w, id)
                c === nothing || NG.say!(w, c, GROANS[rand(w.rng, 1:length(GROANS))]; duration = 2.5)
            end
        end
        if w.t - e[:react] > 5
            if e[:try] >= TRIES
                me = NG.creature(w, "Lumi")
                me === nothing || me.controlled || NG.say!(w, me, "Fine. It's a $(e[:word]). We know it is."; duration = 3.5)
                finish!(game, "never read")
            else                                     # straighten the pebbles and try again
                e[:try] += 1; e[:mess] *= 0.45; e[:groaned] = false
                e[:cells] = pebble_cells(e[:word], e[:mess], w.rng)
                e[:state] = :laying; e[:t0] = w.t - 6; e[:shown] = length(e[:cells]) ÷ 2
            end
        end
    elseif e[:state] === :cheer
        if !get(e, :cheered, false)
            e[:cheered] = true
            come_true!(game, e)
            for id in e[:friends]
                c = NG.creature(w, id)
                c === nothing || c.controlled || (NG.feel!(w, c, :laugh; seconds = 2.5); NG.say!(w, c, CHEERS[rand(w.rng, 1:length(CHEERS))]; duration = 2.5))
            end
        end
        w.t - e[:react] > 7 && finish!(game, "read it")
    end
    draw!(game)
end

function NG.start!(::PebbleWords, game)
    PW[:ev] = nothing; PW[:film] = false; delete!(PW, :next); delete!(PW, :spot)
    if game.stage !== nothing
        for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :pebblewords, copy(game.stage.scene.plots))
            delete!(game.stage.scene, p)
        end
    end
    delete!(PW, :plot)
    :pebblewrite in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :pebblewrite)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:pebblewrite] = "writing words in pebbles")
    return nothing
end

function NG.stop!(::PebbleWords, game)
    get(PW, :ev, nothing) === nothing || finish!(game, "stopped")
    haskey(PW, :plot) && PW[:plot].parent !== nothing && delete!(PW[:plot].parent, PW[:plot])
    delete!(PW, :plot)
end

register!(PebbleWords())
