module ReviewPitch
using NeverendingGame; const NG = NeverendingGame
using NeverendingGame.FakeInteraction, Makie
import Main.ReviewPlay as RP
const OUT = String[]
pitch(g) = (d = g.rig.target .- g.rig.eye; string(round(rad2deg(atan(-d[3], hypot(d[1], d[2])))), "° d=", round(sqrt(sum(abs2, d)); digits = 1)))
function run(game)
    for opt in ("Firefly catch (WASD)", "Berry race (WASD)", "Hide and seek (WASD)", "Jump in (WASD)")
        RP.choose(game, RP.current_menu(game), opt); RP.click(game, "Play")
        push!(OUT, "$opt card: " * pitch(game))
        NG.interact!(game, [KeyPress(Keyboard.w; duration = 4.0)])
        push!(OUT, "$opt playing 4s: " * pitch(game))
        NG.interact!(game, [KeyPress(Keyboard.w; duration = 6.0)])
        push!(OUT, "$opt playing 10s: " * pitch(game))
        RP.click(game, "Stop")
    end
end
function go!(game)
    empty!(OUT)
    t = NG.UITest("review: pitch", "review", run)
    r = NG.TestRun([t], Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 300.0, nothing)
    game.tests = r
    r.task = @async (try Base.invokelatest(t.f, game) catch e; push!(OUT, sprint(showerror, e)) end; game.minigame === nothing || NG.stop_minigame!(game))
    "started"
end
end
