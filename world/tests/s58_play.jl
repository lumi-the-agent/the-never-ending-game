# Session 58 (tester): playing what s58 changed as a person.
const XP = NeverendingGame

function kp_fly!(game)
    w = game.world; K = Main.KITE
    game.minigame === nothing || XP.stop_minigame!(game)
    me = creature(w, "Lumi")
    XP.leave_interactions!(w, me); me.controlled = false
    # a kite still up from the test before (since s85 Lumi keeps flying it after Stop) comes down first: a
    # skip_to_hour! a moment later ended it as "done" right after this helper saw it up (s86, flaky first Play)
    if K[:flyer] != 0
        km = game.plugins["kite"].mod
        Base.invokelatest(km.land!, w, :test); Base.invokelatest(km.show_kite!, false)
    end
    h = 24 * XP.daytime(w); (h < 13.2 || h > 15.5) && XP.skip_to_hour!(w, 13.5)
    me.action === :sleep && (me.action = :idle); me.needs.energy = 0.9
    me.goal = XP.Goal(:idle, me.pos, :idle, 20.0, w.t + 20, true, 0, false)
    K[:day] = -1; K[:retry] = -Inf
    t1 = w.t
    while !(K[:flyer] != 0 && get(K, :up, false)) && w.t - t1 < 90
        K[:retry] = -Inf; wait_seconds(game, 1)
    end
    me
end

include_string(Main, "")  # noop

# nearest other creature (or Lumi itself) that stands between the camera and Lumi
function blocker(game, me)
    e = Point3f(game.rig.eye); t = Point3f(me.pos) + Point3f(0, 0, 0.5)
    d = t - e; L = sqrt(sum(abs2, d)); best = nothing
    for c in game.world.creatures
        c === me && continue
        v = Point3f(c.pos) + Point3f(0, 0, 0.5) - e
        s = sum(v .* d) / L
        (0 < s < L) || continue
        off = sqrt(max(sum(abs2, v) - s^2, 0f0))
        off < 0.9 && (best === nothing || off < best[2]) && (best = (c.name, off, s))
    end
    best, L
end

function play_kite!(game)
    w = game.world; K = Main.KITE
    s0 = creature(w, "Lumi"); game.minigame === nothing || XP.stop_minigame!(game)
    XP.skip_to_hour!(w, 13.3)
    s0.pos = Point3f(K[:spot])
    me = kp_fly!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me
end

uitest("Kite player (s58): A and D turn Lumi while running, Space and E keep the kite in Lumi's hand") do game
    K = Main.KITE
    me = play_kite!(game)
    check(me.controlled && K[:flyer] == me.id, "not the holder (flyer $(K[:flyer]))")
    y0 = me.yaw
    interact!(game, [KeyDown(Keyboard.w), KeyDown(Keyboard.a), Wait(1.5), KeyUp(Keyboard.a), KeyUp(Keyboard.w), Wait(0.2)])
    dy = abs(angle(cis(me.yaw - y0)))
    check(dy > 0.4, "holding W+A for 1.5 s did not turn Lumi (yaw change $(dy) rad, Lumi at $(me.pos))")
    interact!(game, [KeyPress(Keyboard.space), Wait(0.6), KeyPress(Keyboard.e), Wait(0.6)])
    check(me.controlled && K[:flyer] == me.id && K[:up], "Space/E dropped the kite or the control (flyer $(K[:flyer]), up $(K[:up]), controlled $(me.controlled))")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(!me.controlled && !K[:meter].visible[], "Stop left Lumi controlled or the meter up")
end

uitest("Kite player (s58): Play, Stop, Play again works and the meter comes back") do game
    K = Main.KITE
    me = play_kite!(game)
    check(K[:meter].visible[], "no meter on the first play")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(!K[:meter].visible[] && !me.controlled, "Stop did not clear meter/control")
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    check(me.controlled && game.minigame isa XP.JumpIn, "second Play did not hand Lumi over ($(typeof(game.minigame)))")
    check(K[:flyer] == me.id && K[:meter].visible[], "a second Play after Stop gives no kite: the kite is gone for the day (flyer $(K[:flyer]), meter $(K[:meter].visible[]))")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
end

uitest("Kite player (s58): while running, no friend or solid fills the view between the camera and Lumi") do game
    me = play_kite!(game)
    worst = nothing
    for i in 1:6
        interact!(game, [KeyDown(Keyboard.w), Wait(1.0), KeyUp(Keyboard.w)])
        b, L = blocker(game, me)
        b !== nothing && (worst = (i, b, L))
    end
    screenshot(game, "s58_kite_running_view")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(worst === nothing, "a creature stands in the camera's line to Lumi: $(worst)")
end

uitest("Kite player (s58): Lumi is in view right after jumping in, not hidden behind a house or a friend") do game
    me = play_kite!(game)
    screenshot(game, "s58_kite_jumpin_view")
    b, L = blocker(game, me)
    ons = XP.on_screen(game.stage.scene, Point3f(me.pos))
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(ons !== nothing, "Lumi is off screen right after Play (eye $(game.rig.eye), Lumi $(me.pos))")
    check(b === nothing, "right after Play the camera line to Lumi is blocked by $(b)")
