# ── The dashboard: Makie GUI blocks on a RayMakie raster screen ─────────────
#
# Left: the live game and the controls (play a mini game, jump in, camera,
# tell the agent something). Right: what the agent is doing, how Lumi feels, the
# todo list, the agent's messages, and the panels plugins add. The host's
# status files come in read only at `/run/neverending` (NEVERENDING_RUN).

const UI_BG = RGBf(0.085, 0.09, 0.11)
const UI_PANEL = RGBf(0.13, 0.14, 0.17)
const UI_TEXT = RGBf(0.93, 0.94, 0.96)
const UI_DIM = RGBf(0.66, 0.70, 0.76)
const UI_ACCENT = RGBf(0.98, 0.78, 0.35)
const UI_BUTTON = RGBf(0.165, 0.18, 0.21)
const UI_BUTTON_HOVER = RGBf(0.22, 0.24, 0.28)
const UI_BORDER = RGBf(0.29, 0.31, 0.35)
const UI_DARK_TEXT = RGBf(0.1, 0.1, 0.1)
const UI_FONTSIZE = 15
const UI_SIDE_WIDTH = 390

mutable struct Dashboard
    fig::Figure
    view::LScene
    agent::Label
    activity::Label
    mood::Label
    todos::Label
    messages::Label
    status::Label
    play_menu::Menu
    play_button::Button
    tell_box::Textbox
    panels::GridLayout
    plugin_panels::Vector{Panel}
end

"Where the host's status files are: /run/neverending in the jail, .jail/run outside."
host_run_dir(p::GamePaths) = get(ENV, "NEVERENDING_RUN", joinpath(p.root, ".jail", "run"))

function host_json(p::GamePaths, name::AbstractString)
    path = joinpath(host_run_dir(p), name)
    isfile(path) || return nothing
    text = read(path, String)
    isempty(text) && return nothing
    return JSON.parse(text; dicttype = Dict{String,Any})
end

# Text is wrapped by `wrap_text` (Makie centers word-wrapped labels whatever `halign` says).
ui_label(pos, text; kw...) = Label(pos, text; fontsize = UI_FONTSIZE, color = UI_TEXT, halign = :left,
                                   justification = :left, tellwidth = false, kw...)
ui_header(pos, text) = Label(pos, text; fontsize = 18, font = :bold, color = UI_ACCENT, halign = :left, tellwidth = false)

ui_button(pos, label; accent = false, kw...) =
    Button(pos; label, fontsize = UI_FONTSIZE, cornerradius = 4, strokewidth = 1, strokecolor = UI_BORDER,
           buttoncolor = accent ? UI_ACCENT : UI_BUTTON, buttoncolor_hover = accent ? RGBf(1.0, 0.85, 0.5) : UI_BUTTON_HOVER,
           buttoncolor_active = accent ? RGBf(0.9, 0.7, 0.3) : UI_BORDER,
           labelcolor = accent ? UI_DARK_TEXT : UI_TEXT, labelcolor_hover = accent ? UI_DARK_TEXT : UI_TEXT,
           labelcolor_active = accent ? UI_DARK_TEXT : UI_TEXT, kw...)

ui_menu(pos, options; kw...) =
    Menu(pos; options, fontsize = UI_FONTSIZE, textcolor = UI_TEXT, dropdown_arrow_color = UI_TEXT,
         cell_color_inactive_even = UI_BUTTON, cell_color_inactive_odd = UI_BUTTON, cell_color_hover = UI_BUTTON_HOVER,
         cell_color_active = UI_BORDER, selection_cell_color_inactive = UI_BUTTON, kw...)

