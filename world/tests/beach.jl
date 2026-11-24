const BEACH_NG = NeverendingGame

uitest("Shell beach: a sandy cove with driftwood, shells, starfish and dune grass") do game
    B = Main.BEACH
    plots = get(B, :plots, Any[])
    names = [p.attributes[:name][] for p in plots]
    for n in (:beach_driftwood, :beach_shells, :beach_starfish, :beach_dunegrass)
        check(n in names, "no $n plot (have $names)")
    end
    check(all(p -> p.visible[] && p in game.stage.scene.plots, plots), "some beach plots are hidden or not in the stage")
    th = B[:things]
    check(length(th[:shells]) >= 10 && length(th[:starfish]) >= 6 && length(th[:dunegrass]) >= 30,
          "too few things on the beach: $(Dict(k => length(v) for (k, v) in th))")
    m = game.plugins["meadow"].mod
    is = game.world.island
    sandy = count(p -> first(Base.invokelatest(m.beach_weight, is, p[1], p[2])) > 0.8f0, th[:shells])
    check(sandy == length(th[:shells]), "only $sandy of $(length(th[:shells])) shells lie on the sand")
    trees = count(p -> p.kind in (:tree, :bush) && first(Base.invokelatest(m.beach_weight, is, p.pos[1], p.pos[2])) > 0.3f0, game.world.props)
    check(trees == 0, "$trees trees or bushes stand on the beach")
    a = m.BEACH_A; rc = Base.invokelatest(m.coast_r, is, a)
    game.rig.mode = :fixed
    game.rig.target = Point3f((rc - 3) * cos(a), (rc - 3) * sin(a), 0.5)
    game.rig.eye = Point3f((rc + 7) * cos(a) - 6, (rc + 7) * sin(a), 6)
    wait_seconds(game, 1.5)
    screenshot(game, "beach_cove")
    game.rig.mode = :follow
end

uitest("A critter walks down to the beach and finds a shell or a starfish") do game
    w = game.world
    # no new game of tag for the next minute: one started with the beachcomber mid-walk (s53, "goal tag")
    TS = Main.TAG_STATE; TS[:next] = max(TS[:next], w.t + 60)
    tagging = TS[:game] === nothing ? Int32[] : TS[:game][:players]
    c = first(filter(c -> !c.controlled && c.name != "Lumi" && c.action !== :sleep && !(c.goal.kind in BEACH_NG.BUSY_GOALS) && !(c.id in tagging), w.creatures))
    BEACH_NG.leave_interactions!(w, c)
    c.goal = BEACH_NG.start_goal(Val(:beachcomb), c, w)
    check(c.goal !== nothing, "no free shell to look at")
    t = c.goal.target
    # start on the sand a few metres up the beach from the find
    d = BEACH_NG.Vec2f(t[1], t[2]); d = d / sqrt(d[1]^2 + d[2]^2)
    c.pos = BEACH_NG.ground(w.island, (t[1] - 3.0f0 * d[1], t[2] - 3.0f0 * d[2]))
    said = Ref(false)
    for _ in 1:30
        wait_seconds(game, 0.5)
        any(s -> s.who == c.id, w.speech) && c.goal.kind === :beachcomb && (said[] = true)
        said[] && break
    end
    check(c.goal.kind === :beachcomb && c.goal.arrived,
          "$(c.name) did not reach the find (pos $(c.pos), target $t, goal $(c.goal.kind), action $(c.action))")
    check(said[], "$(c.name) said nothing about the find")
    game.rig.mode = :fixed; game.rig.eye = Point3f(c.pos[1] - 2.5, c.pos[2] - 2.5, c.pos[3] + 1.8); game.rig.target = c.pos
    wait_seconds(game, 1.5)
    screenshot(game, "beachcomb")
    game.rig.mode = :follow
end
