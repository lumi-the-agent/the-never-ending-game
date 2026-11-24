"""
The Neverending Game: a life sim without an end. An agent lives in it as
Lumi and grows it: new places, creatures, interactions, mini games and
videos, written as plugins in `world/plugins`. Everything that happens is
written to `world/log`, so any moment can be replayed, rendered live or path
traced into a movie.

Processes (the host, `NeverendingHost`, keeps them running in the jail):

    NeverendingGame.run_game()     the human's world and its dashboard
    NeverendingGame.run_game(instance = :sandbox)   the agent's copy to try and test things (publish.jl)
    NeverendingGame.run_worker()   slow GPU jobs: generated assets, path traced stills

From an agent's Julia session: `live_status()`, `live_eval(code)`,
`live_screenshot(path)` (the sandbox; `game = :live` the human's), `publish()`, `todos()`, `todo!`, `doing!`, `done!`, `journal!`,
`say_to_human`, `submit_job`, `assets`. Plugins: `register!` with `System`,
`Actor`, `MiniGame`, `Panel` (see `plugins.jl`).
"""
module NeverendingGame

using Dates, Printf, Random, LinearAlgebra, Sockets, Serialization
import FileWatching
import JSON
using GeometryBasics
using GeometryBasics: Point3f, Vec3f, Point2f, Vec2f, Sphere, Cylinder, Rect3f, GLTriangleFace
using Colors
using Makie
using Makie: Quaternionf, qrotation, RGBf
import Hikari
import RayMakie
import VideoIO
import OIDNRunner
import Bonito, WGLMakie
import GPUMeshing, Mantle

export run_game, run_worker, publish
export live, live_status, live_eval, live_screenshot, live_reload, live_path_tracing
export todos, todo!, doing!, done!, drop!, journal!, say_to_human, think!
export submit_job, job, wait_job, assets, place_asset
export register!, System, Actor, MiniGame, Panel, ActorLook, InputEvent, Game
export ui_elements, ui_find, ui_pos, ui_option_pos, interact!
export uitest, check, wait_frames, wait_seconds, screenshot, live_tests

include("paths.jl")
include("eventlog.jl")
include("timing.jl")
include("todos.jl")
include("shapes.jl")
include("species.jl")
include("faces.jl")
include("paintedface.jl")
include("bird.jl")
include("herd.jl")
include("interfaces.jl")
include("world.jl")
include("behavior.jl")
include("scenery.jl")
include("render.jl")
include("actors.jl")
include("plugins.jl")
include("game.jl")
include("live.jl")
include("publish.jl")
include("web.jl")
include("play.jl")
include("dashboard.jl")
include("uidriver.jl")
include("uitests.jl")
include("meshrepair.jl")
include("assets.jl")
include("progress.jl")
include("agentapi.jl")

function __init__()
    init_shapes!()
    init_species!()
    init_interactions!()
    return nothing
end

end