"""
    build_dashboard!(g, size; window = false)

The dashboard figure and its RayMakie screen (raster until switched, see
`set_path_tracing!`). `window`: a real window on this machine's display;
otherwise offscreen (screenshots, tests). Browsers draw the same figure with
WGLMakie (web.jl).
"""
function build_dashboard!(g::Game, size::Tuple{Int,Int}; window::Bool = false)
    fig = Figure(; size, backgroundcolor = UI_BG, figure_padding = 8)
    w = g.world
    view = LScene(fig[1, 1]; show_axis = false, scenekw = (lights = stage_lights(w),))
    g.stage = Stage(view.scene, w)
    controls = fig[2, 1] = GridLayout(; tellwidth = false, halign = :left)
    play_menu = ui_menu(controls[1, 1], play_options(g); width = 200, prompt = "Mini game", default = nothing)
    play_button = ui_button(controls[1, 2], "Play"; accent = true, width = 70)
    cam_menu = ui_menu(controls[1, 3], ["Camera: follow", "Camera: orbit", "Camera: free"]; width = 160)
    tell_box = Textbox(controls[1, 4]; placeholder = "Wish…", width = size[1] - UI_SIDE_WIDTH - 760,
                       fontsize = UI_FONTSIZE, textcolor = UI_TEXT, textcolor_placeholder = UI_DIM,
                       boxcolor = UI_BUTTON, boxcolor_focused = UI_BUTTON_HOVER, boxcolor_hover = UI_BUTTON_HOVER,
                       bordercolor = UI_BORDER, bordercolor_hover = UI_ACCENT, bordercolor_focused = UI_ACCENT,
                       cursorcolor = UI_ACCENT)
    send = ui_button(controls[1, 5], "Send"; accent = true, width = 70)
    trace = ui_button(controls[1, 6], "Path tracing: off"; width = 150)
    colgap!(controls, 10)
    side = fig[0:2, 2] = GridLayout(; valign = :top, halign = :left)
    colsize!(side, 1, Fixed(UI_SIDE_WIDTH))
    colsize!(fig.layout, 2, Fixed(UI_SIDE_WIDTH))
    ui_header(side[1, 1], "Lumi")
    agent = ui_label(side[2, 1], "")
    activity = ui_label(side[3, 1], ""; color = UI_DIM, fontsize = 14)
    mood = ui_label(side[4, 1], "")
    ui_header(side[5, 1], "Messages to you")
    messages = ui_label(side[6, 1], "")
    ui_header(side[7, 1], "Things to try")
    todos = ui_label(side[8, 1], "")
    panels = side[9, 1] = GridLayout()
    rowgap!(side, 6)
    status = Label(fig[0, 1], ""; fontsize = UI_FONTSIZE, color = UI_DIM, halign = :left, tellwidth = false)
    # the view sits right on the controls; this relayout also clears the black strip the raster
    # left above the view (perfectionist-0027: "a black strip sits above the 3D view in every screenshot")
    rowgap!(fig.layout, 1, Fixed(2))   # after row 1 (the view); rows start at 0
    d = Dashboard(fig, view, agent, activity, mood, todos, messages, status, play_menu, play_button, tell_box,
                  panels, Panel[])
    g.dash = d
    # callbacks only queue work for the game loop (see `later!`)
    on(_ -> later!(g, () -> g.minigame === nothing ? start_selected!(g) : stop_minigame!(g)), play_button.clicks)
    on(cam_menu.selection) do s
        s === nothing || later!(g, () -> set_camera!(g, s))
    end
    # decided at the press: a wish typed by `interact!` (a test) goes to the tests' inbox, not the agent's
    on(_ -> (test = g.driven > 0; later!(g, () -> send_wish!(g; test))), tell_box.stored_string)
    on(_ -> (test = g.driven > 0; later!(g, () -> send_wish!(g; test))), send.clicks)
    on(_ -> later!(g, () -> set_path_tracing!(g, g.screen.rasterize)), trace.clicks)
    # any input `interact!` did not make is the human's: UI tests wait until they leave the dashboard alone
    e = Makie.events(fig)
    for obs in (e.mousebutton, e.keyboardbutton, e.scroll, e.mouseposition)
        on(_ -> (g.driven == 0 && (g.human_input = time()); nothing), obs)
    end
    # keys reach the game the same way from the window and from browsers
    on(ev -> later!(g, () -> key_to_game!(g, ev)), Makie.events(fig).keyboardbutton)
    build_plugin_panels!(g)
    if window
        g.screen = RayMakie.Screen(fig.scene; visible = true, rasterize = true, exposure = FILM_EXPOSURE,
                                   title = "The Neverending Game")
        display(g.screen, fig.scene)
        keep_window_on_escape!(g.screen, fig.scene)
    else
        g.screen = RayMakie.Screen(fig.scene; visible = false, rasterize = true, exposure = FILM_EXPOSURE)
    end
    update_dashboard!(g)
    return d
