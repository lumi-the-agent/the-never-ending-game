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
            ("game", "sandbox", "worker", "runner"))
    extra = merge(secret_env(jp), Dict("CLAUDE_MAX_TURNS" => "400"))
    return Dict{String,Any}("home" => home(jp, :agent), "depot" => jp.depot,
                            "writable" => m.whitelist, "readonly" => m.readonly, "masks" => m.masks,
                            "ro_binds" => ro_binds, "env" => role_env(jp, cfg, :agent, extra),
                            "hosts" => all_hosts(cfg), "provider_state" => false)
end

"""
    GameView(port)

The live game's 3D view: its `/scene` page (WGLMakie, served by the game process on `port` of the
machine the page came from), so a game that restarts is only a view that reloads. The page tells
the view's size; the card takes its proportions at the largest size the space holds.
"""
struct GameView
    port::Int
end

function Bonito.jsrender(session::Bonito.Session, v::GameView)
    frame = DOM.iframe(; class = "ne-game", allow = "fullscreen")
    card = DOM.div(frame; class = "ne-game-card")
    area = DOM.div(card; class = "ne-game-area")
    fit = js"""
        const frame = $(frame), card = $(card), area = $(area);
        frame.src = location.protocol + '//' + location.hostname + ':' + $(v.port) + '/scene';
        let aspect = 1.25;
        const fit = () => {
            const w = Math.min(area.clientWidth, area.clientHeight * aspect);
            card.style.width = Math.floor(w) + 'px';
            card.style.height = Math.floor(w / aspect) + 'px';
        };
        window.addEventListener('message', e => {
            if (e.source !== frame.contentWindow || !e.data || !e.data.sceneSize) return;
            const [w, h] = e.data.sceneSize;
            if (Math.abs(w / h - aspect) > 1e-3) { aspect = w / h; fit(); }
        });
        new ResizeObserver(fit).observe(area);
        fit();
    """
    return Bonito.jsrender(session, DOM.div(area, fit; class = "ne-game-slot"))
end

"""
    IslandPanel(jp)

How the character is and what the host does, as a column of cards beside the game: its feeling and
moods, the last thing that happened on the island for the first time, the reviewer's surprise and
why, and the host's latest notes. Read again every few seconds while a page shows it.
"""
struct IslandPanel
    jp::JailPaths
end

"""
    TopBar(jp)

The page's title, the character's live status (what it is doing, its session, its feeling, its
thought bubble) and the links to its blog and to the game's repository.
"""
struct TopBar
    jp::JailPaths
end

"What the panel and the bar show, from the files the host keeps for the game and its mood."
function island_state(jp::JailPaths)
    view = read_json(joinpath(jp.run, "mood.json"))
    m = load_mood(jp)
    feed = isfile(joinpath(jp.run, "activity.json")) ? read_json(joinpath(jp.run, "activity.json")) : Any[]
    agent = isfile(joinpath(jp.run, "agent.json")) ? read_json(joinpath(jp.run, "agent.json")) : Dict{String,Any}()
    thought_file = joinpath(jp.world, "state", "thought.json")
    thought = isfile(thought_file) ? string(get(read_json(thought_file), "text", "")) : ""
    cfg = load_config(jp)
    return (; name = character_name(jp), feeling = string(view["feeling"]),
            moods = [k => Float64(view[k]) for k in ("joy", "boredom", "loneliness")],
            new = get(m, "last_new", nothing), surprise = get(m, "last_surprise", nothing),
            repetition = get(m, "last_repetition", nothing), ideas = last_ideas_log(jp),
            notes = last([a for a in feed if get(a, "kind", "") in ("host", "review")], 4),
            state = string(get(agent, "state", "off")), current = get(agent, "current", nothing), thought,
            blog = isempty(cfg.blog_repo) ? "" : pages_url(cfg.blog_repo),
            repo = isempty(cfg.game_repo) ? "" : "https://github.com/$(cfg.game_repo)", port = cfg.web_port)
end

"The latest session's rounds of ideas: how many passed the critic, and those (or the strongest)."
ideas_body(::Nothing) = [DOM.div("no ideas pitched yet"; class = "ne-muted")]
function ideas_body(log::AbstractDict)
    isempty(log["rounds"]) && return [DOM.div("session $(log["session"]): no round yet"; class = "ne-muted")]
    ideas = last(log["rounds"])["ideas"]
    passed = filter(i -> i["passes"], ideas)
    shown = isempty(passed) ? [argmax(strength, ideas)] : passed
    return [DOM.div(DOM.span(string(length(passed)); class = "ne-score"),
                    DOM.span(" of $(length(ideas)) passed · round $(length(log["rounds"])) of $IDEA_ROUNDS · session $(log["session"])";
                             class = "ne-muted")),
            (DOM.div("“$(i["title"])”, surprise $(i["surprise"]), fun $(get(i, "fun", "–")): $(i["critique"])"; class = "ne-quote") for i in shown)...]
