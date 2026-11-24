# ── Two games: the human's and the agent's sandbox ──────────────────────────
#
# The human's game (`:live`, the dashboard at the host's address) runs the
# published copies of the plugins (`world/live/plugins`) and takes engine
# edits only when something is published. The sandbox (`:sandbox`, the next
# port) runs the plugins the agent edits (`world/plugins`) and takes engine
# edits within a second; the agent, the tester, the reviewers and the UI tests
# use it, so nobody clicks in the human's dashboard. It starts as a copy of the
# human's world.
#
# `publish()` (the agent, when something is verified in the sandbox; the host
# after every session) asks the human's game to take the work: it applies the
# engine edits (Revise), then loads every changed plugin of `world/plugins`.
# One that loads is copied to `world/live/plugins` and swapped in; one that
# does not is refused and its published version keeps running. A plugin whose
# mini game the human is playing is swapped in when that game ends. Every
# system hears what arrived (`published!`), so something in the world can show
# it arriving.

"Before a game starts. The sandbox takes a fresh copy of the human's world and the plugins' saved state."
prepare_instance!(::Val{:live}, p::GamePaths) = p
function prepare_instance!(::Val{:sandbox}, p::GamePaths)
    live = GamePaths(p.root, :live).state
    for f in readdir(live)
        endswith(f, ".json") && !(f in ("todos.json", "perf.json")) && cp(joinpath(live, f), joinpath(p.state, f); force = true)
    end
    return p
end

"Engine edits: the sandbox takes them every second, the human's game only with `publish`."
follow_edits!(::Val{:sandbox}, g::Game) = g.revise()
follow_edits!(::Val{:live}, g::Game) = nothing

"Whether the mini game being played comes from plugin `name`."
plays(g::Game, name::AbstractString) =
    g.minigame !== nothing && haskey(g.plugins, name) && typeof(g.minigame) in g.plugins[name].minigames

"A changed plugin waits in the human's game while the human plays its mini game; the sandbox reloads it at once."
reload_waits(::Val{:live}, g::Game, name::AbstractString) = plays(g, name)
reload_waits(::Val{:sandbox}, g::Game, name::AbstractString) = false

"""
    publish!(game, why) -> (; published, removed, waiting, refused)

Swap the changed plugins of `world/plugins` into the human's game (see the
top of this file). Call it in the world after the engine edits (`revise`).
"""
function publish!(g::Game, why::AbstractString)
    src = working_plugins(g.paths)
    published, removed, waiting = String[], String[], String[]
    refused = Dict{String,String}()
    for f in plugin_files(src)
        from, to = joinpath(src, f), joinpath(g.paths.plugins, f)
        code = read(from, String)
        isfile(to) && read(to, String) == code && continue
        name = first(splitext(f))
        p = load_plugin(name, from)
        if !isempty(p.error)
            refused[name] = first(p.error, 2000)
            continue
        end
        atomic_write(to, code)
        if plays(g, name)
            push!(waiting, name)          # `check_plugins!` swaps it in when the mini game ends
        else
            p.path, p.mtime = to, mtime(to)
            install!(g, p)
            push!(published, name)
        end
    end
    for f in plugin_files(g.paths.plugins)
        isfile(joinpath(src, f)) && continue
        rm(joinpath(g.paths.plugins, f))
        push!(removed, first(splitext(f)))
    end
    check_plugins!(g)                     # takes the removed ones out
    log_event!(g.log, g.world.t, :publish; published, removed, waiting, refused = collect(keys(refused)), why)
    arrived = vcat(published, removed)
    if !isempty(arrived)
        # the new systems start now rather than next frame, so they (and their plots) are there to hear it
        for slot in copy(g.systems)
            slot.started || (slot.started = guarded(() -> start!(slot.system, g), g, "start!", slot))
            slot.started && guarded(() -> published!(slot.system, g, arrived), g, "published!", slot)
        end
    end
    return (; published, removed, waiting, refused)
end

function live_command(g::Game, ::Val{:publish}, msg)
    g.paths.instance === :live ||
        return Dict{String,Any}("ok" => false, "error" => "publish goes to the human's game: publish(), not to the sandbox")
    g.revise()                            # the engine edits first: the plugins may need them
    r = Base.invokelatest(publish!, g, string(get(msg, "why", "")))
    return Dict{String,Any}("ok" => true, "published" => r.published, "removed" => r.removed, "waiting" => r.waiting,
                            "refused" => r.refused)
end

"""
    publish(; why = "") -> Dict

Bring your work from the sandbox into the human's game: the engine edits,
and every plugin in `world/plugins` that changed and loads. The answer has
`published`, `removed`, `waiting` (the human plays its mini game: swapped in
when that ends) and `refused` (name => why it does not load; the published
version keeps running). Publish what you verified in the sandbox; the host
publishes the rest after every session.
"""
publish(; why::AbstractString = "", kw...) = live("publish"; game = :live, why, kw...)