end

"""
RayMakie's window closes on Escape (a viewer convenience). In a game Escape is
a key like any other, so the window's key callback is replaced by one that only
reports keys.
"""
function keep_window_on_escape!(screen, scene::Scene)
    G = RayMakie.GLFW
    e = Makie.events(scene)
    G.SetKeyCallback(screen.window.handle, (_, key, _scancode, action, _mods) ->
        (e.keyboardbutton[] = Makie.KeyEvent(Makie.Keyboard.Button(Int(key)), Makie.Keyboard.Action(Int(action)))))
    return nothing
end

"""
    set_path_tracing!(game, on)

RayMakie's screen of the game: path traced (progressive) or raster. Only this
machine's RayMakie screen changes; browsers draw with WGLMakie.
"""
function set_path_tracing!(g::Game, on::Bool)
    # Switching off always rebuilds every plot: a switch that failed half way (the GPU
    # ran out of memory dropping the glowing plots) left the screen saying "raster"
    # with plots still traced, and `setrasterize!` returns early when the flag matches.
    on || (g.screen.rasterize = false)
    RayMakie.setrasterize!(g.screen, !on)
    b = only(filter(b -> b isa Button && startswith(string(b.label[]), "Path tracing"), g.dash.fig.content))
    b.label[] = on ? "Path tracing: on" : "Path tracing: off"
    log_event!(g.log, g.world.t, :path_tracing; on)
    return on
end

"""
    path_traced(game) -> Bool

The game's screen is path tracing. Plugins hold glowing (Hikari `Emission`) plots
still then: Hikari makes area lights of every glowing mesh pushed, each move
pushes them again and the old lights are not freed, so moving motes ran the GPU
out of memory in seconds (and a progressive trace restarts on every move anyway).
"""
path_traced(g::Game) = g.screen !== nothing && !g.screen.rasterize

"""
The camera the player picked in the menu: `:follow`, `:orbit` or `:free`. Outside games it is
the camera's mode; during a game the menu keeps the pick, so a game's camera can honour it.
"""
function camera_pick(g::Game)
    s = only(b for b in g.dash.fig.content if b isa Menu && "Camera: follow" in b.options[]).selection[]
    return s == "Camera: orbit" ? :orbit : s == "Camera: free" ? :free : :follow
end

function set_camera!(g::Game, choice::AbstractString)
    g.rig.mode = choice == "Camera: follow" ? :follow : choice == "Camera: orbit" ? :orbit : :fixed
end

"""
Send what is in the wish box (Enter or the Send button) and clear the box. The
box's current text is its editor's, submitted or not. It goes to the agent's
inbox, or with `test` (typed by `interact!`) to `world/tests/inbox`, where
tests look for it and the agent never reads it.
"""
function send_wish!(g::Game; test::Bool = false)
    tb = g.dash.tell_box
    text = strip(tb.editor.arg1[])
    isempty(text) && return
    tell_agent(g.paths, text; inbox = test ? test_inbox(g.paths) : agent_inbox(g.paths))
    test || log_event!(g.log, g.world.t, :wish; text)
    # not Makie.reset!: it stores the function `string` as the text
    tb.editor.arg1 = ""
    tb.stored_string = nothing
    tb.focused = false
    return text
end

agent_inbox(p::GamePaths) = joinpath(p.world, "inbox")
test_inbox(p::GamePaths) = joinpath(p.world, "tests", "inbox")

