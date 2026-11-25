# Perfectionist review 0082: play every mini game for about a minute like a person (FakeInteraction).
const NG = NeverendingGame
const OUT = "/sim/Programmieren/SimGame/world/reviews/p82/play"
mkpath(OUT)
isdefined(Main, :REVIEW_LOG) || Core.eval(Main, :(const REVIEW_LOG = String[]))
note(s) = (push!(Main.REVIEW_LOG, s); nothing)
shot(game, name) = (Makie.save(joinpath(OUT, name * ".png"), Makie.colorbuffer(game.screen)); note("shot $name"))
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.2)])
function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end
press(game, k; hold = 0.15) = interact!(game, [KeyDown(k), Wait(hold), KeyUp(k), Wait(0.1)])
cardtext(P) = haskey(P, :card) ? replace(string(P[:card].text[]), "\n" => " / ") : "-"
hudtext(P) = haskey(P, :hud) ? replace(string(P[:hud].text[]), "\n" => " / ") : "-"

"Steer like a person for `seconds`: W held, A/D towards `target_of()` (or wander if nothing), Shift bursts."
function steer(game, target_of, seconds; tag = "", every = 10, P = nothing, run = true)
    c = creature(game.world, "Lumi"); K = Keyboard
    interact!(game, [KeyDown(K.w)])
    held = nothing; t0 = time(); last = -every; shifted = false
    while time() - t0 < seconds
        el = time() - t0
        if el - last >= every
            last = el
            shot(game, "$(tag)-$(round(Int, el))")
            P === nothing || note("$tag t=$(round(Int, el)) hud: $(hudtext(P)) | card: $(cardtext(P)) | lumi $(round.(c.pos; digits = 1)) $(c.action)")
        end
        if run && !shifted && el > 3
            interact!(game, [KeyDown(K.left_shift)]); shifted = true
        elseif run && shifted && el > 8 && mod(el, 10) < 0.2
            interact!(game, [KeyUp(K.left_shift)]); shifted = false
        end
        p = target_of()
        want = if p === nothing
            mod(el, 6) < 1 ? K.a : nothing
        else
            d = NG.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
            abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
        end
        if want !== held
            held === nothing || interact!(game, [KeyUp(held)])
            want === nothing || interact!(game, [KeyDown(want)])
            held = want
        end
        interact!(game, [Wait(0.1)])
    end
    held === nothing || interact!(game, [KeyUp(held)])
    shifted && interact!(game, [KeyUp(K.left_shift)])
    interact!(game, [KeyUp(K.w), Wait(0.1)])
end

uitest("review: berry race for a minute") do game
    P = Main.BERRY_PLOTS
    choose(game, "Berry race (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    wait_frames(game, 10); shot(game, "berry-card")
    note("berry start card: $(cardtext(P)) | level $(get(P, :level, nothing))")
    nearest() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    steer(game, nearest, 45; tag = "berry", P)
    note("berry after 45 s: me $(m.score) critters $(m.rival_score) state $(m.state) | card $(cardtext(P))")
    wait_seconds(game, 2); shot(game, "berry-end")
    press(game, Keyboard.r); wait_frames(game, 10)
    note("berry after R: state $(game.minigame === nothing ? nothing : game.minigame.state) card $(cardtext(P)) level $(get(P, :level, nothing))")
    shot(game, "berry-again")
    m2 = game.minigame
    m2 === nothing || (m = m2; steer(game, nearest, 12; tag = "berry2", P))
    note("berry round 2 after 12 s: me $(m.score) critters $(m.rival_score)")
    click(game, "Stop")
end

uitest("review: firefly catch for a minute") do game
    P = isdefined(Main, :FIREFLY_PLOTS) ? Main.FIREFLY_PLOTS : Dict{Symbol,Any}()
    choose(game, "Firefly catch (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    wait_frames(game, 10); shot(game, "firefly-card")
    note("firefly start: keys $(collect(keys(P)))  card $(cardtext(P))")
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    nearest() = (free = findall(!, m.caught); isempty(free) ? nothing : fly(free[argmin([hypot(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2]) for i in free])]))
    steer(game, nearest, 50; tag = "firefly", P)
    note("firefly after 50 s: caught $(m.score) state $(m.state) t $(round(m.t; digits = 1))")
    wait_seconds(game, 12); shot(game, "firefly-end")
    note("firefly end: state $(game.minigame === nothing ? nothing : game.minigame.state) card $(cardtext(P))")
    press(game, Keyboard.r); wait_frames(game, 10); shot(game, "firefly-again")
    note("firefly after R: $(game.minigame === nothing ? nothing : (game.minigame.state, game.minigame.score))")
    click(game, "Stop")
end

uitest("review: hide and seek for a minute") do game
    P = Main.HIDESEEK_PLOTS
    choose(game, "Hide and seek (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); c = creature(game.world, "Lumi")
    wait_frames(game, 10); shot(game, "hide-card")
    note("hide start card: $(cardtext(P)) hiders $(length(m.hiders))")
    target() = all(m.found) ? nothing : something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    steer(game, target, 60; tag = "hide", P, run = false)
    note("hide after 60 s: found $(count(m.found))/$(length(m.found)) state $(m.state) hud $(hudtext(P)) card $(cardtext(P))")
    shot(game, "hide-end")
    click(game, "Stop")
end

uitest("review: jump in, every key for a minute") do game
    choose(game, "Jump in"); click(game, "Play")
    check(game.minigame isa NG.JumpIn, "no jump in")
    c = creature(game.world, "Lumi"); K = Keyboard
    wait_frames(game, 10); shot(game, "jump-card")
    for (k, name, secs) in ((K.w, "walk", 3), (K.space, "space", 2), (K.e, "e-wave", 3), (K.e, "e-wave2", 3), (K.x, "x-sneeze", 5),
                            (K.h, "h-hiccup", 5), (K.c, "c-sing", 6), (K.p, "p-paint", 5), (K.g, "g-fly", 9), (K.t, "t-storm", 8))
        if k === K.w
            interact!(game, [KeyDown(K.w), Wait(secs), KeyUp(K.w)])
        else
            press(game, k)
            wait_seconds(game, min(secs, 1.5)); shot(game, "jump-$name")
            wait_seconds(game, max(secs - 1.5, 0))
        end
        note("jump $name: lumi $(c.action) goal $(c.goal.kind) pos $(round.(c.pos; digits = 1)) followers $(count(o -> o.goal.kind === :follow, game.world.creatures)) speech $(get(game.world.speech, c.id, nothing))")
    end
    shot(game, "jump-last")
    click(game, "Stop")
end
