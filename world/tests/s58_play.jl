# Session 58 (tester): playing what s58 changed as a person.
const XP = NeverendingGame

function kp_fly!(game)
    w = game.world; K = Main.KITE
    game.minigame === nothing || XP.stop_minigame!(game)
    me = creature(w, "Lumi")
    XP.leave_interactions!(w, me); me.controlled = false
    h = 24 * XP.daytime(w); (h < 13.2 || h > 15.5) && XP.skip_to_hour!(w, 13.5)
    me.action === :sleep && (me.action = :idle); me.needs.energy = 0.9
    me.goal = XP.Goal(:idle, me.pos, :idle, 20.0, w.t + 20, true, 0, false)
    K[:day] = -1; K[:retry] = -Inf
    t1 = w.t
    while !(K[:flyer] != 0 && get(K, :up, false)) && w.t - t1 < 90
        K[:retry] = -Inf; wait_seconds(game, 1)
    end
    me
end

include_string(Main, "")  # noop

# nearest other creature (or Lumi itself) that stands between the camera and Lumi
function blocker(game, me)
    e = Point3f(game.rig.eye); t = Point3f(me.pos) + Point3f(0, 0, 0.5)
    d = t - e; L = sqrt(sum(abs2, d)); best = nothing
    for c in game.world.creatures
        c === me && continue
        v = Point3f(c.pos) + Point3f(0, 0, 0.5) - e
        s = sum(v .* d) / L
        (0 < s < L) || continue
        off = sqrt(max(sum(abs2, v) - s^2, 0f0))
        off < 0.9 && (best === nothing || off < best[2]) && (best = (c.name, off, s))
    end
    best, L
end

function play_kite!(game)
    w = game.world; K = Main.KITE
    s0 = creature(w, "Lumi"); game.minigame === nothing || XP.stop_minigame!(game)
    XP.skip_to_hour!(w, 13.3)
    s0.pos = Point3f(K[:spot])
    me = kp_fly!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me
end

uitest("Kite player (s58): A and D turn Lumi while running, Space and E keep the kite in Lumi's hand") do game
    K = Main.KITE
    me = play_kite!(game)
    check(me.controlled && K[:flyer] == me.id, "not the holder (flyer $(K[:flyer]))")
    y0 = me.yaw
    interact!(game, [KeyDown(Keyboard.w), KeyDown(Keyboard.a), Wait(1.5), KeyUp(Keyboard.a), KeyUp(Keyboard.w), Wait(0.2)])
    dy = abs(angle(cis(me.yaw - y0)))
    check(dy > 0.4, "holding W+A for 1.5 s did not turn Lumi (yaw change $(dy) rad, Lumi at $(me.pos))")
    interact!(game, [KeyPress(Keyboard.space), Wait(0.6), KeyPress(Keyboard.e), Wait(0.6)])
    check(me.controlled && K[:flyer] == me.id && K[:up], "Space/E dropped the kite or the control (flyer $(K[:flyer]), up $(K[:up]), controlled $(me.controlled))")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(!me.controlled && !K[:meter].visible[], "Stop left Lumi controlled or the meter up")
end

uitest("Kite player (s58): Play, Stop, Play again works and the meter comes back") do game
    K = Main.KITE
    me = play_kite!(game)
    check(K[:meter].visible[], "no meter on the first play")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(!K[:meter].visible[] && !me.controlled, "Stop did not clear meter/control")
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    check(me.controlled && game.minigame isa XP.JumpIn, "second Play did not hand Lumi over ($(typeof(game.minigame)))")
    check(K[:flyer] == me.id && K[:meter].visible[], "a second Play after Stop gives no kite: the kite is gone for the day (flyer $(K[:flyer]), meter $(K[:meter].visible[]))")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
end

uitest("Kite player (s58): while running, no friend or solid fills the view between the camera and Lumi") do game
    me = play_kite!(game)
    worst = nothing
    for i in 1:6
        interact!(game, [KeyDown(Keyboard.w), Wait(1.0), KeyUp(Keyboard.w)])
        b, L = blocker(game, me)
        b !== nothing && (worst = (i, b, L))
    end
    screenshot(game, "s58_kite_running_view")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(worst === nothing, "a creature stands in the camera's line to Lumi: $(worst)")
end

uitest("Kite player (s58): Lumi is in view right after jumping in, not hidden behind a house or a friend") do game
    me = play_kite!(game)
    screenshot(game, "s58_kite_jumpin_view")
    b, L = blocker(game, me)
    ons = XP.on_screen(game.stage.scene, Point3f(me.pos))
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(ons !== nothing, "Lumi is off screen right after Play (eye $(game.rig.eye), Lumi $(me.pos))")
    check(b === nothing, "right after Play the camera line to Lumi is blocked by $(b)")
end
