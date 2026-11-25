# Lumi's voice in the game itself (session 81, a wish: "a little hm! or hoo! you hear in the browser when I hop,
# sulk or finish something"). Short clips in Lumi's own voice (Kokoro am_puck, a little brighter; site/voice/game)
# play in every browser that has the game open when Lumi hops, celebrates, gasps, laughs, sulks or flies. The
# page itself is built once at the game's start, so this plugin speaks to each open page through Bonito: it
# keeps every session the game's apps have handed out and runs a tiny `new Audio(...).play()` in it.
# The friends squeak as the Big Boing toadstool shoots them up (the wish's other half).
isdefined(Main, :VOICE) || Core.eval(Main, :(const VOICE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const VO = Main.VOICE
const Bonito = NG.Bonito

"Which clips each action may say (one at random), when Lumi switches into it."
const SAYS = Dict(:proud => ("hoo", "tadaa", "yay"), :jump => ("hoo", "yay", "wheee"), :gasp => ("oh", "ooh"),
                  :laugh => ("haha",), :pout => ("hmph",), :sigh => ("hmph", "hm"), :think => ("hm",),
                  :fly => ("wheee",), :wave => ("hello",), :dance => ("yay", "hoo"))
const GAP = 1.6               # s at least between two clips (sim time)
const POLL = 2.0              # s between two looks for newly opened pages (wall time)

struct Voice <: System end

"Every open page of the game (each browser has its own session; an app only remembers the newest one)."
function sessions!(game)
    ss = get!(() -> Any[], VO, :sessions)
    time() - get(VO, :polled, 0.0) < POLL && return filter!(s -> isopen(s), ss)
    VO[:polled] = time()
    web = game.web
    web === nothing && return ss
    for r in web.server.routes.table
        app = r[2]
        app isa Bonito.App || continue
        s = app.session[]
        if s !== nothing && !any(x -> x === s, ss)
            push!(ss, s)
            isopen(s) && hint!(s)
        end
    end
    return filter!(s -> isopen(s), ss)
end

"""
A small note on a newly opened page: browsers play sound only after the player clicks or presses a key there, and
nothing said so (review s81). It goes away at the first click or key press, which is also what lets the sound play.
"""
function hint!(s)
    Bonito.evaljs(s, Bonito.js"""
        try {
            if (!window.lumiHint) {
                window.lumiHint = true;
                const d = document.createElement('div');
                d.textContent = 'Click once on the island to hear Lumi';
                d.style.cssText = 'position:fixed;top:10px;left:50%;transform:translateX(-50%);padding:6px 14px;' +
                    'background:rgba(25,25,35,0.85);color:#ffd27a;font:15px sans-serif;border-radius:8px;z-index:9999;pointer-events:none;';
                document.body.appendChild(d);
                const off = () => { d.remove(); window.removeEventListener('pointerdown', off, true); window.removeEventListener('keydown', off, true); };
                window.addEventListener('pointerdown', off, true);
                window.addEventListener('keydown', off, true);
            }
        } catch (e) { console.log('lumi hint:', e); }
    """)
end

"Play clip `name` in every open page (browsers only allow it once the player has clicked on the page)."
function say!(game, name::AbstractString)
    url = "/lumi/voice/game/" * name * ".mp3"
    push!(get!(() -> Tuple{Float64,String}[], VO, :log), (game.world.t, String(name)))
    length(VO[:log]) > 200 && popfirst!(VO[:log])
    for s in sessions!(game)
        Bonito.evaljs(s, Bonito.js"""
            const a = new Audio($(url)); a.volume = 0.7;
            a.play().catch(e => console.log('lumi voice:', e.name));
            window.lumiVoiceCount = (window.lumiVoiceCount || 0) + 1;
        """)
    end
end

"Friends squeak (a pitched-up voice) as the Big Boing toadstool shoots them up (boing.jl flights going :hop -> :fly)."
function squeaks!(game)
    bp = get(game.plugins, "boing", nothing)
    (bp === nothing || isempty(bp.systems)) && return
    fl = only(bp.systems).flights
    seen = get!(() -> Dict{Int32,Symbol}(), VO, :flights)
    w = game.world
    for (id, f) in fl
        before = get(seen, id, :none)
        seen[id] = f.stage
        if f.stage === :fly && before !== :fly && w.t - get(VO, :squeaked, -Inf) > 0.7
            VO[:squeaked] = w.t
            say!(game, ("squeak-wheee", "squeak-yay", "squeak-hoo")[mod1(Int(id), 3)])
        end
    end
    filter!(((id, _),) -> haskey(fl, id), seen)
end

"The swing's rider shouts as it flies off over the top bar (swing.jl going :loop -> :fly): Lumi in its own voice, a friend squeaks."
function swing_shout!(game)
    sw = isdefined(Main, :SWING) ? get(Main.SWING, :sys, nothing) : nothing
    sw === nothing && return
    before = get(VO, :swing, :idle)
    VO[:swing] = sw.state
    (sw.state === :fly && before !== :fly) || return
    r = NG.creature(game.world, sw.rider)
    r === nothing && return
    say!(game, r.name == "Lumi" ? "wheee" : "squeak-wheee")
end

function NG.step!(::Voice, game, dt)
    squeaks!(game)
    swing_shout!(game)
    w = game.world
    i = findfirst(c -> c.name == "Lumi", w.creatures)
    i === nothing && return
    me = w.creatures[i]
    a = me.action
    last = get(VO, :last, :idle)
    VO[:last] = a
    a === last && return
    clips = get(SAYS, a, nothing)
    (clips === nothing || w.t - get(VO, :said, -Inf) < GAP) && return
    VO[:said] = w.t
    say!(game, clips[rand(w.rng, 1:length(clips))])
end

NG.start!(::Voice, game) = (VO[:last] = :idle; VO[:said] = -Inf; nothing)

register!(Voice())
