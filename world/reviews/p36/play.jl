# reviewer scratch: plays a mini game through interact! inside a hand-made TestRun
let g = game, NGm = NeverendingGame
  FI = NGm.fake_interaction()
  MouseTo=FI.MouseTo; LeftClick=FI.LeftClick; Wait=FI.Wait; Lazy=FI.Lazy; KeyPress=FI.KeyPress
  K = NGm.Makie.Keyboard
  run = NGm.TestRun(NGm.UITest[], Dict{String,Any}[], 0, Base.Threads.Condition(), "reviewer", time(), 400.0, nothing)
  g.tests = run
  run.task = @async try
    io = open(LOGPATH, "w")
    say(x) = (println(io, x); flush(io))
    interact!(g, [MouseTo(ui_pos(g, "Mini game")), LeftClick(), Wait(0.3)])
    interact!(g, [Lazy(_ -> MouseTo(ui_option_pos(g, "Mini game", GAMENAME))), LeftClick(), Wait(0.3)])
    interact!(g, [MouseTo(ui_pos(g, "Play")), LeftClick(), Wait(1.0)])
    say("started " * string(typeof(g.minigame)))
    c = NGm.creature(g.world, "Sprout")
    say("start pos " * string(round.(c.pos; digits=1)))
    for i in 1:STEPS
      interact!(g, [KeyPress(K.w; duration=1.5), KeyPress(K.a; duration=0.5)])
      say("t$i " * string(round.(c.pos; digits=1)) * " " * string(typeof(g.minigame)) * " " * string(try NGm.minigame_status(g.minigame) catch; "" end))
    end
    close(io)
  catch e
    open(LOGPATH, "a") do f; println(f, "ERR ", sprint(showerror, e, catch_backtrace())); end
  end
end
