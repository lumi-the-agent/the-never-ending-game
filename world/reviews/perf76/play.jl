# Perfectionist review s76: play every mini game for about a minute through interact!, and the camera modes.
# Loaded in the sandbox with Base.include(Main, this file); runs as a TestRun of its own.
module ReviewPlay76
const NG = Main.NeverendingGame
const DIR = "/sim/Programmieren/SimGame/world/reviews/perf76/play"
mkpath(DIR)
mod = Module(:ReviewHelpers76)
Core.eval(mod, NG.PLUGIN_IMPORTS)
FI = NG.fake_interaction()
Core.eval(mod, :(using NeverendingGame: uitest, check, wait_frames, wait_seconds, screenshot, creature,
                       interact!, ui_pos, ui_option_pos, ui_elements, ui_find))
Core.eval(mod, :(using $(nameof(parentmodule(FI))).FakeInteraction))
junk = NG.UITest[]
Base.ScopedValues.with(NG.LOADING_TESTS => junk) do
    Base.include(mod, "/sim/Programmieren/SimGame/world/tests/minigames.jl")
end
const H = mod
const LOG = String[]
say(x...) = push!(LOG, string(x...))
shot(game, name) = (NG.Makie.save(joinpath(DIR, name * ".png"), NG.Makie.colorbuffer(game.screen)); name)

const K = NG.Makie.Keyboard

function cam(game, label)
    H.interact!(game, [H.MouseTo(H.ui_pos(game, camlabel(game))), H.LeftClick(), H.Wait(0.3),
                       H.Lazy(_ -> H.MouseTo(H.ui_option_pos(game, camlabel(game), label))), H.LeftClick(), H.Wait(0.3)])
end

camlabel(game) = string(only(b for b in game.dash.fig.content if b isa NG.Makie.Menu && "Camera: follow" in b.options[]).selection[])

function play(game, option, target_of, tag; seconds = 60)
    H.fly_choose(game, option)
    H.fly_click(game, "Play")
    m = game.minigame
    say(tag, ": started ", typeof(m))
    H.wait_frames(game, 8); shot(game, tag * "-0start")
    c = H.creature(game.world, "Lumi")
    t0 = time(); k = 1
    while time() - t0 < seconds
        H.steer_wad(game, () -> target_of(m, c), 12)
        shot(game, tag * "-$(k)"); k += 1
        say(tag, " t=", round(time() - t0; digits = 1), " ", hud(m))
        m.state === :over && break
    end
    H.wait_seconds(game, 1.5); shot(game, tag * "-end")
    say(tag, " end: ", hud(m))
    # R: a second round, how it starts
    H.interact!(game, [H.KeyPress(K.r), H.Wait(1.0)])
    shot(game, tag * "-again")
    say(tag, " after R: ", hud(game.minigame))
    H.fly_click(game, "Stop")
end

function hud(m)
    m === nothing && return "no game"
    s = String[]
    for f in (:score, :state, :t, :level, :found, :caught)
        hasproperty(m, f) && push!(s, "$f=$(getproperty(m, f))")
    end
    join(s, " ")
end

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

berry_target(m, c) = (fr = [b for b in m.berries if b.taken == 0]; isempty(fr) ? nothing : fr[argmin([flat(b.foot, c.pos) for b in fr])].foot)
function review(game)
    w = game.world
    # cameras
    for (lab, tag) in (("Camera: follow", "cam-follow"), ("Camera: orbit", "cam-orbit"), ("Camera: free", "cam-free"))
        cam(game, lab)
        for i in 1:3
            H.wait_seconds(game, 4); shot(game, "$tag-$i")
        end
        say(tag, " rig ", game.rig.mode, " pitch ", round(H.rig_pitch(game); digits = 1))
    end
    # free camera: fly with W, turn with A
    H.interact!(game, [H.KeyPress(K.w; duration = 2.0), H.KeyPress(K.a; duration = 1.0), H.Wait(0.5)])
    shot(game, "cam-free-flown")
    cam(game, "Camera: follow")
    # mini games
    play(game, "Berry race (WASD)", berry_target, "berry")
    play(game, "Firefly catch (WASD)", (m, c) -> begin
            M = parentmodule(typeof(m)); free = findall(!, m.caught)
            isempty(free) ? nothing : (ps = [M.fly_pos(m.flies[i], game.world.t, i) for i in free]; ps[argmin([flat(p, c.pos) for p in ps])])
        end, "firefly")
    play(game, "Hide and seek (WASD)", (m, c) -> begin
            M = parentmodule(typeof(m))
            something(Base.invokelatest(M.hint_spot, m, c), Base.invokelatest(M.hint_spot, m, c; heard_only = false), Some(nothing))
        end, "hideseek"; seconds = 90)
    # jump in: walk, then every gag key
    H.fly_choose(game, "Jump in (WASD)")
    H.fly_click(game, "Play")
    H.wait_seconds(game, 1); shot(game, "jump-0")
    H.interact!(game, [H.KeyPress(K.w; duration = 3.0), H.KeyPress(K.d; duration = 0.6), H.KeyPress(K.w; duration = 2.0)])
    shot(game, "jump-walk")
    for (key, tag) in ((K.e, "E"), (K.e, "E2"), (K.space, "space"), (K.x, "X"), (K.h, "H"), (K.c, "C"), (K.p, "P"), (K.g, "G"))
        H.interact!(game, [H.KeyPress(key; duration = 0.15), H.Wait(1.2)])
        shot(game, "jump-$tag")
        me = H.creature(game.world, "Lumi")
        say("jump ", tag, ": Lumi ", me.action, " goal ", me.goal.kind, " speech ", join([s.text for s in game.world.speech if s.who == me.id], " | "))
        H.wait_seconds(game, tag == "G" ? 6 : 3)
        shot(game, "jump-$tag-later")
    end
    H.wait_seconds(game, 8); shot(game, "jump-G-end")
    H.fly_click(game, "Stop")
end

function start!(game)
    empty!(LOG)
    t = NG.UITest("perfectionist review play s76", "review", g -> review(g))
    run = NG.TestRun([t], Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 900.0, nothing)
    game.tests = run
    run.task = @async begin
        game.minigame === nothing || NG.stop_minigame!(game)
        err = try
            Base.invokelatest(t.f, game); ""
        catch e
            sprint(showerror, e, catch_backtrace())
        end
        push!(run.results, Dict{String,Any}("name" => t.name, "passed" => isempty(err), "error" => first(err, 3000)))
        game.minigame === nothing || NG.stop_minigame!(game)
        write(joinpath(DIR, "log.txt"), join(LOG, "\n") * "\n\nERROR: " * err)
    end
    return "started"
end
end
