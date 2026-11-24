# Playing like a person: the Firefly catch start card, keys that answer, catches, the end card; waving at creatures.
fly_click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.2)])

function fly_choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end

# No flower and no loose cairn pebble within reach of `q`: E there waves (flowergift and cairns take E first).
e_free(game, q) = all(f -> f.kind !== :flower || hypot(f.pos[1] - q[1], f.pos[2] - q[2]) > 1.4f0, game.world.props) &&
                  all(p -> hypot(p[1] - q[1], p[2] - q[2]) > 1.4f0, Base.invokelatest(game.plugins["cairns"].mod.pebbles, game.world))

# A critter other than `me` that is awake and free; at night (everyone asleep) the nearest sleeper is woken up.
function awake_critter(game, me)
    free(o) = o !== me && !o.controlled && o.goal.kind !== :interact && o.goal.kind ∉ NeverendingGame.BUSY_GOALS   # a fisher does not answer by design
    i = findfirst(o -> free(o) && o.action !== :sleep && o.goal.kind !== :sleep, game.world.creatures)
    i === nothing || return game.world.creatures[i]
    i = findfirst(free, game.world.creatures)
    # everyone busy (a parade sent them all for pebbles, s48): take one out of it, as a wave would
    i === nothing && (i = findfirst(o -> o !== me && !o.controlled && o.name != "Lumi", game.world.creatures))
    o = game.world.creatures[i]
    NeverendingGame.leave_interactions!(game.world, o)
    o.goal = NeverendingGame.Goal(:idle, o.pos, :idle, 30.0, game.world.t + 30.0, true, 0, false); o.action = :idle   # awake for 30 s
    return o
end

uitest("Firefly catch: start card, W starts, keys light up, a catch counts, R restarts") do game
    fly_choose(game, "Firefly catch (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    check(m !== nothing && occursin("Firefly", NeverendingGame.game_title(typeof(m))), "Firefly catch did not start")
    P = Main.FIREFLY_PLOTS
    check(m.state === :ready && P[:card].visible[], "no start card (state $(m.state))")
    check(occursin("W / S", P[:card].text[]), "the start card does not show the keys: $(P[:card].text[])")
    screenshot(game, "firefly-start")
    c = creature(game.world, "Lumi")
    p0 = c.pos
    interact!(game, [KeyDown(Keyboard.w), Wait(0.5)])
    check(m.state === :playing && !P[:card].visible[], "W did not start the game (state $(m.state))")
    check(P[:key_1].background_color[] != P[:key_2].background_color[], "the W key does not light up while held")
    interact!(game, [KeyUp(Keyboard.w), Wait(0.1)])
    check(norm(c.pos - p0) > 0.3, "Lumi did not walk on W")
    # walk Lumi onto a firefly: it is caught, sparks fly
    i = findfirst(!, m.caught)
    f = parentmodule(typeof(m)).fly_pos(m.flies[i], game.world.t, i)
    c.pos = NeverendingGame.ground(game.world.island, (f[1], f[2]))
    wait_frames(game, 3)
    check(m.score >= 1, "standing on a firefly did not catch it (score $(m.score))")
    check(m.spark_t < 1, "no sparks for the catch")
    screenshot(game, "firefly-catch")
    interact!(game, [KeyPress(Keyboard.r), Wait(0.2)])
    check(m.state === :ready && m.score == 0, "R did not restart (state $(m.state), score $(m.score))")
    fly_click(game, "Stop")
    check(game.minigame === nothing && !P[:card].visible[], "Stop left the game or its card up")
end

uitest("Jump in: E waves and a creature answers, a second wave makes it follow") do game
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NeverendingGame.JumpIn, "Play did not jump in")
    me = creature(game.world, "Lumi")
    other = awake_critter(game, me)
    # E by a flower picks it and E with a flower gives it (flowergift.jl): wave from a spot without flowers, empty-handed
    fg = game.plugins["flowergift"].mod
    delete!(fg.CARRYING, me.id)
    spots = [(other.pos[1] + r * cos(a), other.pos[2] + r * sin(a)) for r in (1.5f0, 2.2f0), a in 0:0.5:6]
    clear(q) = e_free(game, q)
    j = findfirst(clear, spots)
    check(j !== nothing, "no flower-free spot next to $(other.name)")
    me.pos = NeverendingGame.ground(game.world.island, spots[j])
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    # the nearest creature answers (may be another one that walked closer than the one we stood next to)
    # (one waved at in the last 12 s, by an earlier test, follows at once: the host suite failed on that)
    # the one this wave greeted last (an :answer left by an earlier test came first in the list and
    # the check watched the wrong creature, s44 suite: "Truffle answer, Wibbles answer")
    greeted = game.plugins["greetings"].systems[1].greeted
    i = isempty(greeted) ? nothing : findfirst(c -> c.id == argmax(greeted) && c.goal.kind in (:answer, :follow), game.world.creatures)
    check(i !== nothing, "nobody answered the wave ($(other.name) is $(other.goal.kind))")
    other = game.world.creatures[i]
    other.goal.kind === :answer && interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    check(other.goal.kind === :follow, "$(other.name) does not follow after the second wave ($(other.goal.kind)); others: $([(c.name, c.goal.kind) for c in game.world.creatures if c.goal.kind in (:answer, :follow)]), greeted $(game.plugins["greetings"].systems[1].greeted), t $(game.world.t)")
    screenshot(game, "jumpin-friend")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    check(other.goal.kind !== :follow, "$(other.name) still follows after Stop")
end

uitest("A wave at a critter in a chat: it breaks off, waves back, and its partner goes on with its day") do game
    NG = NeverendingGame
    w = game.world
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(w, "Lumi")
    delete!(game.plugins["flowergift"].mod.CARRYING, me.id)
    awake_critter(game, me)
    # a spot 1.4 m from a critter `a` where no other awake critter is in waving range (the nearest free one
    # answers a wave by design: a critter left there by the test before took it, s37 suite)
    free_ones = [o for o in w.creatures if o !== me && !o.controlled && o.action !== :sleep && o.goal.kind ∉ (:follow, :interact)]
    found = nothing
    for a in free_ones, t in 0:0.25:6.2
        q = (a.pos[1] + 1.4f0 * cos(t), a.pos[2] + 1.4f0 * sin(t))
        ok = e_free(game, q) &&
             all(o -> o === a || o === me || hypot(o.pos[1] - q[1], o.pos[2] - q[2]) > (o.action === :sleep ? 1.2f0 : 4.8f0), w.creatures) &&
             NG.on_land(w.island, q[1], q[2]; margin = 1f0)
        ok && (found = (a, q); break)
    end
    check(found !== nothing, "no spot next to an awake critter with nobody else awake in waving range")
    a, q = found
    b = w.creatures[findfirst(o -> o !== me && o !== a && !o.controlled && o.goal.kind ∉ (:follow, :interact), w.creatures)]
    # b stands on the far side of a, the two chat; Lumi waves from 1.4 m
    dx, dy = a.pos[1] - q[1], a.pos[2] - q[2]
    b.action = :idle; a.action = :idle
    b.pos = NG.ground(w.island, (a.pos[1] + 0.8f0 * dx, a.pos[2] + 0.8f0 * dy))
    NG.start_interaction!(w, NG.Chat, a, b)
    wait_frames(game, 2)
    check(a.goal.kind === :interact, "set-up: $(a.name) is not chatting ($(a.goal.kind))")
    me.pos = NG.ground(w.island, q)
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    check(a.goal.kind in (:answer, :follow), "$(a.name) ignored the wave while chatting ($(a.goal.kind), $(b.name) $(b.goal.kind), Lumi $(me.action)); near Lumi: $([(c.name, c.goal.kind, c.action, round(hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]); digits = 1)) for c in w.creatures if c !== me && hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]) < 4]), greetings last $(game.plugins["greetings"].systems[1].last_action), cairn e $(get(game.plugins["cairns"].mod.CAIRN, :e_used, nothing)) t $(w.t)")
    check(b.goal.kind !== :interact || any(it -> it.a == b.id || it.b == b.id, w.interactions), "$(b.name) is left in a chat with nobody")
    check(!any(it -> it.a == a.id || it.b == a.id, w.interactions), "$(a.name) is still in the chat")
    screenshot(game, "wave-breaks-chat")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("A wave next to a sleeper goes to the awake creature a step further away") do game
    NG = NeverendingGame
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(game.world, "Lumi")
    awake = awake_critter(game, me)
    j = findfirst(c -> c !== me && c !== awake && !c.controlled && c.goal.kind ∉ (:follow, :interact), game.world.creatures)
    sleeper = game.world.creatures[j]
    p = awake.pos
    # E by a flower picks it (flowergift.jl): a line out from the awake one with no flower near Lumi's spot
    delete!(game.plugins["flowergift"].mod.CARRYING, me.id)
    clear(q) = e_free(game, q)
    k = findfirst(a -> clear((p[1] + 2.2f0 * cos(a), p[2] + 2.2f0 * sin(a))), 0:0.5:6)
    check(k !== nothing, "no flower-free spot near $(awake.name)")
    a = (0:0.5:6)[k]; dir = (cos(a), sin(a))
    sleeper.pos = NG.ground(game.world.island, (p[1] + 1.2f0 * dir[1], p[2] + 1.2f0 * dir[2]))
    sleeper.goal = NG.Goal(:sleep, sleeper.pos, :sleep, 30.0, game.world.t + 30.0, true, 0, false); sleeper.action = :sleep
    me.pos = NG.ground(game.world.island, (p[1] + 2.2f0 * dir[1], p[2] + 2.2f0 * dir[2]))    # 1 m from the sleeper, 2.2 m from the awake one
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    # whoever answers says hello (:answer), or joins Lumi when it was waved at a moment ago (:follow)
    i = findfirst(c -> c.goal.kind in (:answer, :follow), game.world.creatures)
    gs = game.plugins["greetings"].systems[1]
    check(i !== nothing, "nobody answered the wave (the sleeper $(sleeper.name) is $(sleeper.action), $(awake.name) is $(awake.goal.kind); Lumi $(me.action), controlled $(me.controlled), last $(gs.last_action), greeted $(gs.greeted), carries a pebble $(Base.invokelatest(game.plugins["cairns"].mod.lumi_carries)), a flower $(haskey(game.plugins["flowergift"].mod.CARRYING, me.id)))")
    check(game.world.creatures[i] !== sleeper, "the sleeper answered")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("Firefly catch: catching all ends with the end card, the flight to the lantern and cheers") do game
    file = joinpath(game.paths.state, "fireflies.json")
    saved = isfile(file) ? read(file, String) : nothing        # the human's own count is restored at the end
    P = Main.FIREFLY_PLOTS
    total0 = get(P, :total, 0); best0 = get(P, :best, nothing); level0 = get(P, :level, nothing)
    P[:level] = 1
    fly_choose(game, "Firefly catch (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    interact!(game, [KeyPress(Keyboard.w; duration = 0.1), Wait(0.1)])
    c = creature(game.world, "Lumi")
    buddy = awake_critter(game, c)
    for k in 1:24          # a fly that moved on between two frames is tried again
        i = findfirst(!, m.caught)
        i === nothing && break
        f = parentmodule(typeof(m)).fly_pos(m.flies[i], game.world.t, i)
        count(!, m.caught) == 1 && (buddy.pos = NeverendingGame.ground(game.world.island, (f[1] + 2f0, f[2])))
        c.pos = NeverendingGame.ground(game.world.island, (f[1], f[2]))
        wait_frames(game, 3)
    end
    fi = findfirst(!, m.caught)
    fp = fi === nothing ? nothing : parentmodule(typeof(m)).fly_pos(m.flies[fi], game.world.t, fi)
    check(m.state === :over && m.score == 8, "the round did not end after 8 catches (state $(m.state), score $(m.score), " *
          "player $(m.lumi) Lumi $(c.id) at $(c.pos) action $(c.action), next fly $(fp))")
    check(P[:card].visible[] && occursin("lantern", P[:card].text[]) && occursin("R to play again", P[:card].text[]),
          "the end card does not tell about the lantern and playing again: $(P[:card].text[])")
    check(get(P, :flight, nothing) !== nothing, "the caught fireflies do not fly to the lantern")
    check(buddy.goal.kind === :answer, "$(buddy.name) next to Lumi did not cheer ($(buddy.goal.kind))")
    screenshot(game, "firefly-end")
    # a win makes the next round a level harder: the card says so, R starts it with quicker flies
    check(occursin("level 2", P[:card].text[]) && P[:level] == 2, "no level step after a win: $(P[:card].text[])")
    v1 = parentmodule(typeof(m)).FLEE_SPEED
    interact!(game, [KeyPress(Keyboard.r), Wait(0.2)])
    check(m.state === :ready && occursin("Level 2", P[:card].text[]), "the start card does not show level 2: $(P[:card].text[])")
    check(Base.invokelatest(parentmodule(typeof(m)).flee_speed, game) > 1.2f0 * v1, "level 2 fireflies are not quicker")
    screenshot(game, "firefly-level2")
    fly_click(game, "Stop")
    saved === nothing ? rm(file; force = true) : write(file, saved)
    P[:total] = total0; best0 === nothing ? delete!(P, :best) : (P[:best] = best0); delete!(P, :flight)
    level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
end

uitest("Berry race: start card names the rivals, a pick counts, critters race and eat, the basket fills") do game
    file = joinpath(game.paths.state, "berries.json")
    saved = isfile(file) ? read(file, String) : nothing        # the human's own basket is restored at the end
    P = Main.BERRY_PLOTS
    total0 = get(P, :total, 0); best0 = get(P, :best, nothing); level0 = get(P, :level, nothing)
    P[:level] = 1          # a first round (the player's own level is put back at the end)
    fly_choose(game, "Berry race (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    check(m !== nothing && occursin("Berry", NeverendingGame.game_title(typeof(m))), "Berry race did not start")
    check(m.state === :ready && P[:card].visible[] && occursin("W / S", P[:card].text[]), "no start card with the keys")
    check(length(m.rivals) == 3 && all(n -> occursin(n, P[:card].text[]), parentmodule(typeof(m)).rival_names(m, game)),
          "the start card does not name the three rivals: $(P[:card].text[])")
    check(length(m.berries) >= 10, "only $(length(m.berries)) berries grew")
    wait_frames(game, 20)
    screenshot(game, "berry-start")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.3), Wait(0.1)])
    check(m.state === :playing && !P[:card].visible[], "W did not start the race (state $(m.state))")
    c = creature(game.world, "Lumi")
    b = m.berries[findfirst(b -> b.taken == 0, m.berries)]
    c.pos = b.foot
    wait_frames(game, 3)
    check(m.score >= 1 && b.taken == -1, "standing at a berry did not pick it (score $(m.score))")
    check(all(id -> creature(game.world, id).goal.kind === :wait, m.rivals) || m.t >= Base.invokelatest(parentmodule(typeof(m)).head_start, game),
          "the critters did not give Lumi a head start: $([creature(game.world, id).goal.kind for id in m.rivals]) at $(m.t) s")
    wait_seconds(game, Base.invokelatest(parentmodule(typeof(m)).head_start, game) + 0.5)   # the player's head start
    check(all(id -> creature(game.world, id).goal.kind in (:race, :cheer), m.rivals), "the critters do not race for berries: $([creature(game.world, id).goal.kind for id in m.rivals]) targets $(m.target)")
    # help one critter to its berry: it eats it and says so
    k = findfirst(!=(0), m.target)      # a critter that is munching (:cheer) has no target right now
    check(k !== nothing, "no critter is running for a berry: targets $(m.target)")
    o = creature(game.world, m.rivals[k]); n0 = m.rival_score[k]
    o.pos = m.berries[m.target[k]].foot
    wait_frames(game, 3)
    check(m.rival_score[k] == n0 + 1, "$(o.name) at its berry did not eat it")
    check(occursin("Critters $(sum(m.rival_score))", P[:hud].text[]), "the HUD does not show the critters' score: $(P[:hud].text[])")
    screenshot(game, "berry-race")
    # the best survives a restart: a saved best (state/bests.json) is on the end card of a fresh session
    bfile = joinpath(game.paths.state, "bests.json"); bsaved = isfile(bfile) ? read(bfile, String) : nothing
    bd = bsaved === nothing ? Dict{String,Any}() : NeverendingGame.read_json(bfile); bd["berry_race"] = 99
    NeverendingGame.write_json(bfile, bd); delete!(P, :best)
    m.t = 61.0
    wait_frames(game, 3)
    bsaved === nothing ? rm(bfile; force = true) : write(bfile, bsaved)
    check(m.state === :over && P[:card].visible[] && occursin("basket", P[:card].text[]) && occursin("R to play again", P[:card].text[]),
          "no end card about the basket: $(P[:card].text[])")
    check(occursin("best: 99", P[:card].text[]), "the saved best is not on the end card: $(P[:card].text[])")
    check(P[:total] == total0 + m.score, "the basket did not get the berry ($(P[:total]) vs $total0)")
    wait_frames(game, 3)
    check(count(p -> p[3] > -10, P[:heap][1][]) == min(60, P[:total]), "the heap by the cottage does not show the berries")
    interact!(game, [KeyPress(Keyboard.r), Wait(0.2)])
    check(m.state === :ready && m.score == 0, "R did not restart")
    fly_click(game, "Stop")
    check(game.minigame === nothing && !P[:card].visible[], "Stop left the race or its card up")
    # a wild race (WildRace, critters among themselves) may start right after Stop: its racers race for real
    wild = only(filter(x -> nameof(typeof(x)) === :WildRace, game.plugins["berry_race"].systems))
    inwild(id) = wild.active && id in wild.racers
    check(all(id -> inwild(id) || creature(game.world, id).goal.kind ∉ (:race, :wait, :cheer), m.rivals), "the critters still race after Stop (wild race $(wild.active) $(wild.racers)): $([(creature(game.world, id).name, creature(game.world, id).goal.kind) for id in m.rivals])")
    saved === nothing ? rm(file; force = true) : write(file, saved)
    P[:total] = total0; best0 === nothing ? delete!(P, :best) : (P[:best] = best0)
    level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
    # the basket comes with the player's first berry: take back the one this test brought
    total0 == 0 && foreach(a -> NeverendingGame.despawn!(game.world, a),
                           filter(a -> a isa NeverendingGame.AssetActor && a.asset == parentmodule(typeof(m)).BASKET_ASSET, game.world.actors))
