# Generated props stand in the world, and the dashboard shows no developer numbers.

uitest("A placed asset is drawn and two of the same asset can coexist") do game
    n0 = count(a -> a isa NeverendingGame.AssetActor, game.world.actors)
    id = only(filter(e -> true, first(NeverendingGame.load_catalog(game.paths), 1)))["id"]
    a1 = NeverendingGame.place_asset(game, id, (0.0, 0.0))
    a2 = NeverendingGame.place_asset(game, id, (1.0, 1.0))
    wait_frames(game, 5)
    check(count(a -> a isa NeverendingGame.AssetActor, game.world.actors) == n0 + 2, "assets were not spawned")
    filter!(a -> a !== a1 && a !== a2, game.world.actors)
    wait_frames(game, 3)
end

uitest("The dashboard shows no token counts") do game
    wait_frames(game, 3)
    d = game.dash
    for t in (d.agent.text[], d.mood.text[], d.activity.text[])
        check(!occursin("tokens", t), "the side panel shows \"$t\"")
    end
end

uitest("Island flora is generated, bright enough, and never metallic") do game
    plots = get(Main.FLORA_PLOTS, :plots, Any[])
    names = Set(p.attributes[:name][] for p in plots)
    check(length(plots) >= 5, "only $(length(plots)) flora plots")
    check(count(n -> startswith(string(n), "flora_tree"), names) >= 3, "fewer than 3 tree varieties: $names")
    C = Makie.Colors
    lum(p) = (img = p.attributes[:color][]; sum(c -> (Float32(C.red(c)) + Float32(C.green(c)) + Float32(C.blue(c))) / 3, img) / length(img))
    for p in plots
        mat = p.attributes[:material][]
        check(mat.metallic_factor == 0, "$(p.attributes[:name][]) is metallic ($(mat.metallic_factor))")
    end
    # the pine's texture is far darker than the broadleaf's: brightened, it reads green instead of black
    byname = Dict(p.attributes[:name][] => p for p in plots)
    broad, pine = byname[:flora_tree_1], byname[:flora_tree_2]
    # one instanced plot per variety, never a plot per tree (every plot goes to each browser that opens the page)
    check(length(plots) <= 16, "$(length(plots)) flora plots: copies must share one instanced plot per variety")
    # the meadow flowers are generated models (pink flowers, pale blue clumps), bright, and the engine's
    # primitive stems and heads are hidden
    flowers = [p for p in plots if startswith(string(p.attributes[:name][]), "flora_flower")]
    check(length(flowers) >= 2, "fewer than 2 flower varieties: $names")
    for f in flowers
        check(lum(f) > 0.4f0, "$(f.attributes[:name][]) is too dark ($(lum(f)))")
    end
    stems = [p for p in game.stage.statics if p.attributes[:name][] === :flower_stems]
    check(all(p -> !p.visible[], stems), "the primitive flower stems are still drawn")
    check(lum(pine) > 0.6f0 * lum(broad), "pines are too dark: $(lum(pine)) vs broadleaf $(lum(broad))")
    game.rig.mode = :fixed; game.rig.eye = Point3f(0, -22, 14); game.rig.target = Point3f(0, 0, 0)
    wait_seconds(game, 1.0)
    screenshot(game, "flora")
    game.rig.mode = :follow
end

uitest("Name tags are light text with a dark outline, day and night") do game
    wait_seconds(game, 0.5)
    t = game.stage.labels.plots[1]
    check(t.strokewidth[] >= 2, "name tags have no outline (strokewidth $(t.strokewidth[]))")
    c = Makie.to_color(game.stage.labels.textcolor[])
    check(Makie.Colors.green(c) > 0.7, "name tag text is dark ($(c)): it vanishes in front of trees")
end

