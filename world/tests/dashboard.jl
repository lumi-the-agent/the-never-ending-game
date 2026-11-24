# The dashboard's controls, used the way a person uses them (Makie's FakeInteraction events).

# Wishes typed by `interact!` go to the tests' inbox (world/tests/inbox), never to the agent's.
box(game, which) = which === :test ? NeverendingGame.test_inbox(game.paths) : NeverendingGame.agent_inbox(game.paths)
inbox_files(game, which = :test) =
    (d = box(game, which); isdir(d) ? Set(filter(f -> endswith(f, ".json"), readdir(d))) : Set{String}())
inbox_count(game, which = :test) = length(inbox_files(game, which))

"Remove the messages a test sent."
forget_new_messages!(game, before) =
    foreach(f -> rm(joinpath(box(game, :test), f)), setdiff(inbox_files(game), before))
click(game, name) = interact!(game, [MouseTo(ui_pos(game, name)), LeftClick(), Wait(0.2)])

function choose(game, menu, option)
    interact!(game, [MouseTo(ui_pos(game, menu)), LeftClick(), Wait(0.3),
                     Lazy(_ -> MouseTo(ui_option_pos(game, menu, option))), LeftClick(), Wait(0.2)])
end

uitest("Play with nothing chosen starts Jump in, Stop ends it") do game
    # an earlier run may have left a game chosen in the live menu: choose nothing
    game.dash.play_menu.i_selected[] = 0
    wait_frames(game, 3)
    check(game.dash.play_menu.selection[] === nothing, "could not clear the menu choice: $(game.dash.play_menu.selection[])")
    click(game, "Play")
    check(game.minigame isa NeverendingGame.JumpIn, "Play started $(typeof(game.minigame))")
    check(game.dash.play_button.label[] == "Stop", "while playing the button reads \"$(game.dash.play_button.label[])\"")
    screenshot(game, "play-jumpin")
    click(game, "Stop")
    check(game.minigame === nothing, "Stop left $(typeof(game.minigame)) running")
    check(game.dash.play_button.label[] == "Play", "after Stop the button reads \"$(game.dash.play_button.label[])\"")
end

uitest("W walks Lumi while jumped in") do game
    click(game, "Play")
    c = creature(game.world, "Lumi")
    p0 = c.pos
    interact!(game, [KeyPress(Keyboard.w; duration = 1.0), Wait(0.1)])
    d = norm(c.pos - p0)
    check(d > 0.5, "Lumi moved only $(round(d; digits = 2)) m in a second of W")
    click(game, "Stop")
end

uitest("Every mini game in the menu starts and stops") do game
    for option in string.(game.dash.play_menu.options[])
        choose(game, ui_name_of(game.dash.play_menu), option)
        check(game.dash.play_menu.selection[] == option, "chose \"$option\", the menu shows \"$(game.dash.play_menu.selection[])\"")
        click(game, "Play")
        wait_seconds(game, 0.5)
        check(game.minigame !== nothing, "\"$option\" did not start")
        started = NeverendingGame.game_title(typeof(game.minigame))
        check(started == option, "chose \"$option\" but \"$started\" started")
        screenshot(game, "minigame-" * option)
        click(game, "Stop")
        check(game.minigame === nothing, "\"$option\" did not stop")
    end
end

ui_name_of(menu) = menu.selection[] === nothing ? string(menu.prompt[]) : string(menu.selection[])

uitest("The camera menu switches the camera") do game
    for (option, mode) in (("Camera: orbit", :orbit), ("Camera: free", :fixed), ("Camera: follow", :follow))
        menu = only(filter(e -> e.kind === :menu && startswith(e.name, "Camera"), ui_elements(game))).name
        choose(game, menu, option)
        check(game.rig.mode === mode, "\"$option\" gave camera mode $(game.rig.mode)")
    end
end

