# Session 51 play checks (tester): the lookout at dusk, and the camera menu while jumped in.
const S51 = NeverendingGame

function s51_lumi(w)
    S51.creature(w, first(c.id for c in w.creatures if c.name == "Lumi"))
end

function s51_menu_name(game)
    names = [string(e) for e in ui_elements(game)]
    "Mini game" in names ? "Mini game" : "Jump in (WASD)"
end

uitest("Sunset bench: at dusk (20:00) nobody stays on the bench, within 12 s") do game
    w = game.world
    game.minigame === nothing || S51.stop_minigame!(game)
    L = Main.LOOKOUT
    me = s51_lumi(w)
    S51.leave_interactions!(w, me); me.controlled = false
    # friends left on the bench by an earlier test (a second gather in one evening orphans them: reported)
    for c in w.creatures
        c.goal.kind === :sunset && (c.goal = S51.Goal(:idle, c.pos, :idle, 1.0, w.t + 1.0, true, 0, false); c.action = :idle)
    end
    S51.skip_to_hour!(w, 17.6)
    # a clock jump makes the vegetable patch visit due and leaves friends asleep from an earlier night jump:
    # a free Lumi (the garden waits) is what a normal evening looks like
    isdefined(Main, :GARDEN) && (Main.GARDEN[:next_tend] = w.t + 1e6)
    me.action === :sleep && (me.action = :idle)
    me.goal = S51.Goal(:idle, me.pos, :idle, 20.0, w.t + 20, true, 0, false)
    L[:day] = -1
    t0 = w.t
    while length([c for c in w.creatures if c.goal.kind === :sunset && c.goal.arrived]) < 1 && w.t - t0 < 60
        wait_seconds(game, 2)
    end
    seated = [c.name for c in w.creatures if c.goal.kind === :sunset && c.goal.arrived]
    check(!isempty(seated), "nobody sat down at the bench within 60 s of 17:36 (Lumi $(me.goal.kind)/$(me.action), L day $(L[:day]), sitters $(get(L, :sitters, nothing)), next tend in $(round(get(Main.GARDEN, :next_tend, 0.0) - w.t)) s)")
    screenshot(game, "s51-tester-bench")
    S51.skip_to_hour!(w, 20.0)
    t1 = w.t
    while any(c -> c.goal.kind === :sunset, w.creatures) && w.t - t1 < 12
        wait_seconds(game, 1)
    end
    left = [(c.name, c.action) for c in w.creatures if c.goal.kind === :sunset]
    check(isempty(left), "still on the bench 12 s after 20:00: $(left)")
    screenshot(game, "s51-tester-dusk")
end

uitest("Jumped in: the camera menu switches orbit and follow, and follow keeps Lumi in view") do game
    w = game.world
    game.minigame === nothing || S51.stop_minigame!(game)
    wait_frames(game, 3)
    S51.skip_to_hour!(w, 11.0)
    menu = game.dash.play_menu     # the menu shows whatever game was chosen last (a test before may have left Berry race)
    mg = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, mg)), LeftClick(), Wait(0.3),
        Lazy(_ -> MouseTo(ui_option_pos(game, mg, "Jump in (WASD)"))), LeftClick(), Wait(0.3)])
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(2.0)])
    check(game.minigame isa S51.JumpIn, "Play did not start Jump in ($(typeof(game.minigame)); menu $(menu.selection[]) / $(menu.prompt[]))")
    interact!(game, [MouseTo(ui_pos(game, "Camera: follow")), LeftClick(), Wait(0.3),
        Lazy(_ -> MouseTo(ui_option_pos(game, "Camera: follow", "Camera: orbit"))), LeftClick(), Wait(1.5)])
    check(game.rig.mode !== :follow, "orbit picked but the rig is still $(game.rig.mode)")
    screenshot(game, "s51-tester-orbit")
    interact!(game, [MouseTo(ui_pos(game, "Camera: orbit")), LeftClick(), Wait(0.3),
        Lazy(_ -> MouseTo(ui_option_pos(game, "Camera: orbit", "Camera: follow"))), LeftClick(), Wait(2.0)])
    me = s51_lumi(w)
    check(game.rig.mode in (:follow, :fixed), "follow picked but the rig is $(game.rig.mode)")
    d = hypot(game.rig.eye[1] - me.pos[1], game.rig.eye[2] - me.pos[2])
    check(0.5 < d < 25, "follow eye is $(round(d; digits = 1)) m from Lumi")
    screenshot(game, "s51-tester-follow")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(game.minigame === nothing, "Stop did not end Jump in")
end
