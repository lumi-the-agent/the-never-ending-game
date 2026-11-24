# ── UI tests: the dashboard and the mini games, used the way a person uses them
#
# A test file `world/tests/<name>.jl` registers tests, written with Makie's
# FakeInteraction events (see uidriver.jl):
#
#   uitest("Play starts Jump in and W walks") do game
#       interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.2)])
#       check(game.minigame isa NeverendingGame.JumpIn, "Play started \$(typeof(game.minigame))")
#       c = creature(game.world, "Lumi"); p0 = c.pos
#       interact!(game, [KeyPress(Keyboard.w; duration = 1.0)])
#       check(norm(c.pos - p0) > 0.5, "Lumi moved \$(norm(c.pos - p0)) m")
#       screenshot(game, "jumpin-walk")            # evidence, saved under world/tests/shots
#   end
#
# Tests run inside the sandbox game as tasks between frames, so they can wait
# for frames while the game goes on; the human's game refuses them. Run them
# with `live_tests()` (all) or `live_tests("Play")` (names containing "Play");
# the host runs all of them after every work session and puts failures into
# the next session's prompt.

struct UITest
    name::String
    file::String
    f::Function
end

struct TestFailure <: Exception
    msg::String
end
Base.showerror(io::IO, e::TestFailure) = print(io, "check failed: ", e.msg)

"""
    check(condition, message)

Fail the running test with `message` unless `condition` holds.
"""
check(cond::Bool, msg::AbstractString = "check failed") = cond || throw(TestFailure(String(msg)))

"Registrations go to the test file being loaded."
const LOADING_TESTS = Base.ScopedValues.ScopedValue{Union{Nothing,Vector{UITest}}}(nothing)

function uitest(f::Function, name::AbstractString)
    tests = LOADING_TESTS[]
    tests === nothing && error("uitest is only valid while a test file is loaded")
    push!(tests, UITest(String(name), "", f))
    return nothing
end

tests_dir(p::GamePaths) = joinpath(p.world, "tests")

"Load every test file (fresh modules, like plugins). Files that do not load become failing tests."
function load_uitests(p::GamePaths)
    dir = tests_dir(p)
    isdir(dir) || return UITest[]
    all = UITest[]
    for f in sort!(filter(f -> endswith(f, ".jl") && !startswith(f, "_"), readdir(dir)))
        path = joinpath(dir, f)
        found = UITest[]
        mod = Module(Symbol("Tests_", replace(first(splitext(f)), r"[^A-Za-z0-9_]" => "_")))
        Core.eval(mod, PLUGIN_IMPORTS)
        FI = fake_interaction()
        Core.eval(mod, :(using NeverendingGame: uitest, check, wait_frames, wait_seconds, screenshot, creature,
                               interact!, ui_pos, ui_option_pos, ui_elements, ui_find))
        Core.eval(mod, :(using $(nameof(parentmodule(FI))).FakeInteraction))
        try
            Base.ScopedValues.with(LOADING_TESTS => found) do
                Base.include(mod, path)
            end
            append!(all, [UITest(t.name, f, t.f) for t in found])
        catch e
            e isa InterruptException && rethrow()
            err = sprint(showerror, e, catch_backtrace())
            push!(all, UITest("$(f) loads", f, _ -> throw(TestFailure("the file does not load: " * first(err, 2000)))))
        end
    end
    return all
end

# ── a test run: one task, woken by the game loop every frame ────────────────

mutable struct TestRun
    tests::Vector{UITest}
    results::Vector{Dict{String,Any}}
    frame::Int
    waiting::Base.Threads.Condition
    current::String
    test_started::Float64
    timeout::Float64
    task::Union{Nothing,Task}
end

running(r::TestRun) = r.task !== nothing && !istaskdone(r.task)

