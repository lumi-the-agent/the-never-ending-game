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

uitest("Bubble trouble (s90): Lumi's giant bubbles carry the friends up, pop, and the last one takes Lumi") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    B = Main.BUBBLES; s = B[:sys]
    s.state === :idle || return check(false, "bubbles were already going ($(s.state))")
    for c in w.creatures
        c.controlled = false
        c.action === :sleep && (c.action = :idle)
        c.goal = XP.Goal(:idle, c.pos, :idle, 20.0, w.t + 20, true, 0, false)
    end
    B[:t_gather] = 2.0; B[:gap] = 0.5; B[:big_gap] = 1.0; B[:lumi_pop] = 3.0; B[:pop_min] = 2.5
    ok = Base.invokelatest(B[:start])
    check(ok, "the bubbles did not start")
    me = creature(w, "Lumi")
    t1 = w.t; high = 0f0; shot = false
    while s.state !== :idle && w.t - t1 < 60
        wait_seconds(game, 0.25)
        high = max(high, me.pos[3] - XP.ground(w.island, (me.pos[1], me.pos[2]))[3])
        if !shot && count(b -> b.who != 0, s.bubbles) >= 3
            screenshot(game, "s90_bubbles"); shot = true
        end
    end
    for k in (:t_gather, :gap, :big_gap, :lumi_pop, :pop_min); delete!(B, k); end
    log = B[:log]
    n(k) = count(x -> x[2] === k, log)
    check(n(:caught) >= 3 && n(:pop) == n(:caught) && n(:bump) == n(:pop) && high > 2 && s.state === :idle,
          "caught $(n(:caught)), popped $(n(:pop)), landed $(n(:bump)), Lumi rose $(round(high; digits = 1)) m, state $(s.state)")
end

uitest("Lantern float (s91): everyone sets a glowing lantern on the pond, then they all fly up into the sky") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    L = Main.LANTERNS; s = L[:sys]
    s.state === :idle || return check(false, "a lantern float was already going ($(s.state))")
    for c in w.creatures
        c.controlled = false
        c.action === :sleep && (c.action = :idle)
        c.goal = XP.Goal(:idle, c.pos, :idle, 20.0, w.t + 20, true, 0, false)
    end
    L[:t_gather] = 5.0; L[:t_float] = 4.0; L[:gap] = 0.4
    ok = Base.invokelatest(L[:start])
    check(ok, "the lantern float did not start")
    A = game.plugins["areas"].mod; m = game.plugins["lanterns"].mod
    t1 = w.t; on_water = 0; high = 0f0
    while s.state !== :idle && w.t - t1 < 70
        wait_seconds(game, 0.5)
        if s.state === :float
            ps = [Base.invokelatest(m.lantern_pos, game, l, w.t) for l in s.lanterns]
            on_water = max(on_water, count(p -> hypot(p[1] - A.POND[1], p[2] - A.POND[2]) < A.POND_R, ps))
            on_water == length(s.lanterns) && screenshot(game, "s91_lanterns")
        elseif s.state === :rise && !isempty(s.lanterns)
            high = max(high, maximum(l -> Base.invokelatest(m.lantern_pos, game, l, w.t)[3], s.lanterns) - Main.AREA_PLOTS[:pond][3])
        end
    end
    for k in (:t_gather, :t_float, :gap); delete!(L, k); end
    n = count(x -> x[2] === :place, L[:log])
    check(n >= 4 && on_water >= n - 1 && high > 3 && s.state === :idle,
          "placed $(n), on the water at once $(on_water), rose $(round(high; digits = 1)) m, state $(s.state)")
end

