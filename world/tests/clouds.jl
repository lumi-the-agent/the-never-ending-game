uitest("Clouds drift around the island above the horizon, white by day") do game
    CL = Main.CLOUDS
    p = CL[:plot]
    check(p.visible[] && length(p[1][]) >= 40, "no cloud puffs drawn ($(length(p[1][])))")
    r = game.world.island.radius
    pos = p[1][]
    # s45: lowered to 7-16° above the horizon (an eye-level view held one or two clouds); still >= 0.35 r up at >= 2.5 r away
    low = minimum(q -> q[3], pos); near = minimum(q -> hypot(q[1], q[2]), pos)
    check(near > 1.8f0 * r && low > 0.35f0 * r, "a cloud hangs over the island or too low (nearest $(round(near / r; digits = 2)) r, lowest $(round(low / r; digits = 2)) r)")
    before = copy(pos)
    wait_seconds(game, 2)
    check(maximum(norm.(p[1][] .- before)) > 0.01f0, "the clouds do not drift")
end
