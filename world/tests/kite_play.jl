# Session 57 (tester): playing the kite as a person: jump in as the holder.
const KP = NeverendingGame

function kp_fly!(game)
    w = game.world; K = Main.KITE
    game.minigame === nothing || KP.stop_minigame!(game)
    me = creature(w, "Lumi")
    KP.leave_interactions!(w, me); me.controlled = false
    h = 24 * KP.daytime(w); (h < 13.2 || h > 15.5) && KP.skip_to_hour!(w, 13.5)
    me.action === :sleep && (me.action = :idle); me.needs.energy = 0.9
    me.goal = KP.Goal(:idle, me.pos, :idle, 20.0, w.t + 20, true, 0, false)
    K[:day] = -1; K[:retry] = -Inf
    t1 = w.t
    while !(K[:flyer] != 0 && get(K, :up, false)) && w.t - t1 < 90
        K[:retry] = -Inf; wait_seconds(game, 1)
    end
    me
end

uitest("Jumping in with Play while the kite flies makes the player the holder; standing lets it sink; Stop frees Lumi") do game
    w = game.world; K = Main.KITE
    me = kp_fly!(game)
    check(K[:flyer] == me.id && K[:up], "the kite did not go up (flyer $(K[:flyer]))")
    wait_seconds(game, 3)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    check(me.controlled && game.minigame isa KP.JumpIn, "Play did not hand Lumi over ($(typeof(game.minigame)), controlled $(me.controlled))")
    check(K[:flyer] == me.id, "the kite string left Lumi when the player jumped in (flyer $(K[:flyer]))")
    wait_seconds(game, 2); e0 = K[:elev]
    wait_seconds(game, 6)
    check(K[:elev] < e0 - 0.05, "standing still did not lower the kite (elev $(e0) -> $(K[:elev]))")
    screenshot(game, "kite_play_standing")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(!me.controlled && game.minigame === nothing, "Stop did not release Lumi")
    KP.skip_to_hour!(w, 18.2); wait_frames(game, 5)
    check(K[:flyer] == 0, "kite still flies in the evening after a jump-in")
end

# Session 58 (tester s57: "the kite is not in view, nothing tells the player that running lifts it")
uitest("Flying the kite as the player: the kite is in view, a meter says run to lift it, and running lifts it clearly") do game
    w = game.world; K = Main.KITE
    # on the kite meadow (a test before may leave Lumi on the beach, where W does not walk)
    game.minigame === nothing || KP.stop_minigame!(game)
    s0 = creature(w, "Lumi"); s0.pos = Point3f(K[:spot])
    me = kp_fly!(game)
    check(K[:flyer] == me.id && K[:up], "the kite did not go up (flyer $(K[:flyer]))")
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    check(me.controlled && K[:flyer] == me.id, "Play did not make the player the holder (flyer $(K[:flyer]))")
    wait_seconds(game, 6)          # standing: it sinks
    e0 = K[:elev]
    meter = K[:meter]
    check(meter.visible[] && occursin("run to lift", meter.text[]), "no kite meter for the player (visible $(meter.visible[]), text $(meter.text[]))")
    interact!(game, [KeyDown(Keyboard.w), Wait(4.0), KeyUp(Keyboard.w), Wait(0.1)])
    check(K[:elev] > e0 + 0.15, "running 4 s did not lift the kite clearly (elev $(e0) -> $(K[:elev]), Lumi at $(me.pos))")
    wait_seconds(game, 1.5)        # the camera settles behind the runner
    kite = only(filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :kite, game.stage.scene.plots))
    kp = Point3f(Makie.translation(kite)[])
    check(KP.on_screen(game.stage.scene, kp) !== nothing, "the kite is out of the player's view (kite $(kp), eye $(game.rig.eye))")
    check(KP.on_screen(game.stage.scene, Point3f(me.pos)) !== nothing, "the player's Lumi is out of view (eye $(game.rig.eye))")
    screenshot(game, "kite_play_running")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    wait_frames(game, 3); check(!meter.visible[], "the kite meter stays up after Stop")
    KP.skip_to_hour!(w, 18.2); wait_frames(game, 5)
    check(K[:flyer] == 0 && !meter.visible[], "kite or meter still up in the evening (flyer $(K[:flyer]))")
end
