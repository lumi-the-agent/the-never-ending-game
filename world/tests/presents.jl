# Session 55: Lumi brings each friend the present it loves (plugins/presents.jl).
const PRS = NeverendingGame

uitest("Presents: Lumi knows each friend's favourite and carries the right present to one of them") do game
    w = game.world
    game.minigame === nothing || PRS.stop_minigame!(game)
    mod = game.plugins["presents"].mod
    PR = Main.PRESENTS
    favs = Dict(c.name => Base.invokelatest(mod.favourite, c.name) for c in w.creatures if c.name != "Lumi")
    known = [n for (n, f) in favs if f !== nothing]
    check(length(known) >= 3, "Lumi knows the favourites of only $(length(known)) friends: $(favs)")
    check(length(unique(first(favs[n]) for n in known)) >= 2, "every friend has the same favourite: $(favs)")
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    PRS.leave_interactions!(w, me); me.controlled = false
    h = 24 * PRS.daytime(w)
    (h < 9 || h > 16) && PRS.skip_to_hour!(w, 11.0)
    me.action === :sleep && (me.action = :idle)
    isdefined(Main, :GARDEN) && (Main.GARDEN[:next_tend] = w.t + 1e6)
    empty!(get!(PR, :given, Dict{String,Float64}()))
    delete!(PR, :job)
    me.goal = PRS.Goal(:idle, me.pos, :idle, 1.0, w.t + 1.0, true, 0, false)
    PR[:next] = 0.0
    t0 = w.t
    while !haskey(PR, :job) && w.t - t0 < 30
        wait_seconds(game, 1)
        me.goal.kind in PRS.BUSY_GOALS || me.goal.kind === :present || (me.goal = PRS.Goal(:idle, me.pos, :idle, 1.0, w.t + 1.0, true, 0, false); PR[:next] = 0.0)
    end
    check(haskey(PR, :job), "Lumi did not plan a present within 30 s (goal $(me.goal.kind), next $(round(PR[:next] - w.t)) s)")
    job = PR[:job]
    to = PRS.creature(w, job[:to])
    check(job[:gift] === first(favs[to.name]), "$(to.name) loves $(favs[to.name]) but gets $(job[:gift])")
    while haskey(PR, :job) && get(PR[:job], :stage, :fetch) !== :given && w.t - t0 < 100
        wait_seconds(game, 1)
    end
    stage = haskey(PR, :job) ? PR[:job][:stage] : :gone
    check(stage === :given, "the present never reached $(to.name) (stage $(stage), Lumi $(me.goal.kind)/$(me.action), $(round(hypot(me.pos[1] - to.pos[1], me.pos[2] - to.pos[2]), digits = 1)) m away)")
    plot = PR[:plots][job[:gift]][1]
    check(plot.visible[] && Makie.to_value(plot.markersize)[1][1] > 0, "the present is not drawn at the giving")
    screenshot(game, "present-given")
    # the friend keeps it and carries it around for a while
    wait_seconds(game, 2.5)
    check(haskey(PR[:kept], to.id) && PR[:kept][to.id][1] === job[:gift], "$(to.name) does not keep its present (kept $(PR[:kept]))")
    check(Makie.to_value(plot.markersize)[1][1] > 0, "the kept present is not drawn")
end

