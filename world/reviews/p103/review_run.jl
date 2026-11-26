# Perfectionist review s103: play every mini game for a minute through FakeInteraction,
# try the jump-in keys and every camera mode, with screenshots. Runs as a test run in the sandbox.
using NeverendingGame.FakeInteraction
const NG = NeverendingGame
const K = NG.Makie.Keyboard
const DIR = "/sim/Programmieren/SimGame/world/reviews/p103/play"
const LOG = Dict{String,Any}[]

note!(d...) = (push!(LOG, Dict{String,Any}(string(k) => string(v) for (k, v) in d)); NG.write_json(joinpath(DIR, "play.json"), LOG))
shot(game, name) = NG.Makie.save(joinpath(DIR, name * ".png"), NG.Makie.colorbuffer(game.screen))
texts(game) = [string(p.text[]) for p in NG.Makie.collect_atomic_plots(game.dash.view.scene) if p isa NG.Makie.Text && p.visible[] && !isempty(strip(string(p.text[])))]

function helpers(game)
    tests = NG.load_uitests(game.paths)
    t = only(filter(t -> startswith(t.name, "Firefly catch: a first play"), tests))
    tm = parentmodule(t.f)
    late(f) = (a...) -> Base.invokelatest(f, a...)
    return late(getglobal(tm, :steer_wad)), late(getglobal(tm, :fly_choose)), late(getglobal(tm, :fly_click))
end

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

function play_for(game, steer, target, seconds, tag, m)
    t0 = time()
    k = 0
    while time() - t0 < seconds
        steer(game, target, 15)
        k += 1
        shot(game, "$(tag)-$(k)")
        note!(:game => tag, :t => round(time() - t0), :score => hasproperty(m, :score) ? m.score : "",
              :rival => hasproperty(m, :rival_score) ? m.rival_score : "", :state => hasproperty(m, :state) ? m.state : "",
              :texts => join(first(texts(game), 8), " | "))
        target() === nothing && break
    end
end

function firefly(game)
    steer, choose, click = helpers(game)
    choose(game, "Firefly catch (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = NG.creature(game.world, "Lumi")
    interact!(game, [Wait(1.0)]); shot(game, "firefly-0-start")
    note!(:game => "firefly", :start_texts => join(texts(game), " | "))
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    near() = (free = findall(!, m.caught); isempty(free) ? nothing : fly(free[argmin([flat(fly(i), c.pos) for i in free])]))
    play_for(game, steer, near, 62, "firefly", m)
    interact!(game, [Wait(2.0)]); shot(game, "firefly-9-end")
    note!(:game => "firefly", :end_score => m.score, :state => m.state, :end_texts => join(texts(game), " | "))
    interact!(game, [KeyPress(K.r), Wait(1.5)]); shot(game, "firefly-9-replay")
    note!(:game => "firefly", :after_R => string(typeof(game.minigame)), :texts => join(texts(game), " | "))
    click(game, "Stop")
end

function hideseek(game)
    steer, choose, click = helpers(game)
    choose(game, "Hide and seek (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = NG.creature(game.world, "Lumi")
    interact!(game, [Wait(1.0)]); shot(game, "hideseek-0-start")
    note!(:game => "hideseek", :start_texts => join(texts(game), " | "))
    target() = all(m.found) ? nothing : something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    play_for(game, steer, target, 62, "hideseek", m)
    interact!(game, [Wait(2.0)]); shot(game, "hideseek-9-end")
    note!(:game => "hideseek", :found => count(m.found), :of => length(m.found), :t => m.t, :state => m.state, :end_texts => join(texts(game), " | "))
    click(game, "Stop")
end

function berry(game)
    steer, choose, click = helpers(game)
    choose(game, "Berry race (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = NG.creature(game.world, "Lumi")
    interact!(game, [Wait(1.0)]); shot(game, "berry-0-start")
    note!(:game => "berry", :start_texts => join(texts(game), " | "))
    near() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    play_for(game, steer, near, 62, "berry", m)
    interact!(game, [Wait(2.0)]); shot(game, "berry-9-end")
    note!(:game => "berry", :end_score => m.score, :rival => m.rival_score, :state => m.state, :end_texts => join(texts(game), " | "))
    click(game, "Stop")
end

function jumpin(game)
    steer, choose, click = helpers(game)
    game.dash.play_menu.i_selected[] = 0
    interact!(game, [Wait(0.1)]); click(game, "Play")
    c = NG.creature(game.world, "Lumi")
    interact!(game, [Wait(1.0)]); shot(game, "jump-0")
    for (key, name) in ((K.e, "E"), (K.space, "Space"), (K.g, "G"), (K.t, "T"), (K.x, "X"), (K.h, "H"), (K.b, "B"), (K.v, "V"), (K.p, "P"), (K.c, "C"), (K.z, "Z"))
        p0 = c.pos
        interact!(game, [KeyPress(key; duration = 0.15), Wait(0.6), KeyDown(K.w), Wait(1.5), KeyUp(K.w), Wait(1.0)])
        shot(game, "jump-$(name)")
        note!(:game => "jumpin", :key => name, :moved => round(flat(c.pos, p0); digits = 1), :action => c.action, :goal => c.goal.kind,
              :z => round(c.pos[3]; digits = 2), :texts => join(first(texts(game), 6), " | "))
        interact!(game, [Wait(4.0)])
    end
    click(game, "Stop")
end

function cameras(game)
    for choice in ("Camera: follow", "Camera: orbit", "Camera: free")
        NG.set_camera!(game, choice)
        for k in 1:3
            interact!(game, [Wait(5.0)])
            shot(game, "cam-$(split(choice)[end])-$(k)")
        end
        note!(:camera => choice, :mode => game.rig.mode, :eye => game.rig.eye, :target => game.rig.target)
    end
    NG.set_camera!(game, "Camera: follow")
end

function start!(game)
    mkpath(DIR); empty!(LOG)
    tests = [NG.UITest(n, "review", f) for (n, f) in (("review firefly", firefly), ("review hideseek", hideseek),
                                                      ("review berry", berry), ("review jumpin", jumpin), ("review cameras", cameras))]
    run = NG.TestRun(tests, Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 200.0, nothing)
    game.tests = run
    run.task = @async begin
        for t in run.tests
            run.current = t.name; run.test_started = time()
            game.minigame === nothing || NG.stop_minigame!(game)
            err = try
                Base.invokelatest(t.f, game); ""
            catch e
                sprint(showerror, e, catch_backtrace())
            end
            push!(run.results, Dict{String,Any}("name" => t.name, "passed" => isempty(err), "seconds" => round(time() - run.test_started; digits = 1), "error" => first(err, 2000)))
            game.minigame === nothing || NG.stop_minigame!(game)
        end
        run.current = ""
    end
    return "started"
end
