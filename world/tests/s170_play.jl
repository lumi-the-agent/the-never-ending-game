# s170 play: Jump in, walk to the parked yacht's bow (where the reviewer stood), Q for a friend, watch.
uitest("s170 play by the yacht") do game
    LY = Main.LANDYACHT
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    st = LY[:st]; P0 = st.P
    me = creature(game.world, "Lumi")
    me.pos = NeverendingGame.ground(game.world.island, (P0[1] + 1.8f0 * cos(st.yaw), P0[2] + 1.8f0 * sin(st.yaw)))
    interact!(game, [Wait(1.0)])
    screenshot(game, "s170-bow")
    interact!(game, [KeyPress(Keyboard.q; duration = 0.2), Wait(0.5)])
    log = String[]
    for k in 1:14
        interact!(game, [Wait(1.0)])
        pu = get(LY, :pusher, nothing)
        push!(log, "t=$k pusher=$(pu === nothing ? "-" : pu) d=$(round(LY[:st].d; digits = 2)) R=$(round(get(LY, :sandR, 0.0); digits = 0))")
        k == 6 && screenshot(game, "s170-q6")
    end
    screenshot(game, "s170-q14")
    println(join(log, "\n"))
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
end
