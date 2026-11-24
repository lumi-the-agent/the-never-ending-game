const AREAS_NG = NeverendingGame

uitest("Path, pond and pier are on the island") do game
    plots = get(Main.AREA_PLOTS, :plots, Any[])
    names = [p.attributes[:name][] for p in plots]
    for n in (:area_path, :area_pond, :area_pier_planks)
        check(n in names, "no $n plot (have $names)")
    end
    check(all(p -> p.visible[], plots), "some area plots are hidden")
    game.rig.mode = :fixed; game.rig.eye = Point3f(6, -6, 14); game.rig.target = Point3f(-4, 7, 1)
    wait_seconds(game, 1.5)
    screenshot(game, "areas_overview")
    game.rig.mode = :follow
end

uitest("A creature walks out on the pier and fishes") do game
    w = game.world
    c = first(filter(c -> !c.controlled && c.name != "Lumi", w.creatures))
    for o in w.creatures   # a free pier: everyone else stops fishing
        if o.goal.kind === :fish   # and off the narrow deck: an idle ex-fisher there blocks the way (failed once)
            o.pos = AREAS_NG.ground(w.island, (rand(Float32) * 4 - 2, rand(Float32) * 4 - 2))
            o.goal = AREAS_NG.start_goal(Val(:idle), o, w)
        end
    end
    c.goal = AREAS_NG.start_goal(Val(:fish), c, w)
    check(c.goal !== nothing, "no free fishing spot")
    root = c.goal.target   # anyone else standing on the low deck (a dancer, a fisher on the way) blocks the 6 m plank walk (failed in the suite)
    for o in w.creatures
        o === c && continue
        if o.pos[3] < 1.0f0 && hypot(o.pos[1] - root[1], o.pos[2] - root[2]) < 9
            AREAS_NG.leave_interactions!(w, o)
            o.pos = AREAS_NG.ground(w.island, (rand(Float32) * 4 - 2, rand(Float32) * 4 - 2))
            o.goal = AREAS_NG.start_goal(Val(:idle), o, w)
        end
    end
    c.pos = AREAS_NG.ground(w.island, c.goal.target)      # start at the root of the pier
    wait_seconds(game, 18)   # slow species need a while for the 6 m deck
    check(c.goal.kind === :fish && c.goal.arrived, "$(c.name) did not reach the fishing spot (pos $(c.pos), goal $(c.goal.kind))")
    check(c.pos[3] > 0.5f0, "$(c.name) is not standing on the deck (z = $(c.pos[3]))")
    rods = Main.AREA_PLOTS[:fishing][:rods]
    check(length(rods[1][]) >= 1, "no fishing rod drawn")
    game.rig.mode = :fixed; game.rig.eye = Point3f(c.pos[1] - 3, c.pos[2] - 4, 3); game.rig.target = c.pos
    wait_seconds(game, 1.5)
    screenshot(game, "fishing")
    game.rig.mode = :follow
    c.goal = AREAS_NG.start_goal(Val(:idle), c, w)
end

uitest("The side panel talks to the player, not about development") do game
    d = game.dash
    text = join([d.agent.text[], d.activity.text[], d.messages.text[], d.todos.text[]], "\n")
    for word in ("token", "test", "session report", "RayMakie", "verdict", "stack")
        check(!occursin(word, text), "side panel mentions '$word': $text")
    end
end