uitest("While jumped in, the camera menu still counts: follow chases, orbit circles Lumi, free turns with the mouse") do game
    NeverendingGame.start_minigame!(game, NeverendingGame.JumpIn)
    menu() = only(filter(e -> e.kind === :menu && startswith(e.name, "Camera"), ui_elements(game))).name
    eyes(s) = (e0 = game.rig.eye; wait_seconds(game, s); norm(game.rig.eye - e0))
    choose(game, menu(), "Camera: follow"); wait_seconds(game, 2.0)
    me = NeverendingGame.creature(game.world, game.minigame.id)
    back, aim = norm(game.rig.eye - me.pos), norm(game.rig.target - (me.pos + Point3f(0, 0, 0.6)))
    check(back < 8 && aim < 1, "follow while jumped in is no chase camera: eye $(back) m from Lumi, looking $(aim) m off it")
    choose(game, menu(), "Camera: orbit"); wait_seconds(game, 0.5)
    moved = eyes(2.0)
    check(moved > 1.0, "orbit while jumped in moved the camera only $(moved) m in 2 s (the chase camera took every pick, 2026-11-23)")
    choose(game, menu(), "Camera: free"); wait_seconds(game, 1.0)
    still = eyes(1.0)
    check(still < 0.3, "the free camera moved $(still) m without the mouse")
    vp = game.dash.view.scene.viewport[]
    mid = Point2f(vp.origin .+ vp.widths ./ 2)
    e0 = game.rig.eye
    interact!(game, [MouseTo(mid), LeftDown(), MouseTo(mid + Point2f(220, 0), 0.5), LeftUp(), Wait(0.6)])
    dragged = norm(game.rig.eye - e0)
    check(dragged > 0.5, "dragging the mouse while jumped in with the free camera moved it only $(dragged) m")
    screenshot(game, "jumpin-free-camera")
    choose(game, menu(), "Camera: follow")
    NeverendingGame.stop_minigame!(game)
end

uitest("A wish typed and sent with Enter is sent and clears the box") do game
    before = inbox_files(game)
    n0, agent0 = length(before), inbox_count(game, :agent)
    interact!(game, [MouseTo(ui_pos(game, "Wish…")), LeftClick(), Wait(0.2),
                     TypeText("UI test: a wish sent with Enter (please ignore)"), KeyPress(Keyboard.enter), Wait(0.3)])
    sent = inbox_count(game) - n0
    forget_new_messages!(game, before)
    check(sent == 1, "the tests' inbox got $sent messages")
    check(inbox_count(game, :agent) == agent0, "the test's wish reached the agent's inbox")
    check(isempty(game.dash.tell_box.editor.arg1[]), "the box still shows \"$(game.dash.tell_box.editor.arg1[])\"")
    screenshot(game, "wish-enter")
end

uitest("A wish typed and sent with the Send button is sent") do game
    before = inbox_files(game)
    n0, agent0 = length(before), inbox_count(game, :agent)
    interact!(game, [MouseTo(ui_pos(game, "Wish…")), LeftClick(), Wait(0.2),
                     TypeText("UI test: a wish sent with Send (please ignore)"),
                     MouseTo(ui_pos(game, "Send")), LeftClick(), Wait(0.3)])
    sent = inbox_count(game) - n0
    forget_new_messages!(game, before)
    check(sent == 1, "the tests' inbox got $sent messages")
    check(inbox_count(game, :agent) == agent0, "the test's wish reached the agent's inbox")
    check(isempty(game.dash.tell_box.editor.arg1[]), "the box still shows \"$(game.dash.tell_box.editor.arg1[])\"")
end

