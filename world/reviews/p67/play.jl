# Perfectionist review s67: play every mini game like a person through FakeInteraction.
module ReviewPlay
using NeverendingGame
const NG = NeverendingGame
using NeverendingGame: interact!, ui_pos, ui_option_pos, creature
using NeverendingGame.FakeInteraction
using Makie, LinearAlgebra, GeometryBasics

const DIR = "/sim/Programmieren/SimGame/world/reviews/p67"
const LOG = String[]
note(s) = (push!(LOG, string(round(time(); digits = 1) % 10000, "  ", s)); nothing)
shot(game, name) = (Makie.save(joinpath(DIR, "play-" * name * ".png"), Makie.colorbuffer(game.screen)); note("shot $name"))

click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
function choose(game, menuname, option)
    interact!(game, [MouseTo(ui_pos(game, menuname)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, menuname, option))), LeftClick(), Wait(0.3)])
end
current_menu(game) = (m = game.dash.play_menu; m.selection[] === nothing ? string(m.prompt[]) : string(m.selection[]))

function steer(game, target_of, seconds; every = 15.0, tag = "x", hud = () -> "")
    c = creature(game.world, "Lumi")
    K = Keyboard
    interact!(game, [KeyDown(K.w)])
    held = nothing
    t0 = time(); nexts = t0 + every; k = 0
    while time() - t0 < seconds
        p = target_of()
        p === nothing && break
        d = NG.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
        want = abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
        if want !== held
            held === nothing || interact!(game, [KeyUp(held)])
            want === nothing || interact!(game, [KeyDown(want)])
            held = want
        end
        interact!(game, [Wait(0.1)])
        if time() > nexts
            k += 1; shot(game, "$(tag)-$(k)"); note("$tag t=$(round(time() - t0)) s: $(hud())")
            nexts += every
        end
    end
    held === nothing || interact!(game, [KeyUp(held)])
    interact!(game, [KeyUp(K.w), Wait(0.1)])
end

function card_text(P)
    for k in (:card, :hud, :score)
        haskey(P, k) && P[k] !== nothing && try
            return string(k, "=", replace(P[k].text[], '\n' => " | "))
        catch
        end
    end
    return ""
end

function firefly(game)
    choose(game, current_menu(game), "Firefly catch (WASD)")
    click(game, "Play"); m = game.minigame; note("firefly started: $(typeof(m))")
    interact!(game, [Wait(1.0)]); shot(game, "firefly-card")
    mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    nearest() = (free = findall(!, m.caught); isempty(free) ? nothing :
                 fly(free[argmin([norm(Vec2f(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2])) for i in free])]))
    steer(game, nearest, 70; tag = "firefly", hud = () -> "score $(m.score) state $(m.state)")
    interact!(game, [Wait(1.5)]); shot(game, "firefly-end")
    note("firefly end: score $(m.score) state $(m.state)")
    interact!(game, [KeyPress(Keyboard.r), Wait(1.0)]); shot(game, "firefly-again")
    note("firefly after R: $(game.minigame === nothing ? "none" : string(getfield(game.minigame, :state)))")
    click(game, "Stop")
end

function berry(game)
    P = Main.BERRY_PLOTS
    choose(game, current_menu(game), "Berry race (WASD)")
    click(game, "Play"); m = game.minigame; note("berry started: $(typeof(m)) level $(get(P, :level, nothing))")
    interact!(game, [Wait(1.0)]); shot(game, "berry-card"); note("berry card: $(card_text(P))")
    mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    nearest() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) || m.state === :over ? nothing :
                 free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    steer(game, nearest, 70; tag = "berry", hud = () -> "me $(m.score) critters $(m.rival_score) state $(m.state)")
    interact!(game, [Wait(1.5)]); shot(game, "berry-end")
    note("berry end: me $(m.score) critters $(m.rival_score) state $(m.state) $(card_text(P))")
    click(game, "Stop")