end

"A label and a bar from 0 to 1."
mood_bar(label, v) = DOM.div(DOM.span(label; class = "ne-bar-label"),
                             DOM.span(DOM.span(; class = "ne-bar-fill", style = "width:$(round(Int, 100v))%");
                                      class = "ne-bar"); class = "ne-bar-row")

card(title, body...) = DOM.div(DOM.div(title; class = "ne-card-title"), body...; class = "ne-card")

function island_dom(s)
    new = s.new === nothing ? [DOM.div("nothing yet"; class = "ne-muted")] :
        [DOM.div((DOM.span(k; class = "ne-chip") for k in first(s.new["kinds"], 6))...; class = "ne-chips"),
         DOM.div("session $(s.new["session"])"; class = "ne-muted")]
    surprise = s.surprise === nothing ? [DOM.div("not scored yet"; class = "ne-muted")] :
        [DOM.div(DOM.span(string(s.surprise["score"]); class = "ne-score"), DOM.span(" / 10 · fun $(get(s.surprise, "fun", "–")) · session $(s.surprise["session"])";
                 class = "ne-muted")), DOM.div(s.surprise["why"]; class = "ne-quote")]
    rp = s.repetition
    repetition = rp === nothing ? [DOM.div("not judged yet"; class = "ne-muted")] :
        [DOM.div(DOM.span(string(rp["score"]); class = "ne-score"),
                 DOM.span(" / 10 · session $(rp["session"])" * (rp["factor"] < 1 ? @sprintf(" · worth ×%.2f", rp["factor"]) : "");
                          class = "ne-muted")),
         DOM.div(isempty(rp["post"]) ? "nothing posted" : "“$(rp["post"])” like “$(rp["nearest"])”: $(rp["shared"])" *
                 (isempty(get(rp, "form", "")) ? "" : " · its form, “$(rp["form"])”, in $(rp["form_count"]) of the last $FORM_MEMORY");
                 class = "ne-quote")]
    notes = [DOM.div(DOM.span(first(string(get(a, "time", "")), 16)[12:end]; class = "ne-note-time"), " ",
                     string(get(a, "text", "")); class = "ne-note") for a in reverse(s.notes)]
    return DOM.div(
        card("How $(s.name) feels", DOM.div(s.feeling; class = "ne-feeling"), (mood_bar(k, v) for (k, v) in s.moods)...),
        card("New on the island", new...),
        card("The reviewer's surprise", surprise...),
        card("Doing the same again", repetition...),
        card("Ideas and the critic", ideas_body(s.ideas)...),
        card("The host", notes...); class = "ne-cards")
end

function topbar_dom(s)
    cur = s.current
    status = cur === nothing ? s.state : "$(s.state) · $(cur["label"]) · $(round(Int, cur["minutes"])) min"
    links = filter(!isnothing, [DOM.a("Full game"; href = "#", target = "_blank", class = "ne-full-game",
                                      onclick = js"event => { event.target.href = location.protocol + '//' + location.hostname + ':' + $(s.port) + '/'; }"),
                                isempty(s.blog) ? nothing : DOM.a("Blog"; href = s.blog, target = "_blank"),
                                isempty(s.repo) ? nothing : DOM.a("GitHub"; href = s.repo, target = "_blank")])
    return DOM.div(
        DOM.div(DOM.span("The Never Ending Game"; class = "ne-title"),
                DOM.span("an experiment in how creative an AI can be"; class = "ne-subtitle"); class = "ne-brand"),
        DOM.div(DOM.span("●"; class = "ne-dot ne-dot-$(s.state)"), DOM.b(s.name), " · ", status, " · feels ", s.feeling,
                isempty(s.thought) ? "" : DOM.span(" “$(s.thought)”"; class = "ne-thought"); class = "ne-status"),
        DOM.div(links...; class = "ne-links"); class = "ne-topbar")
end

"A part of the page that shows `f(island_state(jp))`, read again every few seconds."
function live_part(session::Bonito.Session, jp::JailPaths, f)
    state = Observable(island_state(jp))
    errormonitor(@async while isopen(session)
        sleep(5)
        state[] = island_state(jp)
    end)
    return Bonito.jsrender(session, map(f, session, state))
