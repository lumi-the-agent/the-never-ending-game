---
name: write-plugin
description: How to add things to the game as plugins - systems that run every frame, actors with their own state, mini games the human can play, dashboard panels, species and interactions. Use for any new game feature.
---

# Plugins

A plugin is `world/plugins/<name>.jl`. Your sandbox game loads it within a
second of saving (the human's game when you `publish()`), in a fresh module with `NeverendingGame`, `Makie`, `GeometryBasics`,
`Colors`, `LinearAlgebra`, `Random`, `Printf` in scope, and replaces the old
version (its actors are carried over by `snapshot`/`restore`). Files starting
with `_` are ignored (drafts). A plugin that throws is switched off and you
get an urgent todo with the error; the game keeps running.

## The four kinds

```julia
# A System runs every frame
struct Breeze <: System
    strength::Float32
end
NeverendingGame.start!(s::Breeze, game) = nothing          # once (create plots here)
NeverendingGame.step!(s::Breeze, game, dt) = nothing        # every frame: keep it < 1 ms
NeverendingGame.stop!(s::Breeze, game) = nothing            # on reload/removal (delete your plots)
register!(Breeze(0.3f0))

# An Actor is a thing with state, saved with the world
mutable struct Firefly <: Actor
    pos::Point3f
    phase::Float32
end
NeverendingGame.step!(f::Firefly, game, dt) = (f.phase += dt; f.pos += Point3f(0, 0, 0.01f0 * sin(f.phase)))
NeverendingGame.actor_look(::Type{Firefly}) = ActorLook(marker = :sphere, scale = Vec3f(0.05),
    material = NeverendingGame.Hikari.Emission(color = (1.0, 0.9, 0.4), strength = 4.0))
register!(Firefly)
# spawn some (in live_eval or a system):  NeverendingGame.spawn!(game.world, Firefly(Point3f(1, 2, 1), 0f0))

# A MiniGame is played from the dashboard's Play menu
mutable struct CatchTheBall <: MiniGame
    score::Int
    t::Float64
end
CatchTheBall(game) = CatchTheBall(0, 0.0)
NeverendingGame.game_title(::Type{CatchTheBall}) = "Catch the ball"
NeverendingGame.start!(m::CatchTheBall, game) = nothing
NeverendingGame.step!(m::CatchTheBall, game, dt) = (m.t += dt)
NeverendingGame.input!(m::CatchTheBall, game, ev) = nothing        # ev.key, ev.action (Makie)
NeverendingGame.finished(m::CatchTheBall) = m.t > 60
register!(CatchTheBall)
# game.keys_down is the set of held Makie keys

# A Panel is a box on the dashboard (right column)
struct Weather <: Panel end
NeverendingGame.build_panel!(p::Weather, layout, game) = Label(layout[1, 1], "sunny"; fontsize = 15, color = :white)
NeverendingGame.update_panel!(p::Weather, game) = nothing          # twice a second
register!(Weather())
```

Also: `register!(species)` for a new body plan (see `species.jl`), and
`register!(MyInteraction, weight)` for a new interaction between creatures
(see `Chat`, `Boop`, `DanceOff` in `behavior.jl`).

## Faces and feelings

Every creature's face is part of its body (engine `faces.jl`): brows, lids, a mouth line
that smiles or frowns, an open mouth, ^ ^ joy eyes, blush, tears and a sweat drop, all a
pure function of the recorded numbers, so replays and films show them too. Plain actions
show the mood (`c.mood`, -1 sad … 1 happy); a moment gets its feeling with

    NG.feel!(w, c, :gasp; seconds = 1.5)   # stops c, shows the feeling, then it goes on

Feelings: `:laugh :cry :pout :gasp :think :proud :shy :yawn :sigh :scared :angry` (each
with its own face, body and arms; `:dance :jump :wave` close the eyes into ^ ^). A runner
laughs when a plugin sets `c.extra = 1` after it moved (tag.jl). Give every moment you
make the feeling it has: a present → gasp, then joy; a lost race → pout; thunder → scared;
a friend leaving → sigh. Look at the face up close (a 1.5 m camera) before you call it done.

## Rules of thumb

- Find what exists first (find-existing-code skill). Extend the engine in
  `dev/NeverendingGame/src` only when a plugin cannot do it.
- Build and test in your own session first (`NG.Game()` loads the plugins
  headless; call `NG.frame!` on it), then save into `world/plugins/` and
  check `live_reload()` and `live_status()` (the sandbox); `publish()` once
  it works.
- Plots you create in `start!` must be deleted in `stop!` (reloads!).
- Text on screen: at least 15 px, high contrast, never stroke or glow
  outlines on text (they overlap the neighbouring letters). The human watches
  at 1280×720. Text goes on `game.stage.overlay`, the 2D pixel scene over the
  3D view, not into the 3D scene:
  - a HUD or a message: `textlabel!(game.stage.overlay, Point2f(0.5, 0.93);
    space = :relative, text, background_color, ...)`, a box behind the text;
  - pointing at something in the world: Makie's `annotation!` with the
    targets' pixel positions (`NeverendingGame.on_screen(scene, p)`); it
    places labels so they do not overlap and draws a line to the target.
    Creature names and speech already work this way (`game.stage.labels`).
- Everything in the scene goes to every browser that opens the page: many
  copies of one thing are ONE instanced plot (`meshscatter`, for generated
  assets `NG.asset_instances!`, see `skills/make-asset`), never a plot per
  copy, and textures stay small.
- Keep per-frame work tiny: no allocations in hot loops, update plots with
  `Makie.update!(plot, data; attr = ...)`, never recreate plots per frame.