uitest("Bubbles (s91): B as Lumi blows a giant bubble at the nearest friend, who floats up and comes down again") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me = creature(w, "Lumi")
    m = game.plugins["bubbles"].mod
    sp = Base.invokelatest(m.open_spot, game)
    me.pos = XP.ground(w.island, (sp[1], sp[2])); me.yaw = 0f0
    f = me.yaw + XP.species_of(me).heading
    pal = first(c for c in w.creatures if c !== me && !c.controlled)      # (at night everyone sleeps: wake one, s92)
    pal.action === :sleep && (pal.action = :idle)
    pal.pos = XP.ground(w.island, (sp[1] + 2.2f0 * cos(f), sp[2] + 2.2f0 * sin(f)))
    pal.goal = XP.Goal(:idle, pal.pos, :idle, 30.0, w.t + 30, true, 0, false)
    log0 = length(get(Main.BUBBLES, :log, []))
    interact!(game, [KeyPress(Keyboard.b), Wait(2.5)])
    caught = [x for x in Main.BUBBLES[:log][log0+1:end] if x[2] === :caught]
    up = 0f0                    # the highest the friend floats (the lift eases in over 3 s, one look was borderline, s92)
    for _ in 1:16
        wait_seconds(game, 0.25)
        up = max(up, pal.pos[3] - XP.ground(w.island, (pal.pos[1], pal.pos[2]))[3])
    end
    screenshot(game, "s91_bubble_b")
    wait_seconds(game, 7.0)
    bumps = count(x -> x[2] === :bump, Main.BUBBLES[:log][log0+1:end])
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(length(caught) == 1 && up > 1 && bumps == 1, "B: caught $(length(caught)), highest friend $(round(up; digits = 1)) m up, landed $(bumps)")
end

uitest("Pocket watch (s92): Z as Lumi winds the island back, and Lumi walks backwards to where it started") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me = creature(w, "Lumi")
    sp = Base.invokelatest(game.plugins["bubbles"].mod.open_spot, game)
    me.pos = XP.ground(w.island, (sp[1], sp[2])); me.yaw = 0f0
    R = Main.REWIND; s = R[:sys]
    empty!(s.hist)                                   # history from here on
    interact!(game, [Wait(1.0)])
    start = me.pos
    interact!(game, [KeyDown(Keyboard.w), Wait(3.0), KeyUp(Keyboard.w), Wait(0.2)])
    walked = hypot(me.pos[1] - start[1], me.pos[2] - start[2])
    interact!(game, [KeyPress(Keyboard.z), Wait(0.6)])
    state = s.state
    t1 = w.t
    while s.state !== :rec && w.t - t1 < 10; wait_seconds(game, 0.25); end
    back = hypot(me.pos[1] - start[1], me.pos[2] - start[2])
    screenshot(game, "s92_rewind")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(walked > 1.5 && state === :rewind && back < 0.6 && s.state === :rec,
          "walked $(round(walked; digits = 2)) m, state after Z $(state), $(round(back; digits = 2)) m from the start after the rewind, now $(s.state)")
end

uitest("Gallery (s94): six of Lumi's pictures stand framed on easels on open ground, and a friend walks over to look") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    gm = game.plugins["gallery"].mod
    pics = [p for p in game.stage.scene.plots if haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "gallery_pic_")]
    ez = Base.invokelatest(gm.easels, game)
    on = count(e -> XP.on_land(w.island, e[1][1], e[1][2]; margin = 0.3f0), ez)
    for c in w.creatures
        c.controlled = false; c.action === :sleep && (c.action = :idle)
        c.goal = XP.Goal(:idle, c.pos, :idle, 20.0, w.t + 20, true, 0, false)
    end
    Main.GALLERY[:next] = -Inf
    wait_seconds(game, 0.5)
    who = [c for c in w.creatures if c.goal.kind === :gallery]
    check(length(pics) == 6 && on == 6 && length(who) >= 1,
          "$(length(pics)) pictures, $(on) easels on land, $(length(who)) friends on their way to look")
end