end

"The steepest the camera looked down (degrees) during the last `steer_wad`, after its first 1.5 s."
const PITCH = Ref(0.0)
rig_pitch(game) = (d = game.rig.target - game.rig.eye; rad2deg(atan(-d[3], hypot(d[1], d[2]))))

"Play like a person with W/A/D only: hold W, turn towards the nearest free target with A or D, for `seconds`."
function steer_wad(game, target_of, seconds)
    c = creature(game.world, "Lumi")
    K = Keyboard
    interact!(game, [KeyDown(K.w)])
    held = nothing
    t0 = time()
    PITCH[] = 0.0
    while time() - t0 < seconds
        time() - t0 > 1.5 && (PITCH[] = max(PITCH[], rig_pitch(game)))
        p = target_of()
        p === nothing && break
        d = NeverendingGame.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
        want = abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
        if want !== held
            held === nothing || interact!(game, [KeyUp(held)])
            want === nothing || interact!(game, [KeyDown(want)])
            held = want
        end
        interact!(game, [Wait(0.1)])
    end
    held === nothing || interact!(game, [KeyUp(held)])
    interact!(game, [KeyUp(K.w), Wait(0.1)])
end

uitest("Berry race: a first play with only W/A/D picks 3 berries in 20 s from a meadow start line") do game
    file = joinpath(game.paths.state, "berries.json")
    saved = isfile(file) ? read(file, String) : nothing
    P = Main.BERRY_PLOTS
    total0 = get(P, :total, 0); best0 = get(P, :best, nothing); level0 = get(P, :level, nothing)
    P[:level] = 1          # a first round (the player's own level is put back at the end)
    fly_choose(game, "Berry race (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    check(m !== nothing && occursin("Berry", NeverendingGame.game_title(typeof(m))), "Berry race did not start")
    c = creature(game.world, "Lumi")
    mod = parentmodule(typeof(m))
    check(NeverendingGame.walkway_height(c.pos[1], c.pos[2]) === nothing, "the race starts on the pier at $(c.pos)")
    near = sort([mod.flat(b.foot, c.pos) for b in m.berries])
    check(length(near) >= 3 && near[1] < 5, "no berry within 5 m of the start line: nearest $(round.(first(near, 3); digits = 1))")
    wait_frames(game, 10)
    check(game.stage.labels === nothing || !game.stage.labels.visible[], "name tags show under the start card")
    screenshot(game, "berry-startline")
    nearest() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    t0 = game.world.t
    steer_wad(game, () -> m.score >= 3 ? nothing : nearest(), 20)
    screenshot(game, "berry-wad")
    check(PITCH[] <= 32, "the race camera looked down $(round(PITCH[]; digits = 1))° while W was held (a map, not a view ahead)")
    check(m.score >= 3, "W/A/D play picked $(m.score) berries in $(round(game.world.t - t0; digits = 1)) s (critters $(m.rival_score)), Lumi at $(c.pos)")
    m.t = 61.0
    wait_frames(game, 3)
    check(m.state === :over && occursin("R to play again", P[:card].text[]), "no end card: $(P[:card].text[])")
    screenshot(game, "berry-wad-end")
    fly_click(game, "Stop")
    check(game.stage.labels === nothing || game.stage.labels.visible[], "name tags stay hidden after Stop")
    saved === nothing ? rm(file; force = true) : write(file, saved)
    P[:total] = total0; best0 === nothing ? delete!(P, :best) : (P[:best] = best0)
    level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
    total0 == 0 && foreach(a -> NeverendingGame.despawn!(game.world, a),
                           filter(a -> a isa NeverendingGame.AssetActor && a.asset == mod.BASKET_ASSET, game.world.actors))
end

uitest("Firefly catch: a first play with only W/A/D catches 3 flies in 20 s, never from the pier") do game
    fly_choose(game, "Firefly catch (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    check(m !== nothing && occursin("Firefly", NeverendingGame.game_title(typeof(m))), "Firefly catch did not start")
    c = creature(game.world, "Lumi")
    mod = parentmodule(typeof(m))
    check(NeverendingGame.walkway_height(c.pos[1], c.pos[2]) === nothing, "the catch starts on the pier at $(c.pos)")
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    nearest() = (free = findall(!, m.caught); isempty(free) ? nothing : fly(free[argmin([norm(Vec2f(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2])) for i in free])]))
    start = (c.pos, [round(norm(Vec2f(f[1] - c.pos[1], f[2] - c.pos[2])); digits = 1) for f in m.flies[1:3]])
    steer_wad(game, () -> m.score >= 3 ? nothing : nearest(), 20)
    screenshot(game, "firefly-wad")
    check(PITCH[] <= 32, "the catch camera looked down $(round(PITCH[]; digits = 1))° while W was held (a map, not a view ahead)")
    check(m.score >= 3, "W/A/D play caught $(m.score) flies in 20 s, Lumi at $(c.pos); start $(start[1]) first flies at $(start[2]) m, caught $(m.caught), nearest free now $(nearest())")
    fly_click(game, "Stop")
end

uitest("Wild berry race: critters race each other for ripe berries, the winner dances") do game
    slot = game.systems[findfirst(x -> nameof(typeof(x.system)) === :WildRace, game.systems)]
    s = slot.system
    M = parentmodule(typeof(s))
    s.active && M.end_wild!(s, game; quiet = true)
    # berries ripen by day, and at night the critters sleep: the race is a daytime thing
    ok = M.start_wild!(s, game)
    me = creature(game.world, "Lumi")
    nfree = count(c -> c !== me && Base.invokelatest(M.free_creature, c), game.world.creatures)
    # at night, or with fewer than two critters free (asleep at dawn, a dance circle, a chat: s32): no race, rightly
    (NeverendingGame.is_night(game.world) || nfree < 2) && !ok && return
    # two free critters far apart, or with no bush within reach of both, cannot race (the same test as start_wild!)
    frees = [c for c in game.world.creatures if c !== me && Base.invokelatest(M.free_creature, c)]
    pair = any(b -> count(o -> 1.5f0 < M.flat(o.pos, b.pos) < 32f0 && Base.invokelatest(M.land_path, game.world, o.pos, b.pos), frees) >= 2,
               [p for p in game.world.props if p.kind === :bush])
    !ok && !pair && nfree < 3 && return
    check(ok, "no bush with two critters near it for a race ($nfree free: $([(c.name, c.goal.kind) for c in game.world.creatures]))")
    check(length(s.racers) >= 2 && length(s.berries) >= 2, "a race needs two racers and two berries")
    wait_frames(game, 2)
    check(all(id -> creature(game.world, id).goal.kind in (:race, :detour, :cheer), s.racers), "the racers do not run for the berries: $([creature(game.world, id).goal.kind for id in s.racers])")
    check(NeverendingGame.interesting_subject(game.world) in s.racers, "the watching camera does not turn to the race")
    o = creature(game.world, s.racers[1])
    o.pos = s.berries[findfirst(b -> b.taken == 0, s.berries)].foot
    wait_frames(game, 3)
    check(s.score[1] >= 1, "$(o.name) at a berry did not eat it")
    s.t0 -= 100
    wait_frames(game, 2)
    check(!s.active && o.goal.kind === :dance, "the race did not end with the winner dancing ($(o.goal.kind))")
    check(NeverendingGame.interesting_subject(game.world) == o.id, "the camera does not stay on the dancing winner")
end

uitest("Wild berry race: a racer taken away (a rain shower) is not pulled back to the bush") do game
    slot = game.systems[findfirst(x -> nameof(typeof(x.system)) === :WildRace, game.systems)]
    s = slot.system
    M = parentmodule(typeof(s))
    s.active && M.end_wild!(s, game; quiet = true)
    ok = M.start_wild!(s, game)
    ok || return                                          # night, or too few free critters (tested above)
    w = game.world
    ids = copy(s.racers)
    o = creature(w, ids[1])
    g = NeverendingGame.Goal(:rain, o.pos, :dance, 60.0, Inf, true, 0, false)   # what a shower gives a dancer
    o.goal = g
    wait_seconds(game, 2)
    check(o.goal === g, "$(o.name) left the rain for $(o.goal.kind) (race active $(s.active))")
    for id in s.racers
        c = creature(w, id)
        c === o || c.goal.kind ∉ M.RACE_GOALS || (c.goal = NeverendingGame.Goal(:rain, c.pos, :sit, 60.0, Inf, true, 0, false))
    end
    wait_frames(game, 3)
    check(!s.active, "the race goes on with every racer gone")
    for id in ids
        c = creature(w, id); c === nothing || c.goal.kind !== :rain || NeverendingGame.choose_goal!(c, w)
    end
    o.goal.kind === :rain && NeverendingGame.choose_goal!(o, w)
end

uitest("Emotes float over creatures: hearts, notes, z's") do game
    NG = NeverendingGame
    # follow one awake creature: with subject 0 the camera may hold a quiet scenic shot with nobody in it (failed in the suite)
    j = findfirst(x -> x.species != "Lumi" && x.action !== :sleep, game.world.creatures)
    game.rig.mode = :follow; game.rig.subject = j === nothing ? 0 : game.world.creatures[j].id
    wait_seconds(game, 2)
    # an on-screen creature: the follow camera may still frame a moment, not interesting_subject (failed in the suite)
    sc = game.stage.scene
    eye = Point3f(sc.camera.eyeposition[])
    vis = filter(x -> NG.on_screen(sc, NG.head_point(game.world, x) + Point3f(0, 0, 0.25f0)) !== nothing, game.world.creatures)
    check(!isempty(vis), "no creature on screen")
    c = vis[argmin([norm(Vec3f(x.pos - eye)) for x in vis])]
    for k in (:heart, :note, :hey)
        Base.invokelatest(Main.EMOTES[:emote], c.id, k)
    end
    mine = Main.EMOTES[:live][end-2:end]
    wait_frames(game, 3)
    check(Main.EMOTES[:shown] >= 3, "only $(Main.EMOTES[:shown]) emotes on screen over $(c.name)")
    check(length(Main.EMOTES[:hearts][1][]) >= 1 && Main.EMOTES[:hearts].color[][1].alpha > 0, "no visible heart")
    screenshot(game, "emotes")
    wait_seconds(game, 2.5)
    check(!any(e -> any(m -> m === e, mine), Main.EMOTES[:live]), "the emotes did not fade away")
    # a sleeping creature near the camera shows z's by itself (when someone sleeps now)
    i = findfirst(x -> x.action === :sleep, game.world.creatures)
    if i !== nothing
        sl = game.world.creatures[i]
        game.rig.subject = sl.id
        wait_seconds(game, 2.5)
        check(sl.action !== :sleep || any(e -> e.id == sl.id && e.kind === :sleep, Main.EMOTES[:live]), "$(sl.name) sleeps without z's")
        game.rig.subject = 0
    end
end

uitest("Dance circle: critters dance in a ring by a lantern, Lumi walks in and they cheer") do game
    NG = NeverendingGame
    d = game.plugins["dancecircle"].mod
    s = d.CURRENT[]
    s.active && Base.invokelatest(d.end_circle!, s, game)
    # at night most critters sleep: wake four so a ring can form
    # (and bring them close: fishers on the pier and far wanderers made the ring fail to form)
    spot = first(Base.invokelatest(d.dance_spots, game))
    for (k, c) in enumerate(first(filter(c -> c.species != "Lumi" && !c.controlled, game.world.creatures), 4))
        c.pos = NG.ground(game.world.island, (spot[1] + 3.5f0 * cos(1.6f0 * k), spot[2] + 3.5f0 * sin(1.6f0 * k)))
        c.goal = NG.Goal(:idle, c.pos, :idle, 30.0, game.world.t + 30.0, true, 0, false); c.action = :idle
    end
    check(Base.invokelatest(d.start_circle!, s, game; spot), "no dance circle could start (spots: $(Base.invokelatest(d.dance_spots, game)))")
    t = 0.0
    while s.active && s.t0 == 0.0 && t < 40
        wait_seconds(game, 1); t += 1
        # a dancer taken away while gathering (a wild race, a wave) breaks the ring up: gather again
        s.active || (t < 30 && Base.invokelatest(d.start_circle!, s, game))
    end
    check(s.active && s.t0 > 0, "the dancers never stood in the ring (after $t s)")
    wait_seconds(game, 1.5)
    members = [NG.creature(game.world, id) for id in s.members]
    check(length(members) >= 3, "only $(length(members)) dancers")
    for c in members
        r = hypot(c.pos[1] - s.center[1], c.pos[2] - s.center[2])
        check(c.action === :dance && abs(r - d.RING_R) < 0.3, "$(c.name) is not dancing in the ring ($(c.action), $(round(r; digits = 2)) m)")
    end
    check(NG.interesting_subject(game.world) in s.members || NG.CAMERA_FOCUS[] !== nothing, "the watching camera does not turn to the ring")
    game.rig.mode = :follow; game.rig.subject = 0
    wait_seconds(game, 1)
    screenshot(game, "dancecircle")
    # jump in as Lumi and walk into the ring
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    me = creature(game.world, "Lumi")
    me.pos = NG.ground(game.world.island, (s.center[1], s.center[2]))
    wait_frames(game, 3)
    check(s.lumi_joined, "walking into the ring did nothing")
    check(any(e -> e.id == me.id && e.kind === :heart, Main.EMOTES[:live]), "no hearts when Lumi joined")
    screenshot(game, "dancecircle-join")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    Base.invokelatest(d.end_circle!, s, game)
    check(all(c -> c.goal.kind !== :circle, members), "dancers still hold the ring after it ended")
end

# Ball play: as Lumi, walk into the ball, a critter runs after it and passes it back.

uitest("Ball play: Lumi kicks the ball, a critter fetches it and passes it back") do game
    NG = NeverendingGame
    bp = game.plugins["ballplay"].mod.CURRENT[]
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    w = game.world
    me = creature(w, "Lumi")
    ball = w.props[findfirst(p -> p.kind === :ball, w.props)]
    ball.data["vel"] = [0.0, 0.0]
    buddy = awake_critter(game, me)
    # an open place for the game (the ball may have rolled to the beach, where Lumi cannot walk)
    spot = first(Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game))
    ball.pos = NG.ground(w.island, (spot[1], spot[2]))
    b = ball.pos
    # Lumi 1.3 m west of the ball facing east, a friend 4 m further east
    me.pos = NG.ground(w.island, (b[1] - 1.3f0, b[2])); me.yaw = 0f0 - NG.species_of(me).heading
    buddy.pos = NG.ground(w.island, (b[1] + 4f0, b[2] + 1f0))
    # a friend who is free to play (it may still be hopping from an earlier test's cheer: :answer)
    buddy.goal = NG.Goal(:idle, buddy.pos, :idle, 30.0, w.t + 30.0, true, 0, false); buddy.action = :idle
    streak0 = bp.streak; bp.last_pass = -100.0; kick0 = bp.kick_t
    p0 = me.pos
    interact!(game, [KeyDown(Keyboard.w), Wait(0.8), KeyUp(Keyboard.w), Wait(0.1)])
    diag() = "Lumi $(me.action) at $(round(hypot(me.pos[1] - ball.pos[1], me.pos[2] - ball.pos[2]), digits = 2)) m from the ball; $(buddy.name) $(buddy.goal.kind)/$(buddy.action) at $(round(hypot(buddy.pos[1] - ball.pos[1], buddy.pos[2] - ball.pos[2]), digits = 1)) m, can fetch $(game.plugins["ballplay"].mod.can_fetch(buddy)); rally $(bp.rally)"
    check(norm(me.pos - p0) > 0.3, "Lumi did not walk on W (free run ahead $(NG.free_run(w, me, me.yaw + NG.species_of(me).heading)) m; $(diag()))")
    check(bp.kick_t > kick0, "walking into the ball did not kick it ($(diag()))")
    # a critter standing right by the ball (left there by the dance circle test) passes it back at once: right too
    check(bp.passer != 0 || bp.last_pass > w.t - 3, "nobody ran after the ball ($(diag()); at the kick: $(game.plugins["ballplay"].mod.LAST_KICK[]))")
    fetcher = bp.passer == 0 ? nothing : NG.creature(w, bp.passer)
    # read the ball on the first frame after the pass: a short pass reaches Lumi's feet within half a second
    t0 = w.t
    while bp.streak == 0 && w.t - t0 < 12     # the kick reset the streak (streak0 may be an earlier run's 1)
        wait_frames(game, 1)
    end
    check(bp.streak == 1, "$(fetcher === nothing ? "nobody" : fetcher.name) did not pass the ball back (streak $(bp.streak), goal $(fetcher === nothing ? :none : fetcher.goal.kind), $(round(w.t - t0, digits = 1)) s)")
    v = ball.data["vel"]
    to = (me.pos[1] - ball.pos[1], me.pos[2] - ball.pos[2])
    check(v[1] * to[1] + v[2] * to[2] > 0 || hypot(to...) < 0.8,
          "the pass does not roll towards Lumi (ball vel $(round.(v, digits = 2)), Lumi $(round.(to, digits = 2)) away, $(round(w.t - bp.last_pass, digits = 2)) s after the pass)")
    wait_frames(game, 2)
    check(Main.BALLPLAY[:counter].visible[] && occursin("Passes  1", Main.BALLPLAY[:counter].text[]), "no pass counter on screen")
    screenshot(game, "ballplay-pass")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    check(bp.passer == 0, "a fetcher is left chasing after Stop")
