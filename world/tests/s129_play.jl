# Session 129: playing as a person at the start of the session (Jump in, walk, fly, paint).
uitest("s129 play: jump in, walk, fly, paint") do game
    game.minigame === nothing || NeverendingGame.stop_minigame!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    check(game.minigame isa NeverendingGame.JumpIn, "Play started $(typeof(game.minigame))")
    me = creature(game.world, "Lumi"); p0 = me.pos
    interact!(game, [KeyPress(Keyboard.w; duration = 2.5), Wait(0.3)])
    screenshot(game, "s129-walk")
    walked = sqrt(sum(abs2, me.pos - p0))
    interact!(game, [KeyPress(Keyboard.g), Wait(2.5)])
    screenshot(game, "s129-fly")
    interact!(game, [KeyPress(Keyboard.w; duration = 2.0), Wait(1.5)])
    screenshot(game, "s129-fly2")
    interact!(game, [KeyPress(Keyboard.p), Wait(1.5)])
    screenshot(game, "s129-paint")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
    check(walked > 1.0, "W for 2.5 s walked only $(walked) m")
end
