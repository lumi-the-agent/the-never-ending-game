# Load reviews/p82/play.jl as a test file and run it in the sandbox the way start_uitests! does
# (the tests folder is not mine to write).
function review_play82(g)
    NG = NeverendingGame; path = "/sim/Programmieren/SimGame/world/reviews/p82/play.jl"
    found = NG.UITest[]
    mod = Module(:ReviewPlay82)
    Core.eval(mod, NG.PLUGIN_IMPORTS)
    FI = NG.fake_interaction()
    Core.eval(mod, :(using NeverendingGame: uitest, check, wait_frames, wait_seconds, screenshot, creature,
                           interact!, ui_pos, ui_option_pos, ui_elements, ui_find))
    Core.eval(mod, :(using $(nameof(parentmodule(FI))).FakeInteraction))
    Base.ScopedValues.with(NG.LOADING_TESTS => found) do
        Base.include(mod, path)
    end
    (g.tests !== nothing && NG.running(g.tests)) && error("a test run is going")
    run = NG.TestRun(found, Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 150.0, nothing)
    g.tests = run
    run.task = @async begin
        for t in run.tests
            run.current = t.name; run.test_started = time()
            g.minigame === nothing || NG.stop_minigame!(g)
            err = try
                Base.invokelatest(t.f, g); ""
            catch e
                sprint(showerror, e, catch_backtrace())
            end
            push!(run.results, Dict{String,Any}("name" => t.name, "passed" => isempty(err),
                  "seconds" => round(time() - run.test_started; digits = 1), "error" => first(err, 2000)))
            g.minigame === nothing || NG.stop_minigame!(g)
        end
        run.current = ""
    end
    [t.name for t in found]
end
