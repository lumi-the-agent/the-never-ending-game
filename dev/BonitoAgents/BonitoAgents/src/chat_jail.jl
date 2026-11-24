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
