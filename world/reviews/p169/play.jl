# Perfectionist review s169: play each mini game for about a minute like a person (W/A/D toward the obvious target).
# Loaded after tests/minigames.jl (for fly_choose, fly_click, steer_wad), into one module, run as a test task.
R = Main.REVIEW_PLAY

function rv_fields(m)
    d = Dict{String,Any}()
    for f in (:score, :state, :t, :rival_score, :found, :caught)
        hasfield(typeof(m), f) && (d[string(f)] = string(getfield(m, f)))
    end
    d
end

function rv_play(game, option, target_maker, key)
    log = Any[]
    R[key] = log
    fly_choose(game, option)
    fly_click(game, "Play")
    m = game.minigame
    push!(log, ("started", string(typeof(m)), rv_fields(m)))
    R[:phase] = "$key start card"
    interact!(game, [Wait(4.0)])                      # what does the start card ask?
    c = creature(game.world, "Lumi")
    mod = parentmodule(typeof(m))
    tgt = target_maker(game, m, mod, c)
    t0 = time()
    for k in 1:12
        R[:phase] = "$key playing $(5k) s"
        steer_wad(game, tgt, 5)
        push!(log, (round(time() - t0; digits = 1), rv_fields(m)))
        game.minigame === m || break
        hasfield(typeof(m), :state) && m.state === :over && (R[:phase] = "$key over"; interact!(game, [Wait(4.0)]); break)
    end
    push!(log, ("end", rv_fields(m)))
    R[:phase] = "$key end card"
    interact!(game, [Wait(3.0)])
    # play twice? R restarts on the end card in some games
    interact!(game, [KeyPress(Keyboard.r; duration = 0.2), Wait(1.0)])
    push!(log, ("after R", string(typeof(game.minigame)), game.minigame === nothing ? "" : rv_fields(game.minigame)))
    game.minigame === nothing || fly_click(game, "Stop")
end

fire_t(game, m, mod, c) = function ()
    fly(i) = mod.fly_pos(m.flies[i], game.world.t, i)
    free = findall(!, m.caught); isempty(free) && return nothing
    fly(free[argmin([hypot(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2]) for i in free])])
end
berry_t(game, m, mod, c) = function ()
    free = [b for b in m.berries if b.taken == 0]; isempty(free) && return nothing
    free[argmin([mod.flat(b.foot, c.pos) for b in free])].foot
end
hide_t(game, m, mod, c) = () -> all(m.found) ? nothing :
    something(Base.invokelatest(mod.hint_spot, m, c), Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))

uitest("REVIEW play firefly") do game
    rv_play(game, "Firefly catch (WASD)", fire_t, :firefly)
end
uitest("REVIEW play berry") do game
    file = joinpath(game.paths.state, "berries.json"); saved = isfile(file) ? read(file, String) : nothing
    P = Main.BERRY_PLOTS; snap = copy(P)
    try
        rv_play(game, "Berry race (WASD)", berry_t, :berry)
    finally
        saved === nothing ? rm(file; force = true) : write(file, saved)
        for k in (:total, :best, :level); haskey(snap, k) ? (P[k] = snap[k]) : delete!(P, k); end
    end
end
uitest("REVIEW play hide") do game
    rv_play(game, "Hide and seek (WASD)", hide_t, :hide)
end
