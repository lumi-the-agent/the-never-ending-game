# Reviewer's play-through, s151: every mini game for about a minute, like a person.
const SHOTS = "/sim/Programmieren/SimGame/world/reviews/p151/play"
const LOG = String[]
mkpath(SHOTS)
shot(game, name) = (p = joinpath(SHOTS, name * ".png"); NeverendingGame.Makie.save(p, NeverendingGame.Makie.colorbuffer(game.screen)); p)
note(s) = (push!(LOG, s); write(joinpath(SHOTS, "log.txt"), join(LOG, "\n")))

function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.4),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.3)])
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(1.0)])
end
function stop(game)
    try interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.5)]) catch e; note("stop: $e") end
end
state(game) = (m = game.minigame; m === nothing ? "none" :
    string(typeof(m), " ", join(["$f=$(getfield(m, f))" for f in fieldnames(typeof(m))
                                 if getfield(m, f) isa Union{Number,Symbol,AbstractString}], " ")))
lumi(game) = round.(creature(game.world, "Lumi").pos; digits = 1)

function wander(game, tag, keys; n = 8, extra = [])
    for i in 1:n
        k = keys[mod1(i, length(keys))]
        interact!(game, [KeyPress(k; duration = 1.5 + 0.5 * (i % 3)), Wait(0.3)])
        for e in extra
            i % 2 == 0 && interact!(game, [KeyPress(e; duration = 0.2), Wait(0.6)])
        end
        i in (2, 5, n) && (shot(game, "$tag-$i"); note("$tag $i: Lumi $(lumi(game)) $(state(game))"))
    end
end

uitest("review: Jump in (done)") do game
    return
end
function jumpin_unused(game)
    choose(game, "Jump in (WASD)")
    shot(game, "jumpin-start"); note("jumpin start: $(state(game))")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.3), Wait(0.5)])
    wander(game, "jumpin", [Keyboard.w, Keyboard.a, Keyboard.w, Keyboard.d];
           extra = [Keyboard.space, Keyboard._1, Keyboard._6, Keyboard._9, Keyboard.j])
    shot(game, "jumpin-end"); note("jumpin end: $(state(game))")
    stop(game)
end

uitest("review: Firefly catch") do game
    choose(game, "Firefly catch (WASD)")
    shot(game, "firefly-start"); note("firefly start: $(state(game))")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.2), Wait(0.3)])
    wander(game, "firefly", [Keyboard.w, Keyboard.a, Keyboard.w, Keyboard.d, Keyboard.w]; n = 12)
    shot(game, "firefly-end"); note("firefly end: $(state(game))")
    stop(game)
end

uitest("review: Hide and seek") do game
    choose(game, "Hide and seek (WASD)")
    shot(game, "hide-start"); note("hide start: $(state(game))")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.2), Wait(0.3)])
    wander(game, "hide", [Keyboard.w, Keyboard.d, Keyboard.w, Keyboard.a]; n = 10)
    shot(game, "hide-end"); note("hide end: $(state(game))")
    stop(game)
end

uitest("review: Berry race") do game
    choose(game, "Berry race (WASD)")
    shot(game, "berry-start"); note("berry start: $(state(game))")
    interact!(game, [KeyPress(Keyboard.w; duration = 0.2), Wait(0.3)])
    wander(game, "berry", [Keyboard.w, Keyboard.w, Keyboard.a, Keyboard.w, Keyboard.d]; n = 10)
    shot(game, "berry-end"); note("berry end: $(state(game))")
    stop(game)
end