end

function hide(game)
    P = Main.HIDESEEK_PLOTS
    choose(game, current_menu(game), "Hide and seek (WASD)")
    click(game, "Play"); m = game.minigame; note("hide started: $(typeof(m))")
    interact!(game, [Wait(1.0)]); shot(game, "hide-card")
    mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    target() = all(m.found) ? nothing : something(Base.invokelatest(mod.hint_spot, m, c),
                                                 Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    steer(game, target, 75; tag = "hide", hud = () -> "found $(count(m.found)) t $(round(m.t)) hud $(replace(P[:hud].text[], '\n' => ' '))")
    interact!(game, [Wait(1.5)]); shot(game, "hide-end")
    w = game.world
    lag = [round(mod.flat(creature(w, id).pos, c.pos); digits = 1) for (k, id) in enumerate(m.hiders) if m.found[k]]
    note("hide end: found $(count(m.found)) of $(length(m.hiders)) followers at $(lag) m, card $(card_text(P))")
    click(game, "Stop")
end

function jumpin(game)
    choose(game, current_menu(game), "Jump in (WASD)")
    click(game, "Play"); note("jump in: $(typeof(game.minigame))")
    interact!(game, [Wait(1.0)]); shot(game, "jump-0")
    interact!(game, [KeyPress(Keyboard.w; duration = 3.0), KeyPress(Keyboard.a; duration = 0.6), KeyPress(Keyboard.w; duration = 2.0)])
    shot(game, "jump-walk")
    for (k, name) in ((Keyboard.e, "e"), (Keyboard.e, "e2"), (Keyboard.space, "space"), (Keyboard.x, "x"),
                      (Keyboard.h, "h"), (Keyboard.c, "c"), (Keyboard.g, "g"))
        interact!(game, [KeyPress(k), Wait(name in ("x", "g", "c") ? 4.0 : 1.5)])
        shot(game, "jump-" * name)
        l = creature(game.world, "Lumi")
        note("jump $name: lumi action $(l.action) speech $(get(game.world.speech, l.id, nothing))")
    end
    interact!(game, [Wait(8.0)]); shot(game, "jump-late")
    click(game, "Stop")
end

function cameras(game)
    for opt in ("Camera: orbit", "Camera: free", "Camera: follow")
        name = string(only(b for b in game.dash.fig.content if b isa Makie.Menu && "Camera: follow" in b.options[]).selection[])
        choose(game, name, opt)
        interact!(game, [Wait(3.0)]); shot(game, "cam-" * split(opt)[2] * "-a")
        if opt == "Camera: free"
            interact!(game, [KeyPress(Keyboard.w; duration = 1.5), KeyPress(Keyboard.r; duration = 0.8)])
        end
        interact!(game, [Wait(4.0)]); shot(game, "cam-" * split(opt)[2] * "-b")
    end
end

function go!(game)
    empty!(LOG)
    parts = [("cameras", cameras), ("firefly", firefly), ("berry", berry), ("hide", hide), ("jumpin", jumpin)]
    tests = [NG.UITest("review: " * n, "review", g -> (try f(g) catch e
        note("$(n) ERROR " * first(sprint(showerror, e, catch_backtrace()), 1500))
        game.minigame === nothing || NG.stop_minigame!(g)
    end)) for (n, f) in parts]
    run = NG.TestRun(tests, Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 900.0, nothing)
    game.tests = run
    run.task = @async begin
        for t in run.tests
            run.current = t.name; run.test_started = time()
            game.minigame === nothing || NG.stop_minigame!(game)
            Base.invokelatest(t.f, game)
            push!(run.results, Dict{String,Any}("name" => t.name, "passed" => true, "seconds" => round(time() - run.test_started), "error" => ""))
        end
        run.current = ""
        write(joinpath(DIR, "play-log.txt"), join(LOG, "\n"))
    end
    return "started"
end
end
