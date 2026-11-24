"""
    set_jail!(state, project_id, on) -> ProjectInfo

Run this chat's agent in a jail on its worker, or not (experimental, off by default): its
folder to write, a HOME and a Julia depot of its own, the provider's login bound in, the
network only through an allowlisting proxy and the worker's relay (BonitoWorker's
`jailed_session`, on the Jail package's `agent_jail`). Persists the switch; the caller
restarts the session, since the agent process is what gets jailed.
"""
function set_jail!(state::ServerState, project_id::AbstractString, on::Bool)
    p = dev_project(state, project_id)
    visible(state, p) || error("chat is not available")
    p.jail == on && return p
    p.jail = on
    @lock state.lock begin; save_projects!(state); end
    notify_projects!(state)
    return p
end

"""
    app_jail(app, chat::ProjectInfo) -> true or a Dict

How an app's chat is jailed when its jail switch is on. `true`: the worker's defaults (the chat's
folder to write, a HOME of its own under the worker's state, the provider's login bound in from
the real HOME). A `Dict` adds to or changes them; the worker's `jail_command` reads:

| key | what |
| --- | --- |
| `"home"` | a folder on the worker to be the agent's HOME |
| `"depot"` | its writable Julia depot (default: one shared by the worker's jailed chats) |
| `"writable"`, `"readonly"`, `"masks"` | more folders it may write, may only read, may not see |
| `"ro_binds"` | `[[source, inside], ...]` mounted read only |
| `"env"` | variables on top of the provider's |
| `"hosts"` | more hosts its proxy lets through (port 443) |
| `"provider_state"` | bind the provider's login from the real HOME (default `true`) |
| `"writable_dir"` | whether its working folder is writable (default `true`) |
"""
app_jail(::AgentApp, ::ProjectInfo) = true

"What a jailed chat's session header says: `true`, or its app's spec (`app_jail`)."
function jail_spec(server::ServerState, p::ProjectInfo)
    app = app_of(server, p)
    return app === nothing ? true : app_jail(app, p)
end

