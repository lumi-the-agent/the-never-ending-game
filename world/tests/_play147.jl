# scratch: s147 play check, as a player: Jump in, spin a top (hold 1), bend the wire (hold 2)
uitest("play147 tops and wire") do game
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    check(game.minigame isa NeverendingGame.JumpIn, "Play started $(typeof(game.minigame))")
    me = creature(game.world, "Lumi")
    me.pos = NeverendingGame.ground(game.world.island, (5.0f0, -13.8f0))
    interact!(game, [KeyPress(Keyboard.w; duration = 0.4), Wait(0.3), KeyPress(Keyboard._1; duration = 2.0), Wait(0.3)])
    screenshot(game, "play147-top")
    interact!(game, [KeyPress(Keyboard.d; duration = 0.5), Wait(0.3), KeyPress(Keyboard._2; duration = 2.0), Wait(0.3)])
    screenshot(game, "play147-wire")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
end
