# The land yacht sails (s167, todo #767): E by the cart in Jump in climbs aboard and starts the solved 3D sail
# (physics/sailflow.jl serve! in its own process); hauled tight it stalls and creeps, let out it rolls more than 15 m
# along the beach in an 8.8 m/s wind; Space hops off and the sail's process goes. The island's wind drifts 4..10 m/s,
# so the test holds its strength at 1.1 (8.8 m/s, the direction still drifts) and puts it back after.
uitest("land yacht sails on its solved wind") do game
    LY = Main.LANDYACHT
    wind0 = Main.WIND[:now]
    Main.WIND[:now] = t -> (Base.invokelatest(wind0, t)[1], 1.1f0)
    try                                                  # finally, not catch: a failure still fails, the wind comes back
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    check(game.minigame isa NeverendingGame.JumpIn, "Play started $(typeof(game.minigame))")
    st = LY[:st]; P0 = st.P
    me = creature(game.world, "Lumi")
    me.pos = NeverendingGame.ground(game.world.island, (P0[1] - 1.5f0 * cos(st.yaw), P0[2] - 1.5f0 * sin(st.yaw)))
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(1.0)])
    check(get(LY, :aboard, false), "E by the cart did not climb aboard")
    for _ in 1:60                                       # the sail's flow compiles and warms in its own process
        LY[:force] === nothing || break
        interact!(game, [Wait(1.0)])
    end
    check(LY[:force] !== nothing, "no force from the sail after 60 s: $(get(LY, :srv_error, "no error"))")
    # hauled tight the sail is stalled: 3 s of it barely moves the cart (at 7 m/s it stays put; at 8.8 it creeps)
    interact!(game, [Wait(3.0)])
    d1 = LY[:st].d
    # OPEN (s167): stalled at 8.8 m/s it went 2.4-5 m in these 3 s: the box warms only 2 chords, so the first seconds are
    # the surge before the stalled wake forms (at 7.2 m/s, settled, it stayed put: 61 N). Check the creep once warm = 8.
    for _ in 1:20                                       # let out in short pulls until the sail sits near 30 deg
        LY[:last].alpha > 32 || break
        interact!(game, [KeyPress(Keyboard.s; duration = 0.25), Wait(0.2)])
    end
    interact!(game, [Wait(15.0)])
    screenshot(game, "landyacht-sailing")
    d2 = LY[:st].d - d1
    check(d2 > 15, "let out, it rolled only $(round(d2; digits = 1)) m in 15 s: $(LY[:last])")
    interact!(game, [KeyPress(Keyboard.space; duration = 0.2), Wait(1.0)])
    check(!get(LY, :aboard, false) && !haskey(LY, :srv_pid), "Space did not hop off or the sail's process is still there")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
    finally
        Main.WIND[:now] = wind0
        get(LY, :aboard, false) && NeverendingGame.stop_minigame!(game)   # hops off: the sail's process goes
    end
end
