uitest("Play and Stop twice in a row: W moves Lumi each time, wild race camera hook stays set") do game
    NG = NeverendingGame
    for round in 1:2
        interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.3)])
        check(game.minigame !== nothing, "round $round: Play did not start")
        s = creature(game.world, "Lumi"); p0 = copy(collect(s.pos))
        interact!(game, [KeyPress(Keyboard.w; duration = 1.0), Wait(0.2)])
        p1 = collect(s.pos)
        check(sum(abs.(p1 .- p0)) > 0.3, "round $round: W did not move Lumi $p0 -> $p1")
        interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
        check(game.minigame === nothing, "round $round: Stop failed")
    end
    screenshot(game, "explore-end")
    check(NG.CAMERA_FOCUS[] !== nothing, "wild race camera hook missing")
end
