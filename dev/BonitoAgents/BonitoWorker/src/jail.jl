# ── jailed chats (experimental, only when a chat asks) ──────────────────────
#
# A chat whose jail switch is on (the server's session header says
# `"jail" => true`) gets its agent spawned in the Jail package's agent jail
# (`Jail.agent_jail`): the chat's folder to write, a HOME of its own with the
# provider's login and transcripts bound in from the real HOME (so resuming and
# "Continue on" still find them), a Julia depot of its own in front of the
# user's, the network only through an allowlisting proxy, and the worker's relay
# through loopback bridges, so its MCP server and eval workers still reach the
# chat with the tokens this session hands out. The worker's own config (its
# server credential) is hidden; the ACP adapters in it stay readable.
#
# Each session starts its own proxy and bridges, in a short temporary folder
# (unix socket paths are limited), and `close` stops them when it ends. Full on
# Linux with bubblewrap; on macOS and Windows the Jail package's folder rules.

"Where jailed chats keep their HOMEs and their shared Julia depot (outside `config_dir`, which they must not see)."
jail_dir() = joinpath(dirname(config_dir()), "jail")

"Hosts every jailed chat may reach on top of its provider's: Julia's package servers and GitHub downloads."
const JAIL_HOSTS = ["pkg.julialang.org", "*.pkg.julialang.org", "storage.julialang.net", "github.com",
                    "codeload.github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]

"The hosts a provider's agent talks to."
jail_hosts(::AgentProviders.ClaudeCodeAgent) = ["api.anthropic.com"]
jail_hosts(::AgentProviders.CodexAgent) = ["api.openai.com", "chatgpt.com", "*.chatgpt.com", "auth.openai.com"]
jail_hosts(::AgentProviders.OpenCodeAgent) = ["openrouter.ai", "opencode.ai", "*.opencode.ai", "models.dev", "registry.npmjs.org"]
jail_hosts(::AgentProviders.KimiAgent) = ["api.moonshot.ai", "api.moonshot.cn", "api.kimi.com"]
jail_hosts(::AgentProviders.MiMoAgent) = ["api.xiaomimimo.com"]
jail_hosts(::AgentProviders.AgentProvider) = String[]

"Where a provider keeps its login and sessions, below the real HOME: bound into the jail's HOME."
jail_state(::AgentProviders.ClaudeCodeAgent) = [".claude", ".claude.json"]
jail_state(::AgentProviders.CodexAgent) = [".codex"]
jail_state(::AgentProviders.OpenCodeAgent) = [".config/opencode", ".local/share/opencode", ".local/state/opencode"]
jail_state(::AgentProviders.KimiAgent) = [".kimi"]
jail_state(::AgentProviders.AgentProvider) = String[]

"A jailed chat session's own proxy and relay bridges; `close` stops them."
struct JailedSession
    dir::String
    proxy::Jail.HostProxy
    bridges::Vector{Jail.LoopbackBridge}
end

function Base.close(s::JailedSession)
    close(s.proxy)
    foreach(close, s.bridges)
    rm(s.dir; recursive = true, force = true)
    return nothing
end

"The loopback ports of the worker's relay (its websocket and its TCP listener)."
relay_ports(relay::MCPRelay) = [parse(Int, last(split(addr, ':'))) for addr in (WebSockets.server_addr(relay.server), tcp_address(relay))]

"""
    jailed_session(relay, provider) -> JailedSession

The proxy (its provider's hosts and `JAIL_HOSTS`) and the relay bridges of one jailed session.
"""
function jailed_session(relay::MCPRelay, provider)
    dir = mktempdir()
    proxy = Jail.HostProxy(joinpath(dir, "proxy.sock"); allow = vcat(jail_hosts(provider), JAIL_HOSTS))
    bridges = [Jail.LoopbackBridge(port, joinpath(dir, "relay-$(port).sock")) for port in relay_ports(relay)]
    return JailedSession(dir, proxy, bridges)
end

"""
    jail_command(s, cmd; provider, project_id, cwd, env) -> Cmd

`cmd`, the chat's agent, in its jail (see the top of this file), with `env` (the provider's
variables, without the worker's own environment) on top of the jail's clean one.
"""
function jail_command(s::JailedSession, cmd::Cmd; provider, project_id::AbstractString, cwd::AbstractString,
                      env::AbstractDict)
    root = jail_dir()
    home = mkpath(joinpath(root, "homes", project_id))
    full = Jail.full_agent_jail()
    state = filter(ispath, [joinpath(homedir(), p) for p in jail_state(provider)])
    # without binds (macOS, Windows) the jail's HOME links to them instead
    full || Sys.iswindows() || for p in state
        link = joinpath(home, relpath(p, homedir()))
        ispath(link) || islink(link) || (mkpath(dirname(link)); symlink(p, link))
    end
    path = haskey(env, "PATH") ? String[split(env["PATH"], Sys.iswindows() ? ';' : ':'; keepempty = false)...] : String[]
    vars = Dict{String,String}(k => v for (k, v) in env if k != "PATH")
    return Jail.agent_jail(cmd; dir = cwd, home, depot = mkpath(joinpath(root, "depot")),
                           readonly = full ? [harness_root()] : String[],
                           masks = full ? [config_dir()] : String[],
                           binds = full ? [p => p for p in state] : Pair{String,String}[],
                           writable = full ? String[] : state,
                           env = vars, path, proxy = s.proxy,
                           loopback = [b.port => b.path for b in s.bridges])
end
