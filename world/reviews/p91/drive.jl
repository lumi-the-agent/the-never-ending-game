# Reviewer helpers (perfectionist 0091): drive the sandbox dashboard with FakeInteraction from an async task.
const NG = Main.NeverendingGame
const FI = NG.fake_interaction()
const RV = Dict{Symbol,Any}(:task => nothing, :log => String[])

rv_pick(game, menu, opt) = [FI.MouseTo(NG.ui_pos(game, menu)), FI.LeftClick(), FI.Wait(0.4),
    FI.Lazy(_ -> FI.MouseTo(NG.ui_option_pos(game, menu, opt))), FI.LeftClick(), FI.Wait(0.3)]
rv_click(game, name) = [FI.MouseTo(NG.ui_pos(game, name)), FI.LeftClick(), FI.Wait(0.3)]
rv_key(k, d) = FI.KeyPress(getfield(NG.Makie.Keyboard, k); duration = d)

function rv_run(game, events)
    RV[:task] = @async try
        NG.interact!(game, events)
        push!(RV[:log], "done")
    catch err
        push!(RV[:log], sprint(showerror, err))
    end
    "started"
end
rv_state() = (RV[:task] === nothing ? "none" : istaskdone(RV[:task]) ? "done" : "running") * " | " * join(last(RV[:log], 2), " / ")

# a person playing: mostly W, turning towards the target the HUD/game points at, a few keys
function rv_play_events(game, secs; keys = (:w,))
    ev = Any[]
    t = 0.0
    while t < secs
        push!(ev, FI.KeyDown(NG.Makie.Keyboard.w))
        push!(ev, FI.Lazy(_ -> rv_steer(game)))
        push!(ev, FI.Wait(0.6))
        t += 0.6
    end
    push!(ev, FI.KeyUp(NG.Makie.Keyboard.w))
    ev
end

# turn towards the nearest thing the mini game wants (by asking the game), as a person would by looking
function rv_steer(game)
    me = findfirst(c -> c.controlled, game.world.creatures)
    me === nothing && return FI.Wait(0.05)
    c = game.world.creatures[me]
    tgt = get(RV, :target, nothing)
    p = tgt === nothing ? nothing : Base.invokelatest(tgt, game)
    p === nothing && return FI.Wait(0.05)
    want = atan(p[2] - c.pos[2], p[1] - c.pos[1])
    d = mod(want - c.yaw + pi, 2pi) - pi
    abs(d) < 0.25 && return FI.Wait(0.05)
    FI.KeyPress(d > 0 ? NG.Makie.Keyboard.a : NG.Makie.Keyboard.d; duration = clamp(abs(d) / 2.5, 0.05, 0.5))
end
"loaded"

# ── a reviewer play session inside a TestRun (so interact!/wait_frames work) ──
function rv_shot(game, name)
    p = "/sim/Programmieren/SimGame/world/reviews/p91/$(name).png"
    NG.Makie.save(p, NG.Makie.colorbuffer(game.screen))
    push!(RV[:log], "shot $name")
    p
end

function rv_target(game)
    mg = game.minigame
    mg === nothing && return nothing
    me = findfirst(c -> c.controlled, game.world.creatures)
    me === nothing && return nothing
    pos = game.world.creatures[me].pos
    pts = Any[]
    T = string(nameof(typeof(mg)))
    if T == "FireflyCatch"
        pts = [mg.flies[i] for i in eachindex(mg.flies) if !mg.caught[i]]
    elseif T == "HideSeek"
        pts = [mg.spots[i] for i in eachindex(mg.spots) if !mg.found[i] && mg.heard[i]]
    elseif T == "BerryRace"
        pts = [b.foot for b in mg.berries if b.taken == 0]
    end
    isempty(pts) && return nothing
    pts[argmin([hypot(p[1] - pos[1], p[2] - pos[2]) for p in pts])]
end
RV[:target] = rv_target

function rv_describe(game)
    mg = game.minigame
    mg === nothing && return "no minigame"
    s = "$(nameof(typeof(mg))) state=$(getfield(mg, :state)) t=$(round(getfield(mg, :t); digits = 1))"
    hasfield(typeof(mg), :score) && (s *= " score=$(mg.score)")
    hasfield(typeof(mg), :rival_score) && (s *= " rivals=$(mg.rival_score)")
    hasfield(typeof(mg), :found) && (s *= " found=$(sum(mg.found))/$(length(mg.found))")
    s
end

function rv_session(game, f; timeout = 400)
    run = NG.TestRun(NG.UITest[], Dict{String,Any}[], 0, Base.Threads.Condition(), "reviewer", time(), Float64(timeout), nothing)
    game.tests = run
    run.task = @async try
        Base.invokelatest(f, game)
        push!(RV[:log], "session done")
    catch err
        push!(RV[:log], "ERR " * first(sprint(showerror, err), 400))
    end
    RV[:task] = run.task
    "session started"
end

function rv_play_minigame(game, label, tag; secs = 60)
    push!(RV[:log], "start $tag")
    NG.interact!(game, rv_pick(game, NG.ui_elements(game)[1].name, label))
    NG.interact!(game, rv_click(game, "Play"))
    NG.wait_seconds(game, 1.0)
    rv_shot(game, "$(tag)-card")
    push!(RV[:log], "card: " * rv_describe(game))
    t0 = time()
    k = 0
    while time() - t0 < secs
        NG.interact!(game, rv_play_events(game, 10))
        k += 1
        rv_shot(game, "$(tag)-play$(k)")
        push!(RV[:log], "$(round(time() - t0)) s: " * rv_describe(game))
        mg = game.minigame
        (mg === nothing || getfield(mg, :state) == :over) && break
    end
    NG.wait_seconds(game, 1.5)
    rv_shot(game, "$(tag)-end")
    push!(RV[:log], "end: " * rv_describe(game))
    NG.interact!(game, [FI.KeyPress(NG.Makie.Keyboard.r; duration = 0.1), FI.Wait(1.0)])
    push!(RV[:log], "after R: " * rv_describe(game))
    rv_shot(game, "$(tag)-again")
    mg = game.minigame
    mg === nothing || NG.stop_minigame!(game)
end
"loaded2"