uitest("Invitations: a friend asks a friend nearby to come along to what it loves, and they go together") do game
    w = game.world
    game.minigame === nothing || PRS.stop_minigame!(game)
    mod = game.plugins["presents"].mod
    PR = Main.PRESENTS
    h = 24 * PRS.daytime(w)
    (h < 9 || h > 16) && PRS.skip_to_hour!(w, 11.0)
    pick() = [c for c in w.creatures if Base.invokelatest(mod.free_friend, c) && Base.invokelatest(mod.favourite, c.name) !== nothing &&
              PRS.on_land(w.island, c.pos[1], c.pos[2]; margin = 0.4f0)]
    free = pick()
    t1 = w.t
    while length(free) < 2 && w.t - t1 < 30      # friends still waking up after a night, or busy for a moment
        wait_seconds(game, 2); free = pick()
    end
    check(length(free) >= 2, "fewer than two free friends with a favourite ($(length(free)); goals $([(c.name, c.goal.kind, c.action) for c in w.creatures]))")
    a, b = free[1], free[2]
    # a waits, b walks over to it (no teleport)
    a.goal = PRS.Goal(:idle, a.pos, :idle, 60.0, w.t + 60.0, true, 0, false); a.action = :idle
    b.goal = PRS.Goal(:wander, PRS.ground(w.island, (a.pos[1] + 1.4f0, a.pos[2])), :idle, 60.0, w.t + 60.0, false, 0, false)
    delete!(PR, :invite)
    t0 = w.t
    while !haskey(PR, :invite) && w.t - t0 < 40
        PR[:next_invite] = 0.0
        wait_seconds(game, 1)
    end
    check(haskey(PR, :invite), "no invitation within 40 s ($(a.name) $(a.goal.kind), $(b.name) $(b.goal.kind), $(round(hypot(a.pos[1] - b.pos[1], a.pos[2] - b.pos[2]), digits = 1)) m apart)")
    ia, ib, p, yes, _ = PR[:invite]
    inviter, guest = PRS.creature(w, ia), PRS.creature(w, ib)
    check(inviter.goal.kind === :invite && guest.goal.kind === :invite, "the two do not stop for the question")
    wait_seconds(game, 2.5)
    k = mod.INVITE_GOAL[p]
    check(inviter.goal.kind in (k, :wander), "$(inviter.name) invited to $(k) but goes $(inviter.goal.kind)")
    check(!yes || guest.goal.kind in (k, :wander), "$(guest.name) said yes but goes $(guest.goal.kind)")
    screenshot(game, "invite")
end

# ── session 55, tester: what a person sees of presents, invitations and chats ──

"Two free friends with the same favourite pastime `p`, close together on land, or nothing."
function pair_loving(game, p)
    w = game.world; mod = game.plugins["presents"].mod
    cs = [c for c in w.creatures if Base.invokelatest(mod.free_friend, c) && (f = Base.invokelatest(mod.favourite, c.name); f !== nothing && f[1] === p) &&
          PRS.on_land(w.island, c.pos[1], c.pos[2]; margin = 0.4f0)]
    length(cs) >= 2 ? (cs[1], cs[2]) : nothing
end

uitest("Presents: the island panel names who gets a present, and a friend with one 'shows off a present'") do game
    w = game.world
    game.minigame === nothing || PRS.stop_minigame!(game)
    PR = Main.PRESENTS
    doing = game.plugins["islandnow"].mod.doing
    me = PRS.creature(w, findfirst(c -> c.name == "Lumi", w.creatures) |> i -> w.creatures[i].id)
    PRS.leave_interactions!(w, me); me.controlled = false
    # Lumi on its way with a present: the panel line names the friend
    friend = first(c for c in w.creatures if c.name != "Lumi" && c.action !== :sleep)
    PR[:job] = Dict{Symbol,Any}(:to => friend.id, :gift => :beach, :stage => :fetch)
    me.goal = PRS.Goal(:present, me.pos, :idle, 5.0, w.t + 5.0, true, 0, false)
    line = first(Base.invokelatest(doing, w, me))
    check(occursin("present for $(friend.name)", line), "panel says '$line' while Lumi fetches a present for $(friend.name)")
    PR[:job][:stage] = :carry
    line = first(Base.invokelatest(doing, w, me))
    check(occursin("brings $(friend.name) a present", line), "panel says '$line' while Lumi carries it over")
    delete!(PR, :job)
    me.goal = PRS.Goal(:idle, me.pos, :idle, 1.0, w.t + 1.0, true, 0, false)
    # a friend keeping a present shows it to a friend within 3 m and the friend admires it
    a, b = [c for c in w.creatures if c.name != "Lumi" && c.action !== :sleep && !c.controlled][1:2]
    a.goal = PRS.Goal(:idle, a.pos, :idle, 30.0, w.t + 30.0, true, 0, false); a.action = :idle
    b.goal = PRS.Goal(:wander, PRS.ground(w.island, (a.pos[1] + 1.2f0, a.pos[2])), :idle, 30.0, w.t + 30.0, false, 0, false)
    PR[:kept][a.id] = (:flowers, w.t + 60.0, w.t)
    t0 = w.t
    shown = false
    while w.t - t0 < 25 && !shown
        wait_seconds(game, 1)
        shown = any(s -> s.who == a.id && (occursin("present", s.text) || occursin("Lumi", s.text)), w.speech)
    end
    check(shown, "$(a.name) keeps a present but never shows it ($(b.name) $(round(hypot(a.pos[1] - b.pos[1], a.pos[2] - b.pos[2]), digits = 1)) m away, goals $(a.goal.kind)/$(b.goal.kind))")
    check(startswith(first(Base.invokelatest(doing, w, a)), "shows off a present") || a.goal.kind ∉ (:idle,), "panel shows $(first(Base.invokelatest(doing, w, a))) for the keeper")
    wait_seconds(game, 3)
    delete!(PR[:kept], a.id)
    screenshot(game, "present-show-off")
