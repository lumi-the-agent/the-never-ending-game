# Reviewer 0139: play every mini game for about a minute like a person, screenshots under reviews/p139/play.
const SHOTS = "/sim/Programmieren/SimGame/world/reviews/p139/play"
mkpath(SHOTS)
const LOG = String[]
note(s) = (push!(LOG, s); nothing)

function fix_dayfall!(game)   # the s137 day-fall reset leaves markersize at the old length and crashes the render
    for p in game.stage.scene.plots
        if p isa Makie.MeshScatter && get(p.attributes, :name, Observable(:none))[] == :dayfall_tiles
            ms = p.markersize[]
            ms isa AbstractVector && length(ms) != length(p[1][]) &&
                Makie.update!(p; markersize = [Vec3f(1, 1, 1) for _ in 1:length(p[1][])])
        end
    end
end

function shot(game, name)
    fix_dayfall!(game)
    try
        Makie.save(joinpath(SHOTS, name * ".png"), Makie.colorbuffer(game.screen))
    catch e
        note("shot $name failed: " * first(sprint(showerror, e), 200))
    end
end

function choose(game, option)
    menu = game.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, name, option))), LeftClick(), Wait(0.2)])
end
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.3)])
key(k; d = 0.15) = KeyPress(k; duration = d)
hud(game) = string(typeof(game.minigame))

# a person playing: hold W, steer, look around
function wander(game, seconds; extra = Keyboard.Button[])
    t = 0.0; i = 0
    while t < seconds
        i += 1
        evs = Any[key(Keyboard.w; d = 1.6)]
        push!(evs, key(isodd(i) ? Keyboard.a : Keyboard.d; d = 0.35))
        isempty(extra) || push!(evs, key(extra[mod1(i, length(extra))]))
        push!(evs, Wait(0.2))
        interact!(game, evs)
        t += 2.4
    end
end

function play_one(game, option, tag; extra = Keyboard.Button[], start_keys = [Keyboard.w])
    t0 = time()
    choose(game, option); click(game, "Play"); wait_seconds(game, 1.0)
    shot(game, tag * "-0-start")
    note("$option: started $(hud(game))")
    for k in start_keys
        interact!(game, [key(k), Wait(0.5)])
    end
    for (j, s) in enumerate((15, 15, 15, 15))
        game.minigame === nothing && (note("$option: ended by itself after $(round(time()-t0)) s"); break)
        wander(game, s; extra)
        shot(game, tag * "-$(j)")
    end
    note("$option: after play $(hud(game)) $(round(time() - t0)) s")
    game.minigame === nothing || click(game, "Stop")
    fix_dayfall!(game)
end

function review_play(game)
    opts = string.(game.dash.play_menu.options[])
    note("options: " * join(opts, " | "))
    for o in opts
        tag = lowercase(replace(first(split(o, " (")), r"[^A-Za-z]" => ""))
        try
            if startswith(o, "Jump in")
                play_one(game, o, tag; extra = [Keyboard.e, Keyboard.o, Keyboard.l, Keyboard.r, Keyboard.i, Keyboard.n, Keyboard.space])
            else
                play_one(game, o, tag; extra = [Keyboard.e])
            end
        catch e
            note("$o: ERROR " * first(sprint(showerror, e), 400))
            game.minigame === nothing || try click(game, "Stop") catch end
        end
    end
    # the chip stone, played by hand: Lumi put next to it, R chips, L knocks
    try
        choose(game, opts[findfirst(startswith("Jump in"), opts)]); click(game, "Play"); wait_seconds(game, 1)
        me = creature(game.world, "Lumi")
        me.pos = Point3f(4.0, -15.2, me.pos[3]); wait_seconds(game, 0.5)
        shot(game, "chip-0")
        for k in 1:4
            interact!(game, [key(Keyboard.r), Wait(1.5)]); shot(game, "chip-r$k")
            interact!(game, [key(Keyboard.l), Wait(1.5)])
        end
        shot(game, "chip-end")
        click(game, "Stop"); fix_dayfall!(game)
    catch e
        note("chip: ERROR " * first(sprint(showerror, e), 400))
        game.minigame === nothing || try click(game, "Stop") catch end
    end
    write(joinpath(SHOTS, "log.txt"), join(LOG, "\n"))
end
