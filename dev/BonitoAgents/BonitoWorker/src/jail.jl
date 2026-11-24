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
# An app can give its chats more (BonitoAgents' `app_jail`): the header then
# carries a spec instead of `true` (`jail_spec`: its HOME, more folders to
# write, read or hide, variables, hosts, no provider login).
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
    jailed_session(relay, provider, spec) -> JailedSession

The proxy (its provider's hosts, `JAIL_HOSTS` and the spec's `"hosts"`) and the relay bridges of
one jailed session. `spec` is the header's `"jail"`: `true` or an app's spec.
"""
function jailed_session(relay::MCPRelay, provider, spec)
    dir = mktempdir()
    hosts = vcat(jail_hosts(provider), JAIL_HOSTS, String.(spec_value(spec, "hosts", String[])))
    proxy = Jail.HostProxy(joinpath(dir, "proxy.sock"); allow = hosts)
    bridges = [Jail.LoopbackBridge(port, joinpath(dir, "relay-$(port).sock")) for port in relay_ports(relay)]
    return JailedSession(dir, proxy, bridges)
end

"A key of a jail spec (`true` has none)."
spec_value(spec, key, default) = spec isa AbstractDict ? get(spec, key, default) : default

"""
    jail_command(s, cmd; provider, project_id, cwd, env, spec = true) -> Cmd

`cmd`, the chat's agent, in its jail (see the top of this file), with `env` (the provider's
variables, without the worker's own environment) and the spec's `"env"` on top of the jail's
clean one.
"""
function jail_command(s::JailedSession, cmd::Cmd; provider, project_id::AbstractString, cwd::AbstractString,
                      env::AbstractDict, spec = true)
    root = jail_dir()
    home = mkpath(String(spec_value(spec, "home", joinpath(root, "homes", project_id))))
    full = Jail.full_agent_jail()
    state = spec_value(spec, "provider_state", true) === true ?
        filter(ispath, [joinpath(homedir(), p) for p in jail_state(provider)]) : String[]
    # without binds (macOS, Windows) the jail's HOME links to them instead
    full || Sys.iswindows() || for p in state
        link = joinpath(home, relpath(p, homedir()))
        ispath(link) || islink(link) || (mkpath(dirname(link)); symlink(p, link))
    end
    path = haskey(env, "PATH") ? String[split(env["PATH"], Sys.iswindows() ? ';' : ':'; keepempty = false)...] : String[]
    vars = Dict{String,String}(k => v for (k, v) in env if k != "PATH")
    merge!(vars, Dict{String,String}(String(k) => String(v) for (k, v) in spec_value(spec, "env", Dict())))
    strs(key) = String[String(x) for x in spec_value(spec, key, String[])]
    ro_binds = Pair{String,String}[String(b[1]) => String(b[2]) for b in spec_value(spec, "ro_binds", Any[])]
    depot = mkpath(String(spec_value(spec, "depot", joinpath(root, "depot"))))
    return Jail.agent_jail(cmd; dir = cwd, home, depot,
                           readonly = full ? [harness_root(); strs("readonly")] : strs("readonly"),
                           masks = full ? [config_dir(); strs("masks")] : String[],
                           binds = full ? [p => p for p in state] : Pair{String,String}[],
                           ro_binds = full ? ro_binds : Pair{String,String}[],
                           writable = full ? strs("writable") : [state; strs("writable")],
                           writable_dir = spec_value(spec, "writable_dir", true) === true,
                           env = vars, path, proxy = s.proxy,
                           loopback = [b.port => b.path for b in s.bridges])
end