uitest("Flowers glow at night and not by day") do game
    p = Main.NIGHTGLOW[:plot]
    check(length(p[1][]) >= 10, "only $(length(p[1][])) glowing flower heads")
    nf = count(q -> q.kind === :flower, game.world.props)
    check(length(p[1][]) == 3nf, "each flower should have 3 glowing motes over it: $(length(p[1][])) instances for $nf flowers")
    check(length(unique(p.color[])) >= 3, "the motes should come in several hues, not one flat cyan")
    h = Main.NIGHTGLOW[:halo]
    check(h.transparency[] && all(c -> c.alpha < 0.3, h.color[]), "the motes have no soft halo")
    wait_seconds(game, 0.3)
    on = NeverendingGame.night_factor(game.world) > 0.35f0
    check(p.visible[] == on && h.visible[] == on, "glow visible=$(p.visible[]) halo $(h.visible[]) at night factor $(NeverendingGame.night_factor(game.world))")
    if on    # they drift: not the same spots a second later
        a = copy(p[1][]); wait_seconds(game, 1.0)
        check(a != p[1][], "the motes stand still")
    end
end

uitest("Stars come out at night and hide by day") do game
    p = Main.STARS[:plot]
    check(length(p[1][]) >= 200, "only $(length(p[1][])) stars")
    wait_seconds(game, 0.3)
    check(p.visible[] == (NeverendingGame.night_factor(game.world) > 0.5f0), "stars visible=$(p.visible[]) at night factor $(NeverendingGame.night_factor(game.world))")
end

uitest("A glowing moon rises at night above the horizon and hides by day") do game
    nf = NeverendingGame.night_factor(game.world)
    wait_seconds(game, 0.3)
    disc = Main.MOON[:moon1]
    check(disc.visible[] == (nf > 0.4f0), "moon visible=$(disc.visible[]) at night factor $nf")
    check(count(v -> v isa Makie.AbstractPlot, values(Main.MOON)) >= 6, "the moon has no halo shells")
    dir = Base.invokelatest(game.plugins["moon"].mod.moon_dir, game.world)
    check(dir[3] > 0.15, "the moon is too low: elevation $(dir[3])")
    if disc.visible[]
        pos = Makie.translation(disc)[]
        check(pos[3] > 0.1f0 * sqrt(sum(abs2, pos)), "the drawn moon is below the horizon: $pos")
    end
end

uitest("Trees come in several shapes and tints, none near black") do game
    trees = Main.FLORA_PLOTS[:trees]
    check(length(trees) >= 4, "only $(length(trees)) tree varieties")
    # mean texture colour per variety: no two the same, none near black (perfectionist-0024)
    means = map(trees) do v
        img = v.plot.color[]
        sum(c -> Makie.RGBf(c.r, c.g, c.b), img) / length(img)
    end
    for m in means
        check(m.r + m.g + m.b > 0.45, "a tree variety is near black: $m")
    end
    for i in eachindex(means), j in (i + 1):length(means)
        d = abs(means[i].r - means[j].r) + abs(means[i].g - means[j].g) + abs(means[i].b - means[j].b)
        check(d > 0.03, "two tree varieties have the same tint: $(means[i]) $(means[j])")
    end
end

uitest("Placed props are as bright as their generated image (the cottage is not muddy)") do game
    NG = NeverendingGame
    id = "20261122-214627-077-asset"      # the cottage: its baked texture was half as bright as its image
    plain = NG.load_asset(game.paths, id)
    lifted = NG.lifted_asset(game.paths, id)
    l(c) = 0.3f0 * Float32(c.r) + 0.59f0 * Float32(c.g) + 0.11f0 * Float32(c.b)
    med(v) = sort(v)[cld(length(v), 2)]
    a = med([l(c) for c in plain.color if l(c) > 0.04]); b = med([l(c) for c in lifted.color if l(c) > 0.04])
    check(b > 1.4a, "the cottage texture was not brightened ($a -> $b)")
    v = game.actor_views[NG.AssetActor]
    check(haskey(v.plots, id), "the cottage is not drawn")
end

uitest("The browser sky follows the time of day (blue by day, navy at night)") do game
    wait_seconds(game, 0.3)
    sc = game.stage.scene
    check(sc.clear[], "the 3D scene does not paint its background: the browser shows a black sky")
    nf = NeverendingGame.night_factor(game.world)
    bg = sc.backgroundcolor[]
    # dusk and dawn blend: only the clear day (nf < 0.3) and clear night (nf > 0.8) have a fixed colour; between, it must be darker than noon blue
    check(nf > 0.8 ? bg.b < 0.4 : nf < 0.3 ? bg.b > 0.5 : bg.b < 0.75, "sky colour $bg at night factor $nf")
