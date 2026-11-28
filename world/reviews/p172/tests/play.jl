# Reviewer s172: play every mini game for about a minute with a naive steering bot (W + A/D toward the nearest target).
const SHOT = "/sim/Programmieren/SimGame/world/reviews/p172/play"
shot(game, name) = (mkpath(SHOT); game.screen === nothing ? "" : (Makie.save(joinpath(SHOT, name * ".png"), Makie.colorbuffer(game.screen)); name))
const LOG = String[]
say(s) = (push!(LOG, s); open(joinpath(SHOT, "log.txt"), "a") do io; println(io, s); end)

function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end
click(game, n) = interact!(game, [MouseTo(ui_pos(game, n)), LeftClick(), Wait(0.3)])
wrapa(a) = mod(a + pi, 2pi) - pi

"one steering step toward `tgt` (x, y); returns the distance"
function steer!(game, c, tgt)
    dx = tgt[1] - c.pos[1]; dy = tgt[2] - c.pos[2]
    d = hypot(dx, dy)
    diff = wrapa(atan(dy, dx) - c.yaw)
    if abs(diff) > 0.35
        interact!(game, [KeyPress(diff > 0 ? Keyboard.a : Keyboard.d; duration = clamp(abs(diff) / 3, 0.08, 0.3))])
    else
        interact!(game, [KeyPress(Keyboard.w; duration = 0.35)])
    end
    return d
end

function bot!(game, name, targets; secs = 60, shots = (5, 25, 50))
    c = creature(game.world, "Lumi")
    t0 = time(); k = 0; last = nothing
    while time() - t0 < secs
        m = game.minigame
        m === nothing && (say("$name: the game ended itself at $(round(time() - t0; digits = 1)) s"); break)
        (hasproperty(m, :state) && m.state === :over) && (say("$name: over at $(round(time() - t0; digits = 1)) s"); shot(game, "$name-over"); break)
        ts = targets(game, m)
        if isempty(ts)
            interact!(game, [Wait(0.3)])
        else
            _, j = findmin(p -> hypot(p[1] - c.pos[1], p[2] - c.pos[2]), ts)
            steer!(game, c, ts[j])
        end
        el = time() - t0
        for s in shots
            if el >= s && (last === nothing || last < s)
                shot(game, "$name-$(s)s"); last = s
            end
        end
    end
    m = game.minigame
    fields = m === nothing ? "" : join(["$f=$(getfield(m, f))" for f in (:state, :score, :t) if hasproperty(m, f)], " ")
    say("$name after $(round(time() - t0; digits = 1)) s: $fields")
    return m
end

uitest("review172 play") do game
    rm(joinpath(SHOT, "log.txt"); force = true)
    # Firefly catch
    choose(game, "Firefly catch (WASD)"); click(game, "Play")
    shot(game, "firefly-card")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.3)])
    FM = game.plugins["firefly_catch"].mod
    m = bot!(game, "firefly", (g, m) -> [FM.fly_pos(m.flies[i], g.world.t, i) for i in eachindex(m.flies) if !m.caught[i]])
    m === nothing || say("firefly caught $(count(m.caught)) of $(length(m.caught))")
    shot(game, "firefly-end"); game.minigame === nothing || click(game, "Stop")
    # Hide and seek
    choose(game, "Hide and seek (WASD)"); click(game, "Play")
    shot(game, "hide-card")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.3)])
    m = bot!(game, "hide", (g, m) -> [m.spots[i] for i in eachindex(m.spots) if !m.found[i]])
    m === nothing || say("hide found $(count(m.found)) of $(length(m.found))")
    shot(game, "hide-end"); game.minigame === nothing || click(game, "Stop")
    # Berry race
    choose(game, "Berry race (WASD)"); click(game, "Play")
    shot(game, "berry-card")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.3)])
    m = bot!(game, "berry", (g, m) -> [b.pos for b in m.berries if b.taken == 0])
    m === nothing || say("berry me $(m.score) vs rivals $(m.rival_score)")
    shot(game, "berry-end"); game.minigame === nothing || click(game, "Stop")
    # Jump in (no selection): walk, then every gag key
    game.dash.play_menu.i_selected[] = 0
    click(game, "Play")
    say("jump in: $(typeof(game.minigame))")
    c = creature(game.world, "Lumi"); p0 = c.pos
    interact!(game, [KeyPress(Keyboard.w; duration = 3.0)])
    say("jump in walked $(round(hypot(c.pos[1]-p0[1], c.pos[2]-p0[2]); digits = 2)) m in 3 s")
    shot(game, "jump-walk")
    for (i, k) in enumerate((Keyboard.e, Keyboard.q, Keyboard.r, Keyboard.f, Keyboard.g, Keyboard.h, Keyboard._1, Keyboard._6, Keyboard.space))
        interact!(game, [KeyPress(k; duration = 0.2), Wait(1.8)])
        say("jump key $k: Lumi action $(c.action), goal $(c.goal.kind)")
        i in (1, 4, 6, 9) && shot(game, "jump-key-$k")
    end
    interact!(game, [KeyPress(Keyboard.d; duration = 1.0), KeyPress(Keyboard.w; duration = 6.0)])
    shot(game, "jump-end")
    game.minigame === nothing || click(game, "Stop")
end