end

Bonito.jsrender(session::Bonito.Session, p::IslandPanel) = live_part(session, p.jp, island_dom)
Bonito.jsrender(session::Bonito.Session, b::TopBar) = live_part(session, b.jp, topbar_dom)

"Warm paper around the game's night, the character's gold for what is alive."
const DASHBOARD_STYLE = Bonito.Styles(
    Bonito.CSS(".ne-layout", "display" => "flex", "flex-direction" => "column", "height" => "100%", "min-height" => "0",
               "background" => "#f4f1ea", "color" => "#1f2328", "font-family" => "system-ui, sans-serif"),
    Bonito.CSS(".ne-topbar", "display" => "flex", "align-items" => "center", "gap" => "28px", "padding" => "12px 22px",
               "background" => "#fffdf8", "border-bottom" => "1px solid #e6e0d4"),
    Bonito.CSS(".ne-brand", "display" => "flex", "flex-direction" => "column", "line-height" => "1.2"),
    Bonito.CSS(".ne-title", "font-weight" => "750", "font-size" => "18px", "letter-spacing" => "-.01em"),
    Bonito.CSS(".ne-subtitle", "font-size" => "12px", "color" => "#7a746a"),
    Bonito.CSS(".ne-status", "flex" => "1", "min-width" => "0", "font-size" => "14px", "white-space" => "nowrap",
               "overflow" => "hidden", "text-overflow" => "ellipsis", "color" => "#4b4f56"),
    Bonito.CSS(".ne-status b", "color" => "#1f2328"),
    Bonito.CSS(".ne-thought", "font-style" => "italic", "color" => "#a36b00"),
    Bonito.CSS(".ne-dot", "margin-right" => "6px", "color" => "#b8b2a6"),
    Bonito.CSS(".ne-dot-working", "color" => "#22a05a"),
    Bonito.CSS(".ne-links", "display" => "flex", "gap" => "8px"),
    Bonito.CSS(".ne-links a", "color" => "#1f2328", "text-decoration" => "none", "background" => "#f4f1ea",
               "border" => "1px solid #e0d9cb", "padding" => "5px 12px", "border-radius" => "999px", "font-size" => "13px"),
    Bonito.CSS(".ne-links a:hover", "background" => "#ece6d8"),
    Bonito.CSS(".ne-main", "flex" => "1", "display" => "flex", "gap" => "18px", "padding" => "18px", "min-height" => "0"),
    Bonito.CSS(".ne-game-slot", "flex" => "1 1 0", "min-width" => "0", "display" => "flex"),
    Bonito.CSS(".ne-game-area", "flex" => "1 1 0", "min-width" => "0", "display" => "flex", "justify-content" => "center",
               "align-items" => "flex-start"),
    Bonito.CSS(".ne-game-card", "flex" => "0 0 auto", "border-radius" => "14px", "overflow" => "hidden",
               "background" => "#0b0d10", "box-shadow" => "0 6px 24px rgba(40,30,10,.18)"),
    Bonito.CSS(".ne-game", "border" => "0", "display" => "block", "width" => "100%", "height" => "100%"),
    Bonito.CSS(".ne-island", "flex" => "0 0 250px", "min-height" => "0", "overflow-y" => "auto"),
    Bonito.CSS(".ne-cards", "display" => "flex", "flex-direction" => "column", "gap" => "12px"),
    Bonito.CSS(".ne-card", "background" => "#fffdf8", "border" => "1px solid #e6e0d4", "border-radius" => "14px",
               "padding" => "14px 16px", "font-size" => "13px", "line-height" => "1.45"),
    Bonito.CSS(".ne-card-title", "font-size" => "11px", "font-weight" => "600", "text-transform" => "uppercase",
               "letter-spacing" => ".07em", "color" => "#8a8377", "margin-bottom" => "10px"),
    Bonito.CSS(".ne-feeling", "font-size" => "22px", "font-weight" => "650", "margin-bottom" => "10px"),
    Bonito.CSS(".ne-bar-row", "display" => "flex", "align-items" => "center", "justify-content" => "space-between",
               "gap" => "10px", "margin" => "5px 0"),
    Bonito.CSS(".ne-bar-label", "color" => "#4b4f56"),
    Bonito.CSS(".ne-bar", "display" => "inline-block", "flex" => "0 0 55%", "height" => "8px", "background" => "#ece6d8",
               "border-radius" => "4px", "overflow" => "hidden"),
    Bonito.CSS(".ne-bar-fill", "display" => "block", "height" => "100%", "background" => "#e0a526", "border-radius" => "4px"),
    Bonito.CSS(".ne-chips", "display" => "flex", "flex-wrap" => "wrap", "gap" => "6px", "margin-bottom" => "8px"),
    Bonito.CSS(".ne-chip", "background" => "#fbefd2", "color" => "#7a5300", "border-radius" => "999px",
               "padding" => "3px 10px", "font-size" => "12px"),
    Bonito.CSS(".ne-score", "font-size" => "30px", "font-weight" => "750"),
    Bonito.CSS(".ne-quote", "color" => "#4b4f56", "font-style" => "italic", "margin-top" => "6px", "display" => "-webkit-box",
               "-webkit-line-clamp" => "4", "-webkit-box-orient" => "vertical", "overflow" => "hidden"),
    Bonito.CSS(".ne-muted", "color" => "#8a8377"),
    Bonito.CSS(".ne-note", "margin" => "4px 0", "color" => "#4b4f56", "display" => "-webkit-box",
               "-webkit-line-clamp" => "2", "-webkit-box-orient" => "vertical", "overflow" => "hidden"),
    Bonito.CSS(".ne-note-time", "color" => "#a39c90", "font-variant-numeric" => "tabular-nums"),
    Bonito.CSS(".ne-chat", "flex" => "0 0 400px", "display" => "flex", "flex-direction" => "column", "min-height" => "0",
               "background" => "#fffdf8", "border" => "1px solid #e6e0d4", "border-radius" => "14px", "overflow" => "hidden"),
    # the host drives the turns: BonitoAgents' own auto-continue would fight it
    Bonito.CSS(".ne-chat .bt-yolo-bar", "display" => "none"),
    Bonito.CSS(".ne-chat-head", "padding" => "14px 18px 12px", "border-bottom" => "1px solid #eee8dc"),
    Bonito.CSS(".ne-chat-title", "font-weight" => "700", "font-size" => "16px"),
    Bonito.CSS(".ne-chat-sub", "font-size" => "12px", "color" => "#8a8377", "margin-top" => "2px"))