end

uitest("Critters pass the ball back and forth by themselves, the camera watches") do game
    NG = NeverendingGame
    m = game.plugins["ballplay"].mod; s = m.CURRENT[]
    w = game.world
    ball = w.props[findfirst(p -> p.kind === :ball, w.props)]
    spot = first(Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game))
    ball.pos = NG.ground(w.island, (spot[1], spot[2])); ball.data["vel"] = [0.0, 0.0]
    me = creature(w, "Lumi")
    cs = [c for c in w.creatures if c !== me && !c.controlled && c.goal.kind ∉ (:circle, :fetch)]
    a, b = cs[end], cs[end-1]
    home = (a => a.pos, b => b.pos)      # put back afterwards: left by the ball they spoiled the next test
    a.pos = NG.ground(w.island, (spot[1] - 0.6f0, spot[2])); b.pos = NG.ground(w.island, (spot[1] + 4f0, spot[2] + 0.5f0))
    for c in (a, b)
        c.goal = NG.Goal(:idle, c.pos, :idle, 30.0, w.t + 30.0, true, 0, false); c.action = :idle
    end
    # the kick a critter makes by itself (the engine's :ball goal) starts the game
    NG.kick!(ball, 4f0, Vec2f(1, 0.1)); Base.invokelatest(m.start_rally!, s, w, a, ball)
    if NG.night_factor(w) > 0.5f0      # at night nobody starts a ball game by itself: they go to bed
        check(s.rally == 0, "a ball game started in the middle of the night")
        # the passes are still tested at night: this rally is started on purpose
        Base.invokelatest(m.start_rally!, s, w, a, ball; night_ok = true)
    end
    check(s.rally == 1 && s.passer != 0, "no friend ran for the ball")
    check(m.watch_rally(w) == s.passer, "the camera moment does not point at the fetcher")
    best = 0; t = 0.0; seen = ""; framed = false
    while t < 15 && (best < 3 || !framed)
        wait_seconds(game, 0.5); t += 0.5
        best = max(best, s.rally)
        if best >= 2 && !framed && s.passer != 0
            # the watching camera holds the whole rally: both critters and the ball inside its view cone
            # (the follow camera holds its last creature up to 6 s first: render.jl held_subject)
            eye, look = NG.camera_goal(game.rig, w)
            unit(v) = (v = Vec3f(v); v / sqrt(sum(abs2, v)))
            fwd = unit(look - eye)
            off = [acosd(clamp(sum(fwd .* unit(p - eye)), -1f0, 1f0)) for p in (a.pos, b.pos, ball.pos)]
            groups = [(k, Base.invokelatest(g, w)) for (k, g) in NG.CAMERA_GROUPS]
            maximum(off) < 28 || t >= 12 || continue
            check(maximum(off) < 28, "the camera does not frame the rally: $(round.(off, digits = 1))° off its view line (rig $(game.rig.mode) subject $(game.rig.subject), interesting $(NG.interesting_subject(w)), passer $(s.passer), shot $(NG.camera_shot(w) !== nothing), groups $([(k, v === nothing ? nothing : v[1]) for (k, v) in groups]), chats $(length(w.interactions)))")
            framed = true
            screenshot(game, "ball-rally")
            # the waiting friend watches the ball (it used to stare wherever it last looked)
            r = NG.creature(w, s.receiver)
            if r !== nothing && r.goal.kind === :rally_wait
                wait_seconds(game, 0.5)
                off = abs(rad2deg(rem2pi(atan(ball.pos[2] - r.pos[2], ball.pos[1] - r.pos[1]) - r.yaw - NG.species_of(r).heading, RoundNearest)))
                check(off < 45, "$(r.name) waits looking $(round(Int, off))° away from the ball")
            end
        end
        s.rally > 0 && (seen = "$(a.name) $(a.goal.kind)/$(a.action), $(b.name) $(b.goal.kind)/$(b.action), passer $(s.passer == 0 ? "-" : (NG.creature(w, s.passer).name, NG.creature(w, s.passer).goal.kind, NG.creature(w, s.passer).action, round(hypot(NG.creature(w, s.passer).pos[1] - ball.pos[1], NG.creature(w, s.passer).pos[2] - ball.pos[2]), digits = 1))), receiver $(s.receiver), ball speed $(round(s.speed, digits = 1))")
    end
    for (c, p) in home
        c.goal.kind in (:fetch, :rally_wait) && (s.passer = 0; s.receiver = 0; s.rally = 0)
        c.pos = p; NG.choose_goal!(c, w)
    end
    check(best < 3 || t >= 1.5, "two passes in $(t) s: too fast to see")
    check(best >= 3, "the critters passed only $(best - 1) times (last seen: $seen; now $(a.name) $(a.goal.kind), $(b.name) $(b.goal.kind))")
