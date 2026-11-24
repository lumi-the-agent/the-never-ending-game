# ── Paths and configuration ──────────────────────────────────────────────────
#
#   <root>/                     the game folder and Julia environment
#   <root>/world/               the game itself; the agent works here (its cwd)
#   <root>/dev/NeverendingGame  the engine, writable by the agent
#   <root>/dev/*                every other checkout, read only in the jail
#   <root>/.jail/               the host's own state, invisible in the jail
#       config.toml             providers, budget, network (edit this, not code)
#       home-<role>/            HOME of each jailed role, mounted at the real HOME path
#       depot/                  writable first entry of JULIA_DEPOT_PATH (shared)
#       run/                    proxy sockets and status files, read only at /run/neverending
#       logs/                   output of every jailed process
#       romeodb/                RomeoDB index
#       secrets/env/<NAME>      becomes environment variable NAME of agent sessions

"Where the jail sees the host's run directory."
const JAIL_RUN = "/run/neverending"

"The jailed roles. Each has its own HOME, so the reviewer never sees the implementer's transcripts."
const ROLES = (:game, :worker, :agent, :review)

struct JailPaths
    root::String
    world::String
    state::String
    depot::String
    run::String
    logs::String
    romeodb::String
    secrets::String
    user_home::String       # the real HOME; each role's home is mounted there
end

function JailPaths(root::AbstractString; user_home::AbstractString = homedir())
    root = abspath(root)
    st = joinpath(root, ".jail")
    jp = JailPaths(root, joinpath(root, "world"), st, joinpath(st, "depot"), joinpath(st, "run"),
                   joinpath(st, "logs"), joinpath(st, "romeodb"), joinpath(st, "secrets"), String(user_home))
    for d in (jp.world, jp.depot, jp.run, jp.logs, jp.romeodb, joinpath(jp.secrets, "env"))
        mkpath(d)
    end
    foreach(r -> mkpath(home(jp, r)), ROLES)
    chmod(jp.secrets, 0o700)
    return jp
end

home(jp::JailPaths, role::Symbol) = joinpath(jp.state, "home-$(role)")

const DEFAULT_CONFIG = """
# The Neverending Game host. Read again before every session, so edits take
# effect without a restart.

[agent]
# Any AgentProviders name: ClaudeCode, Codex, OpenCode, KimiCode, MiMoCode.
provider = "ClaudeCode"
# Empty: the provider's default. ClaudeCode: "opus", "sonnet", ...; OpenCode: a
# free model such as "opencode/big-pickle" (no key; `opencode models` lists them),
# or "openrouter/<model id>" with OPENROUTER_API_KEY in .jail/secrets/env/.
model = ""
session_minutes = 45
# Seconds between two sessions.
cooldown = 20
# true: finish the running session, start no new one.
pause = false

[review]
# A separate agent judges finished work. It never sees the implementer's
# conversation, only the results; a different model keeps it from sharing
# the implementer's taste.
enabled = true
provider = "ClaudeCode"
model = "sonnet"
session_minutes = 15
# Every this many work sessions a perfectionist review (art director, game
# designer, demanding player) scores the whole game 0-10 per category
# (world/reviews/quality.jsonl); its findings become the author's next todos.
perfectionist_every = 3
perfectionist_minutes = 30
# It sets the direction for the next sessions: worth the builder's model.
perfectionist_model = "opus"

[budget]
# Tokens per rolling 24 hours, all agents together. Counted from Claude Code's
# transcripts: input + cache writes + output + cache reads × cache_read_weight.
# Free models (OpenCode "*-free") do not count. 0: no cap, sessions never wait.
tokens_per_day = 3_000_000
cache_read_weight = 0.1
# Above this fraction a running session is told to wrap up.
low_fraction = 0.85

[github]
# The host publishes for the character after every session, with the token in
# ~/.config/neverending (outside every jail); the character itself never writes
# online. "owner/name" of each repository; empty: not published.
# The character's pages (world/site), served by GitHub Pages.
blog = ""
# The whole game, one commit and tag per session: what people fork.
game = ""
# The commits' author address (the account's GitHub noreply address).
email = ""

[jail]
# "auto": every role runs in a bubblewrap jail where bubblewrap is installed
# (Linux): its own files to write, the network only through the allowlist below.
# "no": roles run as plain processes of this user (macOS, Windows, or Linux
# without bubblewrap): their own HOME, but they can read and write everything
# this user can, and reach any host.
mode = "auto"

[game]
# "auto": the dashboard also opens as a RayMakie window on this machine's
# desktop when one runs (through its X server, XWayland; the game's jail gets
# the X socket and its cookie, nothing else); "yes" / "no" to force. While the
# display sleeps the window is throttled, the game runs on.
window = "auto"
# Browsers draw the same dashboard with WGLMakie at http://<this machine>:web_port
# (the host forwards the port to the game's jail).
web_port = 8790
fps = 30
width = 1280
height = 720
threads = 8

[network]
# Hosts every agent session may reach (port 443 only), on top of its
# provider's. "*.x" matches subdomains.
allow = [
    "pkg.julialang.org", "*.pkg.julialang.org", "storage.julialang.net",
    "github.com", "codeload.github.com", "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
]

[providers.ClaudeCode]
hosts = ["api.anthropic.com"]

[providers.Codex]
hosts = ["api.openai.com", "chatgpt.com", "*.chatgpt.com", "auth.openai.com"]

[providers.OpenCode]
# free models ("opencode/<name>-free", "opencode/big-pickle") need no key; OpenRouter models need
# OPENROUTER_API_KEY in .jail/secrets/env/. OpenCode fetches provider SDKs from npm at runtime.
hosts = ["openrouter.ai", "opencode.ai", "*.opencode.ai", "models.dev", "registry.npmjs.org"]

[providers.KimiCode]
hosts = ["api.moonshot.ai", "api.moonshot.cn", "api.kimi.com"]

[providers.MiMoCode]
hosts = ["api.xiaomimimo.com"]
"""

