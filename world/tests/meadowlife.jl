uitest("The meadows have stones, daisies and toadstools in the grass, out of everyone's way") do game
    NG = NeverendingGame
    ML = Main.MEADOWLIFE
    wait_frames(game, 3)
    pieces = get(ML, :pieces, nothing)
    check(pieces !== nothing, "the meadow clusters were never built (key $(get(ML, :key, nothing)))")
    for k in (:stones, :daisies, :toadstools)
        check(length(pieces[k]) >= 10, "only $(length(pieces[k])) $(k) on the island")
        p = ML[:plots][k]
        check(p.parent === game.stage.scene && p.visible[], "the $(k) plot is not in the scene")
    end
    # none on a path, in the pond or inside a tree or bush
    a = game.plugins["areas"].mod
    w = game.world
    for (k, ps) in pieces, (q, _, _) in ps
        check(hypot(q[1] - a.POND[1], q[2] - a.POND[2]) > a.POND_R, "a $(k) stands in the lily pond at $(q)")
        for p in w.props
            p.kind in (:tree, :bush) || continue
            check(hypot(q[1] - p.pos[1], q[2] - p.pos[2]) > NG.SOLID_FOOTPRINT[p.kind] * p.scale, "a $(k) at $(q) grows inside a $(p.kind)")
        end
    end
    # the eye-level view's foreground has some
    r = w.island.radius
    eye = (-0.7r, -0.2r)
    near = count(((q, _, _),) -> hypot(q[1] - eye[1], q[2] - eye[2]) < 12, reduce(vcat, collect(values(pieces))))
    check(near >= 8, "only $(near) meadow things within 12 m of the eye-level camera")
    screenshot(game, "meadowlife")
end

uitest("No stars while the sunset sun is still over the sea, and the evening clouds are warm") do game
    w = game.world
    wait_frames(game, 3)
    h = 24 * NeverendingGame.daytime(w)
    12 < h < 20.4 && check(!Main.STARS[:plot].visible[], "stars shine at $(round(h; digits = 2)) h")
    cols = Base.invokelatest(game.plugins["clouds"].mod.puff_colors, Main.CLOUDS[:puffs], w)
    if 17.5 < h < 19.8
        # warm: red above blue on average, and a lit side brighter than the shade side
        check(sum(c -> c.r - c.b, cols) / length(cols) > 0.1, "evening clouds are not warm at $(round(h; digits = 2)) h")
    end
    lum = [c.r + c.g + c.b for c in cols]
    check(maximum(lum) - minimum(lum) > 0.15, "clouds are one flat colour (lum $(extrema(lum)))")
end

uitest("Far trees fade into a soft blue haze at noon, the near meadow stays crisp") do game
    RM = NeverendingGame.RayMakie
    check(isdefined(RM, :RASTER_HAZE), "the renderer has no distance haze")
    wait_frames(game, 3)
    check(RM.RASTER_HAZE[] > 0, "the haze is off ($(RM.RASTER_HAZE[]))")
    screenshot(game, "haze")
end
