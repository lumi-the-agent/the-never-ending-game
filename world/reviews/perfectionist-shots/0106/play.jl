# Reviewer's own play session (perfectionist-0106): plays every mini game ~1 min through interact!.
module ReviewPlay0106
using NeverendingGame, Makie
const NG = NeverendingGame
const FI = NG.fake_interaction()
const K = Makie.Keyboard
const DIR = "/sim/Programmieren/SimGame/world/reviews/perfectionist-shots/0106/play"
const LOG = String[]
logl(s) = (push!(LOG, s); write(joinpath(DIR, "log.txt"), join(LOG, "\n")))
shot(g, name) = (mkpath(DIR); Makie.save(joinpath(DIR, name * ".png"), Makie.colorbuffer(g.screen)))
act!(g, evs) = NG.interact!(g, evs)
click(g, name) = act!(g, [FI.MouseTo(NG.ui_pos(g, name)), FI.LeftClick(), FI.Wait(0.2)])
function choose(g, option)
    menu = g.dash.play_menu
    name = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])
    act!(g, [FI.MouseTo(NG.ui_pos(g, name)), FI.LeftClick(), FI.Wait(0.3),
             FI.Lazy(_ -> FI.MouseTo(NG.ui_option_pos(g, name, option))), FI.LeftClick(), FI.Wait(0.2)])
end
pitch(g) = (d = g.rig.target - g.rig.eye; rad2deg(atan(-d[3], hypot(d[1], d[2]))))
lumi(g) = NG.creature(g.world, "Lumi")

# hold W, turn with A/D at the target; screenshots every `every` s
function steer(g, target_of, seconds, tag; every = 15)
    c = lumi(g); held = nothing; t0 = time(); next = 0.0; maxp = -90.0; n = 0
    act!(g, [FI.KeyDown(K.w)])
    while time() - t0 < seconds
        el = time() - t0
        el > 1.5 && (maxp = max(maxp, pitch(g)))
        if el >= next
            n += 1; shot(g, "$(tag)-$(n)"); next += every
        end
        p = target_of()
        p === nothing && break
        d = NG.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
        want = abs(d) < 0.15 ? nothing : d > 0 ? K.a : K.d
        if want !== held
            held === nothing || act!(g, [FI.KeyUp(held)])
            want === nothing || act!(g, [FI.KeyDown(want)])
            held = want
        end
        act!(g, [FI.Wait(0.1)])
    end
    held === nothing || act!(g, [FI.KeyUp(held)])
    act!(g, [FI.KeyUp(K.w), FI.Wait(0.1)])
    return (round(time() - t0; digits = 1), round(maxp; digits = 1))
end
cardtext(m) = try
    P = getfield(parentmodule(typeof(m)), :P); string(P[:card].text[])
catch
    ""
end

function firefly(g)
    choose(g, "Firefly catch (WASD)"); click(g, "Play"); act!(g, [FI.Wait(1.5)]); shot(g, "fly-0card")
    m = g.minigame; mod = parentmodule(typeof(m)); c = lumi(g)
    fly(i) = mod.fly_pos(m.flies[i], g.world.t, i)
    near() = (fr = findall(!, m.caught); isempty(fr) ? nothing :
              fly(fr[argmin([hypot(fly(i)[1] - c.pos[1], fly(i)[2] - c.pos[2]) for i in fr])]))
    tm, mp = steer(g, near, 62, "fly")
    act!(g, [FI.Wait(2)]); shot(g, "fly-end")
    logl("FIREFLY: caught $(m.score)/$(length(m.flies)) in $(tm) s, state $(getfield(m, :state)), max pitch $(mp)")
    act!(g, [FI.KeyPress(K.r), FI.Wait(1.5)]); shot(g, "fly-R")
    logl("  after R: state $(m === g.minigame ? m.state : typeof(g.minigame)) score $(g.minigame === nothing ? -1 : g.minigame.score)")
    click(g, "Stop")
end

