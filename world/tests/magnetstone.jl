# The magnet stone (s147): picked up with 5 in Jump in and carried towards an iron spike lying a little ahead,
# the stone's field pulls the spike to it (plugins/magnetstone.jl); one lying far to the side stays put.
uitest("magnet stone picks up spikes") do game
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    check(game.minigame isa NeverendingGame.JumpIn, "Play started $(typeof(game.minigame))")
    MS = Main.MAGSTONE
    c = MS[:c]
    me = creature(game.world, "Lumi")
    me.pos = NeverendingGame.ground(game.world.island, (Float32(c[1]) - 0.6f0, Float32(c[2])))
    me.yaw = 0f0
    interact!(game, [Wait(0.3), KeyPress(Keyboard._5; duration = 0.2), Wait(0.3)])
    check(MS[:carried], "the stone was not picked up")
    for s in MS[:spikes]; s.stuck = false; end
    c = MS[:c]
    near, far = MS[:spikes][1], MS[:spikes][2]
    gz(x, y) = Float64(NeverendingGame.ground(game.world.island, (Float32(x), Float32(y)))[3])
    near.p = (c[1] + 0.22, c[2] + 0.05, gz(c[1] + 0.22, c[2] + 0.05) + 0.003); near.v = (0.0, 0.0, 0.0); near.w = 0.0
    far.p = (c[1] + 0.3, c[2] - 1.2, gz(c[1] + 0.3, c[2] - 1.2) + 0.003); far.v = (0.0, 0.0, 0.0); far.w = 0.0
    far0 = far.p
    interact!(game, [KeyPress(Keyboard.w; duration = 0.6), Wait(0.5)])
    screenshot(game, "magnetstone-sweep")
    check(near.stuck, "the spike a little ahead did not come to the stone (at $(round.(near.p; digits = 2)), stone at $(round.(MS[:c]; digits = 2)))")
    check(!far.stuck && hypot(far.p[1] - far0[1], far.p[2] - far0[2]) < 0.01, "the spike 1.2 m to the side moved")
    interact!(game, [KeyPress(Keyboard._5; duration = 0.2), Wait(0.3)])
    check(!MS[:carried], "the stone was not put down")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
end
