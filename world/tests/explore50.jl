# Session 50 checks: what a player sees of the new things (messages panel, watering camera, jump-in card).
const S50 = NeverendingGame

uitest("The latest message to the human fits the 5 lines of the Messages panel (about 200 characters)") do game
    d = joinpath(game.paths.world, "outbox")
    fs = sort(filter(f -> endswith(f, ".json"), readdir(d)))
    check(!isempty(fs), "no message in the outbox")
    txt = string(S50.read_json(joinpath(d, last(fs)))["text"])
    check(length(txt) <= 200, "the message has $(length(txt)) characters / $(length(split(txt))) words, the panel shows 5 lines (~200 chars) and cuts it mid-sentence: $(repr(txt))")
    check(!occursin("no voice yet", lowercase(txt)) || !isfile(joinpath(game.paths.world, "site", "voice", "hello.mp3")), "the message says Lumi has no voice yet, but site/voice/hello.mp3 exists")
end

uitest("While Lumi waters the patch the follow camera watches Lumi (garden moment)") do game
    w = game.world
    game.minigame === nothing || S50.stop_minigame!(game)
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    me.controlled = false
    S50.skip_to_hour!(w, 11.0)
    me.action === :sleep && (me.action = :idle)
    me.goal = S50.Goal()
    G = Main.GARDEN
    G[:next_tend] = 0.0
    t0 = w.t
    while !(me.goal.kind === :tend && me.goal.arrived) && w.t - t0 < 90     # from the far beach it is a long walk (the harness stops a test at 120 s)
        wait_seconds(game, 1)
    end
    check(me.goal.kind === :tend && me.goal.arrived, "Lumi never reached the gate (goal $(me.goal.kind), at $(me.pos))")
    f = S50.CAMERA_MOMENTS["garden"]
    check(Base.invokelatest(f, w) == me.id, "the garden moment does not ask for Lumi while it waters")
    game.rig.mode = :follow
    tw = w.t
    while first(S50.AUTO_SUBJECT[]) != me.id && me.goal.kind === :tend && w.t - tw < 10
        wait_seconds(game, 0.5)
    end
    screenshot(game, "s50-garden-moment")
    check(first(S50.AUTO_SUBJECT[]) == me.id, "the follow camera watches $(S50.AUTO_SUBJECT[]), not Lumi ($(me.id)) within 10 s of watering (goal $(me.goal.kind), arrived $(me.goal.arrived))")
end

uitest("Jump in: the key card is big at 2 s and shrinks to one line of keys by 8 s") do game
    game.dash.play_menu.i_selected[] = 0; wait_frames(game, 3)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(2.0)])
    check(game.minigame isa S50.JumpIn, "Play started $(typeof(game.minigame))")
    screenshot(game, "s50-jumpin-2s")
    wait_seconds(game, 6)
    screenshot(game, "s50-jumpin-8s")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.2)])
    check(game.minigame === nothing, "Stop did not end Jump in")
end