uitest("Keys pressed while typing a wish do not steer Lumi") do game
    click(game, "Play")
    c = creature(game.world, "Lumi")
    p0 = c.pos
    interact!(game, [MouseTo(ui_pos(game, "Wish…")), LeftClick(), Wait(0.2),
                     KeyPress(Keyboard.w; duration = 0.6), TypeText("w")])
    check(norm(c.pos - p0) < 0.1, "holding w in the wish box moved Lumi $(round(norm(c.pos - p0); digits = 2)) m")
    game.dash.tell_box.editor.arg1 = ""
    game.dash.tell_box.focused = false
    click(game, "Stop")
end

uitest("Dashboard todos wrap long titles without cutting them") do game
    long = "Pretty night: blue moon tint, stars/sky, glowing flowers or lamps, so night reads as night but stays readable (lum >= 30)"
    check(!occursin("…", NeverendingGame.wrap_text(long, 48; maxlines = 3)), "a 120 character todo still gets cut with an ellipsis")
end

uitest("Dashboard side panels show Lumi's feeling, todos and activity without ellipses or a failed frame") do game
    wait_seconds(game, 1.5)
    d = game.dash
    for (n, t) in (("todos", d.todos.text[]), ("activity", d.activity.text[]), ("agent", d.agent.text[]), ("mood", d.mood.text[]))
        check(!occursin("…", t), "the $n panel still shows an ellipsis: \"$t\"")
    end
    m = d.mood.text[]
    check(m == "" || startswith(m, "Feels "), "the feeling line shows \"$m\"")
    screenshot(game, "side-panels")
end

"Overlap of two rectangles in square pixels."
function overlap_area(a, b)
    lo = max.(minimum(a), minimum(b))
    hi = min.(maximum(a), maximum(b))
    return prod(max.(hi .- lo, 0))
end

uitest("Name labels stay inside the 3D view and do not overlap") do game
    wait_frames(game, 2)
    a = game.stage.labels
    vw, vh = size(game.stage.scene)
    # each label's text box where the annotation placed it, in the view's pixels
    boxes = [bb + o for (bb, o) in zip(a.text_bbs[], a.offsets[])]
    for b in boxes
        lo, hi = minimum(b), maximum(b)
        check(lo[1] >= -1 && lo[2] >= -1 && hi[1] <= vw + 1 && hi[2] <= vh + 1, "a label pokes out of the view: $b")
    end
    for i in eachindex(boxes), j in (i + 1):length(boxes)
        small = min(prod(widths(boxes[i])), prod(widths(boxes[j])))
        check(overlap_area(boxes[i], boxes[j]) <= 0.2small, "two labels overlap: $(boxes[i]) and $(boxes[j])")
    end
    screenshot(game, "labels")
end

uitest("Activity text has no backticks, tool-call counts or stop reasons") do game
    s = NeverendingGame.plain_text("I wrote `world/outbox/a.json` and it ended (end_turn) after 0.7 min, 6 tool calls")
    check(!occursin('`', s) && !occursin("end_turn", s) && !occursin("tool call", s), "plain_text left: \"$s\"")
    for (n, t) in (("activity", game.dash.activity.text[]), ("agent", game.dash.agent.text[]))
        check(!occursin('`', t), "the $n panel shows a backtick: \"$t\"")
        check(!occursin("end_turn", t), "the $n panel shows a stop reason: \"$t\"")
    end
end

uitest("Wish box placeholder is short enough to show in full") do game
    p = string(game.dash.tell_box.placeholder[])
    check(length(p) <= 24, "the wish box placeholder \"$p\" ($(length(p)) characters) is clipped in the bar")
end

uitest("Player panels show no developer talk") do game
    d = game.dash
    for (n, t) in (("todos", d.todos.text[]), ("messages", d.agent.text[]))
        for w in ("UI test", "UI-test", "token budget", "RayMakie", "raster", "plot name")
            check(!occursin(w, t), "the $n panel shows developer text containing \"$w\": \"$(first(t, 120))\"")
        end
    end
end

uitest("The 'Next on the list' panel names no source files") do game
    t = game.dash.todos.text[]
    for w in (".jl", "scenery", "plugin", "Verify ")
        check(!occursin(w, t), "the todo list shows developer text containing \"$w\": \"$(first(t, 160))\"")
    end