uitest("At night the lanterns and the cottage throw warm light pools") do game
    lamps = game.plugins["lamplight"].mod
    wait_frames(game, 2)
    pools = Main.LAMPLIGHT[:pools]; flames = Main.LAMPLIGHT[:flames]
    srcs = Base.invokelatest(lamps.light_sources, game)
    check(count(s -> s[4] === :lantern, srcs) >= 2, "found $(length(srcs)) light sources")
    check(any(s -> s[4] === :cottage, srcs), "the cottage is not a light source")
    night = NeverendingGame.night_factor(game.world) > 0.3f0
    check(pools.visible[] == night && flames.visible[] == night, "pools visible=$(pools.visible[]) at night=$night")
    # each pool is warm (more red than blue) and fades out to the rim
    cols = pools.color[]
    check(all(c -> c.r > c.b, cols), "a pool is not warm")
    check(maximum(c -> c.alpha, cols) >= 0.5 && minimum(c -> c.alpha, cols) < 0.01, "pools do not fade to the rim")
    Main.LAMPLIGHT[:force] = true
    wait_frames(game, 2)
    check(pools.visible[], "forcing the light on did not show the pools")
    win = Main.LAMPLIGHT[:windows]
    check(win.visible[] && length(win[1][]) >= 2, "the cottage windows do not light up")
    halos = Main.LAMPLIGHT[:halos]
    hc = halos.color[]
    check(halos.visible[] && length(halos[1][]) >= 9 * 3, "no warm halos round the windows and lanterns ($(length(halos[1][])) shells)")
    check(all(c -> c.r > c.b && 0 < c.alpha < 0.2, hc), "a halo shell is not a faint warm glow")
    screenshot(game, "lamplight")
    Main.LAMPLIGHT[:force] = false
    wait_frames(game, 2)
end

uitest("Follow camera: a view low along the pier planks counts as blocked, a view from above does not") do game
    NG = NeverendingGame
    w = game.world
    pts = [(x, y) for x in -30f0:0.5f0:30f0, y in -30f0:0.5f0:30f0 if NG.walkway_height(x, y) !== nothing]
    check(length(pts) >= 10, "no pier found ($(length(pts)) walkway points)")
    a, b = pts[length(pts) ÷ 2], pts[end]
    h = NG.walkway_height(a...)
    low = NG.obstruction(w, Point3f(a[1], a[2], h + 0.6f0), Point3f(b[1], b[2], h + 0.5f0))
    high = NG.obstruction(w, Point3f(a[1], a[2], h + 4.0f0), Point3f(b[1], b[2], h + 0.5f0))
    check(low >= 1 && low > high, "pier planks under the lens are not counted: low view $low, high view $high")
end

uitest("The golden flower field on the open south-east meadow is planted with flowers you can pick, in view of the overview") do game
    w = game.world
    c, r = game.plugins["meadow"].mod.FLOWER_FIELD
    field = [p for p in w.props if p.kind === :flower && get(p.data, "field", false) == true]
    check(length(field) >= 20, "only $(length(field)) flowers in the field")
    check(all(p -> hypot(p.pos[1] - c[1], p.pos[2] - c[2]) < r, field), "a field flower outside the field")
    fg = game.plugins["flowergift"].mod
    check(count(p -> any(q -> q.id == p.id, Base.invokelatest(fg.flowers, w)), field) >= 10, "the field flowers cannot be picked")
    # the field lies in the open, where the overview camera sees it (s41 review: behind the pines it did not read)
    trees = [p for p in w.props if p.kind === :tree]
    check(all(t -> hypot(t.pos[1] - c[1], t.pos[2] - c[2]) > 0.5r, trees), "a tree stands in the middle of the field")
    rad = w.island.radius
    game.rig.mode = :fixed; game.rig.eye = Point3f(0.55rad, -0.75rad, 0.6rad); game.rig.target = Point3f(0, 0, 0)   # the progress overview
    wait_seconds(game, 1.5)
    check(NeverendingGame.on_screen(game.stage.scene, Point3f(c[1], c[2], 0.3)) !== nothing, "the field is out of the overview")
    screenshot(game, "flower_field_overview")
    game.rig.eye = Point3f(c[1] + 6, c[2] - 6, 4); game.rig.target = Point3f(c[1], c[2], 0.5)
    wait_seconds(game, 1.5)
    screenshot(game, "flower_field")
    game.rig.mode = :follow
end

uitest("Butterflies flutter over the flower field by day and move between flowers") do game
    s = only(game.plugins["butterflies"].systems)
    if NeverendingGame.is_night(game.world)
        check(isempty(s.flies), "butterflies out at night")
        return
    end
    wait_frames(game, 2)
    check(length(s.flies) >= 5, "only $(length(s.flies)) butterflies")
    p0 = [f.pos for f in s.flies]
    wait_seconds(game, 3)
    check(count(k -> norm(s.flies[k].pos - p0[k]) > 0.05, eachindex(p0)) >= 1, "no butterfly moved in 3 s")
end
