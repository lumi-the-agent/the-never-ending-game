# Perfectionist review s100: play every mini game for about a minute through interact! (real key events).
const LOG = Main.REVIEW_LOG
const SHOTS = "/sim/Programmieren/SimGame/world/reviews/perfectionist-shots/play100"
const K = Keyboard
const NG = NeverendingGame

shot(game, name) = (mkpath(SHOTS); p = joinpath(SHOTS, name * ".png"); Makie.save(p, Makie.colorbuffer(game.screen)); push!(LOG, "shot $p"); p)
note(s...) = push!(LOG, string(s...))
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.3)])
end
txt(x) = try string(x[]) catch; "?" end

# hold W, steer with A/D towards target_of(); shots every `every` s
function steer(game, target_of, seconds, tag; every = 12)
    c = creature(game.world, "Lumi")
    interact!(game, [KeyDown(K.w)])
    held = nothing; t0 = time(); nxt = 3.0; k = 0
    while time() - t0 < seconds
        if time() - t0 > nxt
            k += 1; shot(game, "$(tag)-$(k)"); nxt += every
        end
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
    end
    held === nothing || interact!(game, [KeyUp(held)])
    interact!(game, [KeyUp(K.w), Wait(0.1)])
    return time() - t0
end

function play_firefly(game)
    choose(game, "Firefly catch (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); P = Main.FIREFLY_PLOTS
    wait_seconds(game, 1); shot(game, "firefly-0-card"); note("firefly card: ", txt(P[:card].text))
    c = creature(game.world, "Lumi")
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    nearest() = (m.state === :over ? nothing : (free = findall(!, m.caught); isempty(free) ? nothing :
                 fly(free[argmin([hypot(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2]) for i in free])])))
    el = steer(game, nearest, 62, "firefly")
    note("firefly after $(round(el)) s: score $(m.score) state $(m.state) hud ", haskey(P, :hud) ? txt(P[:hud].text) : "-")
    wait_seconds(game, 2); shot(game, "firefly-9-end"); note("firefly end card: ", txt(P[:card].text))
    interact!(game, [KeyPress(K.r), Wait(0.5)]); note("firefly after R: state $(m.state) score $(m.score)")
    click(game, "Stop")
end

function play_berry(game)
    choose(game, "Berry race (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); P = Main.BERRY_PLOTS
    note("berry level ", get(P, :level, "-"), " best ", get(P, :best, "-"))
    wait_seconds(game, 1); shot(game, "berry-0-card"); note("berry card: ", txt(P[:card].text))
    c = creature(game.world, "Lumi")
    nearest() = (m.state === :over ? nothing : (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing :
                 free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot))
    el = steer(game, nearest, 62, "berry")
    note("berry after $(round(el)) s: score $(m.score) rivals $(m.rival_score) state $(m.state) hud ", haskey(P, :hud) ? txt(P[:hud].text) : "-")
    wait_seconds(game, 2); shot(game, "berry-9-end"); note("berry end card: ", txt(P[:card].text))
    click(game, "Stop")
end

function play_hide(game)
    choose(game, "Hide and seek (WASD)"); click(game, "Play")
    m = game.minigame; mod = parentmodule(typeof(m)); P = Main.HIDESEEK_PLOTS
    wait_seconds(game, 1); shot(game, "hide-0-card"); note("hide card: ", txt(P[:card].text))
    c = creature(game.world, "Lumi")
    target() = m.state === :over || all(m.found) ? nothing :
               something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    el = steer(game, target, 62, "hide")
    note("hide after $(round(el)) s: found $(count(m.found))/$(length(m.found)) state $(m.state) hud ", txt(P[:hud].text))
    wait_seconds(game, 2); shot(game, "hide-9-end"); note("hide end card: ", txt(P[:card].text))
    click(game, "Stop")
end

function play_jumpin(game)
    choose(game, "Jump in"); click(game, "Play")
    note("jump in: ", typeof(game.minigame))
    wait_seconds(game, 1.5); shot(game, "jump-0")
    for (k, name) in ((K.x, "sneeze"), (K.h, "hiccup"), (K.b, "bubble"), (K.v, "shadow"), (K.c, "sing"), (K.p, "paint"), (K.e, "wave"), (K.t, "storm"), (K.z, "rewind"))
        interact!(game, [KeyPress(k), Wait(0.3)])
        interact!(game, [KeyDown(K.w), Wait(1.0), KeyUp(K.w)])
        wait_seconds(game, 1.5); shot(game, "jump-$(name)")
        me = creature(game.world, "Lumi")
        note("jump $(name): Lumi action $(me.action) goal $(me.goal.kind)")
        wait_seconds(game, 2.5)
    end
    interact!(game, [KeyPress(K.g), Wait(0.3), KeyDown(K.w), Wait(3.0), KeyUp(K.w)]); shot(game, "jump-fly")
    note("jump fly: Lumi action $(creature(game.world, "Lumi").action) z $(creature(game.world, "Lumi").pos[3])")
    wait_seconds(game, 4)
    click(game, "Stop")
end

function review_play(game)
    for (n, f) in (("firefly", play_firefly), ("berry", play_berry), ("hide", play_hide), ("jumpin", play_jumpin))
        try
            f(game)
        catch e
            note("$n FAILED: ", sprint(showerror, e))
            game.minigame === nothing || NG.stop_minigame!(game)
        end
    end
    note("DONE")
end
