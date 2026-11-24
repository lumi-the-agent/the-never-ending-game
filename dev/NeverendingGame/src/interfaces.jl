# ── The extension interfaces (see plugins.jl for how plugins register them) ──

"""
Runs every frame: `step!(s, game, dt)`. Optional: `start!(s, game)` once,
`stop!(s, game)` on unload, and `published!(s, game, plugins)` in the human's
game when plugins (names) were just published into it or taken out (publish.jl).
"""
abstract type System end
start!(::System, game) = nothing
stop!(::System, game) = nothing
published!(::System, game, plugins) = nothing

"""
Something in the world with state of its own, stored in `world.actors` and
saved in snapshots. Interface (all optional except a `pos::Point3f` field or
a `position` method):

- `step!(a, game, dt)`                  behaviour
- `actor_position(a)`                   where it is (default `a.pos`)
- `actor_look(::Type{A})`               an `ActorLook` for the default renderer (an instanced mesh)
- `visual(::Type{A}, scene) -> handle`  and `sync_visual!(handle, actors::Vector{A}, game)`
                                        for a renderer of its own
- `snapshot(a) -> Dict`, `restore(::Type{A}, d)` (default: all fields)
"""
abstract type Actor end

"""
Playable from the dashboard's Play menu.

- `game_title(::Type{G})`, `game_description(::Type{G})`
- `G(game)` builds it; `start!(g, game)` sets it up (plots, spawns)
- `step!(g, game, dt)` every frame; `input!(g, game, ev::InputEvent)` for keys
- `finished(g)` true ends it; `stop!(g, game)` cleans up
"""
abstract type MiniGame end
game_title(T::Type{<:MiniGame}) = string(nameof(T))
game_description(::Type{<:MiniGame}) = ""
start!(::MiniGame, game) = nothing
input!(::MiniGame, game, ev) = nothing
finished(::MiniGame) = false
stop!(::MiniGame, game) = nothing

"A box on the dashboard: `build_panel!(p, layout::GridLayout, game)` once, `update_panel!(p, game)` twice a second."
abstract type Panel end
build_panel!(::Panel, layout, game) = nothing
update_panel!(::Panel, game) = nothing
panel_title(p::Panel) = string(nameof(typeof(p)))

