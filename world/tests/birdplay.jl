# Playing as the bird Lumi (s59): jump in, walk, run, stop; the name tag follows its own head.
const BP_NG = NeverendingGame

uitest("Jump in as the bird: W walks, Shift runs faster, the tag stays above Lumi") do game
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    try
        s = creature(game.world, "Lumi")
        check(game.minigame isa BP_NG.JumpIn && s.controlled, "Play did not hand Lumi over: $(typeof(game.minigame)) controlled=$(s.controlled)")
        dist(a, b) = sqrt(sum(abs2, (a .- b)[1:2]))
        p0 = copy(s.pos)
        interact!(game, [KeyPress(Keyboard.w; duration = 1.5)])
        walked = dist(s.pos, p0)
        p1 = copy(s.pos)
        interact!(game, [KeyDown(Keyboard.left_shift), KeyPress(Keyboard.w; duration = 1.5), KeyUp(Keyboard.left_shift)])
        ran = dist(s.pos, p1)
        # a bush may block a run: only require some movement and no slower run than half the walk
        check(walked > 0.3, "W did not move Lumi: $walked m, action $(s.action)")
        check(ran > 0.5 * walked, "Shift+W ran $ran m, walking gave $walked m")
        screenshot(game, "birdplay-run")
        wait_seconds(game, 1.5)
        l = game.stage.labels
        offs = l.attributes[:arg1][]
        check(all(o -> o[1] == 0 && 0 < o[2] < 150, offs), "a tag is off its head while playing: $offs")
        screenshot(game, "birdplay-stop")
    finally
        interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
    end
    check(game.minigame === nothing, "Stop did not end Jump in")
end

uitest("Jump in: the controls card shrinks to one line as soon as Lumi walks off") do game
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.3)])
    try
        hint = game.plugins["greetings"].mod.GP[:hint]
        check(hint.visible[] && startswith(hint.text[], "You are Lumi"), "no full card after Play: $(hint.visible[]) $(repr(hint.text[]))")
        interact!(game, [KeyPress(Keyboard.w; duration = 2.5)])
        s = creature(game.world, "Lumi")
        check(!startswith(hint.text[], "You are Lumi"), "the full card still covers the view after 2.8 s, walking ($(s.action)): $(repr(hint.text[]))")
        screenshot(game, "birdplay-card-shrinks")
    finally
        interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
    end
end

# s60 (#376): sets up the tester's s59 scene on purpose (a friend right behind the player on screen)
uitest("Jump in: a friend just behind Lumi does not take Lumi's name tag") do game
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.5)])
    w = game.world
    pk = creature(w, "Pickles")
    try
        me = creature(w, "Lumi")
        eye = Point3f(game.stage.scene.camera.eyeposition[])
        d = me.pos - eye; n = sqrt(d[1]^2 + d[2]^2)
        pk.pos = BP_NG.ground(w.island, (me.pos[1] + 1.4f0 * d[1] / n, me.pos[2] + 1.4f0 * d[2] / n))
        pk.controlled = true; pk.goal = BP_NG.Goal()
        wait_seconds(game, 1.0)
        l = game.stage.labels
        offs = l.attributes[:arg1][]
        names = [split(string(t), '\n')[1] for t in l.attributes[:text][]]
        screenshot(game, "birdplay-tag-overlap")
        i = findfirst(n -> occursin("Lumi", n), names)
        check(i !== nothing, "no tag for Lumi: $names")
        check(offs[i][2] < 40, "Lumi's tag floats $(offs[i][2]) px above its head (tags $names, offsets $offs)")
    finally
        pk.controlled = false
        interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.3)])
    end
end
