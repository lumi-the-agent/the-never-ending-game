# Perfectionist review 88: play every mini game like a person for about a minute, and every camera mode.
const OUT = "/sim/Programmieren/SimGame/world/reviews/p88/play"
const LOG = String[]
note(s) = (push!(LOG, s); write(joinpath(OUT, "log.txt"), join(LOG, "\n")))
function shot(game, name)
    mkpath(OUT)
    Makie.save(joinpath(OUT, name * ".png"), Makie.colorbuffer(game.screen))
end
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
function choose(game, menu, option)
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.3)])
end
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
function steer(game, target_of, seconds; shots = String[], every = 15)
    c = creature(game.world, "Lumi"); K = Keyboard
    interact!(game, [KeyDown(K.w)])
    held = nothing; t0 = time(); k = 0
    while time() - t0 < seconds
        if !isempty(shots) && time() - t0 > every * (k + 1) && k < length(shots)
            k += 1; shot(game, shots[k])
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
end
txt(x) = try string(x.text[]) catch; "?" end

uitest("review88 firefly") do game
    menu = game.dash.play_menu
    choose(game, menu, "Firefly catch (WASD)"); click(game, "Play")
    m = game.minigame; P = Main.FIREFLY_PLOTS; mod = parentmodule(typeof(m))
    wait_frames(game, 10); shot(game, "firefly-0-card")
    note("firefly card: " * txt(P[:card]))
    c = creature(game.world, "Lumi"); t0 = time()
    function tgt()
        m.state === :over && return nothing
        idx = findall(!, m.caught); isempty(idx) && return nothing
        ps = [mod.fly_pos(m.flies[i], game.world.t, i) for i in idx]
        ps[argmin([flat(p, c.pos) for p in ps])]
    end
    steer(game, tgt, 60; shots = ["firefly-1", "firefly-2", "firefly-3"], every = 15)
    shot(game, "firefly-4-after")
    note("firefly after $(round(time() - t0; digits = 1)) s: score $(m.score), state $(m.state), hud $(haskey(P, :hud) ? txt(P[:hud]) : "-")")
    m.state === :over || (m.t = 1000.0; wait_frames(game, 5))
    wait_frames(game, 20); shot(game, "firefly-5-end"); note("firefly end card: " * txt(P[:card]))
    click(game, "Stop")
end

uitest("review88 hideseek") do game
    menu = game.dash.play_menu
    choose(game, menu, "Hide and seek (WASD)"); click(game, "Play")
    m = game.minigame; P = Main.HIDESEEK_PLOTS; mod = parentmodule(typeof(m))
    wait_frames(game, 10); shot(game, "hide-0-card"); note("hide card: " * txt(P[:card]))
    c = creature(game.world, "Lumi"); t0 = time()
    tgt() = (m.state === :over || all(m.found)) ? nothing :
        something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    steer(game, tgt, 60; shots = ["hide-1", "hide-2", "hide-3"], every = 15)
    shot(game, "hide-4-after")
    note("hide after $(round(time() - t0; digits = 1)) s: found $(count(m.found))/$(length(m.found)), state $(m.state), hud $(txt(P[:hud]))")
    m.state === :over || (m.t = mod.TIME_LIMIT + 1; wait_frames(game, 5))
    wait_frames(game, 20); shot(game, "hide-5-end"); note("hide end card: " * txt(P[:card]))
    click(game, "Stop")
end

uitest("review88 berry") do game
    menu = game.dash.play_menu
    choose(game, menu, "Berry race (WASD)"); click(game, "Play")
    m = game.minigame; P = Main.BERRY_PLOTS; mod = parentmodule(typeof(m))
    wait_frames(game, 10); shot(game, "berry-0-card"); note("berry card: " * txt(P[:card]))
    c = creature(game.world, "Lumi"); t0 = time()
    function tgt()
        m.state === :over && return nothing
        free = [b for b in m.berries if b.taken == 0]
        isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot
    end
    steer(game, tgt, 60; shots = ["berry-1", "berry-2", "berry-3"], every = 15)
    shot(game, "berry-4-after")
    note("berry after $(round(time() - t0; digits = 1)) s: score $(m.score), rivals $(m.rival_score), state $(m.state), hud $(haskey(P, :hud) ? txt(P[:hud]) : "-")")
    m.state === :over || (m.t = 61.0; wait_frames(game, 5))
    wait_frames(game, 20); shot(game, "berry-5-end"); note("berry end card: " * txt(P[:card]))
    click(game, "Stop")
end

uitest("review88 jumpin keys") do game
    menu = game.dash.play_menu
    menu.i_selected[] = 0
    click(game, "Play")
    c = creature(game.world, "Lumi"); K = Keyboard
    wait_frames(game, 10); shot(game, "jump-0")
    note("jump in: minigame $(typeof(game.minigame)), controlled $(c.controlled)")
    interact!(game, [KeyPress(K.w; duration = 2.0), KeyPress(K.e), Wait(0.5), KeyPress(K.e), Wait(1.0)])
    shot(game, "jump-1-wave")
    interact!(game, [KeyPress(K.x), Wait(1.0)]); shot(game, "jump-2-sneeze")
    interact!(game, [Wait(2.0), KeyPress(K.h), Wait(1.5)]); shot(game, "jump-3-hiccup")
    interact!(game, [Wait(3.0), KeyPress(K.p), Wait(1.5)]); shot(game, "jump-4-paint")
    interact!(game, [Wait(3.0), KeyPress(K.c), Wait(2.0)]); shot(game, "jump-5-sing")
    interact!(game, [Wait(3.0), KeyPress(K.g), Wait(3.0)]); shot(game, "jump-6-fly")
    interact!(game, [Wait(8.0)]); shot(game, "jump-7-fly-later")
    note("jump in after keys: action $(c.action), goal $(c.goal.kind), pos $(round.(c.pos; digits = 1))")
    click(game, "Stop")
end

uitest("review88 cameras") do game
    cur = "Camera: follow"
    for (i, opt) in enumerate(("Camera: orbit", "Camera: free", "Camera: follow"))
        c0 = cur
        interact!(game, [MouseTo(ui_pos(game, c0)), LeftClick(), Wait(0.4),
                         Lazy(_ -> MouseTo(ui_option_pos(game, c0, opt))), LeftClick(), Wait(0.3)])
        cur = opt
        interact!(game, [Wait(3.0)]); shot(game, "cam-$(i)a")
        interact!(game, [Wait(6.0)]); shot(game, "cam-$(i)b")
        note("camera $(opt): mode $(game.rig.mode)")
    end
end
