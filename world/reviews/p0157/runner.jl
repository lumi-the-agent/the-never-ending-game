# run reviews/p0157/play.jl's uitests in the sandbox like start_uitests! does (tests dir is read-only for the reviewer)
let NGm = NeverendingGame, g = game
    p = "/sim/Programmieren/SimGame/world/reviews/p0157/play.jl"
    found = NGm.UITest[]
    mod = Module(:ReviewPlay0157)
    Core.eval(mod, NGm.PLUGIN_IMPORTS)
    FI = NGm.fake_interaction()
    Core.eval(mod, :(using NeverendingGame: uitest, check, wait_frames, wait_seconds, screenshot, creature,
                           interact!, ui_pos, ui_option_pos, ui_elements, ui_find))
    Core.eval(mod, Expr(:using, Expr(:., fullname(parentmodule(FI))..., :FakeInteraction)))
    Base.ScopedValues.with(NGm.LOADING_TESTS => found) do
        Base.include(mod, p)
    end
    tests = [NGm.UITest(t.name, "review0157", t.f) for t in found]
    run = NGm.TestRun(tests, Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 400.0, nothing)
    g.tests = run
    run.task = @async begin
        for t in run.tests
            run.current = t.name
            run.test_started = time()
            g.minigame === nothing || NGm.stop_minigame!(g)
            err = try
                Base.invokelatest(t.f, g); ""
            catch e
                sprint(showerror, e, catch_backtrace())
            end
            push!(run.results, Dict{String,Any}("name" => t.name, "passed" => isempty(err),
                    "seconds" => round(time() - run.test_started; digits = 1), "error" => first(err, 2000)))
            g.minigame === nothing || NGm.stop_minigame!(g)
        end
        run.current = ""
    end
    [t.name for t in tests]
end
