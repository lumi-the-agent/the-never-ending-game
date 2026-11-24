# Perfectionist review s70: play every mini game for a minute like a person (W/A/D, then R), and the camera menu.
const R = "/sim/Programmieren/SimGame/world/reviews/p70"
const LOG = String[]
note(s) = (push!(LOG, s); open(io -> println(io, s), joinpath(R, "play-log.txt"), "a"))
shot(game, name) = (game.screen === nothing || Makie.save(joinpath(R, name * ".png"), Makie.colorbuffer(game.screen)); name)
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
function choose(game, menuname_prefix, option)
    el = ui_find(game, menuname_prefix)
    name = el.name
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.3)])
end
pick_game(game, option) = (m = game.dash.play_menu; choose(game, m.selection[] === nothing ? string(m.prompt[]) : string(m.selection[]), option))
pitch(game) = (d = game.rig.target - game.rig.eye; rad2deg(atan(-d[3], hypot(d[1], d[2]))))

function steer(game, target_of, seconds; shots = String[], every = 15.0)
    c = creature(game.world, "Lumi"); K = Keyboard
    interact!(game, [KeyDown(K.w)])
    held = nothing; t0 = time(); next = every; k = 0; maxp = 0.0
    while time() - t0 < seconds
        maxp = max(maxp, pitch(game))
        if time() - t0 > next && k < length(shots)
            k += 1; shot(game, shots[k]); next += every
        end
        p = target_of()
        p === nothing && break
        d = NeverendingGame.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
        want = abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
        if want !== held
            held === nothing || interact!(game, [KeyUp(held)])
            want === nothing || interact!(game, [KeyDown(want)])
            held = want
        end
        interact!(game, [Wait(0.1)])
    end
    held === nothing || interact!(game, [KeyUp(held)])
    interact!(game, [KeyUp(K.w), Wait(0.1)])
    return (round(time() - t0; digits = 1), round(maxp; digits = 1))
end
cardtext(P) = haskey(P, :card) ? replace(string(P[:card].text[]), '\n' => " | ") : "?"
hudtext(P) = haskey(P, :hud) ? replace(string(P[:hud].text[]), '\n' => " | ") : "?"

uitest("REVIEW camera modes") do game
    for (i, m) in enumerate(["Camera: follow", "Camera: orbit", "Camera: free"])
        choose(game, "Camera", m); wait_seconds(game, 3); shot(game, "cam-$(i)a")
        wait_seconds(game, 5); shot(game, "cam-$(i)b")
        note("camera $m: rig.mode $(game.rig.mode) eye $(round.(game.rig.eye; digits=1)) pitch $(round(pitch(game); digits=1))")
    end
    choose(game, "Camera", "Camera: follow")
end

uitest("REVIEW firefly catch, one minute") do game
    pick_game(game, "Firefly catch (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    wait_seconds(game, 1); shot(game, "ff-start")
    P = Main.FIREFLY_PLOTS
    note("firefly start card: $(cardtext(P))")
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    nearest() = (m.state === :over ? nothing : (free = findall(!, m.caught); isempty(free) ? nothing : fly(free[argmin([hypot(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2]) for i in free])])))
    r = steer(game, nearest, 62; shots = ["ff-15", "ff-30", "ff-45"])
    wait_seconds(game, 1.5); shot(game, "ff-end")
    note("firefly: score $(m.score)/$(length(m.flies)) state $(m.state) t $(round(m.t; digits=1)) played $(r[1]) s, max pitch $(r[2]); card: $(cardtext(P)); hud $(hudtext(P))")
    interact!(game, [KeyPress(Keyboard.r), Wait(1.0)]); shot(game, "ff-replay")
    note("firefly after R: state $(game.minigame === nothing ? "none" : game.minigame.state) card $(cardtext(P))")
    click(game, "Stop")
end

uitest("REVIEW hide and seek, one minute") do game
    pick_game(game, "Hide and seek (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    P = Main.HIDESEEK_PLOTS
    wait_seconds(game, 1); shot(game, "hs-start")
    note("hideseek start card: $(cardtext(P))")
    target() = (m.state === :over || all(m.found)) ? nothing : something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    r = steer(game, target, 62; shots = ["hs-15", "hs-30", "hs-45"])
    wait_seconds(game, 1.5); shot(game, "hs-end")
    note("hideseek: found $(count(m.found))/$(length(m.found)) state $(m.state) t $(round(m.t; digits=1)) played $(r[1]) s, max pitch $(r[2]); card: $(cardtext(P)); hud $(hudtext(P))")
    interact!(game, [KeyPress(Keyboard.r), Wait(1.0)]); shot(game, "hs-replay")
    click(game, "Stop")
end

uitest("REVIEW berry race, one minute") do game
    pick_game(game, "Berry race (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    P = Main.BERRY_PLOTS
    wait_seconds(game, 1); shot(game, "br-start")
    note("berry start card: $(cardtext(P)) level $(get(P, :level, "?"))")
    nearest() = m.state === :over ? nothing : (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    r = steer(game, nearest, 62; shots = ["br-15", "br-30", "br-45"])
    wait_seconds(game, 1.5); shot(game, "br-end")
    note("berry: me $(m.score) critters $(m.rival_score) state $(m.state) t $(round(m.t; digits=1)) played $(r[1]) s, max pitch $(r[2]); card: $(cardtext(P)); hud $(hudtext(P))")
    interact!(game, [KeyPress(Keyboard.r), Wait(1.0)]); shot(game, "br-replay")
    click(game, "Stop")
end

uitest("REVIEW jump in: every key") do game
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    click(game, "Play")
    note("jump in: $(typeof(game.minigame))")
    c = creature(game.world, "Lumi"); K = Keyboard
    interact!(game, [KeyPress(K.w; duration = 2.0)]); shot(game, "ji-walk")
    for (k, name, secs) in [(K.e, "wave", 3), (K.space, "hop", 2), (K.x, "sneeze", 8), (K.h, "hiccups", 8),
                            (K.c, "choir", 25), (K.p, "paint", 20), (K.g, "fly", 18), (K.m, "giant", 20)]
        interact!(game, [KeyPress(k), Wait(1.5)])
        shot(game, "ji-$(name)-a")
        wait_seconds(game, secs / 2); shot(game, "ji-$(name)-b")
        wait_seconds(game, secs / 2)
        speech = [hasproperty(s, :text) ? s.text : s for s in game.world.speech]
        note("jump $name: Lumi action $(c.action) goal $(c.goal.kind) pos $(round.(c.pos; digits=1)) pitch $(round(pitch(game); digits=1)) speech $(first(string(speech), 300))")
    end
    click(game, "Stop")
end
