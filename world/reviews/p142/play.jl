# Reviewer 0142: play every mini game for about a minute through interact!, then the jar and chip stone by hand.
# Runs inside the sandbox as a one-test run (wait_frames needs a TestRun), started from live_eval.
const NG = NeverendingGame
const FI = NG.fake_interaction().FakeInteraction
const K = NG.Makie.Keyboard
const SHOTS = "/sim/Programmieren/SimGame/world/reviews/p142/play"
mkpath(SHOTS)
const LOG = String[]
note(s) = (push!(LOG, s); write(joinpath(SHOTS, "log.txt"), join(LOG, "\n")); nothing)

shot(game, name) = try
    NG.Makie.save(joinpath(SHOTS, name * ".png"), NG.Makie.colorbuffer(game.screen))
catch e
    note("shot $name failed: " * first(sprint(showerror, e), 200))
end
viewtexts(game) = try
    join(unique([strip(string(p.text[])) for p in NG.Makie.collect_atomic_plots(game.dash.view.scene)
                 if p isa NG.Makie.Text && p.visible[] && !isempty(strip(string(p.text[])))]), " | ")
catch; "?" end

ia(game, evs) = NG.interact!(game, evs)
function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    ia(game, Any[FI.MouseTo(NG.ui_pos(game, name)), FI.LeftClick(), FI.Wait(0.3),
                 FI.Lazy(_ -> FI.MouseTo(NG.ui_option_pos(game, name, option))), FI.LeftClick(), FI.Wait(0.2)])
end
click(game, name) = ia(game, Any[FI.MouseTo(NG.ui_pos(game, name)), FI.LeftClick(), FI.Wait(0.3)])
key(k; d = 0.15) = FI.KeyPress(k; duration = d)
score(game) = (m = game.minigame; m === nothing ? "-" : hasproperty(m, :score) ? string(m.score) : "?")

function wander(game, seconds; extra = K.Button[])
    t = 0.0; i = 0
    while t < seconds && game.minigame !== nothing
        i += 1
        evs = Any[key(K.w; d = 1.6), key(isodd(i) ? K.a : K.d; d = 0.35)]
        isempty(extra) || push!(evs, key(extra[mod1(i, length(extra))]))
        push!(evs, FI.Wait(0.2))
        ia(game, evs)
        t += 2.4
    end
end

function play_one(game, option, tag; extra = K.Button[])
    t0 = time()
    choose(game, option); click(game, "Play"); NG.wait_seconds(game, 1.0)
    shot(game, tag * "-0-start")
    note("$option: started $(typeof(game.minigame)); on screen: $(viewtexts(game))")
    for j in 1:4
        game.minigame === nothing && (note("$option: ended by itself after $(round(time()-t0)) s"); break)
        wander(game, 15; extra)
        shot(game, tag * "-$(j)")
        note("$option: t=$(round(time()-t0)) s score $(score(game)); on screen: $(first(viewtexts(game), 400))")
    end
    game.minigame === nothing || click(game, "Stop")
end

function review_play(game)
    opts = string.(game.dash.play_menu.options[])
    note("options: " * join(opts, " | "))
    for o in opts
        tag = lowercase(replace(first(split(o, " (")), r"[^A-Za-z]" => ""))
        try
            play_one(game, o, tag; extra = startswith(o, "Jump in") ?
                     [K.e, K.x, K.c, K.l, K.r, K.h, K.b, K.o] : [K.e])
        catch e
            note("$o: ERROR " * first(sprint(showerror, e), 400))
            game.minigame === nothing || try click(game, "Stop") catch end
        end
    end
    # the new jar and the chip stone, by hand in Jump in
    try
        ji = findfirst(startswith("Jump in"), opts)
        if ji !== nothing
            choose(game, opts[ji]); click(game, "Play"); NG.wait_seconds(game, 1)
            me = NG.creature(game.world, "Lumi")
            me.pos = NG.Point3f(4.0, -15.6, me.pos[3]); NG.wait_seconds(game, 0.8)
            shot(game, "jar-0"); note("by the jar: $(viewtexts(game))")
            ia(game, Any[key(K.l), FI.Wait(1.2)]); shot(game, "jar-knock"); note("L by the jar: $(viewtexts(game))")
            me.pos = NG.Point3f(4.0, -15.0, me.pos[3]); NG.wait_seconds(game, 0.5)
            for k in 1:2
                ia(game, Any[key(K.r), FI.Wait(1.2)]); shot(game, "chip-r$k")
                ia(game, Any[key(K.l), FI.Wait(1.2)])
            end
            note("chip: $(viewtexts(game))")
            click(game, "Stop")
        else
            note("no Jump in in the menu")
        end
    catch e
        note("jar/chip: ERROR " * first(sprint(showerror, e), 400))
        game.minigame === nothing || try click(game, "Stop") catch end
    end
    note("finished")
end

function start_review!(game)
    t = NG.UITest("review 0142 play", "", review_play)
    run = NG.TestRun([t], Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 1500.0, nothing)
    game.tests = run
    run.task = @async begin
        run.current = t.name; run.test_started = time()
        try
            Base.invokelatest(review_play, game)
        catch e
            note("TOP ERROR " * first(sprint(showerror, e, catch_backtrace()), 1500))
        end
        game.minigame === nothing || NG.stop_minigame!(game)
        run.current = ""
    end
    "started"
end
