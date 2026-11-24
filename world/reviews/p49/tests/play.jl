# Perfectionist review s49: play every mini game for about a minute like a person (W/A/D, E, Space, R).
# Loaded into a fresh module by reviews/p46 driver (not part of the suite). Shots go to reviews/p49/play/.
const NG = NeverendingGame
const K = Keyboard
const OUT = "/sim/Programmieren/SimGame/world/reviews/p49/play"
const LOG = String[]
mkpath(OUT)
note(s) = (push!(LOG, s); println("[play] ", s))
shot(game, name) = (Makie.save(joinpath(OUT, name * ".png"), Makie.colorbuffer(game.screen)); note("shot $name"))
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.3)])
end
hud(P) = haskey(P, :hud) ? string(P[:hud].text[]) : ""
card(P) = haskey(P, :card) ? (P[:card].visible[] ? string(P[:card].text[]) : "(hidden)") : ""

"Hold W and steer with A/D towards target_of() for `seconds`; screenshot every `every` s."
function steer(game, target_of, seconds; every = 12, tag = "x", P = nothing, wander = false)
    c = creature(game.world, "Sprout")
    interact!(game, [KeyDown(K.w)])
    held = nothing; t0 = time(); nexts = every; k = 0; turn_t = time()
    while time() - t0 < seconds
        p = target_of()
        want = if p === nothing
            wander ? (time() - turn_t > 3 ? (turn_t = time(); rand((K.a, K.d, nothing))) : held) : break
        else
            d = NG.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
            abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
        end
        if want !== held
            held === nothing || interact!(game, [KeyUp(held)])
            want === nothing || interact!(game, [KeyDown(want)])
            held = want
        end
        interact!(game, [Wait(0.1)])
        if time() - t0 > nexts
            k += 1; nexts += every
            shot(game, "$tag-run$k")
            P === nothing || note("$tag t=$(round(time() - t0)) hud='$(hud(P))'")
        end
        game.minigame !== nothing && hasproperty(game.minigame, :state) && game.minigame.state === :over && break
    end
    held === nothing || interact!(game, [KeyUp(held)])
    interact!(game, [KeyUp(K.w), Wait(0.1)])
end

function play_firefly(game)
    choose(game, "Firefly catch (WASD)"); click(game, "Play")
    m = game.minigame; P = Main.FIREFLY_PLOTS; mod = parentmodule(typeof(m)); c = creature(game.world, "Sprout")
    wait_seconds(game, 1.5); shot(game, "firefly-0start"); note("firefly start card: $(card(P))")
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    nearest() = (free = findall(!, m.caught); isempty(free) ? nothing :
                 fly(free[argmin([hypot(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2]) for i in free])]))
    t0 = time()
    steer(game, nearest, 60; tag = "firefly", P)
    note("firefly after $(round(time() - t0)) s: score $(m.score) state $(m.state) hud '$(hud(P))'")
    wait_seconds(game, 2); shot(game, "firefly-9end"); note("firefly end card: $(card(P))")
    interact!(game, [KeyPress(K.r), Wait(1.0)]); shot(game, "firefly-replay"); note("after R: $(card(P))")
    click(game, "Stop")
end

function play_berry(game)
    choose(game, "Berry race (WASD)"); click(game, "Play")
    m = game.minigame; P = Main.BERRY_PLOTS; mod = parentmodule(typeof(m)); c = creature(game.world, "Sprout")
    wait_seconds(game, 1.5); shot(game, "berry-0start"); note("berry start card: $(card(P))")
    nearest() = (free = [b for b in m.berries if b.taken == 0]; isempty(free) ? nothing :
                 free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot)
    t0 = time()
    interact!(game, [KeyDown(K.left_shift)])     # a person sprints in a race
    steer(game, nearest, 65; tag = "berry", P)
    interact!(game, [KeyUp(K.left_shift)])
    note("berry after $(round(time() - t0)) s: you $(m.score) critters $(m.rival_score) state $(m.state) hud '$(hud(P))'")
    wait_seconds(game, 2); shot(game, "berry-9end"); note("berry end card: $(card(P))")
    interact!(game, [KeyPress(K.r), Wait(1.0)]); shot(game, "berry-replay"); note("after R: $(card(P))")
    click(game, "Stop")
end