end

uitest("Invitations: pairs that go flowers picking or shell hunting talk too, not only the fishers") do game
    w = game.world
    game.minigame === nothing || PRS.stop_minigame!(game)
    mod = game.plugins["presents"].mod
    PR = Main.PRESENTS
    h = 24 * PRS.daytime(w); (h < 9 || h > 16) && PRS.skip_to_hour!(w, 11.0)
    for p in (:flowers, :beach)
        k = mod.INVITE_GOAL[p]
        pr = nothing; t1 = w.t
        while pr === nothing && w.t - t1 < 30
            pr = pair_loving(game, p); pr === nothing && wait_seconds(game, 2)
        end
        pr === nothing && continue      # nobody loves it right now: the other pastime still counts
        a, b = pr
        a.goal = PRS.Goal(:idle, a.pos, :idle, 60.0, w.t + 60.0, true, 0, false); a.action = :idle
        b.goal = PRS.Goal(:wander, PRS.ground(w.island, (a.pos[1] + 1.4f0, a.pos[2])), :idle, 60.0, w.t + 60.0, false, 0, false)
        delete!(PR, :invite); empty!(mod.together())
        t0 = w.t
        while !haskey(PR, :invite) && w.t - t0 < 40
            PR[:next_invite] = 0.0; wait_seconds(game, 1)
        end
        check(haskey(PR, :invite), "no invitation for $(k) within 40 s ($(a.name) $(a.goal.kind), $(b.name) $(b.goal.kind))")
        words = Set(string(x) for pair in mod.TOGETHER_WORDS[k] for x in pair)
        talked = false; t0 = w.t
        while w.t - t0 < 45 && !talked
            wait_seconds(game, 1)
            talked = any(s -> s.text in words, w.speech)
        end
        check(talked, "$(a.name) and $(b.name) went $(k) together but never talked about it in 45 s (goals $(a.goal.kind)/$(b.goal.kind), still paired: $(length(mod.together())))")
    end
end

uitest("Presents: jumping into Lumi while it carries a present drops the job and Lumi answers the keys") do game
    w = game.world
    game.minigame === nothing || PRS.stop_minigame!(game)
    PR = Main.PRESENTS
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    h = 24 * PRS.daytime(w); (h < 9 || h > 16) && PRS.skip_to_hour!(w, 11.0)
    PRS.leave_interactions!(w, me); me.controlled = false
    me.action === :sleep && (me.action = :idle)
    delete!(PR, :job); PR[:next] = 0.0
    t0 = w.t
    while !haskey(PR, :job) && w.t - t0 < 40
        wait_seconds(game, 1)
        me.goal.kind in PRS.BUSY_GOALS || me.goal.kind === :present || (me.goal = PRS.Goal(:idle, me.pos, :idle, 1.0, w.t + 1.0, true, 0, false); PR[:next] = 0.0)
    end
    check(haskey(PR, :job), "Lumi planned no present in 40 s (goal $(me.goal.kind))")
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    wait_seconds(game, 1)
    check(me.controlled, "Play did not hand Lumi over (goal $(me.goal.kind), minigame $(typeof(game.minigame)))")
    check(!haskey(PR, :job) || me.goal.kind !== :present, "the present job still drives Lumi ($(me.goal.kind)) after the player took over")
    p0 = copy(me.pos)
    interact!(game, [KeyPress(Keyboard.w; duration = 1.0), Wait(0.2)])
    moved = hypot(me.pos[1] - p0[1], me.pos[2] - p0[2])
    check(moved > 0.3, "W moved the carrier only $(round(moved, digits = 2)) m (goal $(me.goal.kind), action $(me.action))")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
    check(game.minigame === nothing, "Stop did not end Jump in")
    delete!(PR, :job)
end
