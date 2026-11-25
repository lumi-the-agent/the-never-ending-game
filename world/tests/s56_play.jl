# Session 56 behaviours played like a person: firefly glow, evening cloud rims, the can that tips, the workshop away from the gate.
const S56 = NeverendingGame

function s56_choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end

uitest("S56 Firefly catch at noon: every fly has its glow shells on it and they move with it") do game
    w = game.world
    game.minigame === nothing || S56.stop_minigame!(game)
    S56.skip_to_hour!(w, 11.0)
    s56_choose(game, "Firefly catch (WASD)")
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.2)])
    m = game.minigame
    check(m !== nothing, "Firefly catch did not start")
    interact!(game, [KeyDown(Keyboard.w), Wait(0.4), KeyUp(Keyboard.w), Wait(0.3)])
    P = Main.FIREFLY_PLOTS
    check(P[:halo].visible[], "the glow shells are hidden while playing")
    h1 = copy(P[:halo][1][])
    flies = copy(P[:flies][1][])
    check(length(h1) == 3 * length(flies), "$(length(h1)) shells for $(length(flies)) flies")
    far = count(i -> norm(h1[i] - flies[(i - 1) ÷ 3 + 1]) > 0.8, eachindex(h1))
    check(far == 0, "$far glow shells are not on their fly")
    sz = P[:halo].markersize[]
    check(sz isa AbstractVector && length(unique(sz)) >= 3, "the shells are not three different sizes: $(typeof(sz))")
    screenshot(game, "s56-firefly-glow")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.2)])
    check(game.minigame === nothing, "Stop did not end the game")
    check(all(p -> p[3] < -5 || !P[:halo].visible[], P[:halo][1][]) || !P[:flies].visible[], "glow shells stay in the sky after Stop")
end

uitest("S56 Evening clouds have faint rim shells that follow the puffs") do game
    w = game.world
    game.minigame === nothing || S56.stop_minigame!(game)
    S56.skip_to_hour!(w, 19.4)
    wait_seconds(game, 1)
    C = Main.CLOUDS
    check(haskey(C, :fringe) && haskey(C, :plot), "no clouds plots")
    # since s75 the clouds are lit clay puffs without rim shells (clouds.jl SHADED): then only the puffs must show
    shaded = isdefined(game.plugins["clouds"].mod, :SHADED) && game.plugins["clouds"].mod.SHADED
    check(C[:plot].visible[] && (shaded || C[:fringe].visible[]), "clouds hidden at 19:25 (fringe $(C[:fringe].visible[]))")
    if shaded
        screenshot(game, "s56-clouds-evening")
        return
    end
    a = C[:fringe][1][]
    n = length(C[:puffs])
    check(length(a) == 3n && count(p -> p[3] > 0, a) >= 3n ÷ 2, "rim shells are not up in the sky ($(length(a)) of $(3n))")
    cols = C[:fringe].color[]
    check(all(c -> 0.02 < c.alpha < 0.2, cols), "rim alpha out of the soft range: $(extrema(c.alpha for c in cols))")
    screenshot(game, "s56-clouds-evening")
end

uitest("S56 Watering: the can tips towards the rows while pouring and goes home after; workshop is not at the gate") do game
    w = game.world
    game.minigame === nothing || S56.stop_minigame!(game)
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    me.controlled = false
    S56.skip_to_hour!(w, 11.0)
    me.action === :sleep && (me.action = :idle)
    S56.leave_interactions!(w, me)
    me.goal = S56.Goal()
    Main.GARDEN[:next_tend] = 0.0
    Base.invokelatest(game.plugins["garden"].mod.tend!, game)
    W = Main.WATERING
    t0 = w.t
    while !(me.goal.kind === :tend && me.goal.arrived) && w.t - t0 < 90
        wait_seconds(game, 1)
    end
    check(me.goal.kind === :tend && me.goal.arrived, "Lumi never reached the gate (goal $(me.goal.kind), at $(me.pos))")
    wait_seconds(game, 1.5)
    at = W[:can_at]
    check(at !== nothing, "no can offset while pouring")
    q = at[2]
    ang = 2 * acos(clamp(abs(q[4]), 0, 1))
    check(ang > 0.25, "the can is not tipped (angle $(round(ang, digits = 2)) rad)")
    screenshot(game, "s56-pour")
    # workshop corner keeps off the gate
    gm = game.plugins["garden"].mod
    gate = gm.gate_spot(w)
    ws = game.plugins["workshop"].mod
    c = Base.invokelatest(ws.corner, game)
    c === nothing || check(hypot(c[1][1] - gate[1], c[1][2] - gate[2]) > 2.0, "workshop corner is $(round(hypot(c[1][1] - gate[1], c[1][2] - gate[2]), digits = 1)) m from the gate")
    t1 = w.t
    while watering_now(W, w) && w.t - t1 < 60
        wait_seconds(game, 1)
    end
    wait_seconds(game, 2)
    home = W[:can_at]
    check(home === nothing || norm(home[1]) < 0.01, "the can did not go home after watering: $(home)")
end
watering_now(W, w) = W[:shown][1]
