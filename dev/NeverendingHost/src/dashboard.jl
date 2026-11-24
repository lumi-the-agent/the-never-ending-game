# ── the dashboard: the character's chat beside its game ─────────────────────
#
# One component, two shells. `NeverendingGame` is a BonitoAgents app: its chat
# is the character's session, jailed on its worker like the host's agent role
# (`app_jail`), and its pane (`chat_pane`) shows the live game beside that chat.
# In a BonitoAgents server that is an app tile like any other. Standalone,
# `serve_dashboard` builds a `ServerState` of its own (no BonitoAgents
# dashboard), mounts only the worker endpoint on its own Bonito server, starts a
# BonitoWorker process for the chat (so a crash there, or in the game, never
# takes the host down) and serves the chat's model: rendering it draws the same
# `chat_pane`.

mutable struct NeverendingGame <: BonitoAgents.AgentApp
    ctx::BonitoAgents.AppContext
    jp::JailPaths
end

"The game the app shows: the folder named in `root` in the app's directory (`serve_dashboard` writes it)."
NeverendingGame(ctx::BonitoAgents.AppContext) = NeverendingGame(ctx, JailPaths(strip(read(joinpath(ctx.dir, "root"), String))))

BonitoAgents.app_id(::Type{NeverendingGame}) = "neverending"
BonitoAgents.app_title(::NeverendingGame) = "The Never Ending Game"
BonitoAgents.app_description(g::NeverendingGame) =
    "$(character_name(g.jp))'s island: the live game, and $(character_name(g.jp))'s sessions as its chat."

"The key of the character's own chat among the app's chats."
const CHARACTER_CHAT = "character"

"""
The character's chat is jailed as the host's agent role is (`role_mounts`, `role_env`): the game
folder and the environment to write, the host's code, the human's goals and game read only, `.jail`
hidden but its HOME and depot, its own Claude token, the host's allowed hosts.
"""
function BonitoAgents.app_jail(g::NeverendingGame, ::BonitoAgents.ProjectInfo)
    jp = g.jp
    cfg = load_config(jp)
    m = role_mounts(jp, :agent)
    ro_binds = [[jp.run, JAIL_RUN]]
    foreach(name -> isfile(log_path(jp, name)) && push!(ro_binds, [log_path(jp, name), log_path(jp, name)]),
            ("game", "sandbox", "worker"))
    extra = merge(secret_env(jp), Dict("CLAUDE_MAX_TURNS" => "400"))
    return Dict{String,Any}("home" => home(jp, :agent), "depot" => jp.depot,
                            "writable" => m.whitelist, "readonly" => m.readonly, "masks" => m.masks,
                            "ro_binds" => ro_binds, "env" => role_env(jp, cfg, :agent, extra),
                            "hosts" => all_hosts(cfg), "provider_state" => false)
end

"""
    GameView(port)

The live game: its own page (WGLMakie, served by the game process on `port` of the machine the
page came from), so a game that restarts is only a view that reloads.
"""
struct GameView
    port::Int
end

function Bonito.jsrender(session::Bonito.Session, v::GameView)
    frame = DOM.iframe(; class = "ne-game", allow = "fullscreen")
    show = js"""$(frame).src = location.protocol + '//' + location.hostname + ':' + $(v.port) + '/'"""
    return Bonito.jsrender(session, DOM.div(frame, show; class = "ne-game-view"))
end

const DASHBOARD_STYLE = Bonito.Styles(
    Bonito.CSS(".ne-layout", "display" => "flex", "gap" => "12px", "height" => "100%", "min-height" => "0"),
    Bonito.CSS(".ne-game-view", "flex" => "3 1 0", "min-width" => "0"),
    Bonito.CSS(".ne-game", "width" => "100%", "height" => "100%", "border" => "0", "border-radius" => "8px"),
    Bonito.CSS(".ne-chat", "flex" => "2 1 0", "min-width" => "320px", "display" => "flex",
               "flex-direction" => "column", "min-height" => "0"))

"The pane: the game, and the character's chat beside it."
function BonitoAgents.chat_pane(g::NeverendingGame, view)
    chat = DOM.div(BonitoAgents.ChatHeader(view), BonitoAgents.ChatNotice(view), BonitoAgents.ChatTranscript(view),
                   BonitoAgents.ChatComposer(view), BonitoAgents.ChatToolbar(); class = "ne-chat")
    return DOM.div(DASHBOARD_STYLE, GameView(load_config(g.jp).web_port), chat; class = "ne-layout")
end

# ── standalone ──────────────────────────────────────────────────────────────