function play_hideseek(game)
    choose(game, "Hide and seek (WASD)"); click(game, "Play")
    m = game.minigame; P = Main.HIDESEEK_PLOTS; mod = parentmodule(typeof(m)); c = creature(game.world, "Sprout")
    wait_seconds(game, 1.5); shot(game, "hideseek-0start"); note("hideseek start card: $(card(P))")
    # only what a player can know: the giggle the HUD points at; otherwise wander
    target() = count(m.found) >= length(m.found) ? nothing : Base.invokelatest(mod.hint_spot, m, c)
    t0 = time()
    steer(game, target, 70; tag = "hideseek", P, wander = true)
    note("hideseek after $(round(time() - t0)) s: found $(count(m.found))/$(length(m.found)) state $(m.state) hud '$(hud(P))'")
    shot(game, "hideseek-9after")
    click(game, "Stop")
end

function play_jumpin(game)
    m0 = game.dash.play_menu
    choose(game, "Jump in (WASD)")
    click(game, "Play")
    c = creature(game.world, "Sprout"); w = game.world
    wait_seconds(game, 1); shot(game, "jumpin-0")
    free(o) = o !== c && o.action !== :sleep && o.goal.kind ∉ NG.BUSY_GOALS
    near() = (os = filter(free, w.creatures); isempty(os) ? nothing : os[argmin([hypot(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2]) for o in os])])
    o = near(); note("jump in: walking to $(o === nothing ? "nobody" : o.name)")
    o === nothing || steer(game, () -> hypot(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2]) < 2.5 ? nothing : o.pos, 15; tag = "jumpin")
    interact!(game, [KeyPress(K.e; duration = 0.2), Wait(1.5)]); shot(game, "jumpin-wave1")
    note("after wave 1: $(o === nothing ? "" : (o.goal.kind, o.action))")
    interact!(game, [KeyPress(K.e; duration = 0.2), Wait(1.5)]); shot(game, "jumpin-wave2")
    note("after wave 2: $(o === nothing ? "" : (o.goal.kind, o.action))")
    steer(game, () -> nothing, 15; tag = "jumpin-walk", wander = true)
    interact!(game, [KeyPress(K.space; duration = 0.2), Wait(1.0)]); shot(game, "jumpin-space")
    note("after walk+space: $(o === nothing ? "" : (o.goal.kind, o.action)) followers?")
    click(game, "Stop")
end

uitest("review: firefly") do game; play_firefly(game); end
uitest("review: berry") do game; play_berry(game); end
uitest("review: hideseek") do game; play_hideseek(game); end
uitest("review: jumpin") do game; play_jumpin(game); end

function play_tag(game)
    choose(game, "Jump in (WASD)"); click(game, "Play")
    w = game.world; c = creature(w, "Sprout"); mod = game.plugins["tag"].mod; TS = Main.TAG_STATE
    wait_seconds(game, 1)
    fr = filter(o -> Base.invokelatest(mod.free, o), w.creatures)
    note("tag: free critters $(length(fr)) of $(length(w.creatures))")
    length(fr) < 3 && (note("tag: not enough free critters"); click(game, "Stop"); return)
    o = fr[argmin([hypot(o.pos[1]-c.pos[1], o.pos[2]-c.pos[2]) for o in fr])]
    ps = sort(fr, by = q -> hypot(q.pos[1]-o.pos[1], q.pos[2]-o.pos[2]))[1:3]
    note("tag: players $(join([q.name for q in ps], ", ")) start $(round(hypot(o.pos[1]-c.pos[1], o.pos[2]-c.pos[2]); digits=1)) m from Sprout")
    Base.invokelatest(mod.start_tag!, w, ps)
    tags0 = get(TS, :tags, 0)
    target() = (g = TS[:game]; g === nothing ? nothing :
        g[:it] == c.id ? (qs = [creature(w, i) for i in g[:players] if i != c.id]; qs = filter(!isnothing, qs);
                          isempty(qs) ? nothing : qs[argmin([hypot(q.pos[1]-c.pos[1], q.pos[2]-c.pos[2]) for q in qs])].pos) :
        creature(w, g[:it]).pos)
    steer(game, target, 45; tag = "tag", every = 9)
    g = TS[:game]
    note("tag after 45 s: game $(g === nothing ? "over" : "on, it=$(creature(w, g[:it]).name), players=$(length(g[:players]))") tags $(get(TS, :tags, 0) - tags0) sprout in=$(g !== nothing && c.id in g[:players]) left=$(get(TS, :left, nothing))")
    shot(game, "tag-9end")
    click(game, "Stop")
end
uitest("review: tag") do game; play_tag(game); end
uitest("review: log") do game; write(joinpath(OUT, "log.txt"), join(LOG, "\n")); end
