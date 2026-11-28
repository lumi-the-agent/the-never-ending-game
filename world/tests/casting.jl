# Casting lead in the sand (s170): in Jump in on the beach, H stamps Lumi's foot, H pours lead into the print, it
# freezes, H lifts out a lead foot of about the print's volume.
uitest("cast a lead foot in the sand") do game
    C = Main.CAST
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    me = creature(game.world, "Lumi")
    spot = (-6.8f0, -12.2f0)                                   # open beach by the parked yacht
    me.pos = NeverendingGame.ground(game.world.island, spot)
    interact!(game, [Wait(0.3), KeyPress(Keyboard.h; duration = 0.15), Wait(0.5)])
    check(get(C, :stage, :none) == :print, "H on the beach did not stamp a print: $(get(C, :stage, :none)) at $(me.pos)")
    interact!(game, [KeyPress(Keyboard.h; duration = 0.15), Wait(2.0)])
    screenshot(game, "cast-pouring")
    # a 2 cm deep print freezes in ~3 minutes: the test watches the first 90 s (the thin toes freeze first)
    interact!(game, [Wait(30.0)]); interact!(game, [Wait(30.0)]); interact!(game, [Wait(30.0)])
    p = C[:pour]
    check(p.poured >= C[:volume] - 1e-9, "not all poured: $(p.poured) of $(C[:volume])")
    lead = 1e6 * (sum(p.ds) * 11340 + sum(p.dl) * 10660) * 1e-4 / 10660
    check(abs(lead - 1e6 * C[:volume]) < 1.0, "lead lost or made: $(lead) cm3 of $(1e6 * C[:volume])")
    check(sum(p.ds) > 0.3 * (sum(p.ds) + sum(p.dl)), "barely frozen after $(p.t) s")
    screenshot(game, "cast-freezing")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
end
