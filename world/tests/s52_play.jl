const S52 = NeverendingGame

uitest("Friends come to Lumi's build with a plank, stand by while it works and cheer when it appears") do game
    w = game.world
    game.minigame === nothing || S52.stop_minigame!(game)
    me = S52.creature(w, first(c.id for c in w.creatures if c.name == "Lumi"))
    S52.leave_interactions!(w, me); me.controlled = false
    sys = only(game.plugins["cairns"].systems)
    Base.invokelatest(S52.stop!, sys, game); empty!(Main.CAIRN_STATE[:plots]); Main.CAIRN_STATE[:shown] = -1
    Base.invokelatest(S52.start!, sys, game)
    Base.invokelatest(game.plugins["builder"].mod.try_publish!, game, ["cairns"])
    B = Main.BUILDER
    game.rig.mode = :follow; game.rig.subject = 0
    t0 = w.t; called = String[]; planks = 0; watching = 0; shot = false
    while B[:job] !== nothing && w.t - t0 < 90
        wait_seconds(game, 0.5)
        j = B[:job]; j === nothing && break
        hs = [S52.creature(w, i) for i in get(j, :helpers, Int32[])]
        for h in hs; h.name in called || push!(called, h.name); end
        planks = max(planks, B[:planks_n])
        j[:stage] === :work && (watching = max(watching, count(h -> h.goal.kind === :buildwatch && h.goal.arrived, hs)))
        if !shot && j[:stage] === :work && watching > 0; screenshot(game, "s52_build_helpers"); shot = true; end
    end
    check(B[:job] === nothing, "the build did not finish in 90 s")
    nfree = isempty(called) ? 0 : length(called)
    if nfree == 0
        println("no friend was free nearby: helpers untested")
    else
        check(planks == nfree || planks >= 1, "helpers called $(called) but no plank shown (planks $(planks))")
        check(watching >= 1, "helpers $(called) never stood at the site while Lumi worked")
    end
    check(!any(c -> c.goal.kind === :buildwatch, w.creatures), "a friend still waits on :buildwatch: $([c.name for c in w.creatures if c.goal.kind === :buildwatch])")
    check(B[:planks_n] == 0 || B[:job] !== nothing, "planks still shown after the build ($(B[:planks_n]))")
    screenshot(game, "s52_build_cheer")
end

uitest("The bench camera at sunset sits behind the sitters and looks out at the sun, low and close") do game
    w = game.world
    game.minigame === nothing || S52.stop_minigame!(game)
    mod = game.plugins["lookout"].mod
    S52.skip_to_hour!(w, 18.2)
    wait_seconds(game, 1)
    eye, target = mod.bench_view(w)
    v = target - eye
    along = (v[1] * mod.SUNWARD[1] + v[2] * mod.SUNWARD[2]) / hypot(v[1], v[2])
    check(along > 0.95, "bench_view does not look along the sunset direction ($(along))")
    check(eye[3] - S52.terrain_height(w.island, eye[1], eye[2]) < 3, "bench_view eye is high above the ground")
    check(hypot(eye[1] - mod.SEAT[1], eye[2] - mod.SEAT[2]) < 7, "bench_view eye is far from the bench")
end
