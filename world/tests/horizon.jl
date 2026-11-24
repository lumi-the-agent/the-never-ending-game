# The sea meets the sky in a clean line: with the sky's ground off, the edge of the baked sky map
# drew a jagged grey sawtooth along the horizon (todos #131, #171; scenery.jl SKY_GROUND).
uitest("The sea horizon is a clean line, no jagged sawtooth band") do game
    NG = NeverendingGame
    rig = game.rig
    mode, eye, target = rig.mode, rig.eye, rig.target
    rig.mode = :fixed
    rig.eye = Point3f(0, -20, 3); rig.target = Point3f(0, -200, 2)        # out over the open sea
    wait_frames(game, 4)
    img = Makie.colorbuffer(game.screen)
    path = screenshot(game, "horizon")
    rig.mode = mode; rig.eye = eye; rig.target = target
    # the horizon row is where the brightness drops the most; a sawtooth shows as a ripple along the rows round it
    h, wd = size(img)
    cols = round(Int, 0.02wd):round(Int, 0.6wd)                            # the 3D view, left of the panel
    lum(r) = [Float32(Gray(img[r, c])) for c in cols]
    rows = round(Int, 0.2h):round(Int, 0.8h)
    means = [sum(lum(r)) / length(cols) for r in rows]
    k = argmax([means[i] - means[i + 2] for i in 1:(length(means) - 2)])
    hz = rows[k]
    ripple(r) = (v = lum(r); m = sort(v)[length(v) ÷ 2]; sort(abs.(v .- m))[round(Int, 0.9length(v))])   # 90th percentile deviation
    worst = maximum(ripple(r) for r in (hz - 6):(hz + 6))
    check(worst < 0.03f0, "the horizon (row $hz) ripples by $(round(worst; digits = 3)) along the line: a sawtooth band ($path)")
    sky = first(l for l in Makie.get_lights(game.stage.scene) if l isa Makie.SunSkyLight)
    check(sky.ground_enabled, "the sky has no ground below the horizon (it is black there and the band shows)")
end