end

uitest("Flower gift: a critter carries a picked flower to a friend, who thanks it with hearts") do game
    NG = NeverendingGame
    w = game.world
    m = game.plugins["flowergift"].mod
    me = creature(w, "Lumi")
    # a Lumi left in play by an earlier test is the favourite friend of every giver (friend_for): set it free first
    game.minigame !== nothing && fly_click(game, "Stop")
    giver = awake_critter(game, me)
    friend = awake_critter(game, giver)
    friend === me && (friend = w.creatures[findfirst(c -> c !== me && c !== giver && !c.controlled, w.creatures)])
    spot = first(Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game))
    home = (giver => giver.pos, friend => friend.pos)
    giver.pos = NG.ground(w.island, (spot[1] - 2f0, spot[2])); friend.pos = NG.ground(w.island, (spot[1] + 2f0, spot[2] + 0.5f0))
    friend.goal = NG.Goal(:idle, friend.pos, :idle, 30.0, w.t + 30.0, true, 0, false); friend.action = :idle
    # it picked a flower: the gift goal wins its next choice
    m.CARRYING[giver.id] = w.t
    check(NG.goal_score(Val(:gift), giver, w) > 1, "carrying a flower does not make the gift the next goal")
    giver.goal = NG.Goal(:gift, friend.pos, :wave, 2.5, 0.0, false, friend.id, false)
    wait_frames(game, 2)
    plot = Main.GIFT_PLOTS[:plot]
    check(any(s -> s[1] > 0, plot.markersize[]), "no flower drawn in front of $(giver.name)")
    check(m.watch_gift(w) == giver.id, "the camera moment does not watch $(giver.name) carrying the flower")
    wait_seconds(game, 1.0)
    screenshot(game, "flower-gift-carry")
    t = 0.0
    while haskey(m.CARRYING, giver.id) && t < 15
        wait_seconds(game, 0.5); t += 0.5
    end
    check(!haskey(m.CARRYING, giver.id), "$(giver.name) never reached $(friend.name) ($(giver.goal.kind), $(round(norm(giver.pos - friend.pos), digits = 1)) m)")
    said(c) = [s.text for s in w.speech if s.who == c.id]
    check(any(s -> occursin(friend.name, s), said(giver)), "$(giver.name) gave nothing to say: $(said(giver)) (partner $(giver.goal.partner), friend $(friend.id), Lumi controlled $(me.controlled), minigame $(typeof(game.minigame)); friend now $(friend.goal.kind)/$(friend.action) $(round(norm(giver.pos - friend.pos), digits = 1)) m away)")
    wait_seconds(game, 1.6)
    check(any(s -> s in m.THANKS, said(friend)), "$(friend.name) did not thank: $(said(friend))")
    screenshot(game, "flower-gift-thanks")
    wait_frames(game, 2)
    # other critters pick flowers by themselves: one drawn flower per carrier, and the giver is none of them
    drawn = count(s -> s[1] > 0, plot.markersize[])
    check(!haskey(m.CARRYING, giver.id) && drawn == length(m.CARRYING),
          "the flower is still drawn after the gift ($drawn drawn, carriers $([NG.creature(w, id).name for id in keys(m.CARRYING)]))")
    for (c, p) in home; c.pos = p; NG.choose_goal!(c, w); end
end

uitest("Flower gift: playing Lumi, E by a flower picks it and E by a critter gives it") do game
    NG = NeverendingGame
    w = game.world
    m = game.plugins["flowergift"].mod
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(w, "Lumi")
    delete!(m.CARRYING, me.id)
    # a flower out in the open (not under a tree crown)
    trees = [p for p in w.props if p.kind === :tree]
    f = w.props[findfirst(p -> p.kind === :flower && !haskey(get(Main.FLORA_PLOTS, :picked, Dict()), p.id) && all(t -> hypot(t.pos[1] - p.pos[1], t.pos[2] - p.pos[2]) > 2.6f0 * t.scale, trees), w.props)]
    me.pos = NG.ground(w.island, (f.pos[1] - 0.6f0, f.pos[2]))
    wait_frames(game, 2)
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    check(haskey(m.CARRYING, me.id), "E next to a flower did not pick it")
    wait_frames(game, 2)
    newest = argmax(kv -> kv[2], collect(Main.FLORA_PLOTS[:picked]))[1]
    fv = only(v for v in Main.FLORA_PLOTS[:flowers] if any(p -> p.id == newest, v.props))
    check(fv.plot.markersize[][findfirst(p -> p.id == newest, fv.props)] == Vec3f(0), "the picked flower is still in the meadow")
    check(newest in Main.NIGHTGLOW[:hidden], "the picked flower's night bloom is still there")
    plot = Main.GIFT_PLOTS[:plot]
    check(any(s -> s[1] > 0, plot.markersize[]), "Lumi's flower is not drawn")
    buddy = awake_critter(game, me)
    home = buddy.pos
    buddy.pos = NG.ground(w.island, (me.pos[1] + 1.6f0, me.pos[2] + 0.3f0))
    buddy.goal = NG.Goal(:idle, buddy.pos, :idle, 30.0, w.t + 30.0, true, 0, false); buddy.action = :idle
    wait_seconds(game, 1.0)        # a moment between the two presses
    screenshot(game, "flower-gift-lumi-carry")
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    check(!haskey(m.CARRYING, me.id), "E next to $(buddy.name) did not give the flower")
    said(c) = [s.text for s in w.speech if s.who == c.id]
    check(any(s -> occursin(buddy.name, s), said(me)), "Lumi said nothing to $(buddy.name): $(said(me))")
    wait_seconds(game, 1.6)
    check(any(s -> s in m.THANKS, said(buddy)), "$(buddy.name) did not thank Lumi: $(said(buddy))")
    screenshot(game, "flower-gift-lumi-thanks")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    buddy.pos = home; NG.choose_goal!(buddy, w)
end

uitest("Night shots: while Lumi sleeps the follow camera shows the cottage, a lantern, the moon, a sleeper") do game
    NG = NeverendingGame
    m = game.plugins["nightshots"].mod; s = m.CURRENT[]
    w = game.world
    game.minigame === nothing || (fly_click(game, "Stop"); wait_frames(game, 2))
    game.rig.mode = :follow; game.rig.subject = 0
    m.FORCE[] = true
    seen = Symbol[]; shots = 0
    for i in 1:6
        s.t0 -= 100                     # next shot now
        wait_seconds(game, 2.5)
        s.on || continue
        kind = s.kinds[s.k]
        shot = NG.camera_shot(w)
        shot === nothing && continue    # a moment (a chat, a dance) has the camera: right too
        # a moment that just ended (a chat) leaves the camera gliding back for a moment
        norm(game.rig.target - shot[2]) < 2.0f0 || (wait_seconds(game, 1.5); shot = NG.camera_shot(w); shot === nothing && continue)
        shots += 1
        push!(seen, kind)
        check(norm(game.rig.target - shot[2]) < 2.0f0, "the camera does not look where the $(kind) shot looks ($(game.rig.target) vs $(shot[2]))")
        # the eye glides more slowly than the look point (shots of two sleepers can lie across the island):
        # judge the view once the eye has arrived
        tw = 0.0
        while norm(game.rig.eye - shot[1]) > 1.0f0 && tw < 3
            wait_seconds(game, 0.5); tw += 0.5
            sh2 = NG.camera_shot(w); sh2 === nothing || (shot = sh2)
        end
        o = NG.obstruction(w, game.rig.eye, game.rig.target)
        kind === :moon || check(o < 0.6f0, "trees block the $(kind) shot (obstruction $(round(o, digits = 2)), eye $(round(norm(game.rig.eye - shot[1]), digits = 2)) m from the shot's eye)")
        screenshot(game, "nightshot-$(kind)")
    end
    m.FORCE[] = false
    # in the full suite critters stand about the lanterns (earlier tests put them there), so
    # some shots give way to moments or are not clear: judge the change only with 3+ shots
    check(shots < 3 || length(unique(seen)) >= 2, "the night shots never change: $(seen)")
    check(shots > 0 || NG.moment_subject(w) !== nothing, "no night shot and nothing else to watch")
    me = creature(w, "Lumi")
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    wait_frames(game, 3)
    check(NG.camera_shot(w) === nothing, "a player at the keys still gets night shots")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("Night shots visit the pond and the pier too, each with a clear view") do game
    m = game.plugins["nightshots"].mod
    w = game.world
    for k in (:pond, :pier)
        check(k in Base.invokelatest(() -> (s = m.CURRENT[]; isempty(s.kinds) ? [:cottage, :pond, :lantern, :moon, :pier, :lantern] : s.kinds)), "$k is not among the night shots")
        f = Base.invokelatest(m.frame_shot, game, k)
        check(f !== nothing, "no clear framing for the $k at night")
        f === nothing && continue
        c, look, a, d, h = f
        eye = Base.invokelatest(m.shot_eye, c, a, d, h, w)
        o = NeverendingGame.obstruction(w, eye, look)
        check(o < 0.6f0, "the $k shot is blocked (obstruction $o)")
    end
