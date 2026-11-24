const X = NeverendingGame
xclick(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.2)])
function xchoose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end

note(s) = nothing

uitest("Menu: choosing Jump in (WASD) and pressing Play jumps in, with a chase camera that keeps Lumi in view") do game
    game.minigame === nothing || X.stop_minigame!(game)
    xchoose(game, "Jump in (WASD)"); xclick(game, "Play")
    check(game.minigame isa X.JumpIn, "Play started $(typeof(game.minigame))")
    wait_seconds(game, 2.5)
    c = creature(game.world, "Lumi")
    check(c.controlled, "Lumi is not steered after Jump in")
    back = norm(game.rig.eye - c.pos); aim = norm(game.rig.target - (c.pos + Point3f(0, 0, 0.6)))
    check(back < 9 && aim < 1.5, "the jumped-in camera sits $(round(back; digits = 1)) m from Lumi and looks $(round(aim; digits = 1)) m off it")
    interact!(game, [KeyPress(Keyboard.w; duration = 1.5)])
    back2 = norm(game.rig.eye - c.pos)
    check(back2 < 9, "after walking the camera is $(round(back2; digits = 1)) m from Lumi")
    screenshot(game, "s53-jump-walk")
    xclick(game, "Stop")
    check(game.minigame === nothing, "Stop did not end Jump in")
end

uitest("Berry race from the menu: start card, a whole W/A/D race ends with every berry taken, rivals score, and the player is not left far behind") do game
    P = Main.BERRY_PLOTS; level0 = get(P, :level, nothing); P[:level] = 1
    K = Keyboard
    try
        game.minigame === nothing || X.stop_minigame!(game)
        xchoose(game, "Berry race (WASD)"); xclick(game, "Play")
        m = game.minigame
        check(m !== nothing && occursin("Berry", X.game_title(typeof(m))), "Berry race did not start (got $(typeof(m)))")
        check(P[:card].visible[] && occursin("Press W to start", P[:card].text[]), "no start card: $(P[:card].text[])")
        wait_frames(game, 15); screenshot(game, "s53-berry-start")
        c = creature(game.world, "Lumi"); mod = parentmodule(typeof(m))
        nearest() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
        interact!(game, [KeyDown(K.w)]); held = nothing; tt = time(); shot = false
        while time() - tt < 75 && m.state !== :over
            p = nearest(); p === nothing && break
            d = X.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
            want = abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
            if want !== held
                held === nothing || interact!(game, [KeyUp(held)])
                want === nothing || interact!(game, [KeyDown(want)]); held = want
            end
            interact!(game, [Wait(0.1)])
            if !shot && time() - tt > 12; screenshot(game, "s53-berry-mid"); shot = true; end
        end
        interact!(game, [KeyUp(K.w)]); held === nothing || interact!(game, [KeyUp(held)])
        wait_frames(game, 5); screenshot(game, "s53-berry-end")
        msg = "you $(m.score), critters $(m.rival_score), state $(m.state), $(count(b -> b.taken == 0, m.berries)) of $(length(m.berries)) berries left"
        check(m.state === :over, "the race did not end: $msg")
        check(sum(m.rival_score) >= 3, "the critters hardly raced: $msg")
        check(m.score >= sum(m.rival_score) - 1, "a first W/A/D play (level 1) was lost clearly: $msg")
        xclick(game, "Stop")
    finally
        game.minigame === nothing || X.stop_minigame!(game)
        level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
    end
end

uitest("Meadow life by day: stones, daisies, toadstools, stumps and logs are drawn in the meadow") do game
    game.minigame === nothing || X.stop_minigame!(game)
    X.skip_to_hour!(game.world, 11.0)
    wait_seconds(game, 2)
    ML = Main.MEADOWLIFE
    pl = get(ML, :plots, Dict())
    for k in (:stones, :daisies, :toadstools, :stump, :log)
        check(haskey(pl, k), "no $(k) plot in the meadow (have $(collect(keys(pl))))")
        check(pl[k].visible[], "the $(k) plot is hidden")
    end
    check(!haskey(pl, :pinks) && !haskey(pl, :pink), "the almost black pink clumps are still there")
    screenshot(game, "s53-meadow-noon")
end