"The standalone page: what BonitoAgents' own page mounts around a chat (its stylesheets), full height."
const PAGE_STYLE = Bonito.Styles(
    Bonito.CSS("html, body", "margin" => "0", "height" => "100%"),
    Bonito.CSS(".ne-page", "height" => "100vh", "display" => "flex", "flex-direction" => "column",
               "padding" => "8px", "box-sizing" => "border-box"),
    Bonito.CSS(".ne-page > .bt-app", "flex" => "1 1 0", "min-height" => "0"))

standalone_page(model) = DOM.div(Bonito.MarkdownCSS, BonitoAgents.ChatStyles, PAGE_STYLE, model; class = "ne-page")

"Where the standalone dashboard keeps its server state and its worker's config."
dashboard_dir(jp::JailPaths) = joinpath(jp.state, "dashboard")

"""
    start_dashboard_worker(jp, url) -> Process or nothing

The dashboard's BonitoWorker, its own process with its own config (`dashboard_dir`), connecting to
the dashboard's server at `url` and dying with this process. It uses the ACP adapter the user's
worker installed.
"""
function start_dashboard_worker(jp::JailPaths, url::AbstractString)
    adapter = BonitoWorker.agent_command(AgentProviders.find_provider("ClaudeCode")).bin
    cfg = mkpath(joinpath(dashboard_dir(jp), "worker"))
    proc, _ = withenv("BONITOAGENTS_CONFIG_DIR" => cfg, "CLAUDE_AGENT_ACP" => adapter,
                      "BONITOAGENTS_DIE_WITH_PARENT" => string(getpid())) do
        BonitoWorker.write_config!(; server_url = String(url), projects_root = jp.root,
                                   name = "neverending")
        BonitoWorker.spawn_worker()
    end
    return proc
end

"""
    serve_dashboard(root; host, port) -> NamedTuple

The standalone dashboard of the game in `root` at `http://host:port`: its own BonitoAgents server
state with the `NeverendingGame` app, the worker endpoint on its own Bonito server, a BonitoWorker
process, and the character's chat (jailed, created on first use) as the page. The worker comes in
over loopback (a worker needs no credential there); `host` is where people open the page. It has
no login yet: keep it on a network you trust.
"""
function serve_dashboard(root::AbstractString; host::AbstractString = "0.0.0.0",
                         port::Integer = load_config(JailPaths(root)).web_port + 10, timeout::Real = 120)
    jp = JailPaths(root)
    dir = dashboard_dir(jp)
    appdir = mkpath(joinpath(dir, "state", "apps", BonitoAgents.app_id(NeverendingGame)))
    write(joinpath(appdir, "root"), jp.root)
    server = BonitoAgents.ServerState(; state_dir = joinpath(dir, "state"), working_dir = joinpath(dir, "work"),
                                      apps = (NeverendingGame,))
    game = server.apps[BonitoAgents.app_id(NeverendingGame)]
    page = Observable{Any}(DOM.div("$(character_name(jp)) is waking up…"))
    srv = Bonito.Server(Bonito.App(_ -> page), String(host), Int(port))
    try
        return dashboard_up!(jp, server, srv, game, page; timeout)
    catch
        close(srv)            # a dashboard that did not come up leaves no server behind
        rethrow()
    end
end

function dashboard_up!(jp::JailPaths, server, srv, game, page; timeout::Real)
    BonitoAgents.add_worker_ws_routes!(srv, server)
    worker = start_dashboard_worker(jp, "http://127.0.0.1:$(srv.port)")
    t0 = time()
    while !any(w -> w.online[], values(server.workers[]))
        time() - t0 < timeout || error("the dashboard's worker did not connect in $(timeout) s (log: $(dashboard_dir(jp))/worker)")
        sleep(0.5)
    end
    w = first(w for w in values(server.workers[]) if w.online[])
    chat = BonitoAgents.app_chat(server, game, CHARACTER_CHAT)
    if chat === nothing
        chat = BonitoAgents.start_chat!(server, server.auth.user, w, jp.world; title = character_name(jp),
                                        app = game, key = CHARACTER_CHAT, jail = true)
    else
        BonitoAgents.ensure_project_session!(server, chat)       # the chat of an earlier run, brought up again
    end
    t0 = time()
    while !haskey(server.chat_models, chat.id)
        time() - t0 < timeout || error("the character's chat did not come up in $(timeout) s")
        sleep(0.5)
    end
    page[] = standalone_page(server.chat_models[chat.id])
    return (; server, srv, worker, game, chat)
end