end

uitest("Meadow: the grass has sunny clearings, lush hollows and dark shade under every tree crown") do game
    wait_frames(game, 3)
    sc = game.stage.scene
    terrain = only(p for p in sc.plots if haskey(p.attributes, :name) && p.attributes[:name][] === :terrain)
    cols = terrain.attributes[:color][]
    m, _ = NeverendingGame.terrain_mesh(game.world.island)
    pts = NeverendingGame.GeometryBasics.coordinates(m)
    C = Makie.Colors
    lum(c) = (Float32(C.red(c)) + Float32(C.green(c)) + Float32(C.blue(c))) / 3
    grass = [lum(cols[k]) for (k, p) in enumerate(pts) if p[3] > 0.6f0]
    sorted = sort(grass)
    lo, hi = sorted[round(Int, 0.1 * end)], sorted[round(Int, 0.9 * end)]
    # the engine's meadow spans ~0.33..0.45: painted, clearings and hollows differ clearly
    check(hi - lo > 0.12f0, "the grass is one flat tone: 10%..90% luminance $(round(lo; digits = 3))..$(round(hi; digits = 3))")
    # under each tree crown the ground is darker than in the open meadow
    trees = [p for p in game.world.props if p.kind === :tree]
    under(t) = [lum(cols[k]) for (k, p) in enumerate(pts) if hypot(p[1] - t.pos[1], p[2] - t.pos[2]) < 0.6f0 * t.scale && p[3] > 0.6f0]
    dark = count(t -> (u = under(t); !isempty(u) && sum(u) / length(u) < 0.75f0 * sum(grass) / length(grass)), trees)
    check(dark >= 0.8 * count(t -> !isempty(under(t)), trees), "only $dark of $(length(trees)) trees have shade under the crown")
    # grass tufts: one instanced plot, a few hundred, none on a path or under a crown
    tufts = get(Main.MEADOW, :tufts, nothing)
    check(tufts !== nothing && tufts.visible[], "no grass tufts")
    mm = game.plugins["meadow"].mod
    spots = mm.tuft_spots(game.world; in_the_way = mm.area_check(game))
    check(length(spots) >= 200, "only $(length(spots)) grass tufts")
    check(!any(s -> NeverendingGame.walkway_height(s[1][1], s[1][2]) !== nothing, spots), "a grass tuft on the pier")
    area = game.plugins["areas"].mod
    check(!any(s -> area.in_the_way((pos = s[1], kind = :flower)), spots), "a grass tuft on the dirt path or in the pond")
    check(count(p -> p.attributes[:name][] === :grass_tufts, sc.plots) == 1, "grass tufts must be ONE instanced plot")
end

uitest("A long day: by day 5 real minutes move the clock at most 30 game minutes, and night is at most 35% of the day") do game
    N = NeverendingGame
    w = game.world
    wait_frames(game, 3)
    check(w.day_length == N.DAY_LENGTH && w.day_length >= 18000, "day length $(w.day_length) s (the longday plugin sets N.DAY_LENGTH)")
    # the clock as the world runs it: a copy of the world's day, advanced 300 s from every hour from 7 to 16 (at 17 it is 31 min, dusk speeds up)
    probe = N.new_world(; day_length = w.day_length)
    for h in 7:16
        probe.t = 0.0; N.skip_to_hour!(probe, h)
        check(abs(24N.daytime(probe) - h) < 0.01, "skip_to_hour!($h) landed at $(24N.daytime(probe))")
        d0 = N.daytime(probe); probe.t += 300
        mins = mod(N.daytime(probe) - d0, 1) * 1440
        check(mins <= 30, "5 real minutes from $(h):00 move the clock $(round(mins; digits = 1)) game minutes")
    end
    nights = count(range(0, w.day_length, length = 2001)[1:end-1]) do s
        probe.t = s; N.night_factor(probe) > 0.5f0
    end
    check(nights / 2000 <= 0.35, "night covers $(round(100nights / 2000; digits = 1))% of the day")
end
