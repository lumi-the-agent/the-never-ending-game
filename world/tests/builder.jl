const BUILD_NG = NeverendingGame

uitest("After a publish Lumi carries a crate to the new thing, works there, and it appears when Lumi is done") do game
    w = game.world
    game.minigame === nothing || BUILD_NG.stop_minigame!(game)
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    # a build still going from earlier (a tester's publish, the test before) would come first: finish it (s53)
    B0 = Main.BUILDER; bmod = game.plugins["builder"].mod
    B0[:job] === nothing || Base.invokelatest(bmod.reveal!, game, B0[:job])
    foreach(j -> Base.invokelatest(bmod.reveal!, game, j), B0[:jobs]); empty!(B0[:jobs]); B0[:job] = nothing
    # the cairn is "published" again: its system starts afresh (new plots), then the publish hook runs
    sys = only(game.plugins["cairns"].systems)
    Base.invokelatest(BUILD_NG.stop!, sys, game); empty!(Main.CAIRN_STATE[:plots]); Main.CAIRN_STATE[:shown] = -1
    Base.invokelatest(BUILD_NG.start!, sys, game)
    Base.invokelatest(game.plugins["builder"].mod.try_publish!, game, ["cairns"])
    B = Main.BUILDER
    wait_seconds(game, 0.5)
    job = B[:job]
    check(job !== nothing, "no build job after the publish (jobs $(length(B[:jobs])))")
    # the cairn's own plots: the job also holds whatever other plugins made in that frame (the showers'
    # rainbow, which the showers plugin shows by itself after rain: s52 "not hidden" was the rainbow)
    plots = [p for j in [[job]; B[:jobs]] for (p, _) in j[:plots] if haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "cairn")]
    wanted = copy(job[:plots])      # each new plot with its visibility at the publish (a rainbow is hidden by day)
    check(!isempty(plots) && all(p -> !p.visible[], plots), "the new cairn plots are not hidden while it is being built ($(length(plots)) cairn plots, $(count(p -> p.visible[], plots)) visible, $(length(job[:plots])) in the job, $(length(B[:jobs])) more jobs)")
    check(job[:who] == me.id, "the builder is not Lumi (who $(job[:who]), Lumi $(me.action) $(me.goal.kind))")
    crate = B[:plots][:crate]
    check(crate.markersize[][1] != BUILD_NG.Vec3f(0), "no crate over the builder's head (stage $(job[:stage]), who $(job[:who]), Lumi $(me.goal.kind) $(me.action) arrived $(me.goal.arrived), $(round(hypot(me.pos[1] - job[:centre][1], me.pos[2] - job[:centre][2]), digits = 1)) m from the site)")
    t0 = w.t; shot = false; watched = false
    while B[:job] !== nothing && w.t - t0 < 70
        wait_seconds(game, 1)
        B[:job] !== nothing && B[:job][:stage] === :work && BUILD_NG.AUTO_SUBJECT[][1] == me.id && (watched = true)
        if !shot && B[:job] !== nothing && B[:job][:stage] === :work
            screenshot(game, "builder_work"); shot = true
        end
    end
    check(B[:job] === nothing, "the build did not finish in 70 s (stage $(B[:job] === nothing ? :none : B[:job][:stage]), Lumi $(me.goal.kind) $(me.action))")
    check(watched, "the camera never watched Lumi at work (it watched $(BUILD_NG.AUTO_SUBJECT[][1]))")
    sc = game.stage.scene
    back = [(get(p.attributes, :name, nothing) === nothing ? :none : p.attributes[:name][], p.visible[], v) for (p, v) in wanted if p in sc.plots]
    check(all(b -> b[2] == b[3], back), "the new things did not come back as they were after the build (name, now, before: $(back))")
    stones = [p for p in sc.plots if haskey(p.attributes, :name) && p.attributes[:name][] === :cairn_stones]
    check(!isempty(stones) && all(p -> p.visible[], stones), "the cairn did not appear after the build ($(length(stones)) cairn plots, visible $([p.visible[] for p in stones]))")
    check(any(s -> s.who == me.id && occursin("Ta-da", s.text), w.speech), "Lumi said no 'Ta-da'")
    # friends who were free nearby came to watch and cheered (s52); none free is fine, but nobody stays on :buildwatch
    check(!any(c -> c.goal.kind === :buildwatch, w.creatures), "a friend still stands watching after the build: $([c.name for c in w.creatures if c.goal.kind === :buildwatch])")
    screenshot(game, "builder_done")
end

uitest("Lumi thinks about the todo the agent is on: a cloud over its head with the doing todo in a few words") do game
    w = game.world
    game.minigame === nothing || BUILD_NG.stop_minigame!(game)
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    me.controlled = false
    mod = game.plugins["builder"].mod
    B = Main.BUILDER
    # the thought is the doing todo, read from the shared todo list
    doing = filter(t -> t.status === :doing, BUILD_NG.load_todos(BUILD_NG.todo_path(game)))
    B[:thought_read] = -Inf
    th = Base.invokelatest(mod.current_thought, game)
    # what the agent said it is making (think!, the last three hours) comes first, the doing todo is the fallback
    tf = BUILD_NG.thought_file(game.paths)
    said = isfile(tf) ? BUILD_NG.read_json(tf) : nothing
    if said !== nothing && time() - said["unix"] < 3 * 3600
        check(th == Base.invokelatest(mod.short_thought, string(said["text"])), "the thought is $(repr(th)), not what Lumi said it makes: $(repr(said["text"]))")
    elseif isempty(doing)
        check(th === nothing, "a thought without a doing todo: $(th)")
        return
    else
        check(th == Base.invokelatest(mod.few_words, last(doing).title), "the thought is $(repr(th)), not the doing todo $(repr(last(doing).title))")
    end
    th === nothing && return
    check(length(split(th)) <= 7, "the thought is not a few words: $(th)")
    # the camera on an awake Lumi: the cloud stands over its head
    (me.action === :sleep || me.goal.kind === :sleep) && (me.goal = BUILD_NG.Goal(:idle, me.pos, :idle, 20.0, game.world.t + 20, true, 0, false); me.action = :idle)
    game.rig.mode = :follow; game.rig.subject = me.id
    # the cloud waits while Lumi speaks (by design): give it up to 8 s of quiet, awake time to show
    for _ in 1:16
        filter!(b -> b.who != me.id, w.speech)
        wait_seconds(game, 0.5)
        B[:thought_shown] && break
    end
    T = B[:thought_plots]
    pts = T[:cloud][1][]
    head = BUILD_NG.on_screen(game.stage.scene, BUILD_NG.head_point(w, me))
    check(head !== nothing, "Lumi's head is not on screen in its follow view")
    check(B[:thought_shown] && T[:text].text[] in (th, [th]), "the bubble shows $(repr(T[:text].text[])) (shown $(B[:thought_shown]); Lumi $(me.action)/$(me.goal.kind), controlled $(me.controlled), speaking $(any(s -> s.who == me.id && s.until > w.t, w.speech)), minigame $(game.minigame !== nothing), hour $(round(24 * BUILD_NG.daytime(w); digits = 1)))")
    check(last(pts)[2] > head[2] + 40, "the cloud is not above Lumi's head (cloud $(last(pts)), head $(head))")
    screenshot(game, "builder_thought")
    game.rig.subject = 0
end