end

uitest("At most three name tags, also from the overview camera") do game
    # ten names over the island covered the trees and each other (perfectionist-0024)
    rig = game.rig
    old = (rig.mode, rig.eye, rig.target)
    r = game.world.island.radius
    rig.mode = :fixed; rig.eye = Point3f(0.55r, -0.75r, 0.6r); rig.target = Point3f(0, 0, 0)
    wait_frames(game, 3)
    n = length(game.stage.labels[1][])
    screenshot(game, "tags-overview")
    rig.mode, rig.eye, rig.target = old
    check(n <= 3, "the overview shows $n name tags")
    wait_frames(game, 3)
    check(length(game.stage.labels[1][]) <= 3, "the follow view shows $(length(game.stage.labels[1][])) name tags")
end

uitest("Things to try: the side panel names every mini game and how to start one, no todo titles") do game
    wait_seconds(game, 1.0)
    t = game.dash.todos.text[]
    for T in NeverendingGame.minigame_types(game)
        name = replace(string(NeverendingGame.game_title(T)), r"\s*\(.*\)" => "")
        check(occursin(name, t), "the panel does not name \"$name\": \"$t\"")
    end
    check(occursin("press Play", t), "the panel does not say how to start: \"$t\"")
    check(!occursin("Perfectionist", t) && !occursin("Perfectionist", game.dash.activity.text[]), "review todos show to the player")
end

uitest("Free camera flies: W forward, A turns, R rises; follow takes over again") do game
    game.minigame === nothing || (click(game, "Stop"); wait_frames(game, 2))
    cam = () -> only(filter(e -> e.kind === :menu && startswith(e.name, "Camera"), ui_elements(game))).name
    choose(game, cam(), "Camera: free")
    check(game.rig.mode === :fixed, "free camera not chosen ($(game.rig.mode))")
    wait_frames(game, 3)
    e0 = game.rig.eye; t0 = game.rig.target
    d0 = normalize(Vec2f(t0[1] - e0[1], t0[2] - e0[2]))
    interact!(game, [KeyDown(Keyboard.w), Wait(1.0), KeyUp(Keyboard.w), Wait(0.1)])
    e1 = game.rig.eye
    moved = Vec2f(e1[1] - e0[1], e1[2] - e0[2])
    check(norm(moved) > 2, "W moved the free camera only $(round(norm(moved); digits = 2)) m")
    check(dot(moved, d0) > 0.8 * norm(moved), "W did not fly the way the camera looks")
    interact!(game, [KeyDown(Keyboard.a), Wait(0.8), KeyUp(Keyboard.a), Wait(0.1)])
    d1 = normalize(Vec2f(game.rig.target[1] - game.rig.eye[1], game.rig.target[2] - game.rig.eye[2]))
    check(d0[1] * d1[2] - d0[2] * d1[1] > 0.3, "A did not turn the camera left")
    z = game.rig.eye[3]
    interact!(game, [KeyDown(Keyboard.r), Wait(0.6), KeyUp(Keyboard.r), Wait(0.1)])
    check(game.rig.eye[3] > z + 1, "R did not lift the camera")
    screenshot(game, "freecam")
    choose(game, cam(), "Camera: follow")
    check(game.rig.mode === :follow, "follow not chosen again")
end