uitest("Sleepers (s94): a sleeping piglet lies down in the grass and gets up again when it wakes") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    pig = first(c for c in w.creatures if c.species == "Snootle" && !c.controlled)
    XP.leave_interactions!(w, pig)
    pig.needs.energy = 0.1                 # (a rested pig in daylight is woken by the next goal choice: it went beachcombing, s94)
    pig.goal = XP.Goal(:sleep, pig.pos, :sleep, 60.0, w.t + 60, true, 0, false); pig.action = :sleep
    wait_seconds(game, 2.2)
    asleep = (pig.action, pig.goal.kind)
    down = XP.terrain_height(w.island, pig.pos[1], pig.pos[2]) - pig.pos[3]
    screenshot(game, "s94_sleeper")
    pig.goal = XP.Goal(:idle, pig.pos, :idle, 10.0, w.t + 10, true, 0, false); pig.action = :idle
    wait_seconds(game, 1.2)
    up = XP.terrain_height(w.island, pig.pos[1], pig.pos[2]) - pig.pos[3]
    check(down > 0.15 && abs(up) < 0.02, "$(pig.name) ($(asleep)) lay $(round(down; digits = 2)) m down asleep and is $(round(up; digits = 2)) m down after waking")
end

"A sunny hour for shadow tests (forward only, lesson s33)."
function shadow_sun!(w)
    h = 24 * XP.daytime(w)
    8.5 < h < 15.5 || XP.skip_to_hour!(w, 9.5)
end

uitest("Runaway shadow (s95): on a sunny day Lumi's shadow runs off, dodges, and Lumi chases it down and catches it") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    shadow_sun!(w)
    me = creature(w, "Lumi")
    sp = Base.invokelatest(game.plugins["bubbles"].mod.open_spot, game)
    me.pos = XP.ground(w.island, (sp[1], sp[2]))
    XP.leave_interactions!(w, me); me.action = :idle
    me.goal = XP.Goal(:idle, me.pos, :idle, 5.0, w.t + 5, true, 0, false)
    Main.LUMI_PARTY[:until] = -Inf
    S = Main.SHADOW; s = S[:sys]; S[:log] = Tuple{Float64,Symbol}[]
    start = me.pos
    ok = S[:start]()
    t1 = w.t; far = 0f0; seen = false
    while s.state !== :home && w.t - t1 < 50
        wait_seconds(game, 0.25)
        far = max(far, hypot(me.pos[1] - start[1], me.pos[2] - start[2]))
        !seen && w.t - t1 > 4 && (screenshot(game, "s95_shadow"); seen = true)
    end
    kinds = [k for (_, k) in S[:log]]
    took = get(S, :took, 0.0)
    check(ok && :dodge in kinds && :caught in kinds && took > 3 && far > 3 && s.state === :home,
          "came loose $(ok), log $(kinds), caught after $(round(took; digits = 1)) s, Lumi ran up to $(round(far; digits = 1)) m, now $(s.state)")
end

uitest("Runaway shadow (s95): V as Lumi lets the shadow loose and it runs off for the player to chase") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    shadow_sun!(w)
    S = Main.SHADOW; s = S[:sys]
    t0 = w.t
    while s.state !== :home && w.t - t0 < 50; wait_seconds(game, 0.5); end      # (one left over from the test before)
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
    me = creature(w, "Lumi")
    sp = Base.invokelatest(game.plugins["bubbles"].mod.open_spot, game)
    me.pos = XP.ground(w.island, (sp[1], sp[2]))
    interact!(game, [KeyPress(Keyboard.v), Wait(2.0)])
    state = s.state
    gap = hypot(me.pos[1] - s.pos[1], me.pos[2] - s.pos[2])
    screenshot(game, "s95_shadow_v")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(me.controlled == false && state === :loose && gap > 1.5,
          "after V the shadow is $(state), $(round(gap; digits = 1)) m from Lumi")
end