"""
    start_uitests!(game, pattern = ""; timeout = 120) -> TestRun

Run the tests whose name contains `pattern`, one after the other, in a task
the game loop wakes every frame. Each test gets `timeout` seconds.
"""
function start_uitests!(g::Game, pattern::AbstractString = ""; timeout::Real = 120)
    g.tests !== nothing && running(g.tests) && error("a test run is already going")
    tests = filter(t -> occursin(lowercase(pattern), lowercase(t.name)), load_uitests(g.paths))
    run = TestRun(tests, Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), Float64(timeout), nothing)
    g.tests = run
    run.task = @async begin
        for t in run.tests
            while human_busy(g)       # the tests click in the human's dashboard: never while they use it
                run.current = "waiting: the human is using the dashboard"
                sleep(2)
            end
            run.current = t.name
            run.test_started = time()
            g.minigame === nothing || stop_minigame!(g)
            err = try
                Base.invokelatest(t.f, g)
                ""
            catch e
                e isa InterruptException && rethrow()
                # a failing test is the test's result, not a problem of the game
                e isa TestFailure ? sprint(showerror, e) : sprint(showerror, e, catch_backtrace())
            end
            push!(run.results, Dict{String,Any}("name" => t.name, "file" => t.file, "passed" => isempty(err),
                                                "seconds" => round(time() - run.test_started; digits = 1),
                                                "error" => first(err, 3000)))
            g.minigame === nothing || stop_minigame!(g)
        end
        run.current = ""
        write_json(joinpath(tests_dir(g.paths), "last_run.json"),
                   Dict("time" => string(Dates.now()), "results" => run.results))
    end
    return run
end

"""
Whether the human used the dashboard (window or browser) in the last minute.
UI tests drive the same dashboard, so they wait until it is free.
"""
human_busy(g::Game) = time() - g.human_input < 60

"Let `n` frames of the live game pass (only inside a test)."
function wait_frames(g::Game, n::Integer = 1)
    run = g.tests
    (run === nothing || !running(run)) && error("wait_frames only works inside a test run by the live game")
    target = run.frame + n
    @lock run.waiting while run.frame < target
        time() - run.test_started > run.timeout && throw(TestFailure("timed out after $(run.timeout) s"))
        wait(run.waiting)
    end
    return nothing
end

"Let `seconds` of game time pass (at the game's frame rate)."
wait_seconds(g::Game, seconds::Real) = wait_frames(g, max(1, round(Int, seconds * g.fps)))

"Called by the game loop after every frame: wakes a waiting test."
function tick_tests!(g::Game)
    run = g.tests
    (run === nothing || !running(run)) && return
    @lock run.waiting begin
        run.frame += 1
        notify(run.waiting)
    end
end

"""
    screenshot(game, name) -> path

What the dashboard shows now, as `world/tests/shots/<name>.png`.
"""
function screenshot(g::Game, name::AbstractString)
    g.screen === nothing && return ""
    dir = joinpath(tests_dir(g.paths), "shots")
    mkpath(dir)
    path = joinpath(dir, replace(name, r"[^A-Za-z0-9_\-]" => "_") * ".png")
    Makie.save(path, Makie.colorbuffer(g.screen))
    return path
end

function live_command(g::Game, ::Val{:test}, msg)
    g.paths.instance === :sandbox ||
        return Dict{String,Any}("ok" => false, "error" => "UI tests run in the sandbox, never in the human's game")
    # one run at a time: a caller who finds one going (the agent's, the host's suite, the tester's)
    # waits for it and asks again; that is not a problem of the game
    g.tests !== nothing && running(g.tests) &&
        return Dict{String,Any}("ok" => true, "started" => false, "current" => g.tests.current)
    run = start_uitests!(g, string(get(msg, "pattern", "")); timeout = Float64(get(msg, "timeout", 120)))
    return Dict{String,Any}("ok" => true, "started" => true, "tests" => [t.name for t in run.tests])
end

function live_command(g::Game, ::Val{:test_status}, msg)
    run = g.tests
    run === nothing && return Dict{String,Any}("ok" => true, "running" => false, "results" => [])
    return Dict{String,Any}("ok" => true, "running" => running(run), "current" => run.current,
                            "results" => run.results, "total" => length(run.tests))
end

"""
    live_tests(pattern = ""; timeout = 120) -> results

Run the UI tests (`world/tests/*.jl`) in the sandbox game and wait for them,
after a run that is already going (the host's suite after a session takes
about 5 minutes). Each result has name, file, passed, seconds, error.
"""
function live_tests(pattern::AbstractString = ""; timeout::Real = 120, kw...)
    started = live("test"; pattern, timeout, kw...)
    while !started["started"]
        sleep(2)
        started = live("test"; pattern, timeout, kw...)
    end
    names = started["tests"]
    t0 = time()
    while true
        sleep(1)
        st = live("test_status"; kw...)
        st["running"] || return st["results"]
        time() - t0 > timeout * (length(names) + 1) && error("the test run did not finish")
    end
end
