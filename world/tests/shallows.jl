uitest("The sea is turquoise in the shallows with foam at the beach, deepening to blue further out") do game
    S = Main.SHALLOWS
    p = S[:plot]
    check(p in game.stage.scene.plots && p.visible[], "no shallows ring drawn")
    w = game.world
    base = S[:base]
    nb = length(base) ÷ 360
    # along every ray: foam near the coast, then water that gets bluer and fades out into the open sea
    foam = base[2]; mid = base[4]; far = base[nb - 1]
    check(foam.r > 0.9 && foam.alpha > 0.4, "no foam at the coast: $foam")
    check(mid.g > mid.r + 0.3 && mid.alpha > 0.5, "the shallows are not turquoise: $mid")
    check(far.b > far.g && far.g < mid.g && base[nb].alpha == 0, "the water does not deepen to blue and fade out: $far")
    pts = GeometryBasics.coordinates(p[1][])
    on = count(i -> NeverendingGame.on_land(w.island, pts[i][1], pts[i][2]; margin = 0.05f0), 2:nb:length(pts))
    check(on == 0, "$on foam points lie up on the land, not at the water's edge")
    sw = S[:swash]
    k0 = sw.transformation.scale[][1]
    wait_seconds(game, 1.5)
    check(sw.visible[] && sw.transformation.scale[][1] != k0, "the foam does not wash up and down the beach (scale $k0)")
    screenshot(game, "shallows")
end