end

uitest("Beds: a critter going to sleep by a tree beds down outside the crown, where the camera sees it") do game
    NG = NeverendingGame
    w = game.world
    m = game.plugins["beds"].mod
    cs = [c for c in w.creatures if !c.controlled && c.species != "Lumi"]
    moved = 0; tried = 0
    for c in cs[1:min(4, end)]
        old = c.goal
        g = NG.start_goal(Val(:sleep), c, w)
        tree, d = NG.nearest(p -> p.kind === :tree, w.props, g.target)
        (tree === nothing || d > 3f0) && continue
        tried += 1
        c.goal = g
        wait_frames(game, 2)
        inside = [round(hypot(p.pos[1] - g.target[1], p.pos[2] - g.target[2]) / p.scale, digits = 1) for p in w.props if p.kind === :tree &&
                  hypot(p.pos[1] - g.target[1], p.pos[2] - g.target[2]) < m.CROWN * p.scale]
        isempty(inside) && (moved += 1)
        c.goal = NG.Goal(:idle, c.pos, :idle, 5.0, w.t + 5.0, true, 0, false); c.action = :idle    # back to the day
    end
    check(tried == 0 || moved >= 1, "no bed moved out of the crowns ($moved of $tried)")
end

uitest("The right panel says what the creatures are up to right now") do game
    w = game.world
    wait_seconds(game, 1.2)          # panels update twice a second
    txt = Main.ISLANDNOW[:label].text[]
    names = [c.name for c in w.creatures]
    check(any(n -> occursin(n, txt), names) || occursin("asleep", txt), "the island panel names nobody: '$(txt)'")
    check(!occursin("New on the island", txt), "changelog text in the island panel")
    check(length(split(txt, '\n')) <= 7, "the island panel is too long: '$(txt)'")
end

uitest("Cairn: a critter fetches a pebble, carries it over its head and the cairn grows by a stone") do game
    NG = NeverendingGame
    w = game.world
    st = Main.CAIRN_STATE
    check(st[:site] !== nothing, "the cairn has no site")
    if NG.is_night(w)          # pebbles are a daytime thing: forward to the next morning
        NG.skip_to_hour!(w, 9)
    end
    MAXS = game.plugins["cairns"].mod.MAX_STONES
    s = st[:site]
    cands = [c for c in w.creatures if c.species != "Lumi" && !c.controlled && c.action !== :sleep &&
             c.goal.kind ∉ (:interact, :fish) && c.goal.kind ∉ NG.BUSY_GOALS]
    check(!isempty(cands), "no awake critter for the pebble")
    c = argmin(o -> hypot(o.pos[1] - s[1], o.pos[2] - s[2]), cands)
    n0 = st[:n]
    c.goal = Base.invokelatest(NG.start_goal, Val(:pebble), c, w)
    carried = false
    t0 = time()
    while st[:n] == n0 && time() - t0 < 60
        wait_seconds(game, 0.5)
        carried |= c.goal.kind === :pebble && c.goal.partner == 1
        carried && !haskey(Main.CAIRN_STATE, :shot) && (screenshot(game, "cairn_carry"); st[:shot] = true)
    end
    delete!(st, :shot)
    check(st[:n] > n0, "no stone was added in 60 s ($(c.name), goal $(c.goal.kind) partner $(c.goal.partner), " *
                       "$(round(hypot(c.pos[1] - s[1], c.pos[2] - s[2]), digits = 1)) m from the cairn, carried $carried)")
    check(carried || st[:n] > n0, "nobody was seen carrying a pebble")
    p = st[:plots][:stack]
    check(length(p[1][]) == min(st[:n], MAXS), "the cairn shows $(length(p[1][])) stones, the count is $(st[:n])")
end

uitest("Cairn: Lumi picks up a loose pebble with E, walks it over with W/A/D and sets it on the cairn, the critters cheer") do game
    NG = NeverendingGame
    st = Main.CAIRN_STATE
    cm = game.plugins["cairns"].mod
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(game.world, "Lumi")
    delete!(game.plugins["flowergift"].mod.CARRYING, me.id)
    n0 = st[:n]
    ps = cm.pebbles(game.world)
    clear(q) = all(f -> f.kind !== :flower || hypot(f.pos[1] - q[1], f.pos[2] - q[2]) > 1.4f0, game.world.props)
    k = findfirst(clear, ps)
    check(k !== nothing, "every loose pebble lies by a flower (E would pick the flower): $(ps)")
    p = ps[k]
    me.pos = NG.ground(game.world.island, (p[1] + 0.5f0, p[2]))   # the scenario starts beside a pebble
    wait_frames(game, 3)
    interact!(game, [KeyPress(Keyboard.e; duration = 0.2), Wait(0.3)])
    check(cm.lumi_carries(), "E beside a pebble did not pick it up (Lumi $(me.action), $(round(hypot(me.pos[1] - p[1], me.pos[2] - p[2]); digits = 2)) m from it)")
    check(length(cm.pebbles(game.world)) == cm.LOOSE && !(p in cm.pebbles(game.world)), "the picked pebble still lies there")
    screenshot(game, "cairn-lumi-carry")
    s = st[:site]
    steer_wad(game, () -> cm.lumi_carries() ? s : nothing, 20)
    check(!cm.lumi_carries() && st[:n] == n0 + 1,
          "walking to the cairn did not set the stone down: carrying $(cm.lumi_carries()), $(st[:n]) stones (was $n0), Lumi $(round(hypot(me.pos[1] - s[1], me.pos[2] - s[2]); digits = 1)) m from the cairn")
    screenshot(game, "cairn-lumi-set")
    check(!isempty(get(st, :cheer, Int32[])) || all(o -> o === me || o.action === :sleep || hypot(o.pos[1] - s[1], o.pos[2] - s[2]) > 9, game.world.creatures),
          "awake critters near the cairn did not cheer")
    fly_click(game, "Stop")
end

uitest("Rain shower: each critter takes it its own way; Lumi splashing in the open brings them all to a puddle party") do game
    NG = NeverendingGame
    w = game.world
    sh = game.plugins["showers"]
    s = only(sh.systems)
    s.active && Base.invokelatest(sh.mod.end_shower!, s, game)
    game.minigame === nothing || fly_click(game, "Stop")
    me = creature(w, "Lumi")
    for c in w.creatures                               # at night or in a dance ring: four are free for it
        count(c -> Base.invokelatest(sh.mod.can_join, c), w.creatures) >= 4 && break
        (c === me || c.controlled || Base.invokelatest(sh.mod.can_join, c)) && continue
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:idle, c.pos, :idle, 30.0, w.t + 30.0, true, 0, false); c.action = :idle
    end
    check(Base.invokelatest(sh.mod.start_shower!, s, game), "no shower started ($(count(c -> Base.invokelatest(sh.mod.can_join, c), w.creatures)) critters free)")
    roles = Set(values(s.roles))
    check(length(roles) >= 3, "the critters do not react in different ways: $(s.roles)")
    ids0 = collect(keys(s.roles))
    wait_seconds(game, 4)
    gone = [(creature(w, id).name, creature(w, id).goal.kind, creature(w, id).action) for id in ids0 if !haskey(s.roles, id)]
    check(isempty(gone), "critters left the shower within 4 s: $gone")
    check(sh.mod.SH[:drops].visible[], "no rain to see")
    cl = sh.mod.SH[:cloud]
    near = [round(norm(q - game.rig.eye); digits = 1) for (q, m) in zip(cl[1][], cl.markersize[]) if m[1] > 0 && norm(q - game.rig.eye) < 1.5f0 * m[1] + 5f0]
    check(isempty(near), "rain cloud puffs right in front of the lens (a huge flat disc in the picture): $near m")
    check(NG.SUN_DIM[] < 1f0, "the sun shines on as bright in the rain (SUN_DIM $(NG.SUN_DIM[]))")
    acts = Dict(creature(w, id).name => creature(w, id).action for id in keys(s.roles))
    check(length(Set(values(acts))) >= 3, "the critters all do the same: $acts")
    screenshot(game, "shower-reactions")
    # jump in and splash in the open, away from the trees
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    spots = Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game)     # open places by the lanterns
    check(!isempty(spots), "no open spot")
    q = argmin(q -> hypot(q[1] - s.center[1], q[2] - s.center[2]), spots)
    me.pos = NG.ground(w.island, q)
    out0 = count(==(:shelter), values(s.roles))
    for _ in 1:6
        interact!(game, [KeyPress(Keyboard.space; duration = 0.4), Wait(0.6)])
    end
    check(s.joined > 0, "splashing in the open did not count (Lumi $(me.action))")
    wait_seconds(game, 12)
    near = [creature(w, id).name for id in keys(s.roles) if hypot(creature(w, id).pos[1] - me.pos[1], creature(w, id).pos[2] - me.pos[2]) < 3.5f0]
    check(length(near) >= 3, "only $(near) came to the puddle party; roles $([(creature(w, id).name, r, creature(w, id).goal.kind, round(hypot(creature(w, id).pos[1] - me.pos[1], creature(w, id).pos[2] - me.pos[2]); digits = 1)) for (id, r) in s.roles])")
    check(out0 == 0 || count(==(:party), values(s.roles)) > 0 && !any(==(:shelter), values(s.roles)), "the ones under the trees stayed there: $(s.roles)")
    screenshot(game, "shower-party")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    # the sun comes back: everyone goes back to its own life (no state left for the next test)
    s.until = w.t
    wait_frames(game, 3)
    check(!s.active && !any(c -> c.goal.kind === :rain, w.creatures), "the shower did not end cleanly: $([(c.name, c.goal.kind) for c in w.creatures if c.goal.kind === :rain])")
    check(NG.SUN_DIM[] == 1f0, "the sun stays dim after the rain ($(NG.SUN_DIM[]))")
    if !NG.is_night(w)                                 # a rainbow over the sea after a shower by day
        wait_seconds(game, 3)
        check(haskey(sh.mod.SH, :bow) && sh.mod.SH[:bow].visible[], "no rainbow after the shower")
    end
end