uitest("Gallery opening (s95): a new picture's easel stands empty until Lumi hangs it, then friends gather in front") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    GA = Main.GALLERY
    real = copy(Base.invokelatest(game.plugins["gallery"].mod.hanging, game))
    GA[:pics] = [real[2:end]; "an-older-one"]                 # as if real[1] had just been posted
    GA[:looked] = 0.0
    me = creature(w, "Lumi")
    XP.leave_interactions!(w, me); me.action === :sleep && (me.action = :idle)
    me.goal = XP.Goal(:idle, me.pos, :idle, 5.0, w.t + 5, true, 0, false)
    wait_seconds(game, 0.5)
    op = get(GA, :opening, nothing)
    pic = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :gallery_pic_1, game.stage.scene.plots)
    hidden = pic !== nothing && !game.stage.scene.plots[pic].visible[]
    t1 = w.t
    while haskey(GA, :opening) && GA[:opening][:state] === :carry && w.t - t1 < 60; wait_seconds(game, 0.5); end
    called = get(get(GA, :opening, Dict{Symbol,Any}()), :friends, -1)
    busy = [(c.name, c.goal.kind, c.action) for c in w.creatures if c !== me && c.goal.kind !== :gallery]
    wait_seconds(game, 4.0)
    gathered = count(c -> c.goal.kind === :gallery && c !== me, w.creatures)
    screenshot(game, "s95_gallery_opening")
    pic = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :gallery_pic_1, game.stage.scene.plots)
    shown = pic !== nothing && game.stage.scene.plots[pic].visible[]
    kinds = [k for (_, k) in get(GA, :log, Tuple{Float64,Symbol}[])]
    check(op !== nothing && op[:name] == real[1] && hidden && :opening in kinds && gathered >= min(2, called) && called >= 1 && shown,
          "opening for $(op === nothing ? nothing : op[:name]) (newest $(real[1])), hidden at first $(hidden), log ends $(kinds[max(1, end - 2):end]), $(called) called, $(gathered) friends gathered, picture shown $(shown); the others $(busy)")
end

uitest("The island plays itself (s95b): what the friends do strikes notes on the island's beat and scale") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    X = Main.XYLO
    n0 = length(get(X, :notes, NTuple{3,Float64}[]))
    friend = first(c for c in w.creatures if c.name != "Lumi" && !c.controlled && c.action !== :sleep)
    XP.feel!(w, friend, :laugh; seconds = 1.5)
    wait_seconds(game, 4.0)
    notes = X[:notes][(n0 + 1):end]
    scale, beat = Base.invokelatest(game.plugins["xylophone"].mod.key!, game)
    # every note sits on the beat and on the scale (A pentatonic, any octave)
    onbeat = all(n -> abs(n[1] / beat - round(n[1] / beat)) < 1e-6, notes)
    steps = Set(mod(round(Int, 12 * log2(n[2] / 220.0)), 12) for n in notes)
    inkey = issubset(steps, Set(scale))
    check(length(notes) >= 1 && onbeat && inkey,
          "$(length(notes)) notes in 4 s, on the beat $(onbeat), steps $(sort(collect(steps))) in the scale $(scale): $(inkey)")
end

uitest("Runaway shadow (s95b): while it is loose Lumi throws no shadow of its own (raster)") do game
    w = game.world
    game.minigame === nothing || XP.stop_minigame!(game)
    shadow_sun!(w)
    S = Main.SHADOW; s = S[:sys]
    t0 = w.t
    while s.state !== :home && w.t - t0 < 50; wait_seconds(game, 0.5); end
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.5)])
    me = creature(w, "Lumi")
    sp = Base.invokelatest(game.plugins["bubbles"].mod.open_spot, game)
    me.pos = XP.ground(w.island, (sp[1], sp[2]))
    interact!(game, [Wait(1.0)])
    screenshot(game, "s95b_bare_before")
    interact!(game, [KeyPress(Keyboard.v), Wait(2.0)])
    wrapped = count(p -> p.material[] isa XP.Hikari.MediumInterface, game.stage.herds["Lumi"].plots)
    screenshot(game, "s95b_bare_loose")
    state = s.state
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
    check(state === :loose && wrapped == length(game.stage.herds["Lumi"].plots),
          "state $(state), $(wrapped) of $(length(game.stage.herds["Lumi"].plots)) body parts pass shadows")
end