"Write a message from the human into the agent's inbox (the host delivers it)."
function tell_agent(p::GamePaths, text::AbstractString; from::AbstractString = "human (dashboard)",
                    inbox::AbstractString = agent_inbox(p))
    dir = inbox
    mkpath(dir)
    name = Dates.format(Dates.now(), "yyyymmdd-HHMMSS-sss") * ".json"
    write_json(joinpath(dir, name), Dict("from" => from, "time" => string(Dates.now()), "text" => String(text)))
    return name
end

# invokelatest: a plugin reload defines the title in a newer world than the running frame (else the menu shows the type name)
play_options(g::Game) = [Base.invokelatest(game_title, T) for T in minigame_types(g)]

function clear_layout!(gl::GridLayout)
    for c in copy(Makie.contents(gl))
        if c isa GridLayout       # remove_from_gridlayout! takes the GridContent, not the layout (the plugin-load crashes, #180)
            clear_layout!(c)
            gc = Makie.GridLayoutBase.gridcontent(c)
            gc === nothing || Makie.GridLayoutBase.remove_from_gridlayout!(gc)
        else
            delete!(c)
        end
    end
    Makie.trim!(gl)
end

function build_plugin_panels!(g::Game)
    d = g.dash
    clear_layout!(d.panels)
    empty!(d.plugin_panels)
    row = 1
    for (name, p) in sort!(collect(g.plugins); by = first), panel in p.panels
        ui_header(d.panels[row, 1], Base.invokelatest(panel_title, panel))   # a plugin's method (newer world)
        sub = d.panels[row + 1, 1] = GridLayout()
        try
            Base.invokelatest(build_panel!, panel, sub, g)
            push!(d.plugin_panels, panel)
        catch e
            e isa InterruptException && rethrow()
            clear_layout!(sub)
            report_problem!(g, "Panel $(Base.invokelatest(panel_title, panel)) of plugin $(name) does not build",
                            sprint(showerror, e, catch_backtrace()))
        end
        row += 2
    end
end

function dashboard_plugins_changed!(g::Game)
    g.dash.play_menu.options[] = play_options(g)
    build_plugin_panels!(g)
end


"Break `s` into lines of at most `n` characters at spaces, at most `maxlines` lines."
function wrap_text(s::AbstractString, n::Int; maxlines::Int = 6)
    lines = String[]
    for para in split(strip(replace(s, '…' => "")), '\n')   # quoted text may hold '…': keep the panel ellipsis-free
        line = ""
        for word in split(para)
            if isempty(line)
                line = String(word)
            elseif length(line) + 1 + length(word) <= n
                line *= " " * word
            else
                push!(lines, line)
                line = String(word)
            end
        end
        push!(lines, line)
    end
    if length(lines) > maxlines
        # s132 (perfectionist-0130: panels ended in "U throw up into", "so it"): too long, so end at the last whole
        # sentence that fits, else at the last clause (; or ,) closed with a full stop; never mid-phrase, never "…"
        cut = whole_cut(s, n, maxlines)
        cut === nothing || return cut
        lines = lines[1:maxlines]
    end
    return join((length(l) > n ? first(l, n) : l for l in lines), "\n")
end

"The longest whole-sentence (or else whole-clause) beginning of `s` that wraps into `maxlines` lines, or nothing."
function whole_cut(s::AbstractString, n::Int, maxlines::Int)
    fits(t) = count(==('\n'), wrap_text(t, n; maxlines = typemax(Int))) + 1 <= maxlines
    balanced(t) = count(==('('), t) == count(==(')'), t)
    best = ""
    for (pat, close) in ((r"(?<=[.!?])\s", ""), (r"[;,]\s", "."))
        for m in eachmatch(pat, s)
            e = m.offset
            t = rstrip(s[1:prevind(s, e + (close == "" ? 0 : 1))], [' ', ';', ','])
            t = close == "" ? t : t * close
            !isempty(t) && length(t) > length(best) && balanced(t) && fits(t) && (best = t)
        end
    end
    return isempty(best) ? nothing : wrap_text(best, n; maxlines = typemax(Int))
