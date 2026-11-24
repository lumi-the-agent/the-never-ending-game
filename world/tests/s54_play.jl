const X = NeverendingGame
xclick(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.2)])
function xchoose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end

uitest("Evening: golden at 18:00, still lit at 19:00, dark by 21:00, and the dashboard shows each (screenshots)") do game
    game.minigame === nothing || X.stop_minigame!(game)
    w = game.world
    nfs = Float64[]
    for h in (17.0, 18.4, 19.0, 19.6, 20.5, 21.5)
        X.skip_to_hour!(w, h); wait_frames(game, 8)
        push!(nfs, X.night_factor(w))
        h in (18.4, 19.6, 21.5) && screenshot(game, "s54t-evening-$(round(Int, h * 10))")
    end
    check(issorted(nfs), "night factor not rising through the evening: $(nfs)")
    check(nfs[2] < 0.05 && nfs[end] > 0.9, "evening $(nfs[2]) / night $(nfs[end])")
    X.skip_to_hour!(w, 11.0); wait_frames(game, 8)
end

uitest("Berry race, first play standing still: no friend eats more than two berries and the race ends") do game
    P = Main.BERRY_PLOTS; level0 = get(P, :level, nothing); P[:level] = 1
    try
        game.minigame === nothing || X.stop_minigame!(game)
        X.skip_to_hour!(game.world, 11.0)
        xchoose(game, "Berry race (WASD)"); xclick(game, "Play")
        m = game.minigame
        check(m !== nothing && occursin("Berry", X.game_title(typeof(m))), "got $(typeof(m))")
        interact!(game, [KeyPress(Keyboard.w; duration = 0.3)])
        tt = time(); shot = false
        while time() - tt < 100 && m.state !== :over
            interact!(game, [Wait(0.5)])
            if !shot && time() - tt > 15; screenshot(game, "s54t-berry-mid"); shot = true; end
        end
        check(m.state === :over, "race did not end within 100 s (state $(m.state))")
        check(all(<=(2), m.rival_score), "a friend ate more than 2 berries on level 1: $(m.rival_score)")
        screenshot(game, "s54t-berry-end")
        game.minigame === nothing || X.stop_minigame!(game)
    finally
        level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
    end
end

uitest("Workshop corner: bench, crates and tool rack are in the scene (screenshot)") do game
    game.minigame === nothing || X.stop_minigame!(game)
    wait_seconds(game, 1.0)
    names = Set(p.attributes[:name][] for p in game.stage.scene.plots if haskey(p.attributes, :name))
    for n in (:workshop_bench, :workshop_crate, :workshop_rack)
        check(n in names, "$(n) missing; scene has $(sort(collect(filter(x -> occursin("workshop", string(x)), names))))")
    end
    screenshot(game, "s54t-workshop")
end
