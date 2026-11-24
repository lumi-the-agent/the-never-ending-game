---
name: ui-testing
description: Drive the dashboard and mini games like a person with Makie's FakeInteraction events, write UI regression tests (world/tests) and run them in the sandbox game. Use to verify any change a human can see or touch.
---

# UI tests

Tests live in `world/tests/<area>.jl` (files starting with `_` are scratch,
not part of the suite). The host runs the whole suite after every work
session; failures are the first thing in the next session's prompt.

```julia
uitest("Play starts Jump in, Stop ends it") do game
    interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.2)])
    check(game.minigame isa NeverendingGame.JumpIn, "Play started $(typeof(game.minigame))")
    screenshot(game, "jumpin")                    # world/tests/shots/jumpin.png
    interact!(game, [MouseTo(ui_pos(game, "Stop")), LeftClick(), Wait(0.2)])
    check(game.minigame === nothing, "Stop did not stop it")
end
```

- The events are Makie's FakeInteraction (`../dev/Makie/docs/fake_interaction.jl`):
  `MouseTo(point)`, `LeftClick()`, `RightClick()`, `LeftDown()`/`LeftUp()`,
  `TypeText("text")`, `KeyPress(Keyboard.enter)`, `KeyPress(Keyboard.w; duration = 1.0)`
  (hold), `KeyDown(Keyboard.left_shift)`/`KeyUp(...)`, `Scroll((0, -3))`,
  `Wait(seconds)`, `WaitUntil(() -> condition; timeout = 5)`, `Lazy(fig -> event)`
  (computed when it is its turn, e.g. a menu option that only exists once the
  menu is open), `relative_pos(block, (x, y))`.
- `interact!(game, events)` plays them into the sandbox's dashboard frame by
  frame, through the same Makie events as a real pointer and keyboard.
- Tests run only in the sandbox game (the human's game refuses them), so
  they never click in the dashboard the human watches.
- Wishes typed through `interact!` (the wish box, Enter or Send) go to
  `world/tests/inbox`, never to the agent's inbox: tests check and clean up
  there (`NeverendingGame.test_inbox(game.paths)`).
- Finding things: `ui_elements(game)` lists the controls with their names
  (button label, menu text, text box placeholder); `ui_pos(game, name)` is the
  middle of one; `ui_option_pos(game, menu, option)` an option of an open menu:
  `[MouseTo(ui_pos(game, "Mini game")), LeftClick(), Wait(0.3),
    Lazy(_ -> MouseTo(ui_option_pos(game, "Mini game", "Firefly"))), LeftClick()]`.
- Plugin panels and mini game HUDs are ordinary Makie blocks and plots: use
  `relative_pos(block, (x, y))` on them.
- `check(condition, message)` fails the test with a message that says what
  happened; `wait_frames(game, n)` / `wait_seconds(game, s)` let the game run;
  `creature(game.world, "Lumi")` and the rest of the game state are there to
  check effects.
- Run: `live_tests()` (all) or `live_tests("Play")` (names containing "Play"),
  from your Julia session. Each result has name, passed, seconds, error.
- Keep tests fast (a few seconds), independent (stop what you start) and about
  behaviour a person notices.
