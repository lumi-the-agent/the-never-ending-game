const X = NeverendingGame

uitest("Evening light: at 18:24 the island is still golden daylight, not night (the sunset sun is over the sea until ~19:54)") do game
    w = game.world
    X.skip_to_hour!(w, 18.4)
    nf = X.night_factor(w); col = X.sun_color(w)
    check(nf < 0.05, "night factor at 18:24 is $(nf): the island goes dark while the sunset is still on")
    check(col.b < 0.95, "the 18:24 sun is not warm: colour $(col)")
    X.skip_to_hour!(w, 21.0)
    check(X.night_factor(w) > 0.9, "21:00 is not night: night factor $(X.night_factor(w))")
end

uitest("A friend left on the sunset bench gets up when the clock jumps to the morning: the panel never says 'watches the sunset' at 11:00") do game
    w = game.world
    m = game.plugins["lookout"].mod
    X.skip_to_hour!(w, 18.0)
    c = first(c for c in w.creatures if c.name != "Lumi" && !c.controlled)
    c.goal = Base.invokelatest(m.sit_goal, w, 2); m.L[:sitters] = [c.id]
    X.skip_to_hour!(w, 11.0)
    wait_seconds(game, 1.0)
    check(c.goal.kind !== :sunset, "$(c.name) still sits on the bench for the sunset at 11:00 (goal $(c.goal.kind))")
end

uitest("Lumi's workshop corner: a workbench and a crate pile stand by the cottage, off the path and the pond") do game
    wait_seconds(game, 2.0)
    WS = Main.WORKSHOP
    check(get(WS, :spot, nothing) !== nothing, "no open corner found beside the cottage")
    plots = get(WS, :plots, Dict())
    check(haskey(plots, :bench) && haskey(plots, :crate), "workshop pieces drawn: $(collect(keys(plots)))")
    names = [p.attributes[:name][] for p in game.stage.scene.plots if haskey(p.attributes, :name)]
    check(:workshop_bench in names, "the workbench is not in the scene")
end

uitest("A friend walking straight at the workbench goes round it, never through it") do game
    wait_seconds(game, 1.0)
    sol = get(Main.EXTRA_SOLIDS, "workshop", nothing)
    check(sol !== nothing, "the workbench has no footprint")
    (q, a) = Main.WORKSHOP[:spot]
    out = Point2f(cos(a), sin(a))
    c = first(c for c in game.world.creatures if c.name != "Lumi" && !c.controlled && c.action !== :sleep)
    start = q + 2.5f0 * out; goal = q - 1.5f0 * out     # from the open side through the bench towards the cottage
    c.pos = Point3f(start[1], start[2], NeverendingGame.terrain_height(game.world.island, start[1], start[2]))
    c.goal = NeverendingGame.Goal(:explore, Point3f(goal[1], goal[2], 0), :walk, 1.0, game.world.t + 30, false, 0, false)
    closest = Inf32
    for _ in 1:60
        wait_frames(game, 3)
        closest = min(closest, minimum(norm(Point2f(c.pos[1], c.pos[2]) - p) for (p, _) in sol))
    end
    check(closest > 0.4f0, "$(c.name) came $(closest) m from a bench footprint centre (walked through it)")
end

uitest("Steered Lumi holding W into the workbench slides along it and gets past, never through") do game
    game.minigame === nothing || X.stop_minigame!(game)
    X.start_minigame!(game, X.JumpIn)
    wait_seconds(game, 0.5)
    sol = Main.EXTRA_SOLIDS["workshop"]
    (q, a) = Main.WORKSHOP[:spot]
    out = Point2f(cos(a), sin(a))
    c = creature(game.world, "Lumi")
    s0 = q + 2.2f0 * out                         # in front of the bench, walking straight at it
    c.pos = Point3f(s0[1], s0[2], X.terrain_height(game.world.island, s0[1], s0[2]))
    c.yaw = atan(-out[2], -out[1]) - X.species_of(c).heading
    p0 = c.pos; closest = Inf32
    interact!(game, [KeyDown(Keyboard.w)])
    for _ in 1:40
        wait_frames(game, 3)
        closest = min(closest, minimum(norm(Point2f(c.pos[1], c.pos[2]) - p) for (p, _) in sol))
    end
    interact!(game, [KeyUp(Keyboard.w)])
    moved = norm(c.pos - p0)
    X.stop_minigame!(game)
    check(closest > 0.4f0, "Lumi came $(closest) m from a footprint centre (walked through the bench)")
    check(moved > 1.5f0, "Lumi moved only $(moved) m holding W at the bench (stuck against it)")
end
