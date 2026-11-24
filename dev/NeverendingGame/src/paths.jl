"""
Where everything of one game lives. `root` is the game folder (the Julia
environment); `world` holds the part that is the game itself: state, log,
assets, plugins and media. Copying `world/` plus `dev/NeverendingGame` is a release.

Two games run from one world (publish.jl): `:live`, the human's, and
`:sandbox`, the agent's. Each has its own state, log, snapshots and sockets
(`run`); assets, media, panels, the inbox, jobs and the todo list are shared.
The sandbox runs the plugins the agent edits (`world/plugins`), the human's
game their published copies (`world/live/plugins`).
"""
struct GamePaths
    instance::Symbol
    root::String
    world::String
    state::String
    log::String
    frames::String
    snapshots::String
    media::String
    assets::String
    plugins::String
    panels::String
    inbox::String
    jobs::String
    run::String
end

"The folder of a game's own state, log, snapshots and sockets."
own_dir(::Val{:live}, world) = world
own_dir(::Val{:sandbox}, world) = joinpath(world, "sandbox")

"The plugins a game runs."
plugin_dir(::Val{:live}, world) = joinpath(world, "live", "plugins")
plugin_dir(::Val{:sandbox}, world) = joinpath(world, "plugins")

function GamePaths(root::AbstractString, instance::Symbol = :live)
    root = abspath(root)
    world = joinpath(root, "world")
    own = own_dir(Val(instance), world)
    p = GamePaths(instance, root, world,
                  joinpath(own, "state"), joinpath(own, "log"), joinpath(own, "log", "frames"),
                  joinpath(own, "snapshots"), joinpath(world, "media"), joinpath(world, "assets"),
                  plugin_dir(Val(instance), world), joinpath(world, "panels"), joinpath(world, "inbox"),
                  joinpath(world, "jobs"), joinpath(own, "run"))
    for f in fieldnames(GamePaths)
        f === :instance || mkpath(getfield(p, f))
    end
    return p
end

"The plugins the agent edits: what the sandbox runs and `publish` copies from."
working_plugins(p::GamePaths) = joinpath(p.world, "plugins")

"The todo list, one for both games."
todos_file(p::GamePaths) = joinpath(p.world, "state", "todos.json")

"What Lumi is making right now (`think!`), one for both games."
thought_file(p::GamePaths) = joinpath(p.world, "state", "thought.json")

"The game folder: two levels above this package (`<root>/dev/NeverendingGame`)."
default_root() = normpath(joinpath(@__DIR__, "..", "..", ".."))

"Today's media folder, created on demand."
function media_dir(p::GamePaths, now::DateTime = Dates.now())
    d = joinpath(p.media, Dates.format(now, "yyyy-mm-dd"))
    mkpath(d)
    return d
end

stamp(now::DateTime = Dates.now()) = Dates.format(now, "HHMMSS")

"Write `content` to `path` atomically: readers never see a half written file."
function atomic_write(path::AbstractString, content::AbstractString)
    tmp = path * ".tmp"
    write(tmp, content)
    mv(tmp, path; force = true)
    return path
end

write_json(path::AbstractString, x) = atomic_write(path, JSON.json(x; pretty = true))
read_json(path::AbstractString) = JSON.parsefile(path; dicttype = Dict{String,Any})
