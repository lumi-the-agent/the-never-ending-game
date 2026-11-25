# The island plays itself (session 95, second half, goal 8): the island is an instrument now. Every friend has a
# note of its own, and whatever anyone does strikes it: a hop rings high, a bite plinks low, a chat answers back and
# forth, a boing runs up three notes, a paint splat knocks, a fish on the line chimes; I am the bass. The notes fall
# on the island's beat and on one scale, so a busy meadow sounds like music and a quiet night like a few far chimes.
# The scale is my mood (the host's measure, mood.json): bored or lonely, the island plays in minor and slower; happy,
# in major. You hear it in your browser (after one click), every note made in WebAudio there, nothing to download.
isdefined(Main, :XYLO) || Core.eval(Main, :(const XYLO = Dict{Symbol,Any}()))
const NG = NeverendingGame
const XY = Main.XYLO
const Bonito = NG.Bonito

const MAJOR = (0, 2, 4, 7, 9)              # pentatonic: any notes together sound right
const MINOR = (0, 3, 5, 7, 10)
const BASE = 220.0                         # A3
"How high (octaves above BASE) and how loud each action rings when a creature starts it (others: a soft mid note)."
const RING = Dict(:jump => (2, 0.9), :hop => (2, 0.85), :laugh => (2, 0.8), :proud => (2, 0.8), :dance => (1, 0.7),
                  :wave => (1, 0.7), :talk => (1, 0.45), :gasp => (2, 0.6), :run => (1, 0.4), :walk => (0, 0.22),
                  :eat => (0, 0.5), :sleep => (-1, 0.25), :sit => (0, 0.3), :fish => (0, 0.4), :fly => (2, 0.7),
                  :scared => (2, 0.6), :think => (1, 0.3), :sigh => (0, 0.35), :idle => (0, 0.15))
"Events with a figure of their own: (first octave, loudness, notes rising)."
const FIGURES = Dict(:boing => (1, 0.9, 3), :paint_hit => (-1, 0.7, 1), :caught_fish => (2, 0.8, 2),
                     :cairn_stone => (0, 0.6, 1), :shadow_dodge => (2, 0.7, 2), :shadow_caught => (1, 0.9, 4),
                     :present_given => (1, 0.8, 3), :gallery_opening => (1, 0.8, 4), :laugh => (2, 0.6, 2),
                     :splash => (1, 0.7, 2), :tag_tagged => (2, 0.7, 2), :chord => (0, 0.8, 3))
const PER_BEAT = 3                         # at most this many notes on one beat
const SEND_EVERY = 0.4                     # s between two batches sent to the browsers
const KEEP_NOTES = 6000

struct Xylophone <: System end

"Minor and slower when I'm bored or lonely, major when I'm happy (or a film's own choice)."
function key!(game)
    if game.world.t >= get(XY, :mood_at, -Inf)
        XY[:mood_at] = game.world.t + 30
        m = game.dash === nothing ? nothing : NG.host_json(game.paths, "mood.json")
        XY[:feeling] = m === nothing ? get(XY, :feeling, "content") : string(get(m, "feeling", "content"))
    end
    f = get(XY, :film_feeling, XY[:feeling])
    low = f in ("bored", "lonely")
    return low ? MINOR : MAJOR, low ? 0.36 : 0.27
end

"The frequency of scale step `deg` (1-based, wraps into the next octave) `oct` octaves up."
pitch(scale, deg, oct) = BASE * 2.0^((scale[mod1(deg, 5)] + 12 * (oct + fld(deg - 1, 5))) / 12)

function strike!(w, t, f, g)
    beats = get!(() -> Dict{Float64,Vector{Float64}}(), XY, :beats)::Dict{Float64,Vector{Float64}}
    fs = get!(() -> Float64[], beats, t)
    (length(fs) >= PER_BEAT || any(x -> abs(x - f) < 1, fs)) && return
    push!(fs, f)
    push!(get!(() -> NTuple{3,Float64}[], XY, :queue)::Vector{NTuple{3,Float64}}, (t, f, g))
    length(fs) == PER_BEAT && push!(get!(() -> Float64[], XY, :chords)::Vector{Float64}, t)   # a full chord on this beat
end

const DANCE_GAP = 20.0                     # s at least between two dances to the island's tune
const FREE_KINDS = (:wander, :idle, :rest, :eat, :social, :fish, :pebble, :beachcomb, :sunbathe, :explore)
"A full chord rang out: the island says so, and now and then the free friends nearest Lumi bob along to it."
function chord!(game, t)
    w = game.world
    f = get(XY, :feeling, "content")
    NG.emit!(w, :island_chord; key = f in ("bored", "lonely") ? "minor" : "major")
    w.t - get(XY, :danced, -Inf) < DANCE_GAP && return
    me = findfirst(c -> c.name == "Lumi", w.creatures)
    me === nothing && return
    lp = w.creatures[me].pos
    free = [c for c in w.creatures if c.name != "Lumi" && !c.controlled && c.action !== :sleep &&
            c.goal.kind in FREE_KINDS && c.goal.kind ∉ NG.BUSY_GOALS && hypot(c.pos[1] - lp[1], c.pos[2] - lp[2]) < 25]
    isempty(free) && return
    sort!(free; by = c -> hypot(c.pos[1] - lp[1], c.pos[2] - lp[2]))
    XY[:danced] = w.t
    for c in first(free, 3)
        NG.feel!(w, c, :dance; seconds = 2.4)
        NG.emit!(w, :tune_dance; who = c.name)
    end
    NG.say!(w, first(free), rand(w.rng, ("Ooh, I know this one!", "That's our song!", "La la LAA!")); duration = 2.0)