end
first_line(s::AbstractString) = strip(first(split(strip(s), '\n')))

"How Lumi feels (the host's measure, `mood.json`), in its words and a colour of its own."
const FEELINGS = Dict(
    "lonely"  => ("Nobody has come to play with me for a while. Jump in?", RGBf(0.74, 0.68, 0.98)),
    "annoyed" => ("It still doesn't look right, and it bugs me.", RGBf(0.95, 0.52, 0.4)),
    "bored"   => ("Same old, same old. I need something new to make.", RGBf(0.72, 0.74, 0.78)),
    "proud"   => ("I made something new, and I like it!", RGBf(0.98, 0.78, 0.35)),
    "curious" => ("So much to find out today.", RGBf(0.5, 0.82, 0.98)),
    "content" => ("All is well on my island.", RGBf(0.56, 0.88, 0.5)))
mood_text(::Nothing) = ("", UI_TEXT)
function mood_text(m::AbstractDict)
    f = string(m["feeling"])
    words, color = get(FEELINGS, f, ("", UI_TEXT))
    return ("Feels $f. " * words, color)
end

"What the agent is up to, in one line a person understands."
function agent_line(st::AbstractDict)
    cur = st["current"]
    state = st["state"]
    if cur !== nothing
        what = startswith(cur["label"], "perfectionist") ? "walking the whole island with a critical eye" :
               cur["role"] == "review" ? "looking over the newest things" :
               cur["role"] == "test" ? "trying out the newest things" : "building something new"
        return @sprintf("● %s · %.0f min · %d steps", what, cur["minutes"], cur["tools"])
    end
    state == "idle" && return "○ resting between work sessions"
    state == "waking" && return "○ waking up: looking round the garden"
    state == "publishing" && return "● bringing the session's work into this game"
    state == "paused" && return "○ paused by the human"
    state == "waiting_budget" && return "○ waiting for budget: " * st["detail"]
    state == "waiting_auth" && return "○ waiting for the human's Claude login to be refreshed"
    state == "no_auth" && return "⚠ cannot start: " * st["detail"]
    state == "error" && return "⚠ " * st["detail"]
    state == "off" && return "○ not running"
    return "○ " * get(Dict("testing" => "trying out the newest things", "reviewing" => "looking over the newest things",
                           "working" => "building something new"), state, "resting")
end

"Drop what only a developer reads: code spans, file paths, tool counts, stop reasons."
function plain_text(s::AbstractString)
    s = replace(s, r"`[^`]*`" => "", r"\(?[^\s()]*(end_turn|tool calls?)[^()]*\)?" => "", r"\s+" => " ")
    s = replace(strip(s), r"\s+([,.;:])" => s"\1")
    return s
end

"Activity a person can follow: what the agent said, sessions starting and ending, review verdicts."
activity_line(a::AbstractDict) =
    a["kind"] == "say" ? plain_text(first_line(a["text"])) :
    nothing

"""
What Lumi works towards, for the side panel: the big goal's title, how many steps of its road are
done, and the next open one; empty while there is no big goal with a road (`world/BIG_GOAL.md`,
written by the host once a critic passed it).
"""
function big_goal_line(p::GamePaths)
    path = joinpath(p.world, "BIG_GOAL.md")
    isfile(path) || return ""
    text = read(path, String)
    title = match(r"^# (.+)$"m, text)
    steps = [(m[1] != " ", strip(m[2])) for m in eachmatch(r"^\s*[-*] \[([ xX])\] (.+)$"m, text)]
    (title === nothing || isempty(steps)) && return ""
    next = findfirst(s -> !first(s), steps)
    return "Working towards: $(strip(title[1])) ($(count(first, steps)) of $(length(steps)) steps)" *
           (next === nothing ? "" : "\nNext: " * last(steps[next]))
end

"A todo's title as a player reads it: the part before the first colon or parenthesis."
player_title(s::AbstractString) = strip(first(split(s, r"[:(]"; limit = 2)))

