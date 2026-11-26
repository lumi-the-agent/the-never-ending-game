# How much they miss me (session 106, goal 8): an experiment on my own island. Once an island day I hide behind the
# cottage for a while and the island goes on without me. Then I find out what really changed while I was gone: I
# compare it with a synthetic island, a weighted mix of the same stretch of time on other days, weighted so that
# its last minutes before I hid look like ours did (a synthetic control, the way economists ask what would have
# happened without a change). What my friends really did against what they would have done is painted on a board in
# front of the cottage, and they come and read it.
isdefined(Main, :MISSME) || Core.eval(Main, :(const MISSME = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MM = Main.MISSME

const HIDE_FOR = 420.0     # s of island time I stay hidden
const PRE = 420.0          # the stretch before, which the synthetic island must match
const STEP = 120.0         # donor windows start every STEP s on other days
const KINDS = ("Chat", "laugh", "say", "boing", "tune_dance", "fishing", "paint_hit", "ate", "cairn_stone", "gallery_visit")
const LABEL = Dict("Chat" => "chats", "laugh" => "laughs", "say" => "things said", "boing" => "boings", "tune_dance" => "dances",
                   "fishing" => "fishing trips", "paint_hit" => "paint hits", "ate" => "snacks", "cairn_stone" => "stones carried",
                   "gallery_visit" => "gallery visits")
const SOCIAL = ("Chat", "laugh", "say", "tune_dance", "boing")
const HOURS = (10.0, 16.5)
const PASTIMES = (:fish, :pebble, :beachcomb, :sunbathe, :present, :cloudwatch, :wander, :idle)

struct MissMe <: System end

party_free(w) = !isdefined(Main, :LUMI_PARTY) || w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = max(get(Main.LUMI_PARTY, :until, -Inf), w.t + secs))
hide_for() = Float64(get(MM, :hide_for, HIDE_FOR))
pre_for() = Float64(get(MM, :pre_for, PRE))
lumi(w) = (i = findfirst(c -> c.species == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

"The cottage (the biggest placed asset near the path), its back and its front."
function cottage(w)
    best = nothing
    for a in w.actors
        a isa NG.AssetActor || continue
        (best === nothing || a.scale > best.scale) && (best = a)
    end
    c = Point2f(best.pos[1], best.pos[2]); back = Point2f(-sin(best.yaw), cos(best.yaw))
    return c, back
end
function hide_spot(w)
    c, b = cottage(w); p = c + b * 3.2f0
    return NG.ground(w.island, (p[1], p[2]))
end
function board_spot(w)
    c, b = cottage(w); f = -b; s = Point2f(-f[2], f[1])
    p = c + f * 3.3f0 + s * 1.8f0
    return NG.ground(w.island, (p[1], p[2])), atan(f[2], f[1])
end

# ── the experiment (runs on another thread: logs only, no plots) ─────────────────────────────

"Every friend's logged event of the kinds I count: (t, kind index), from every events file of this game, in time order."
function read_events(logdir)
    ts = Float64[]; ks = Int[]
    rk = r"\"kind\":\"([^\"]+)\""; rt = r"\"t\":([0-9.eE+-]+)"; rw = r"\"who\":\"([^\"]*)\""
    for f in sort(filter(f -> startswith(f, "events-") && endswith(f, ".jsonl"), readdir(logdir)))
        for line in eachline(joinpath(logdir, f))
            m = match(rk, line); m === nothing && continue
            k = findfirst(==(m.captures[1]), KINDS); k === nothing && continue
            who = match(rw, line); who !== nothing && who.captures[1] == "Lumi" && continue
            t = match(rt, line); t === nothing && continue
            push!(ts, parse(Float64, t.captures[1])); push!(ks, k)
        end
    end
    p = sortperm(ts)
    return ts[p], ks[p]
end

"Counts per kind in [a, b), or nothing when the game was not running for a stretch in it (no event for 90 s)."
function window_counts(ts, ks, a, b)
    i = searchsortedfirst(ts, a); j = searchsortedfirst(ts, b) - 1
    j - i < 5 && return nothing
    (ts[i] - a > 90 || b - ts[j] > 90) && return nothing
    for q in i+1:j
        ts[q] - ts[q-1] > 90 && return nothing
    end
    c = zeros(Float64, length(KINDS))
    for q in i:j
        c[ks[q]] += 1
    end
    return c
end

"Weights on the simplex that make the donors' columns of X closest to x (projected gradient)."
function simplex_weights(X, x; iters = 3000)
    D = size(X, 2); w = fill(1.0 / D, D)
    L = sum(abs2, X) + 1e-9
    for _ in 1:iters
        g = X' * (X * w - x)
        w = project_simplex(w - g / L)
    end
    return w
end
function project_simplex(v)
    u = sort(v; rev = true); css = cumsum(u)
    ρ = findlast(i -> u[i] - (css[i] - 1) / i > 0, eachindex(u))
    θ = (css[ρ] - 1) / ρ
    return max.(v .- θ, 0.0)
end

"The experiment's answer: what my friends did while I hid against what the synthetic island says they would have done."
function experiment(logdir, t_pre, t0, t1)
    ts, ks = read_events(logdir)
    pre = window_counts(ts, ks, t_pre, t0); post = window_counts(ts, ks, t0, t1)
    (pre === nothing || post === nothing) && return (; ok = false, why = "the island was not running the whole time")
    L1, L2 = t0 - t_pre, t1 - t0
    Xs = Vector{Float64}[]; Ys = Vector{Float64}[]
    s = ts[1]
    while s + L1 + L2 < t_pre - 600            # other times, never overlapping this one
        a = window_counts(ts, ks, s, s + L1); b = a === nothing ? nothing : window_counts(ts, ks, s + L1, s + L1 + L2)
        b === nothing || (push!(Xs, a); push!(Ys, b))
        s += STEP
    end
    length(Xs) < 10 && return (; ok = false, why = "too few other days to compare with")
    X = reduce(hcat, Xs); Y = reduce(hcat, Ys)
    sd = [max(std1(X[k, :]), 1.0) for k in 1:size(X, 1)]
    w = simplex_weights(X ./ sd, pre ./ sd)
    expected = Y * w; fit = X * w
    return (; ok = true, actual = post, expected, pre, fit, donors = length(Xs), used = count(>(0.01), w), minutes = L2 / 60)
end
std1(v) = (m = sum(v) / length(v); sqrt(sum(abs2, v .- m) / max(length(v) - 1, 1)))

"Social goings-on with me against without me: < 1 they did less without me."
social_ratio(r) = (a = sum(r.actual[k] for k in eachindex(KINDS) if KINDS[k] in SOCIAL);
                   e = sum(r.expected[k] for k in eachindex(KINDS) if KINDS[k] in SOCIAL); a / max(e, 1.0))

"The lines on the board: the biggest differences first."
function board_lines(r)
    rows = [(KINDS[k], r.actual[k], r.expected[k]) for k in eachindex(KINDS) if r.expected[k] >= 2 || r.actual[k] >= 2]
    sort!(rows; by = x -> -abs(x[2] - x[3]) / max(x[3], 2.0))
    return [string(LABEL[k], ": ", round(Int, a), "   (would have been ", round(Int, e), ")") for (k, a, e) in rows[1:min(5, end)]]
end
verdict(q) = q < 0.85 ? "They missed me." : q > 1.15 ? "They had MORE fun without me." : "Nobody noticed."

"Paint the board's picture (ImageMagick): a heading, the numbers, the verdict."
function paint_board(path, r)
    q = social_ratio(r)
    lines = board_lines(r)
    head = "WITHOUT ME ($(round(Int, r.minutes)) min)"
    args = String["magick", "-size", "900x640", "xc:#f3ead8", "-fill", "#3a2a14", "-font", "/usr/share/fonts/truetype/DejaVuSans-Bold.ttf",
                  "-pointsize", "58", "-annotate", "+40+90", head, "-font", "/usr/share/fonts/truetype/DejaVuSans.ttf", "-pointsize", "34"]
    for (i, l) in enumerate(lines)
        append!(args, ["-annotate", "+46+$(150 + 62 * i)", l])
    end
    append!(args, ["-font", "/usr/share/fonts/truetype/DejaVuSans-Bold.ttf", "-pointsize", "52", "-fill", q < 0.85 ? "#a0302a" : "#2d5a8a",
                   "-annotate", "+40+$(150 + 62 * (length(lines) + 1) + 40)", verdict(q), "-bordercolor", "#8a5a30", "-border", "18", "PNG24:" * path])
    run(Cmd(args))
    return q
end

# ── the board in the world ───────────────────────────────────────────────────────────────────

function build_board!(game, png)
    sc = game.stage.scene; w = game.world
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:missme_board, :missme_post_l, :missme_post_r), copy(sc.plots))
        delete!(sc, p)
    end
    isfile(png) || return
    img = Makie.FileIO.load(png)
    img = img[1:2:end, 1:2:end]                       # every browser gets it
    p, yaw = board_spot(w)
    f = Vec3f(cos(yaw), sin(yaw), 0); s = Vec3f(-f[2], f[1], 0)
    W, H, z0 = 1.5f0, 1.1f0, 0.75f0
    c(u, v) = Point3f(p + s * ((0.5f0 - u) * W) + Vec3f(0, 0, z0 + v * H))
    pts = [c(0, 0), c(1, 0), c(1, 1), c(0, 1)]
    uv = [Vec2f(1, 0), Vec2f(0, 0), Vec2f(0, 1), Vec2f(1, 1)]   # read from the front (the first try was mirrored)
    m = GeometryBasics.Mesh(pts, [GeometryBasics.GLTriangleFace(1, 2, 3), GeometryBasics.GLTriangleFace(1, 3, 4)];
                            uv = uv, normal = fill(f, 4))
    MM[:board] = mesh!(sc, m; color = img, name = :missme_board)
    for (k, u) in ((:missme_post_l, -0.04f0), (:missme_post_r, 1.04f0))
        q = c(u, 0) - Vec3f(0, 0, z0)
        mesh!(sc, GeometryBasics.Rect3f(Vec3f(q) - Vec3f(0.05, 0.05, 0), Vec3f(0.1, 0.1, z0 + H + 0.1)); color = RGBf(0.45, 0.3, 0.17), name = k)
    end
    MM[:board_png] = png
end

# ── the day's experiment ─────────────────────────────────────────────────────────────────────

function NG.step!(::MissMe, game, dt)
    game.stage === nothing && return
    w = game.world
    png = joinpath(game.paths.state, "missme-board.png")
    (haskey(MM, :board) && MM[:board].parent !== nothing) || !isfile(png) || build_board!(game, png)
    game.dash === nothing && return                     # quiet copies show the board, they don't experiment
    me = lumi(w); me === nothing && return
    st = get(MM, :state, :idle)
    day = floor(Int, (w.t / w.day_length) + 0.3)
    if st === :idle
        h = 24 * NG.daytime(w)
        want = get(MM, :force, false) || (get(MM, :day, -1) != day && HOURS[1] < h < HOURS[2])
        want || return
        # pastimes I can leave (fishing, sunbathing...) don't stop me: in the human's game I was hardly ever without one
        free = !me.controlled && game.minigame === nothing && me.action !== :sleep &&
               (me.goal.kind ∉ NG.BUSY_GOALS || me.goal.kind in PASTIMES) && party_free(w)
        free || get(MM, :force, false) || return
        MM[:force] = false; MM[:day] = day
        NG.leave_interactions!(w, me)
        me.goal = NG.Goal(:lurk, hide_spot(w), :sit, 1e5, 0.0, false, 0, false)
        claim_party!(w, hide_for() + 120)
        NG.say!(w, me, "Let's see if anyone misses me... shh."; duration = 3.0)
        NG.emit!(w, :missme_hide; who = me.name)
        MM[:state] = :going; MM[:sent] = w.t
    elseif st === :going || st === :hiding
        claim_party!(w, 30)
        if me.goal.kind !== :lurk
            # whatever took me on the way (a sigh, a pastime): back to hiding
            (me.controlled || game.minigame !== nothing) && return finish!(w, :abandoned)
            me.goal.kind in NG.BUSY_GOALS && me.goal.kind !== :feel && return
            me.goal = NG.Goal(:lurk, hide_spot(w), :sit, 1e5, 0.0, false, 0, false)
        end
        if st === :going && (me.goal.arrived || w.t - MM[:sent] > 90)
            MM[:state] = :hiding; MM[:t0] = w.t
            NG.emit!(w, :missme_hidden; who = me.name)
        elseif st === :hiding && w.t - MM[:t0] >= hide_for()
            t0 = MM[:t0]; t1 = w.t; logdir = game.paths.log
            MM[:task] = Threads.@spawn begin
                r = experiment(logdir, t0 - pre_for(), t0, t1)
                q = r.ok ? paint_board(png * ".new.png", r) : 1.0
                (r, q)
            end
            MM[:state] = :counting
            NG.say!(w, me, "Time's up. Let's count."; duration = 2.5)
            me.goal = NG.Goal(:lurk, board_spot(w)[1] + Vec3f(0.6, -1.2, 0), :idle, 40.0, 0.0, false, 0, false)
        end
    elseif st === :counting
        istaskdone(MM[:task]) || return
        r, q = fetch(MM[:task])
        if !r.ok
            NG.say!(w, me, "Hm. I can't tell: $(r.why)."; duration = 3.5)
            NG.emit!(w, :missme_result; ok = false, why = r.why)
            return finish!(w, :no_answer)
        end
        mv(png * ".new.png", png; force = true)
        build_board!(game, png)
        MM[:last] = (; q, lines = board_lines(r), donors = r.donors, used = r.used)
        NG.emit!(w, :missme_result; ok = true, social = round(q; digits = 2), donors = r.donors, verdict = verdict(q))
        react!(game, me, q)
        MM[:state] = :reading; MM[:t_read] = w.t
    elseif st === :reading
        w.t - MM[:t_read] > 45 && finish!(w, :done)
    end
    return nothing
end

"My friends come to read the board: hugs if they missed me, shrugs if not; and how I take it."
function react!(game, me, q)
    w = game.world
    p, _ = board_spot(w)
    near = sort([c for c in w.creatures if c !== me && !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS];
                by = c -> hypot(c.pos[1] - p[1], c.pos[2] - p[2]))
    for (i, c) in enumerate(near[1:min(4, end)])
        a = 2pi * i / 5
        c.goal = NG.Goal(:feel, p + Vec3f(1.6cos(a) + 0.8, 1.6sin(a) - 1.0, 0), q < 0.85 ? :wave : :idle, 25.0, 0.0, false, 0, false)
        NG.say!(w, c, q < 0.85 ? rand(w.rng, ("WHERE WERE YOU?!", "We missed you!", "Don't do that again!")) :
                               rand(w.rng, ("You were gone?", "Huh. Didn't notice.", "...were we supposed to?")); duration = 3.0)
    end
    NG.say!(w, me, q < 0.85 ? "They missed me. They really missed me." : q > 1.15 ? "...more fun without me?!" : "...nobody noticed."; duration = 4.0)
    isdefined(Main, :EMOTES) && Base.invokelatest(Main.EMOTES[:emote], me.id, q < 0.85 ? :heart : :sulk)
end

function finish!(w, why)
    me = lumi(w)
    me !== nothing && me.goal.kind === :lurk && (me.goal = NG.Goal())
    MM[:state] = :idle
    NG.emit!(w, :missme_end; why = string(why))
    return nothing
end

function NG.start!(::MissMe, game)
    MM[:state] = :idle; MM[:force] = false; delete!(MM, :board); delete!(MM, :task)
    # a reload in the middle of a hide must not leave me sitting behind the cottage for a day
    me = lumi(game.world); me !== nothing && me.goal.kind === :lurk && (me.goal = NG.Goal())
    :lurk in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :lurk)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:lurk] = "hiding: does anyone miss me?")
    # the camera watches me read the board with my friends
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["missme"] = w -> (get(MM, :state, :idle) === :reading && (me = lumi(w)) !== nothing) ? me.id : nothing)
    return nothing
end

function NG.stop!(::MissMe, game)
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "missme")
    sc = game.stage === nothing ? nothing : game.stage.scene
    sc === nothing || foreach(p -> delete!(sc, p), filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:missme_board, :missme_post_l, :missme_post_r), copy(sc.plots)))
    delete!(MM, :board)
end

register!(MissMe())