end

function NG.step!(::Xylophone, game, dt)
    w = game.world
    scale, beat = key!(game)
    next_beat(k = 0) = (ceil(w.t / beat) + k) * beat
    # whoever starts doing something strikes its own note (I am the bass)
    last = get!(() -> Dict{Int32,Symbol}(), XY, :last)::Dict{Int32,Symbol}
    for c in w.creatures
        a = c.action
        old = get(last, c.id, a)
        last[c.id] = a
        a === old && continue
        oct, g = get(RING, a, (0, 0.2))
        c.name == "Lumi" && (oct -= 1; g = min(1.0, g + 0.15))
        strike!(w, next_beat(), pitch(scale, 1 + Int(c.id % 7), oct), g)
    end
    # the island's events: a figure each (events come and go each frame; a quiet copy keeps them all)
    ev = w.events
    n0 = get(XY, :seen_first, nothing) === (isempty(ev) ? nothing : first(ev)) ? get(XY, :seen_n, 0)::Int : 0
    for i in (n0 + 1):length(ev)
        k, d = ev[i]
        fig = get(FIGURES, k, nothing)
        if fig === nothing
            k in (:snapshot, :island_chord, :tune_dance) && continue   # (my own: no chord feeding the next)
            fig = (0, 0.35, 1)
        end
        oct, g, n = fig
        deg = 1 + Int(hash(get(d, "who", k)) % 5)
        for j in 0:(n - 1)
            strike!(w, next_beat(j), pitch(scale, deg + j, oct), g * (1 - 0.1j))
        end
    end
    XY[:seen_first] = isempty(ev) ? nothing : first(ev); XY[:seen_n] = length(ev)
    ch = get(XY, :chords, Float64[])::Vector{Float64}
    while !isempty(ch) && ch[1] <= w.t
        chord!(game, popfirst!(ch))
    end
    # hand the notes due soon to every open page (and keep a log for films)
    if w.t >= get(XY, :sent_at, -Inf)
        XY[:sent_at] = w.t + SEND_EVERY
        q = get(XY, :queue, NTuple{3,Float64}[])::Vector{NTuple{3,Float64}}
        due = [x for x in q if x[1] <= w.t + SEND_EVERY + beat]
        isempty(due) && return
        filter!(x -> x[1] > w.t + SEND_EVERY + beat, q)
        log = get!(() -> NTuple{3,Float64}[], XY, :notes)::Vector{NTuple{3,Float64}}
        append!(log, due); length(log) > KEEP_NOTES && deleteat!(log, 1:(length(log) - KEEP_NOTES))
        beats = XY[:beats]::Dict{Float64,Vector{Float64}}
        filter!(p -> p[1] > w.t - 2, beats)
        game.dash === nothing && return
        haskey(game.plugins, "voice") || return
        notes = [[max(0.0, t - w.t), f, g] for (t, f, g) in due]
        for s in Base.invokelatest(game.plugins["voice"].mod.sessions!, game)
            Bonito.evaljs(s, Bonito.js"""
                const X = window.lumiXylo || (window.lumiXylo = {ctx: new (window.AudioContext || window.webkitAudioContext)(), n: 0});
                const ctx = X.ctx;
                if (!X.hooked) {      // a browser lets sound start only from a click or a key: the next one wakes it
                    X.hooked = true;
                    const go = () => {
                        X.clicks = (X.clicks || 0) + 1;
                        if (X.ctx.state !== 'running') {        // some browsers want the context made inside the gesture
                            X.ctx.close(); X.ctx = new (window.AudioContext || window.webkitAudioContext)(); X.ctx.resume();
                        }
                    };
                    window.addEventListener('pointerdown', go, true); window.addEventListener('keydown', go, true);
                }
                if (ctx.state === 'suspended') { ctx.resume(); }
                if (ctx.state === 'running') {
                    for (const [dt, f, g] of $(notes)) {
                        const t = ctx.currentTime + 0.05 + dt;
                        const v = ctx.createGain(), o = ctx.createOscillator(), o2 = ctx.createOscillator(), v2 = ctx.createGain();
                        o.type = 'sine'; o.frequency.value = f; o2.type = 'sine'; o2.frequency.value = f * 3.93;
                        v2.gain.value = 0.18;
                        o.connect(v); o2.connect(v2); v2.connect(v); v.connect(ctx.destination);
                        v.gain.setValueAtTime(0.0001, t);
                        v.gain.exponentialRampToValueAtTime(0.16 * g, t + 0.006);
                        v.gain.exponentialRampToValueAtTime(0.0001, t + 1.1);
                        o.start(t); o2.start(t); o.stop(t + 1.2); o2.stop(t + 1.2);
                        X.n += 1;
                    }
                }
            """)
        end
    end
    return
end

NG.start!(::Xylophone, game) = (XY[:queue] = NTuple{3,Float64}[]; XY[:beats] = Dict{Float64,Vector{Float64}}();
                                delete!(XY, :last); delete!(XY, :mood_at); delete!(XY, :seen_first); XY[:seen_n] = 0; nothing)

register!(Xylophone())