uitest("Free camera: its own low view (not the orbit's), drag turns it, scroll flies in, hint shows, menu label follows the mode") do game
    game.minigame === nothing || (click(game, "Stop"); wait_frames(game, 2))
    cam = () -> only(filter(e -> e.kind === :menu && startswith(e.name, "Camera"), ui_elements(game))).name
    menu = game.plugins["freecam"].mod.cam_menu(game)
    choose(game, cam(), "Camera: orbit")
    wait_frames(game, 30)
    orbit_eye = game.rig.eye
    screenshot(game, "camera-orbit")
    choose(game, cam(), "Camera: free")
    wait_frames(game, 3)
    check(game.rig.mode === :fixed, "free camera not chosen ($(game.rig.mode))")
    check(norm(game.rig.eye - orbit_eye) > 5, "free camera starts where the orbit was ($(game.rig.eye) vs $orbit_eye)")
    ground = NeverendingGame.terrain_height(game.world.island, game.rig.eye[1], game.rig.eye[2])
    check(game.rig.eye[3] - ground < 4, "free camera does not start low: $(round(game.rig.eye[3] - ground; digits = 1)) m above ground")
    hint = game.plugins["freecam"].mod.HUD[:hint]
    check(hint.visible[], "no free camera hint on screen")
    screenshot(game, "camera-free")
    yaw() = (d = game.rig.target - game.rig.eye; atan(d[2], d[1]))
    vp = game.dash.view.scene.viewport[]
    mid = Point2f(vp.origin .+ vp.widths ./ 2)
    y0 = yaw()
    interact!(game, [MouseTo(mid), LeftDown(), MouseTo(mid + Point2f(220, 0), 0.5), LeftUp(), Wait(0.1)])
    dy = rem2pi(yaw() - y0, RoundNearest)
    check(abs(dy) > 0.6, "a 220 px drag turned the free camera only $(round(dy; digits = 2)) rad")
    e0 = game.rig.eye
    interact!(game, [MouseTo(mid), Scroll((0, 3); duration = 0.3), Wait(0.1)])
    check(norm(game.rig.eye - e0) > 2, "scrolling moved the free camera only $(round(norm(game.rig.eye - e0); digits = 2)) m")
    choose(game, cam(), "Camera: follow")
    check(!hint.visible[] || (wait_frames(game, 2); !hint.visible[]), "free camera hint still shown in follow")
    game.rig.mode = :orbit; wait_frames(game, 3)
    check(menu.selection[] == "Camera: orbit", "menu says $(menu.selection[]) while the camera orbits")
    choose(game, cam(), "Camera: follow")
    check(menu.selection[] == "Camera: follow" && game.rig.mode === :follow, "follow not chosen again")
end

uitest("The camera the player picked comes back after a mini game, and a camera set from code keeps its eye") do game
    menu() = only(filter(e -> e.kind === :menu && startswith(e.name, "Camera"), ui_elements(game))).name
    for (option, mode) in (("Camera: orbit", :orbit), ("Camera: free", :fixed))
        choose(game, menu(), option)
        wait_seconds(game, 0.3)
        eye0 = game.rig.eye
        choose(game, ui_name_of(game.dash.play_menu), "Berry race (WASD)")
        click(game, "Play")
        wait_seconds(game, 0.5)
        check(game.minigame !== nothing, "the berry race did not start")
        click(game, "Stop")
        wait_seconds(game, 0.5)
        check(game.rig.mode === mode, "after the race the camera is $(game.rig.mode), the player had picked $option")
        mode === :fixed && check(norm(game.rig.eye - eye0) < 0.5, "the free camera came back at another place ($(game.rig.eye) vs $eye0)")
        screenshot(game, "camera-back-" * option)
    end
    # a plugin or a test sets a fixed camera from follow: the eye stays where it was put (tester s44)
    choose(game, menu(), "Camera: follow"); wait_seconds(game, 0.3)
    eye = Point3f(30, -40, 25); target = Point3f(0, 0, 0)
    game.rig.mode = :fixed; game.rig.eye = eye; game.rig.target = target
    wait_seconds(game, 0.5)
    check(norm(game.rig.eye - eye) < 0.01 && norm(game.rig.target - target) < 0.01, "the code-set camera moved to $(game.rig.eye) / $(game.rig.target)")
    choose(game, menu(), "Camera: follow")
end
