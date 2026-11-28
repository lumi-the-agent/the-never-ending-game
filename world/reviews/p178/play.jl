# Perfectionist review s178: play every mini game about a minute like a player, and every camera mode.
const D = "/sim/Programmieren/SimGame/world/reviews/p178"
const LOG = String[]
shot(game, name) = (game.screen === nothing || NeverendingGame.Makie.save(joinpath(D, name * ".png"), NeverendingGame.Makie.colorbuffer(game.screen)); nothing)
note(s) = (push!(LOG, s); open(io -> println(io, s), joinpath(D, "play-log.txt"), "a"))
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
function choose(game, menu_now, option)
    interact!(game, [MouseTo(ui_pos(game, menu_now)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, menu_now, option))), LeftClick(), Wait(0.3)])
end
mstate(m) = m === nothing ? "none" : string(typeof(m), " state=", hasproperty(m, :state) ? m.state : "-", " score=", hasproperty(m, :score) ? m.score : "-")
hud(game) = try
    join([string(k, "=", repr(v.text[])) for (k, v) in pairs(something(get(Main, :__none__, nothing), Dict())) ], ";")
catch; "" end

# a minute of play: wander with W and turns, like someone exploring
function wander(game, tag, secs)
    keys = [Keyboard.w, Keyboard.a, Keyboard.w, Keyboard.d, Keyboard.w, Keyboard.w, Keyboard.s, Keyboard.d]
    t0 = time(); k = 0
    while time() - t0 < secs
        k += 1
        key = keys[mod1(k, length(keys))]
        interact!(game, [KeyPress(key; duration = key == Keyboard.w ? 2.5 : 0.6), Wait(0.1)])
        k % 6 == 0 && (shot(game, "$tag-$(k ÷ 6)"); note("$tag t=$(round(Int, time() - t0)) $(mstate(game.minigame))"))
    end
end

uitest("review178 play Jump in") do game
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 2)
    click(game, "Play")
    note("JumpIn started: $(mstate(game.minigame))")
    shot(game, "jumpin-0")
    me = creature(game.world, "Lumi"); p0 = me.pos
    interact!(game, [KeyPress(Keyboard.e), Wait(1.0)]); shot(game, "jumpin-wave")
    for k in (Keyboard._6, Keyboard._7, Keyboard._8, Keyboard._1, Keyboard._2, Keyboard.h, Keyboard.space)
        interact!(game, [KeyPress(k; duration = 1.0), Wait(0.8)])
        shot(game, "jumpin-key-$(k)")
    end
    wander(game, "jumpin", 40)
    note("JumpIn Lumi moved $(round(sqrt(sum(abs2, me.pos - p0)); digits = 1)) m")
    click(game, "Stop")
end

for (g, tag) in (("Firefly catch (WASD)", "firefly"), ("Hide and seek (WASD)", "hide"), ("Berry race (WASD)", "berry"))
    uitest("review178 play $tag") do game
        menu = game.dash.play_menu
        name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
        choose(game, name, g)
        click(game, "Play")
        wait_frames(game, 20)
        shot(game, "$tag-0")
        note("$tag started: $(mstate(game.minigame))")
        wander(game, tag, 60)
        shot(game, "$tag-end")
        note("$tag end: $(mstate(game.minigame))")
        interact!(game, [KeyPress(Keyboard.r), Wait(1.0)])
        note("$tag after R: $(mstate(game.minigame))")
        click(game, "Stop")
    end
end

uitest("review178 cameras") do game
    for (i, opt) in enumerate(("Camera: follow", "Camera: orbit", "Camera: free"))
        cur = string(only(b for b in game.dash.fig.content if b isa NeverendingGame.Makie.Menu && "Camera: follow" in b.options[]).selection[])
        try
            choose(game, cur, opt)
        catch e
            note("camera menu: $(sprint(showerror, e))")
        end
        for j in 1:3
            wait_seconds(game, 4)
            shot(game, "cam-$(i)-$(j)")
        end
        note("camera $opt -> rig $(game.rig.mode)")
    end
end
