# ── Plugins: how the game grows ──────────────────────────────────────────────
#
# A plugin is a file `world/plugins/<name>.jl`. It is evaluated in a module of
# its own (with NeverendingGame, Makie, GeometryBasics, Colors, LinearAlgebra
# and Random in scope) and calls `register!` for what it adds:
#
#   register!(MySystem(...))        a System: runs every frame (weather, a rule, a spawner)
#   register!(MyActor)              an Actor type: things in the world with their own state
#   register!(MyMiniGame)           a MiniGame type: playable from the dashboard
#   register!(MyPanel())            a Panel: a box on the dashboard
#   register!(species)              a Species (creature body plan)
#   register!(MyInteraction, 1.0)   an Interaction between two creatures, with its weight
#
# The game watches the files: a changed plugin is loaded again into a fresh
# module, its old registrations are replaced, and its actors are carried over
# through `snapshot`/`restore`. A plugin that fails to load or throws while
# running is switched off and the error is logged (`:plugin_error` event) and
# put on the todo list, so the agent sees it; the game keeps running.

mutable struct Plugin
    name::String
    path::String
    mtime::Float64
    mod::Union{Nothing,Module}
    systems::Vector{System}
    actor_types::Vector{DataType}
    minigames::Vector{DataType}
    panels::Vector{Panel}
    species::Vector{String}
    interactions::Vector{DataType}
    error::String            # "" when healthy
    load_ms::Float64
end

Plugin(name, path) = Plugin(String(name), String(path), 0.0, nothing, System[], DataType[], DataType[], Panel[],
                            String[], DataType[], "", 0.0)

"Registrations go to the plugin being loaded (a scoped value, so loading is reentrant and global free)."
const LOADING = Base.ScopedValues.ScopedValue{Union{Nothing,Plugin}}(nothing)

function loading_plugin()
    p = LOADING[]
    p === nothing && error("register! is only valid while a plugin file is loaded")
    return p
end

register!(s::System) = (push!(loading_plugin().systems, s); s)
register!(T::Type{<:Actor}) = (push!(loading_plugin().actor_types, T); T)
register!(T::Type{<:MiniGame}) = (push!(loading_plugin().minigames, T); T)
register!(p::Panel) = (push!(loading_plugin().panels, p); p)
function register!(sp::Species)
    register_species!(sp)
    push!(loading_plugin().species, sp.name)
    return sp
end
function register!(T::Type{<:Interaction}, weight::Real)
    filter!(p -> nameof(first(p)) != nameof(T), INTERACTIONS)
    push!(INTERACTIONS, T => Float64(weight))
    push!(loading_plugin().interactions, T)
    return T
end

const PLUGIN_IMPORTS = quote
    using NeverendingGame, Makie, GeometryBasics, Colors, LinearAlgebra, Random, Printf
    using NeverendingGame: register!, System, Actor, MiniGame, Panel, ActorLook, InputEvent, Game, World,
                           step!, start!, stop!, input!, finished, game_title, game_description,
                           build_panel!, update_panel!, actor_position, actor_look, visual, sync_visual!,
                           snapshot, restore, spawn!, despawn!, say_to_human, journal!, published!
    using GeometryBasics: Point3f, Vec3f, Point2f, Vec2f
end

"""
    load_plugin(name, path) -> Plugin

Evaluate the file in a fresh module. On failure the plugin has `error` set and
nothing registered.
"""
function load_plugin(name::AbstractString, path::AbstractString)
    p = Plugin(name, path)
    p.mtime = mtime(path)
    t0 = time()
    mod = Module(Symbol("Plugin_", replace(name, r"[^A-Za-z0-9_]" => "_")))
    Core.eval(mod, PLUGIN_IMPORTS)
    Core.eval(mod, :(include(path) = Base.include($mod, path)))
    try
        Base.ScopedValues.with(LOADING => p) do
            Base.include(mod, path)
        end
        p.mod = mod
    catch e
        e isa InterruptException && rethrow()
        # a broken plugin must not take the game down: it is reported and stays off
        p.error = sprint(showerror, e, catch_backtrace())
        empty!(p.systems); empty!(p.actor_types); empty!(p.minigames); empty!(p.panels)
    end
    p.load_ms = 1000 * (time() - t0)
    return p
end

plugin_files(dir::AbstractString) =
    isdir(dir) ? sort!([f for f in readdir(dir) if endswith(f, ".jl") && !startswith(f, "_")]) : String[]