"What a player got last: the title of the newest finished todo a player can see (not dev work), or empty."
function last_built(p::GamePaths)
    path = todos_file(p)
    isfile(path) || return ""
    done = filter(t -> t.status === :done && player_facing(t), load_todos(path))
    isempty(done) && return ""
    return player_title(last(sort!(done; by = t -> t.updated)).title)
end

"Todo kinds a player would care about; :fix, :build and :review are dev work."
const PLAYER_KINDS = (:look, :motion, :world, :feature, :explore, :user)

"A todo a player would want to read about: a player kind, and no dev chore (source files, self checks)."
player_facing(t) = t.kind in PLAYER_KINDS && t.source !== :review && !occursin(r"\.jl\b|^\s*(verify|check|test|perfectionist)\b"i, t.title)

"""
What a player can do, for the side panel: every mini game with the first sentence of
its description, then how to start one. Replaces the agent's todo titles (dev talk).
"""
function things_to_try(g::Game)
    lines = String[]
    for T in minigame_types(g)
        title = replace(string(Base.invokelatest(game_title, T)), r"\s*\(.*\)" => "")
        desc = strip(string(Base.invokelatest(game_description, T)))
        lead = strip(first(split(desc, r"(?<=[.!?])\s+"; limit = 2)))
        text = isempty(lead) ? title : "$(title): $(lead)"
        push!(lines, "· " * replace(wrap_text(text, 48; maxlines = 3), "\n" => "\n  "))
    end
    push!(lines, "Pick one under Mini game, then press Play.")
    return join(lines, "\n")
end

function update_dashboard!(g::Game)
    d = g.dash
    p = g.paths
    w = g.world
    frame_ms = pctl(get(g.clock.parts, "frame", Float64[]), 0.5)
    fps = frame_ms > 0 ? min(g.fps, 1000 / frame_ms) : 0.0
    hour = floor(Int, 24daytime(w))
    d.status.text[] = @sprintf("%02d:%02d on the island   ·   %d creatures   ·   %.0f fps   ·   %s",
                               hour, floor(Int, 60(24daytime(w) - hour)), length(w.creatures), fps,
                               g.minigame === nothing ? "watching" : "playing: " * game_title(typeof(g.minigame)))
    words, color = mood_text(host_json(p, "mood.json"))
    d.mood.text[] = wrap_text(words, 46; maxlines = 3)
    d.mood.color[] = color
    st = host_json(p, "agent.json")
    if st === nothing
        d.agent.text[] = "○ no agent connected"
        d.messages.text[] = "No messages yet."
    else
        d.agent.text[] = wrap_text(agent_line(st), 46; maxlines = 3)
        msgs = st["outbox"]
        d.messages.text[] = isempty(msgs) ? "No messages yet." :
            join([wrap_text(string(m["text"]), 46; maxlines = 5) for m in last(msgs, 1)], "\n\n")
    end
    d.messages.color[] = st === nothing || isempty(st["outbox"]) ? UI_DIM : UI_TEXT
    # the agent's running commentary is developer talk: the player sees what was last built
    built = last_built(p)
    goal = big_goal_line(p)
    d.activity.text[] = join(filter(!isempty, [isempty(goal) ? "" : wrap_text(goal, 52; maxlines = 4),
                                               isempty(built) ? "" : wrap_text("New on the island: " * built, 52; maxlines = 2)]), "\n")
    d.todos.text[] = things_to_try(g)     # the agent's todo list is dev talk (perfectionist-0027): the player sees what to play
    d.todos.color[] = UI_TEXT
    for panel in copy(d.plugin_panels)
        try
            Base.invokelatest(update_panel!, panel, g)
        catch e
            e isa InterruptException && rethrow()
            filter!(x -> x !== panel, d.plugin_panels)
            report_problem!(g, "Panel $(panel_title(panel)) failed in update_panel! and was switched off",
                            sprint(showerror, e, catch_backtrace()))
        end
    end
end
