# reviewer s157: play every mini game for about a minute, steering like a player
const OUT = "/sim/Programmieren/SimGame/world/reviews/p166/play"
mkpath(OUT)
const LOG = String[]
logp(s) = (push!(LOG, s); open(io -> println(io, s), joinpath(OUT, "log.txt"), "a"))
shot(game, n) = NeverendingGame.Makie.save(joinpath(OUT, n * ".png"), NeverendingGame.Makie.colorbuffer(game.screen))

const GAMES = ["Mini game", "Jump in (WASD)", "Firefly catch (WASD)", "Hide and seek (WASD)", "Berry race (WASD)"]
function pick!(game, option)
    have = [e.name for e in ui_elements(game)]
    menu = first(n for n in GAMES if any(h -> occursin(n, h), have))
    interact!(game, [MouseTo(ui_pos(game, menu)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, menu, option))), LeftClick(), Wait(0.3),
                     MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
end

wrapang(a) = mod(a + pi, 2pi) - pi

"Turn toward `p` and walk a bit."
function steer!(game, p; walk = 0.7)
    me = creature(game.world, "Lumi")
    m = game.minigame
    if hasproperty(m, :lumi)
        me = creature(game.world, m.lumi)
    end
    d = (p[1] - me.pos[1], p[2] - me.pos[2])
    da = wrapang(atan(d[2], d[1]) - me.yaw)
    t = abs(da) / 2.2
    t > 0.05 && interact!(game, [KeyPress(da > 0 ? Keyboard.a : Keyboard.d; duration = t)])
    interact!(game, [KeyDown(Keyboard.left_shift), KeyPress(Keyboard.w; duration = walk), KeyUp(Keyboard.left_shift)])
    return hypot(d...)
end

function play_for!(game, name, target; secs = 60)
    t0 = time(); k = 0
    while time() - t0 < secs
        m = game.minigame
        m === nothing && (logp("$name: game ended itself at $(round(time()-t0)) s"); break)
        st = hasproperty(m, :state) ? m.state : :none
        p = target(m)
        if p === nothing
            interact!(game, [KeyPress(Keyboard.w; duration = 0.5)])
        else
            steer!(game, p)
        end
        if time() - t0 > k * 15
            shot(game, "$name-$k"); k += 1
            logp("$name t=$(round(time()-t0)) state=$st score=$(hasproperty(m, :score) ? m.score : (hasproperty(m, :found) ? count(m.found) : "-"))")
        end
        st == :over && (shot(game, "$name-over"); logp("$name over at $(round(time()-t0)) s"); break)
    end
    m = game.minigame
    m !== nothing && hasproperty(m, :state) && logp("$name final state=$(m.state) score=$(hasproperty(m, :score) ? m.score : (hasproperty(m, :found) ? count(m.found) : "-"))" *
        (hasproperty(m, :rival_score) ? " rivals=$(m.rival_score)" : ""))
    shot(game, "$name-end")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
end

function nearest(game, ps)
    isempty(ps) && return nothing
    me = creature(game.world, game.minigame.lumi)
    ps[argmin([hypot(p[1] - me.pos[1], p[2] - me.pos[2]) for p in ps])]
end

uitest("review0166 firefly") do game
    pick!(game, "Firefly catch (WASD)")
    logp("firefly: started $(typeof(game.minigame))")
    shot(game, "firefly-start")
    play_for!(game, "firefly", m -> nearest(game, [m.flies[i] for i in eachindex(m.flies) if !m.caught[i]]))
end

uitest("review0166 berry") do game
    pick!(game, "Berry race (WASD)")
    logp("berry: started $(typeof(game.minigame))")
    shot(game, "berry-start")
    play_for!(game, "berry", m -> nearest(game, [b.pos for b in m.berries if b.taken == 0]))
end

uitest("review0166 hide") do game
    pick!(game, "Hide and seek (WASD)")
    logp("hide: started $(typeof(game.minigame))")
    shot(game, "hide-start")
    play_for!(game, "hide", m -> nearest(game, [m.spots[i] for i in eachindex(m.spots) if !m.found[i]]))
end

uitest("review0166 jumpin") do game
    pick!(game, "Jump in (WASD)")
    logp("jumpin: started $(typeof(game.minigame))")
    shot(game, "jump-start")
    keys = [(Keyboard.e, "parade"), (Keyboard.p, "paint"), (Keyboard.b, "bubble"), (Keyboard.x, "sneeze"),
            (Keyboard.g, "fly"), (Keyboard.u, "throwup"), (Keyboard.l, "stomp"), (Keyboard.o, "boomerang")]
    for (k, n) in keys
        interact!(game, [KeyPress(Keyboard.w; duration = 1.0), Wait(0.2), KeyPress(k; duration = 0.3), Wait(2.5)])
        shot(game, "jump-$n")
        logp("jumpin pressed $n")
    end
    # the motor/magnet boards east of the kiln: hold 6
    interact!(game, [KeyPress(Keyboard._6; duration = 3.0), Wait(1.0)])
    shot(game, "jump-6")
    interact!(game, [KeyPress(Keyboard._2; duration = 2.0), Wait(1.0)])
    shot(game, "jump-2")
    # walk to the land yacht and try to use it like a player would
    yp = Main.LANDYACHT[:pos]
    me = creature(game.world, game.minigame.lumi)
    me.pos = NeverendingGame.ground(game.world.island, (Float32(yp[1]) - 3f0, Float32(yp[2])))
    interact!(game, [Wait(1.0)])
    for i in 1:6; steer!(game, (yp[1], yp[2]); walk = 0.3); end
    shot(game, "jump-yacht-0")
    for (k, n) in [(Keyboard.e, "e"), (Keyboard.f, "f"), (Keyboard.space, "space"), (Keyboard.q, "q")]
        interact!(game, [KeyPress(k; duration = 0.4), Wait(1.5)])
        logp("yacht key $n: yacht pos $(Main.LANDYACHT[:pos]) lumi $(creature(game.world, game.minigame.lumi).pos)")
    end
    shot(game, "jump-yacht-1")
    interact!(game, [KeyPress(Keyboard.w; duration = 2.0), Wait(0.5)])
    logp("yacht after pushing into it: $(Main.LANDYACHT[:pos])")
    shot(game, "jump-yacht-2")
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)])
end