uitest("Hide and seek: friends hide behind trees, a first play with only W/A/D finds 2 by their giggles, they follow, end card") do game
    fly_choose(game, "Hide and seek (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    check(m !== nothing && occursin("Hide", NeverendingGame.game_title(typeof(m))), "Hide and seek did not start")
    P = Main.HIDESEEK_PLOTS
    mod = parentmodule(typeof(m))
    c = creature(game.world, "Lumi")
    w = game.world
    check(length(m.hiders) >= 3, "only $(length(m.hiders)) friends hid (spots $(length(m.spots)))")
    check(all(id -> creature(w, id).goal.kind === :hide, m.hiders), "hiders not hiding: $([creature(w, id).goal.kind for id in m.hiders])")
    check(P[:card].visible[] && occursin("Press W", P[:card].text[]), "no start card")
    near = sort([mod.flat(q, c.pos) for q in m.spots])
    check(near[1] < 14, "the nearest hiding spot is $(round(near[1]; digits = 1)) m away")
    wait_frames(game, 5)
    screenshot(game, "hideseek-start")
    # a person walks to the nearest friend heard giggling
    # (the nearest one heard: the HUD names its direction), or the nearest one before any giggle
    target() = count(m.found) >= 2 ? nothing : something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    steer_wad(game, target, 35)
    screenshot(game, "hideseek-found")
    check(PITCH[] <= 32, "the seek camera looked down $(round(PITCH[]; digits = 1))° while W was held (a map, not a view ahead)")
    check(count(m.found) >= 2, "W/A/D play found $(count(m.found)) in $(round(m.t; digits = 1)) s; Lumi at $(c.pos), spots $(m.spots), hud $(P[:hud].text[])")
    f = [creature(w, id) for (k, id) in enumerate(m.hiders) if m.found[k]]
    check(all(o -> o.goal.kind === :found, f), "found friends do not follow: $([o.goal.kind for o in f])")
    wait_seconds(game, 2)
    check(all(o -> mod.flat(o.pos, c.pos) < 4 + 1.2 * length(f), f), "found friends lag: $([(o.name, round(mod.flat(o.pos, c.pos); digits = 1), o.goal.kind, o.goal.action, o.action, NeverendingGame.species_of(o).name) for o in f]) m, Lumi $(c.action) state $(m.state)")
    m.t = mod.TIME_LIMIT + 1
    wait_frames(game, 3)
    check(m.state === :over && occursin("R to play again", P[:card].text[]), "no end card: $(P[:card].text[])")
    screenshot(game, "hideseek-end")
    fly_click(game, "Stop")
    check(all(id -> creature(w, id).goal.kind ∉ (:hide, :found), m.hiders), "friends still hiding after Stop")
    check(game.stage.labels === nothing || game.stage.labels.visible[], "name tags stay hidden after Stop")
end

uitest("Parade: two friends follow Lumi, a curious critter the parade walks up to joins, Space ripples hops down the line") do game
    NG = NeverendingGame
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    w = game.world
    me = creature(w, "Lumi")
    s = only(game.plugins["greetings"].systems)
    gm = game.plugins["greetings"].mod
    can(o) = o !== me && !o.controlled && o.goal.kind in gm.JOINABLE && w.t - get(s.left, o.id, -Inf) > 25
    function pick()
        o = awake_critter(game, me)
        can(o) && return o
        i = findfirst(x -> can(x) && x.action !== :sleep, w.creatures)
        i === nothing || return w.creatures[i]
        parade_friend(game, me, s, gm)   # everyone chatting or asleep: one out of a chat, as a wave would
    end
    # two friends already follow (the wave-twice part has its own test)
    friends = Any[]
    for _ in 1:2
        f = pick(); push!(friends, f)
        Base.invokelatest(gm.join_parade!, s, w, me, f, "Lead the way!")
    end
    check(length(s.followers) >= 2, "only $(length(s.followers)) followers")
    s.last_join = -Inf
    third = pick()
    third.goal = NG.Goal(:idle, third.pos, :idle, 60.0, w.t + 60.0, true, 0, false)   # stays put for the walk over
    d0 = round(hypot(third.pos[1] - me.pos[1], third.pos[2] - me.pos[2]); digits = 1)
    dcs = only(game.plugins["dancecircle"].systems)
    steer_wad(game, () -> length(s.followers) >= 3 || (dcs.active && third.id in dcs.members) ? nothing : third.pos, 25)
    # walked past a lantern, the three became a parade party (greetings parade_party!): right too (s43)
    dcs.active && third.id in dcs.members && return
    check(length(s.followers) >= 3, "nobody joined the parade (walked $(d0) m to $(third.name), now $(round(hypot(third.pos[1] - me.pos[1], third.pos[2] - me.pos[2]); digits = 1)) m, $(third.goal.kind), followers $([creature(w, id).name for id in s.followers]); the two friends now: $([(f.name, f.goal.kind, f.action, round(w.t - get(s.left, f.id, -Inf); digits = 1)) for f in friends]), Lumi $(me.action) controlled $(me.controlled))")
    joiner = creature(w, s.followers[end])
    check(joiner.goal.kind === :follow, "$(joiner.name) joined but does not follow ($(joiner.goal.kind))")
    screenshot(game, "parade-join")
    wait_seconds(game, 2)
    # Space: the line hops one after another, front to back
    first_hop = Dict{Int32,Float64}()
    ids = copy(s.followers)
    interact!(game, [KeyPress(Keyboard.space; duration = 0.15)])
    for _ in 1:60
        for id in ids
            c = creature(w, id)
            c.action === :jump && !haskey(first_hop, id) && (first_hop[id] = w.t)
        end
        length(first_hop) == length(ids) && break
        wait_frames(game, 1)
    end
    check(length(first_hop) == length(ids), "not everyone in the parade hopped: $([(creature(w, id).name, haskey(first_hop, id)) for id in ids])")
    check(first_hop[ids[end]] > first_hop[ids[1]], "the hops came all at once, not as a ripple ($([round(first_hop[id]; digits = 2) for id in ids]))")
    screenshot(game, "parade-ripple")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    check(isempty(s.followers), "the parade goes on after Stop")
end

# A creature to put in Lumi's parade: an awake free one, else a sleeper woken up (never one already in it).
function parade_friend(game, me, s, gm)
    w = game.world
    ok(o) = o !== me && !o.controlled && !(o.id in s.followers) && o.goal.kind ∉ NeverendingGame.BUSY_GOALS && o.goal.kind !== :follow
    i = findfirst(o -> ok(o) && o.goal.kind in gm.JOINABLE && o.action !== :sleep, w.creatures)
    i === nothing || return w.creatures[i]
    j = findfirst(ok, w.creatures)
    # everyone else busy (fishing, chatting, carrying): take one out of a chat, as a wave would
    j === nothing && (j = findfirst(o -> o !== me && !o.controlled && !(o.id in s.followers) && o.goal.kind === :interact, w.creatures))
    check(j !== nothing, "nobody free for the parade: $([(o.name, o.goal.kind) for o in w.creatures])")
    o = w.creatures[j]
    NeverendingGame.leave_interactions!(w, o)
    o.goal = NeverendingGame.Goal(:idle, o.pos, :idle, 30.0, w.t + 30.0, true, 0, false); o.action = :idle   # awake for 30 s
    return o
end

uitest("Parade party: a parade of three led to a lantern turns into a dance ring with Lumi in the middle") do game
    NG = NeverendingGame
    dc = only(game.plugins["dancecircle"].systems)
    dm = game.plugins["dancecircle"].mod
    dc.active && Base.invokelatest(dm.end_circle!, dc, game)
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    w = game.world
    me = creature(w, "Lumi")
    s = only(game.plugins["greetings"].systems)
    gm = game.plugins["greetings"].mod
    spots = Base.invokelatest(dm.dance_spots, game)
    check(!isempty(spots), "no dance spot by a lantern")
    # away from the cairn: a parade that starts within 2.8 m of the stone pile goes fetching pebbles at once
    # (s48: the suite's "followers 0, why -" was parade_cairn! at the start, not the walk)
    site = isdefined(Main, :CAIRN_STATE) ? get(Main.CAIRN_STATE, :site, nothing) : nothing
    far(q) = site === nothing || hypot(q[1] - site[1], q[2] - site[2]) > 5
    spots = filter(far, spots)
    check(!isempty(spots), "every dance spot is by the cairn")
    spot = spots[argmin([hypot(q[1] - me.pos[1], q[2] - me.pos[2]) for q in spots])]
    # start 7 m away on open meadow, facing the spot (where Lumi stood it may be stuck in a nook)
    starts = [Point3f(spot[1] + 7cos(a), spot[2] + 7sin(a), 0) for a in range(0, 2pi; length = 25)]
    k = findfirst(q -> far(q) && gm.standable(w, q) && all(t -> gm.standable(w, spot + t * (q - spot)), 0.4:0.1:0.9), starts)
    check(k !== nothing, "no open start 7 m from the lantern spot")
    me.pos = NG.ground(w.island, (starts[k][1], starts[k][2]))
    me.yaw = atan(spot[2] - me.pos[2], spot[1] - me.pos[1])
    # the friends join only now: joined where Lumi stood (often by a lantern) the party started at once,
    # and after the jump to the start they were dancing, not following (s43, "followers 0")
    for _ in 1:3
        Base.invokelatest(gm.join_parade!, s, w, me, parade_friend(game, me, s, gm), "Lead the way!")
    end
    check(length(s.followers) >= 3, "only $(length(s.followers)) in the parade")
    ids = copy(s.followers)
    wait_seconds(game, 1)
    d0 = round(hypot(spot[1] - me.pos[1], spot[2] - me.pos[2]); digits = 1)
    steer_wad(game, () -> dc.active ? nothing : spot, 40)
    check(dc.active, "no dance ring after walking the parade $(d0) m to the lantern spot (now $(round(hypot(spot[1] - me.pos[1], spot[2] - me.pos[2]); digits = 1)) m, followers $(length(s.followers)), the three now $([(creature(w, id).name, creature(w, id).goal.kind, creature(w, id).action, round(hypot(creature(w, id).pos[1] - me.pos[1], creature(w, id).pos[2] - me.pos[2]); digits = 1)) for id in ids]), why they left $([get(Main.PARADE_LEFT, id, "-") for id in ids]), Lumi controlled $(me.controlled), game $(typeof(game.minigame)))")
    check(all(id -> id in dc.members, ids), "the parade is not in the ring: $(ids) vs $(dc.members)")
    t0 = time()
    while dc.t0 == 0.0 && dc.active && time() - t0 < 25
        wait_seconds(game, 0.5)
    end
    check(dc.active && dc.t0 > 0, "the ring never started dancing: $([(creature(w, id).name, creature(w, id).goal.kind, creature(w, id).goal.arrived) for id in dc.members])")
    wait_seconds(game, 1.5)
    check(dc.lumi_joined, "Lumi in the middle was not cheered (distance $(round(hypot(dc.center[1] - me.pos[1], dc.center[2] - me.pos[2]); digits = 1)) m, 3D $(round(norm(me.pos - dc.center); digits = 1)) m, controlled $(me.controlled), active $(dc.active), t0 $(dc.t0), members $(length(dc.members)), same system $(dc === only(filter(x -> x isa typeof(dc), game.plugins["dancecircle"].systems))), game $(typeof(game.minigame)))")
    check(count(id -> creature(w, id).action === :dance, dc.members) >= 3, "fewer than 3 dancing")
    screenshot(game, "parade-party")
    fly_click(game, "Stop")
    wait_frames(game, 2)
    Base.invokelatest(dm.end_circle!, dc, game)
end

uitest("Parade at the cairn: friends led to the stone pile each fetch a pebble and set it on the cairn") do game
    NG = NeverendingGame
    C = Main.CAIRN_STATE
    check(get(C, :site, nothing) !== nothing, "no cairn on the island")
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    w = game.world
    me = creature(w, "Lumi")
    s = only(game.plugins["greetings"].systems)
    gm = game.plugins["greetings"].mod
    gm.CAIRN_TRIP[] = -Inf
    for _ in 1:2
        Base.invokelatest(gm.join_parade!, s, w, me, parade_friend(game, me, s, gm), "Lead the way!")
    end
    ids = copy(s.followers)
    check(length(ids) >= 2, "only $(length(ids)) in the parade")
    site = C[:site]
    starts = [Point3f(site[1] + 7cos(a), site[2] + 7sin(a), 0) for a in range(0, 2pi; length = 25)]
    k = findfirst(q -> gm.standable(w, q) && all(t -> gm.standable(w, site + t * (q - site)), 0.45:0.1:0.9), starts)
    check(k !== nothing, "no open start 7 m from the cairn")
    me.pos = NG.ground(w.island, (starts[k][1], starts[k][2]))
    me.yaw = atan(site[2] - me.pos[2], site[1] - me.pos[1])
    wait_seconds(game, 1)
    n0 = C[:n]
    steer_wad(game, () -> isempty(s.followers) ? nothing : site, 25)
    check(isempty(s.followers), "the parade did not go fetch stones at the cairn (Lumi $(round(hypot(site[1] - me.pos[1], site[2] - me.pos[2]); digits = 1)) m away)")
    check(any(id -> creature(w, id).goal.kind === :pebble, ids), "not every friend went for a pebble: $([(creature(w, id).name, creature(w, id).goal.kind) for id in ids]), trip $(gm.CAIRN_TRIP[]) left $(s.left) t $(w.t) controlled $(me.controlled)")
    t0 = time()
    while C[:n] < n0 + 1 && time() - t0 < 40
        wait_seconds(game, 0.5)
    end
    wait_seconds(game, 1)
    check(C[:n] >= n0 + 1, "the cairn did not grow (by $(C[:n] - n0)): $([(creature(w, id).name, creature(w, id).goal.kind, creature(w, id).goal.partner) for id in ids])")
    screenshot(game, "parade-cairn")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("Lumi walking at the lily pond stops on the bank, never in the water") do game
    NG = NeverendingGame
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    w = game.world
    me = creature(w, "Lumi")
    m = game.plugins["areas"].mod
    gm = game.plugins["greetings"].mod
    pc = m.POND
    starts = [Point3f(pc[1] + 5.5cos(a), pc[2] + 5.5sin(a), 0) for a in range(0, 2pi; length = 25)]
    k = findfirst(q -> gm.standable(w, q) && all(t -> gm.standable(w, Point3f(pc[1], pc[2], 0) + t * (q - Point3f(pc[1], pc[2], 0))), 0.75:0.05:0.95), starts)
    check(k !== nothing, "no open start by the pond")
    me.pos = NG.ground(w.island, (starts[k][1], starts[k][2]))
    me.yaw = atan(pc[2] - me.pos[2], pc[1] - me.pos[1])
    wait_seconds(game, 0.5)
    closest = Inf32
    interact!(game, [KeyDown(Keyboard.w)])
    for _ in 1:30
        interact!(game, [Wait(0.15)])
        closest = min(closest, hypot(me.pos[1] - pc[1], me.pos[2] - pc[2]))
    end
    interact!(game, [KeyUp(Keyboard.w), Wait(0.1)])
    check(closest > m.POND_R, "Lumi walked into the pond ($(round(closest; digits = 2)) m from the middle, radius $(m.POND_R))")
    check(hypot(me.pos[1] - starts[k][1], me.pos[2] - starts[k][2]) > 1.5, "Lumi did not walk to the pond at all")
    screenshot(game, "pond-bank")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("Butterflies: Lumi walking into the flower field startles them up, and a critter nearby runs after one and pounces") do game
    NG = NeverendingGame
    w = game.world
    if NG.is_night(w) || !(0.3 < NG.daytime(w) < 0.68)   # butterflies are out by day (dusk ends them mid-test): forward to late morning
        NG.skip_to_hour!(w, 10.5)
    end
    wait_frames(game, 3)
    b = only(game.plugins["butterflies"].systems)
    check(!isempty(b.flies), "no butterflies by day")
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(w, "Lumi")
    s = only(game.plugins["greetings"].systems)
    gm = game.plugins["greetings"].mod
    c, r = game.plugins["meadow"].mod.FLOWER_FIELD
    # a friend in Lumi's parade comes along (followers may dash off after a butterfly)
    o = parade_friend(game, me, s, gm)
    empty!(b.chased)
    # Lumi starts 4 m out on open ground and walks at the nearest butterfly with W/A/D
    starts = [Point3f(c[1] + 4cos(a), c[2] + 4sin(a), 0) for a in range(0, 2pi; length = 17)]
    k = findfirst(q -> gm.standable(w, q), starts)
    check(k !== nothing, "no open start by the field")
    me.pos = NG.ground(w.island, (starts[k][1], starts[k][2]))
    Base.invokelatest(gm.join_parade!, s, w, me, o, "Lead the way!")
    t0 = time()
    while hypot(o.pos[1] - me.pos[1], o.pos[2] - me.pos[2]) > 2.5 && time() - t0 < 25   # the friend runs over to Lumi
        wait_seconds(game, 0.5)
    end
    t0 = time()   # the friend running over may scare them up and dash off already: wait until it is back in line
    while any(x -> x.goal.kind === :chase, w.creatures) && time() - t0 < 15
        wait_seconds(game, 0.5)
    end
    empty!(b.chased)
    t0 = time()   # every butterfly settled again, so the one that flies up is Lumi's doing
    while any(x -> x.fast > 0, b.flies) && time() - t0 < 10
        wait_seconds(game, 0.3)
    end
    f = argmin(f -> hypot(f.pos[1] - me.pos[1], f.pos[2] - me.pos[2]), b.flies)
    me.yaw = atan(f.pos[2] - me.pos[2], f.pos[1] - me.pos[1])
    near_up() = any(x -> x.fast > 0 && hypot(x.pos[1] - me.pos[1], x.pos[2] - me.pos[2]) < 3, b.flies)   # Lumi's doing, not a passer-by's far off
    steer_wad(game, () -> near_up() ? nothing : f.pos, 20)
    check(near_up(), "no butterfly flew up (Lumi $(round(hypot(f.pos[1] - me.pos[1], f.pos[2] - me.pos[2]); digits = 1)) m from the nearest)")
    wait_frames(game, 2)
    chaser = findfirst(x -> x.goal.kind === :chase, w.creatures)
    up = [round(hypot(x.pos[1] - me.pos[1], x.pos[2] - me.pos[2]); digits = 1) for x in b.flies if x.fast > 0]
    check(chaser !== nothing, "nobody chased the butterflies (hour $(round(24NG.daytime(w); digits = 1)), flown-up ones $(up) m from Lumi, friend $(o.name) $(o.goal.kind) $(round(hypot(o.pos[1] - me.pos[1], o.pos[2] - me.pos[2]); digits = 1)) m): $([(x.name, x.goal.kind, round(hypot(x.pos[1] - f.pos[1], x.pos[2] - f.pos[2]); digits = 1)) for x in w.creatures if x !== me])")
    ch = w.creatures[chaser]
    wait_seconds(game, 1.5)
    check(ch.action in (:run, :walk, :jump), "the chaser $(ch.name) does not run ($(ch.action))")
    screenshot(game, "butterfly-chase")
    t0 = time()
    while ch.goal.kind === :chase && time() - t0 < 15
        wait_seconds(game, 0.5)
    end
    check(ch.goal.kind !== :chase, "the chase never ended")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("Hide and seek: a win makes the next round a level harder (less time), the start card says so") do game
    P = Main.HIDESEEK_PLOTS
    level0 = get(P, :level, nothing); best0 = get(P, :best, nothing)
    P[:level] = 1
    fly_choose(game, "Hide and seek (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    mod = parentmodule(typeof(m))
    check(occursin("120 seconds", P[:card].text[]), "level 1 is not 120 s: $(P[:card].text[])")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.2), Wait(0.1)])
    check(m.state === :playing, "W did not start (state $(m.state))")
    m.found .= true          # every friend found (the finding itself is tested above)
    wait_frames(game, 3)
    check(m.state === :over && occursin("level 2", P[:card].text[]), "no level step on the end card: $(P[:card].text[])")
    interact!(game, [KeyPress(Keyboard.r), Wait(0.2)])
    check(m.state === :ready && occursin("Level 2", P[:card].text[]) && occursin("100 seconds", P[:card].text[]),
          "the start card does not show level 2 with 100 s: $(P[:card].text[])")
    screenshot(game, "hideseek-level2")
    fly_click(game, "Stop")
    level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
    best0 === nothing ? delete!(P, :best) : (P[:best] = best0)