struct AgentSettings
    provider::String
    model::String
    session_minutes::Float64
end

mutable struct HostConfig
    agent::AgentSettings
    review::AgentSettings
    review_enabled::Bool
    perfectionist::AgentSettings
    perfectionist_every::Int
    cooldown::Float64
    pause::Bool
    tokens_per_day::Union{Nothing,Float64}   # nothing: no daily cap
    cache_read_weight::Float64
    low_fraction::Float64
    window::String
    web_port::Int
    fps::Int
    width::Int
    height::Int
    threads::Int
    allow::Vector{String}
    provider_hosts::Dict{String,Vector{String}}
    blog_repo::String
    game_repo::String
    github_email::String
    jail::Bool                               # roles run jailed (`[jail] mode`, see `jail_mode`)
end

config_path(jp::JailPaths) = joinpath(jp.state, "config.toml")

"`tokens_per_day` from config.toml: 0 means no cap."
daily_cap(t::Real) = t == 0 ? nothing : Float64(t)

function load_config(jp::JailPaths)
    path = config_path(jp)
    isfile(path) || write(path, DEFAULT_CONFIG)
    d = TOML.parsefile(path)
    a, r, b, g = d["agent"], d["review"], d["budget"], d["game"]
    gh = get(d, "github", Dict{String,Any}())
    hosts = Dict{String,Vector{String}}(k => String.(v["hosts"]) for (k, v) in get(d, "providers", Dict()))
    return HostConfig(AgentSettings(a["provider"], a["model"], Float64(a["session_minutes"])),
                      AgentSettings(r["provider"], r["model"], Float64(r["session_minutes"])),
                      Bool(r["enabled"]),
                      AgentSettings(r["provider"], get(r, "perfectionist_model", r["model"]), Float64(r["perfectionist_minutes"])),
                      Int(r["perfectionist_every"]),
                      Float64(a["cooldown"]), Bool(a["pause"]),
                      daily_cap(get(b, "tokens_per_day", 3e6)), Float64(get(b, "cache_read_weight", 0.1)),
                      Float64(b["low_fraction"]),
                      String(get(g, "window", "auto")), Int(get(g, "web_port", 8790)), Int(g["fps"]),
                      Int(g["width"]), Int(g["height"]),
                      Int(g["threads"]),
                      String.(d["network"]["allow"]), hosts,
                      String(get(gh, "blog", "")), String(get(gh, "game", "")), String(get(gh, "email", "")),
                      jail_mode(get(get(d, "jail", Dict{String,Any}()), "mode", "auto")))
end

"""
Whether roles run jailed: `"auto"` where bubblewrap is (Linux), `"yes"` (an error without it)
or `"no"`. Only the jail is Linux specific; the game, its renderer and the agents run anywhere.
"""
function jail_mode(mode::AbstractString)
    available = Sys.islinux() && Sys.which("bwrap") !== nothing
    mode == "no" && return false
    mode == "auto" && return available
    mode == "yes" || error("[jail] mode must be \"auto\", \"yes\" or \"no\", not \"$mode\"")
    available || error("[jail] mode = \"yes\" needs bubblewrap (bwrap), which only Linux has")
    return true
end

"Every host any configured provider needs: sessions of different providers share one proxy and may overlap."
all_hosts(cfg::HostConfig) = unique!(vcat(cfg.allow, values(cfg.provider_hosts)...))

# ── small file helpers (the host never loads game code, so it has its own) ──

function atomic_write(path::AbstractString, content::AbstractString)
    tmp = path * ".tmp"
    write(tmp, content)
    mv(tmp, path; force = true)
    return path
end

write_json(path::AbstractString, x) = atomic_write(path, JSON.json(x; pretty = true))
read_json(path::AbstractString) = JSON.parsefile(path; dicttype = Dict{String,Any})

function append_jsonl(path::AbstractString, x)
    open(path, "a") do io
        println(io, JSON.json(x))
    end
    return nothing
end

"The last `n` lines of a text file, reading only its tail."
function tail_lines(path::AbstractString, n::Int; maxbytes::Int = 64_000)
    isfile(path) || return String[]
    sz = filesize(path)
    data = open(path) do io
        seek(io, max(0, sz - maxbytes))
        read(io, String)
    end
    lines = split(data, '\n'; keepempty = false)
    sz > maxbytes && !isempty(lines) && popfirst!(lines)   # the first line is cut
    return String.(lines[max(1, end - n + 1):end])
end

now_string() = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