function berry(g)
    file = joinpath(g.paths.state, "berries.json"); saved = isfile(file) ? read(file, String) : nothing
    choose(g, "Berry race (WASD)"); click(g, "Play"); act!(g, [FI.Wait(1.5)]); shot(g, "berry-0card")
    m = g.minigame; mod = parentmodule(typeof(m)); c = lumi(g)
    near() = (fr = [b for b in m.berries if b.taken == 0]; isempty(fr) ? nothing : fr[argmin([mod.flat(b.foot, c.pos) for b in fr])].foot)
    tm, mp = steer(g, () -> m.state === :over ? nothing : near(), 65, "berry")
    act!(g, [FI.Wait(2)]); shot(g, "berry-end")
    logl("BERRY: me $(m.score) critters $(m.rival_score) in $(tm) s, state $(m.state), max pitch $(mp)")
    click(g, "Stop")
    saved === nothing ? rm(file; force = true) : write(file, saved)
end

function hideseek(g)
    choose(g, "Hide and seek (WASD)"); click(g, "Play"); act!(g, [FI.Wait(1.5)]); shot(g, "hide-0card")
    m = g.minigame; mod = parentmodule(typeof(m)); c = lumi(g)
    target() = all(m.found) ? nothing : something(Base.invokelatest(mod.hint_spot, m, c),
                                                  Base.invokelatest(mod.hint_spot, m, c; heard_only = false), Some(nothing))
    tm, mp = steer(g, () -> m.state === :over ? nothing : target(), 65, "hide")
    act!(g, [FI.Wait(2)]); shot(g, "hide-end")
    logl("HIDESEEK: found $(count(m.found))/$(length(m.found)) in $(tm) s, state $(m.state), max pitch $(mp)")
    click(g, "Stop")
end

function jumpin(g)
    choose(g, "Jump in (WASD)"); click(g, "Play"); act!(g, [FI.Wait(2)]); shot(g, "jump-0")
    c = lumi(g)
    act!(g, [FI.KeyPress(K.w; duration = 3.0)]); shot(g, "jump-walk"); logl("JUMP walk: pitch $(round(pitch(g); digits=1)) pos $(c.pos)")
    for (k, name) in ((K.e, "E"), (K.space, "Space"), (K.x, "X"), (K.h, "H"), (K.g, "G"), (K.c, "C"), (K.p, "P"), (K.b, "B"), (K.v, "V"), (K.z, "Z"))
        act!(g, [FI.KeyPress(k), FI.Wait(1.2)])
        shot(g, "jump-$(name)")
        logl("JUMP $(name): action $(c.action) goal $(c.goal.kind) z $(round(c.pos[3]; digits=2)) pitch $(round(pitch(g); digits=1)) eye-lumi $(round(hypot((g.rig.eye - c.pos)[1], (g.rig.eye - c.pos)[2]); digits=1)) m")
        act!(g, [FI.Wait(2.5)])
        shot(g, "jump-$(name)-later")
        logl("   +2.5s: action $(c.action) goal $(c.goal.kind) z $(round(c.pos[3]; digits=2)) pitch $(round(pitch(g); digits=1))")
    end
    click(g, "Stop")
end

function run_all(g)
    empty!(LOG); mkpath(DIR)
    for (n, f) in (("firefly", firefly), ("berry", berry), ("hideseek", hideseek), ("jumpin", jumpin))
        try
            f(g)
        catch e
            logl("ERROR in $(n): " * first(sprint(showerror, e), 600))
            g.minigame === nothing || NG.stop_minigame!(g)
        end
    end
    logl("DONE")
end

"Start the run the way start_uitests! does (the game loop wakes it every frame)."
function start!(g)
    t = NG.UITest("perfectionist-0106 play", "", run_all)
    run = NG.TestRun([t], Dict{String,Any}[], 0, Base.Threads.Condition(), "", time(), 600.0, nothing)
    g.tests = run
    run.task = @async begin
        run.current = t.name; run.test_started = time()
        g.minigame === nothing || NG.stop_minigame!(g)
        err = try
            Base.invokelatest(t.f, g); ""
        catch e
            sprint(showerror, e)
        end
        push!(run.results, Dict{String,Any}("name" => t.name, "file" => "", "passed" => isempty(err), "seconds" => 0.0, "error" => first(err, 2000)))
        run.current = ""
    end
    return "started"
end
end