"""
    dashboard_layout(jp, chat...)

The page: the top bar, then the game, the island's cards and the character's chat (`chat`, its
widgets, under "Talk to ...") side by side.
"""
function dashboard_layout(jp::JailPaths, chat...)
    name = character_name(jp)
    island = DOM.div(IslandPanel(jp); class = "ne-island")
    head = DOM.div(DOM.div("Talk to $name"; class = "ne-chat-title"),
                   DOM.div("$name reads what you write here between its steps."; class = "ne-chat-sub"); class = "ne-chat-head")
    return DOM.div(DASHBOARD_STYLE, TopBar(jp),
                   DOM.div(GameView(load_config(jp).web_port), island, DOM.div(head, chat...; class = "ne-chat"); class = "ne-main");
                   class = "ne-layout")
end

"The pane: the game, and the character's chat beside it (without the session pickers: the host sets those)."
BonitoAgents.chat_pane(g::NeverendingGame, view) =
    dashboard_layout(g.jp, BonitoAgents.ChatNotice(view), BonitoAgents.ChatTranscript(view), BonitoAgents.ChatComposer(view))

# ── standalone ──────────────────────────────────────────────────────────────

"The standalone page: what BonitoAgents' own page mounts around a chat (its stylesheets), full height."
const PAGE_STYLE = Bonito.Styles(
    Bonito.CSS("html, body", "margin" => "0", "height" => "100%"),
    Bonito.CSS(".ne-page", "height" => "100vh", "display" => "flex", "flex-direction" => "column"),
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
        # the chat of an earlier run, brought up again; in its own task: called from the task that
        # serves this dashboard it never finished, while from another one it takes seconds
        errormonitor(@async BonitoAgents.ensure_project_session!(server, chat))
    end
    # as the host's sessions run: its model, no permission prompts (the jail is the limit). The agent
    # starts at the chat's first turn, which asserts these.
    model = load_config(jp).agent.model
    isempty(model) || (chat.desired_config["model"] = model)
    chat.desired_config["mode"] = "bypassPermissions"
    @lock server.lock BonitoAgents.save_projects!(server)
    t0 = time()
    while !haskey(server.chat_models, chat.id)
        time() - t0 < timeout || error("the character's chat did not come up in $(timeout) s")
        sleep(0.5)
    end
    page[] = standalone_page(server.chat_models[chat.id])
    return (; server, srv, worker, game, chat)
end