end

uitest("Pond (s87): jumped in as Lumi, walking into the lily pond sends ripples out") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me = creature(w, "Lumi")
    A = game.plugins["areas"].mod; S = Main.SPLASH[:sys]
    P = A.POND
    me.pos = XP.ground(w.island, (P[1], P[2] - A.POND_R - 0.8f0)); me.yaw = Float32(pi / 2)   # (yaw is the walking direction)
    n0 = length(S.rings)
    interact!(game, [KeyDown(Keyboard.w), Wait(2.0), KeyUp(Keyboard.w), Wait(0.1)])
    d = hypot(me.pos[1] - P[1], me.pos[2] - P[2])
    rings = length(S.rings)
    screenshot(game, "s87_pond_wading")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(d < A.POND_R && rings > n0, "Lumi did not wade in or no ripples: $(round(d, digits = 2)) m from the middle (pond radius $(A.POND_R)), rings $(n0) -> $(rings)")
end

uitest("Pond (s87): Q as Lumi by the pond flings a scoop of water") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me = creature(w, "Lumi")
    A = game.plugins["areas"].mod
    P = A.POND
    me.pos = XP.ground(w.island, (P[1], P[2] - A.POND_R + 0.5f0)); me.yaw = Float32(pi / 2)
    n0 = count(x -> x[2] === :throw, get(Main.SPLASH, :log, Tuple{Float64,Symbol}[]))
    interact!(game, [KeyPress(Keyboard.q), Wait(0.3)])
    th = length(get(Main.SPLASH, :throws, []))
    n1 = count(x -> x[2] === :throw, get(Main.SPLASH, :log, Tuple{Float64,Symbol}[]))
    screenshot(game, "s87_pond_q")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(n1 > n0 && th > 0, "Q by the pond threw nothing (throws logged $(n0) -> $(n1), drops in the air $(th))")
end

uitest("Mix-up (s88): SWAPSIE lends every friend another body and gives it back") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    M = Main.MIXUP; s = M[:sys]
    s.state === :idle || return check(false, "a mix-up was already running ($(s.state))")
    me = creature(w, "Lumi")
    for c in w.creatures
        c.controlled = false
        c.action === :sleep && (c.action = :idle)
        c.goal = XP.Goal(:idle, c.pos, :idle, 20.0, w.t + 20, true, 0, false)
    end
    before = Dict(c.id => c.species for c in w.creatures)
    M[:t_gather] = 1.0; M[:t_mixed] = 4.0
    ok = Base.invokelatest(M[:start])
    check(ok, "the mix-up did not start (Lumi $(me.goal.kind), $(length(w.creatures)) creatures)")
    t1 = w.t
    while s.state !== :mixed && w.t - t1 < 30; wait_seconds(game, 0.5); end
    wait_seconds(game, 0.5)
    swapped = count(c -> c.species != before[c.id], w.creatures)
    screenshot(game, "s88_mixup")
    while s.state !== :idle && w.t - t1 < 60; wait_seconds(game, 0.5); end
    delete!(M, :t_gather); delete!(M, :t_mixed)
    back = all(c -> c.species == before[c.id], w.creatures)
    check(swapped >= 3 && back && me.species == "Lumi", "swapped $(swapped) (want >= 3), all back $(back), Lumi $(me.species)")
end

uitest("Cannonball contest (s89): Lumi's big one gets a TEN, then everybody jumps into the pond at once") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    SPd = Main.SPLASH; s = SPd[:sys]
    s.state === :idle || return check(false, "a contest was already running ($(s.state))")
    for c in w.creatures
        c.controlled = false
        c.action === :sleep && (c.action = :idle)
        c.goal = XP.Goal(:idle, c.pos, :idle, 20.0, w.t + 20, true, 0, false)
    end
    SPd[:t_gather] = 1.5
    ok = Base.invokelatest(SPd[:start])
    check(ok, "the contest did not start")
    n = length(s.crew) + length(s.judges)
    t1 = w.t; said = Set{String}(); shot = false
    while s.state !== :idle && w.t - t1 < 60
        wait_seconds(game, 0.25)
        foreach(b -> push!(said, string(b.text)), w.speech)
        if !shot && any(x -> x[2] === :allin, SPd[:log]) && length(get(SPd, :allin_landed, Set())) > 0
            screenshot(game, "s89_everybody_in"); shot = true
        end
    end
    delete!(SPd, :t_gather)
    log = SPd[:log]
    k = findfirst(x -> x[2] === :allin, log)
    after = k === nothing ? 0 : count(x -> x[2] === :splash, log[k:end])
    check(k !== nothing && after >= n - 1 && "TEN!!" in said && s.state === :idle,
          "everybody in: $(k === nothing ? "never called" : "$(after) splashes after the call") for $(n) in the contest, TEN said $("TEN!!" in said), state $(s.state)")
end
