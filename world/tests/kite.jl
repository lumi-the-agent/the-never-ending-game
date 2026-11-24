# Session 57: the kite (plugins/kite.jl).
const KT = NeverendingGame

uitest("On an afternoon Lumi flies its kite high over the meadow, friends watch, and the string passes on") do game
    w = game.world
    game.minigame === nothing || KT.stop_minigame!(game)
    mod = game.plugins["kite"].mod
    K = Main.KITE
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    KT.leave_interactions!(w, me); me.controlled = false
    h = 24 * KT.daytime(w)
    (h < 13.2 || h > 15.5) && KT.skip_to_hour!(w, 13.5)
    me.action === :sleep && (me.action = :idle)
    me.needs.energy = max(me.needs.energy, 0.9)
    isdefined(Main, :GARDEN) && (Main.GARDEN[:next_tend] = w.t + 1e6)
    isdefined(Main, :PRESENTS) && haskey(Main.PRESENTS, :next) && (Main.PRESENTS[:next] = w.t + 1e6)
    me.goal = KT.Goal(:idle, me.pos, :idle, 20.0, w.t + 20, true, 0, false)
    K[:day] = -1; K[:retry] = -Inf
    # Lumi may be busy a moment (a sigh when lonely, :feel): the kite retries until it is free
    t1 = w.t
    while me.goal.kind !== :kite && w.t - t1 < 40
        K[:retry] = -Inf
        wait_seconds(game, 1)
    end
    check(me.goal.kind === :kite, "Lumi did not go out with its kite at $(round(24 * KT.daytime(w); digits = 1)) h (goal $(me.goal.kind), action $(me.action), flyer $(K[:flyer]))")
    t0 = w.t
    while !(K[:flyer] != 0 && get(K, :up, false)) && w.t - t0 < 60
        wait_seconds(game, 1)
    end
    f = mod.flyer(w)
    check(f !== nothing && K[:up], "the kite never went up (flyer $(K[:flyer]), Lumi $(me.goal.kind) at $(me.pos), $(round(hypot(me.pos[1] - K[:spot][1], me.pos[2] - K[:spot][2]); digits = 1)) m from the spot)")
    wait_seconds(game, 6)
    kite = only(filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :kite, game.stage.scene.plots))
    check(kite.visible[], "the kite plot is hidden while it flies")
    z = Makie.translation(kite)[][3]
    f = mod.flyer(w)
    check(f !== nothing && z - f.pos[3] > 6, "the kite is not high up (kite z $(z), flyer $(f === nothing ? "none" : f.pos))")
    # the follow camera watches the kite (not a dance ring elsewhere), from the kite's own view
    if game.rig.mode === :follow && game.rig.subject == 0 && !any(c -> c.controlled, w.creatures)
        wait_seconds(game, 7)      # past a SUBJECT_HOLD on someone else
        f = mod.flyer(w)
        check(f !== nothing && KT.held_subject(w) == f.id, "the camera does not watch the kite flyer (watches $(KT.held_subject(w)), flyer $(f === nothing ? 0 : f.id), view $(get(K, :view, nothing)))")
    end
    screenshot(game, "s57-kite")
    # the string goes to a friend after a while (when someone watches)
    if !isempty(mod.watchers(w))
        K[:since] = w.t - mod.HANDOVER - 1
        wait_seconds(game, 3)
        f = mod.flyer(w)
        check(f !== nothing, "nobody holds the string after the handover")
    end
    # by evening the kite comes down and everyone is free again
    KT.skip_to_hour!(w, 18.2)
    wait_frames(game, 5)
    check(K[:flyer] == 0 && !kite.visible[], "the kite still flies in the evening (flyer $(K[:flyer]))")
    check(!any(c -> c.goal.kind in (:kite, :kitewatch), w.creatures), "someone is still on a kite goal in the evening")
end
