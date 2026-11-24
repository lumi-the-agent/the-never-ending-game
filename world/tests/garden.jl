const GARDEN_NG = NeverendingGame

uitest("Lumi's vegetable patch: fenced rows by the pond, and Lumi walks there to water it and the plants grow") do game
    w = game.world
    game.minigame === nothing || GARDEN_NG.stop_minigame!(game)
    G = Main.GARDEN
    check(all(k -> haskey(G, k), (:soil, :fence, :plants, :can)), "the patch is not drawn (keys $(collect(keys(G))))")
    check(length(G[:plants]) == 3 && all(p -> p.visible[], G[:plants]), "not three visible rows of plants")
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    me.controlled = false
    GARDEN_NG.skip_to_hour!(w, 11.0)
    me.action === :sleep && (me.action = :idle)
    me.goal = GARDEN_NG.Goal()
    before = copy(G[:state]["sown"])
    G[:next_tend] = 0.0
    wait_seconds(game, 0.5)
    check(me.goal.kind === :tend, "Lumi did not set off to the patch (goal $(me.goal.kind), action $(me.action))")
    t0 = w.t
    while !get(G, :watered, false) && w.t - t0 < 45
        wait_seconds(game, 1)
    end
    gate = game.plugins["garden"].mod.gate_spot(w)
    check(G[:watered], "Lumi never watered (goal $(me.goal.kind), at $(me.pos), gate $(gate))")
    check(hypot(me.pos[1] - gate[1], me.pos[2] - gate[2]) < 1.5, "Lumi watered $(round(hypot(me.pos[1] - gate[1], me.pos[2] - gate[2]), digits = 1)) m from the gate")
    check(all(G[:state]["sown"] .< before), "the rows did not grow from the watering")
    screenshot(game, "garden_water")
end

uitest("While Lumi waters the patch it holds the can and drops fall on the front row, then the row shines") do game
    w = game.world
    game.minigame === nothing || GARDEN_NG.stop_minigame!(game)
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    me.controlled = false
    GARDEN_NG.skip_to_hour!(w, 11.0)
    me.action === :sleep && (me.action = :idle)
    GARDEN_NG.leave_interactions!(w, me)
    me.goal = GARDEN_NG.Goal()
    Main.GARDEN[:next_tend] = 0.0
    Base.invokelatest(game.plugins["garden"].mod.tend!, game)
    t0 = w.t
    while !(me.goal.kind === :tend && me.goal.arrived && !get(Main.GARDEN, :detour, false)) && w.t - t0 < 90
        wait_seconds(game, 1)
    end
    check(me.goal.kind === :tend && me.goal.arrived, "Lumi never reached the gate (goal $(me.goal.kind), at $(me.pos))")
    wait_seconds(game, 1)
    P = Main.WATERING[:plots]
    n = length(P[:drops][1][])
    check(n > 10 && Main.WATERING[:can_at] !== nothing && first(Main.WATERING[:can_at]) != GARDEN_NG.Makie.Vec3f(0), "no stream while watering ($n drops, can offset $(Main.WATERING[:can_at]))")
    screenshot(game, "s56-watering")
    check(Main.WATERING[:shine_until] > w.t + 30, "the row does not shine after the watering")
end