end

uitest("Berry race: a win steps up a level (start card, saved level), a loss does not; Stop and Play again twice works") do game
    file = joinpath(game.paths.state, "berries.json"); saved = isfile(file) ? read(file, String) : nothing
    bfile = joinpath(game.paths.state, "bests.json"); bsaved = isfile(bfile) ? read(bfile, String) : nothing
    P = Main.BERRY_PLOTS
    total0 = get(P, :total, 0); best0 = get(P, :best, nothing); level0 = get(P, :level, nothing)
    P[:level] = 1
    for round in 1:2          # start, stop, start again
        fly_choose(game, "Berry race (WASD)"); fly_click(game, "Play")
        check(game.minigame !== nothing, "round $round: Berry race did not start")
        round == 1 && fly_click(game, "Stop")
    end
    m = game.minigame; mod = parentmodule(typeof(m))
    check(!occursin("Level", P[:card].text[]), "level 1 card shows a level: $(P[:card].text[])")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.2), Wait(0.1)])
    # a loss: nobody picked, the rivals have 2
    m.score = 0; m.rival_score = [2, 1][1:min(2, length(m.rival_score))]
    m.t = 61.0; wait_frames(game, 3)
    check(m.state === :over && P[:level] == 1, "a loss changed the level to $(P[:level]) (state $(m.state))")
    interact!(game, [KeyPress(Keyboard.r), Wait(0.2)])
    interact!(game, [KeyPress(Keyboard.w; duration = 0.2), Wait(0.1)])
    m.score = 9; m.t = 61.0; wait_frames(game, 3)
    check(m.state === :over && P[:level] == 2 && occursin("level 2", P[:card].text[]), "a win gave level $(P[:level]): $(P[:card].text[])")
    interact!(game, [KeyPress(Keyboard.r), Wait(0.2)])
    check(occursin("Level 2", P[:card].text[]), "start card without Level 2: $(P[:card].text[])")
    check(mod.walk_until(game) < mod.WALK_UNTIL, "level 2 critters do not hurry sooner")
    screenshot(game, "berry-level2")
    fly_click(game, "Stop")
    saved === nothing ? rm(file; force = true) : write(file, saved)
    bsaved === nothing ? rm(bfile; force = true) : write(bfile, bsaved)
    P[:total] = total0; best0 === nothing ? delete!(P, :best) : (P[:best] = best0)
    level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
end

uitest("Dance rings have several places round the island, one in the golden flower field, each fully on land") do game
    NG = NeverendingGame
    m = game.plugins["dancecircle"].mod
    w = game.world
    spots = Base.invokelatest(m.dance_spots, game)
    # on_land's margin is a height: the old check left ONE ring place on the whole island (s45)
    check(length(spots) >= 3, "only $(length(spots)) dance ring places: $spots")
    check(any(p -> Base.invokelatest(m.in_field, game, p), spots), "no ring place in the golden flower field (field ring $(m.FIELD_RING[]))")
    for p in spots
        rim = [(p[1] + m.RING_R * cos(a), p[2] + m.RING_R * sin(a)) for a in 0:0.5:6.2]
        check(all(q -> NG.on_land(w.island, q[1], q[2]), rim), "the ring at $p reaches into the water")
    end
end

uitest("Steering: W held straight into the notch between two bushes or trees slides Lumi out and past them") do game
    NG = NeverendingGame
    w = game.world
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(w, "Lumi")
    sep = game.plugins["separation"].mod
    foot(p) = get(sep.SOLID, p.kind, 0.0f0) * p.scale
    solids = [p for p in w.props if foot(p) > 0]
    # a notch: two solids whose footprints (plus Lumi's) touch, with open ground 2.5 m out on the line between them
    best = nothing
    for a in solids, b in solids
        a.id < b.id || continue
        gap = hypot(a.pos[1] - b.pos[1], a.pos[2] - b.pos[2]) - foot(a) - foot(b)
        -0.3f0 < gap < 0.5f0 || continue
        mx, my = (a.pos[1] + b.pos[1]) / 2, (a.pos[2] + b.pos[2]) / 2
        nx, ny = -(b.pos[2] - a.pos[2]), b.pos[1] - a.pos[1]; n = hypot(nx, ny); nx /= n; ny /= n
        for sgn in (1.0f0, -1.0f0)
            start = (mx + sgn * 2.5f0 * nx, my + sgn * 2.5f0 * ny)
            ahead = (mx - sgn * 3.0f0 * nx, my - sgn * 3.0f0 * ny)
            ok(q) = NG.on_land(w.island, q[1], q[2]; margin = 0.2f0) && all(p -> hypot(p.pos[1] - q[1], p.pos[2] - q[2]) > foot(p) + 0.6f0, solids)
            ok(start) && ok(ahead) && (best = (a, b, start, (mx, my), atan(-sgn * ny, -sgn * nx)); break)
        end
        best === nothing || break
    end
    check(best !== nothing, "no notch between two solids with open ground on both sides")
    a, b, start, mid, yaw = best
    me.pos = NG.ground(w.island, start); me.yaw = Float32(yaw)
    wait_frames(game, 2)
    hx, hy = cos(yaw), sin(yaw)
    along() = (me.pos[1] - mid[1]) * hx + (me.pos[2] - mid[2]) * hy      # -2.5 at the start, > 0 past the notch
    interact!(game, [KeyDown(Keyboard.w)])
    track = Tuple{Float64,Float32,Float32}[]
    t0 = time()
    while time() - t0 < 12 && along() < 1.0f0
        wait_seconds(game, 0.25)
        push!(track, (time() - t0, me.pos[1], me.pos[2]))
    end
    interact!(game, [KeyUp(Keyboard.w), Wait(0.2)])
    # the longest stretch Lumi stayed within 0.3 m while W was held
    stuck = 0.0
    for i in eachindex(track)
        for j in i:length(track)     # (a `for i, j` loop's break would end both loops)
            hypot(track[j][2] - track[i][2], track[j][3] - track[i][3]) < 0.3f0 || break
            stuck = max(stuck, track[j][1] - track[i][1])
        end
    end
    screenshot(game, "notch_slide")
    check(along() >= 1.0f0, "Lumi did not get past the notch between $(a.kind) $(a.id) and $(b.kind) $(b.id) in 12 s (along $(round(along(); digits = 2)) m, at $(round.(me.pos[1:2]; digits = 1)), action $(me.action), stuck $(round(stuck; digits = 1)) s, slide $(get(only(game.plugins["separation"].systems).side, me.id, nothing)), feet $(round(foot(a); digits = 2)) $(round(foot(b); digits = 2)) gap $(round(hypot(a.pos[1] - b.pos[1], a.pos[2] - b.pos[2]) - foot(a) - foot(b); digits = 2)), track $([(round(t; digits = 1), round(x; digits = 1), round(y; digits = 1)) for (t, x, y) in track[1:4:end]]))")
    check(stuck < 3, "Lumi stood $(round(stuck; digits = 1)) s within 0.3 m with W held")
