function ex_choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end
uitest("Berry race: W lifts the camera from the low start view to the chase view, Stop ends it") do game
    ex_choose(game, "Berry race (WASD)")
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.8)])
    screenshot(game, "ex-berry-start")
    check(game.minigame !== nothing, "no berry race")
    e0 = copy(collect(game.rig.eye))
    interact!(game, [KeyPress(Keyboard.w; duration = 1.5), Wait(0.5)])
    screenshot(game, "ex-berry-run")
    e1 = collect(game.rig.eye)
    check(sum(abs.(e1 .- e0)) > 0.5, "camera did not rise/move after W: $e0 -> $e1")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.4)])
    check(game.minigame === nothing, "Stop failed")
end
uitest("Hide and seek and Firefly catch: Play shows the start card, W starts with a HUD, Stop ends each") do game
    for opt in ("Hide and seek (WASD)", "Firefly catch (WASD)")
        ex_choose(game, opt)
        interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.8)])
        screenshot(game, "ex-" * first(split(opt)) * "-start")
        check(game.minigame !== nothing, "$opt did not start")
        # Lumi under the card (tester s45): Lumi lies well below the view's centre line (the card sits above it)
        me = game.world.creatures[findfirst(c -> c.name == "Lumi", game.world.creatures)]
        e, t = game.rig.eye, game.rig.target
        elev(v) = asind(v[3] / sqrt(sum(abs2, v)))
        below = elev(me.pos + Point3f(0, 0, 0.4) - e) - elev(t - e)
        check(below < -6, "$opt: Lumi is only $(round(below, digits = 1))° below the view centre, under the start card")
        interact!(game, [KeyPress(Keyboard.w; duration = 1.0), Wait(0.3)])
        screenshot(game, "ex-" * first(split(opt)) * "-run")
        interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.4)])
        check(game.minigame === nothing, "Stop failed $opt")
    end
end
uitest("Follow camera: watching alone for 12 s keeps a creature name tag and the game running") do game
    for i in 1:4
        wait_seconds(game, 3.0)
        screenshot(game, "ex-follow$i")
    end
    check(game.minigame === nothing && game.rig.mode === :follow, "mini game $(game.minigame) camera $(game.rig.mode) while watching")
end