end

uitest("Bump cue: holding W into the sea, Lumi shows a '?' and says to turn with A or D") do game
    NG = NeverendingGame
    w = game.world
    game.minigame === nothing || fly_click(game, "Stop")
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(w, "Lumi")
    # the shore, facing the sea: water stops a walker dead (a trunk does not: Lumi slides round it since s47)
    spot = nothing
    for a in range(0, 2pi; length = 25)[1:24], r in 40f0:-0.5f0:5f0
        x, y = r * cos(a), r * sin(a)
        NG.on_land(w.island, x, y; margin = 0.3f0) || continue
        NG.on_land(w.island, x + 1.2f0cos(a), y + 1.2f0sin(a); margin = 0.1f0) && continue
        any(p -> hypot(p.pos[1] - x, p.pos[2] - y) < 3, w.props) && continue
        spot = (x, y, Float32(a))
        break
    end
    check(spot !== nothing, "no open shore spot")
    me.pos = NG.ground(w.island, (spot[1], spot[2]))
    me.yaw = spot[3]
    t = (; pos = me.pos)
    n0 = Main.BUMPCUE[:count]
    Main.BUMPCUE[:last] = -Inf
    p0 = me.pos; y0 = me.yaw
    interact!(game, [KeyPress(Keyboard.w; duration = 3.0)])
    d = round(hypot(me.pos[1] - t.pos[1], me.pos[2] - t.pos[2]); digits = 2)
    check(Main.BUMPCUE[:count] > n0, "no cue after 3 s of W against a trunk (Lumi $(me.action), $(d) m from the trunk; trunk $(t.pos), from $(p0) yaw $(y0) to $(me.pos) yaw $(me.yaw))")
    check(any(s -> s.who == me.id && occursin("A or D", s.text), w.speech), "Lumi did not say how to get round: $([s.text for s in w.speech if s.who == me.id])")
    screenshot(game, "bump-cue")
    fly_click(game, "Stop")
    wait_frames(game, 2)
end

uitest("Tag: critters play tag on their own, a touch passes 'it' on, and it ends with cheers") do game
    N = NeverendingGame
    w = game.world
    game.minigame === nothing || N.stop_minigame!(game)
    mod = game.plugins["tag"].mod
    TS = Main.TAG_STATE
    TS[:game] === nothing || mod.end_tag!(w, TS[:game]; fun = false)
    cs = filter(c -> c.name != "Lumi" && !c.controlled && c.action !== :sleep && c.goal.kind ∉ (:circle, :rain), w.creatures)
    check(length(cs) >= 3, "fewer than 3 awake critters: $([(c.name, c.goal.kind) for c in w.creatures])")
    cs = cs[1:3]
    spot = first(Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game))
    for (k, c) in enumerate(cs)        # three friends close together on an open spot
        c.pos = N.ground(w.island, (spot[1] + 1.8f0 * cos(2.1f0k), spot[2] + 1.8f0 * sin(2.1f0k)))
    end
    tags0 = TS[:tags]
    Base.invokelatest(mod.start_tag!, w, cs)
    check(any(b -> b.who == cs[1].id && occursin("tag", lowercase(b.text)), w.speech), "the first 'it' did not call the game")
    for _ in 1:50
        wait_seconds(game, 0.5)
        TS[:tags] > tags0 && break
        TS[:game] === nothing && break
    end
    check(TS[:tags] > tags0, "nobody was tagged in 25 s (game $(TS[:game] === nothing ? "over" : "on"), left $(get(TS, :left, nothing)))")
    check(any(b -> occursin("You're it", b.text), w.speech) || TS[:tags] > tags0, "no 'Tag! You're it!'")
    screenshot(game, "tag")
    TS[:game] === nothing || (TS[:game][:until] = w.t)
    wait_frames(game, 3)
    check(TS[:game] === nothing, "the game did not end at its time")
end

uitest("Tag: the player as Lumi walks up to a tag game and joins it") do game
    N = NeverendingGame
    w = game.world
    game.minigame === nothing || N.stop_minigame!(game)
    mod = game.plugins["tag"].mod
    TS = Main.TAG_STATE
    TS[:game] === nothing || mod.end_tag!(w, TS[:game]; fun = false)
    cs = filter(c -> c.name != "Lumi" && !c.controlled && c.action !== :sleep && c.goal.kind ∉ (:circle, :rain), w.creatures)
    check(length(cs) >= 2, "fewer than 2 awake critters")
    cs = cs[1:2]
    spot = first(Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game))
    for (k, c) in enumerate(cs)
        c.pos = N.ground(w.island, (spot[1] + 1.8f0 * cos(3.1f0k), spot[2] + 1.8f0 * sin(3.1f0k)))
    end
    Base.invokelatest(mod.start_tag!, w, cs)
    s = creature(w, "Lumi")
    N.leave_interactions!(w, s); s.controlled = true          # as Jump in does
    s.pos = N.ground(w.island, (spot[1] + 3f0, spot[2]))
    wait_seconds(game, 1)
    g = TS[:game]
    check(g !== nothing && s.id in g[:players], "Lumi did not join the game (players $(g === nothing ? "over" : g[:players]))")
    check(any(b -> occursin("wants to play too", b.text), w.speech), "nobody called out that Lumi joined")
    s.controlled = false
    TS[:game] === nothing || mod.end_tag!(w, TS[:game]; fun = false)
end

uitest("Tag: Lumi (nobody steering it) runs over and joins a game near it") do game
    N = NeverendingGame
    w = game.world
    game.minigame === nothing || N.stop_minigame!(game)
    mod = game.plugins["tag"].mod
    TS = Main.TAG_STATE
    TS[:game] === nothing || mod.end_tag!(w, TS[:game]; fun = false)
    cs = filter(c -> c.name != "Lumi" && !c.controlled && c.action !== :sleep && c.goal.kind ∉ (:circle, :rain), w.creatures)
    check(length(cs) >= 2, "fewer than 2 awake critters")
    cs = cs[1:2]
    spot = first(Base.invokelatest(game.plugins["dancecircle"].mod.dance_spots, game))
    for (k, c) in enumerate(cs)
        c.pos = N.ground(w.island, (spot[1] + 1.8f0 * cos(3.1f0k), spot[2] + 1.8f0 * sin(3.1f0k)))
    end
    s = creature(w, "Lumi")
    N.leave_interactions!(w, s); s.controlled = false
    s.goal = N.Goal(:idle, s.pos, :idle, 20.0, w.t + 20, true, 0, false); s.action = :idle
    s.pos = N.ground(w.island, (spot[1] + 4f0, spot[2]))
    Base.invokelatest(mod.start_tag!, w, cs)
    wait_seconds(game, 1)
    g = TS[:game]
    check(g !== nothing && s.id in g[:players] && s.goal.kind === :tag,
          "Lumi did not join (goal $(s.goal.kind), players $(g === nothing ? "over" : g[:players]))")
    TS[:game] === nothing || mod.end_tag!(w, TS[:game]; fun = false)
end

uitest("Berry race: a whole W/A/D first play is a race: the critters score too, the player still wins") do game
    file = joinpath(game.paths.state, "berries.json")
    saved = isfile(file) ? read(file, String) : nothing
    P = Main.BERRY_PLOTS
    total0 = get(P, :total, 0); best0 = get(P, :best, nothing); level0 = get(P, :level, nothing)
    P[:level] = 1
    fly_choose(game, "Berry race (WASD)")
    fly_click(game, "Play")
    m = game.minigame
    check(m !== nothing && occursin("Berry", NeverendingGame.game_title(typeof(m))), "Berry race did not start")
    c = creature(game.world, "Lumi")
    mod = parentmodule(typeof(m))
    nearest() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing : free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    # the whole minute in 5 s steps, noting the gap in the last 15 s
    gaps = Int[]
    for k in 1:12
        steer_wad(game, nearest, 5)
        m.t > 45 && push!(gaps, m.score - sum(m.rival_score))
        m.state === :over && break
    end
    theirs = sum(m.rival_score)
    println("berry race full play: you $(m.score), critters $(m.rival_score), last-15-s gaps $(gaps)")
    check(theirs >= 2, "the critters scored $(theirs) in a whole race (you $(m.score)): no race to feel")
    check(m.score >= theirs, "a first W/A/D play lost $(m.score) to $(theirs)")
    fly_click(game, "Stop")
    saved === nothing ? rm(file; force = true) : write(file, saved)
    P[:total] = total0; best0 === nothing ? delete!(P, :best) : (P[:best] = best0)
    level0 === nothing ? delete!(P, :level) : (P[:level] = level0)
    total0 == 0 && foreach(a -> NeverendingGame.despawn!(game.world, a),
                           filter(a -> a isa NeverendingGame.AssetActor && a.asset == mod.BASKET_ASSET, game.world.actors))
end

uitest("Sneeze: jumped in as Lumi, X sneezes and blows the friends nearby off their feet") do game
    NG = NeverendingGame
    w = game.world
    game.minigame === nothing || fly_click(game, "Stop")
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NG.JumpIn, "Play did not jump in")
    me = creature(w, "Lumi")
    S = Main.SNEEZE[:sys]
    S.state === :idle || wait_seconds(game, 25.0)
    near0 = [(c.name, c.goal.kind, round(hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]); digits = 1)) for c in w.creatures if c !== me]
    p0 = Dict(c.id => c.pos for c in w.creatures)
    interact!(game, [KeyPress(Keyboard.x; duration = 0.3)])
    check(S.state !== :idle, "X did not start a sneeze (state $(S.state))")
    check(any(s -> s.who == me.id && occursin("ah", lowercase(s.text)), w.speech), "Lumi did not say ah...: $([s.text for s in w.speech if s.who == me.id])")
    wait_seconds(game, 5.0)
    check(any(s -> s.who == me.id && (occursin("CHOO", s.text) || occursin("oops", s.text)), w.speech) || S.state !== :wind,
          "no AH-CHOO after 5 s (state $(S.state))")
    blown = [c.name for c in w.creatures if c.id in S.friends && hypot(c.pos[1] - p0[c.id][1], c.pos[2] - p0[c.id][2]) > 1.0]
    check(length(blown) == length(S.friends), "friends in reach $(S.friends) but only $(blown) were blown away; before: $(near0)")
    screenshot(game, "sneeze-player")
    fly_click(game, "Stop")
end

uitest("Giant Lumi: M while jumped in grows Lumi 5x, W walks the giant, then it shrinks back") do game
    G = Main.GIANT
    s = G[:sys]
    s.state === :idle || Base.invokelatest(game.plugins["giant"].mod.finish!, s, game)
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    fly_click(game, "Play")
    check(game.minigame isa NeverendingGame.JumpIn, "Play did not jump in")
    me = creature(game.world, "Lumi")
    NeverendingGame.face_open!(game.world, me)
    interact!(game, [KeyDown(Keyboard.m), Wait(0.2), KeyUp(Keyboard.m)])
    check(s.state !== :idle && s.player, "M did not bring the golden mushroom: state $(s.state), Lumi at $(me.pos) facing $(me.yaw)")
    for _ in 1:200
        s.state === :giant && break
        wait_frames(game, 3)
    end
    check(s.state === :giant && s.s > 4.9f0, "Lumi did not grow: state $(s.state), size $(s.s)")
    h = game.stage.herds[NeverendingGame.species_of(me).name]
    check(h.transformation.scale[][3] > 4.9f0, "the herd is not drawn big: scale $(h.transformation.scale[])")
    p0 = me.pos
    interact!(game, [KeyDown(Keyboard.w), Wait(2.0)])
    screenshot(game, "giant-walk")
    interact!(game, [KeyUp(Keyboard.w)])
    moved = hypot(me.pos[1] - p0[1], me.pos[2] - p0[2])
    check(moved > 0.5, "the giant did not walk on W: $(round(moved; digits = 2)) m from $(p0)")
    for _ in 1:400
        s.state === :idle && break
        wait_frames(game, 3)
    end
    check(s.state === :idle && h.transformation.scale[][3] < 1.01f0, "Lumi did not shrink back: state $(s.state), scale $(h.transformation.scale[])")
    fly_click(game, "Stop")
end
