# ── a jail for a coding agent ────────────────────────────────────────────────
#
# What a coding agent (and the Julia sessions and tools it starts) needs to work,
# and nothing more. NeverendingHost runs its agents and games in it, and a
# BonitoAgents chat can opt in:
#
#   - its project folder (`dir`): its working directory, writable unless
#     `writable_dir = false` (a reviewer works in a folder it must not change);
#   - a HOME of its own (`home`, a folder on the host): on Linux mounted at the
#     real HOME path, so configs and caches resolve as they would outside;
#     elsewhere HOME points to it;
#   - a Julia depot of its own (`depot`) in front of the user's, which it only reads;
#   - the agent CLIs it runs (read only), with `julia` and `claude` linked into
#     its HOME's `.local/bin`;
#   - the GPU, a clean environment (`env` on top of the basics), and the network
#     only through a `HostProxy` allowlist and the host loopback ports in `loopback`
#     (`LoopbackBridge`s, e.g. a worker's relay);
#   - `writable`, `readonly`, `masks`, `binds` and `ro_binds` for anything else.
#
# On Linux that is bubblewrap, all of it. On macOS and Windows the backend's
# folder rules apply and HOME, the depot and the environment are set, but masks
# and binds are not available and the network is not limited (Seatbelt and
# AppContainer get no proxy here yet).

"Where agent CLIs live outside the Julia depot (read only in the jail, when present)."
agent_tool_dirs(user_home::AbstractString = homedir()) =
    filter(ispath, [joinpath(user_home, ".local", "share", "claude"), joinpath(user_home, ".opencode", "bin"),
                    joinpath(user_home, ".kimi-code", "bin"), joinpath(user_home, ".mimocode", "bin"), "/usr/local/bin"])

"""
    link_tools!(home; user_home = homedir()) -> bin

`julia` (this Julia) and `claude` (when the user has it) in `home/.local/bin`, which an agent
jail puts first on PATH. Windows gets Julia's own folder on PATH instead (no symlinks).
"""
function link_tools!(home::AbstractString; user_home::AbstractString = homedir())
    bin = mkpath(joinpath(home, ".local", "bin"))
    Sys.iswindows() && return bin
    links = ["julia" => joinpath(Sys.BINDIR, "julia")]
    claude = joinpath(user_home, ".local", "bin", "claude")
    ispath(claude) && push!(links, "claude" => realpath(claude))
    for (name, target) in links
        link = joinpath(bin, name)
        islink(link) && readlink(link) == target && continue
        rm(link; force = true)
        symlink(target, link)
    end
    return bin
end

"Whether `agent_jail` can give the full jail here: bubblewrap on Linux."
full_agent_jail() = Sys.islinux() && Sys.which("bwrap") !== nothing

"""
    agent_jail(cmd; dir, home, depot, writable, readonly, masks, binds, ro_binds, env, path,
               proxy, loopback, gpu, writable_dir = true, sandbox = true, user_home = homedir()) -> Cmd

`cmd` as a coding agent in its jail (see the top of this file). `sandbox = false` gives the same
process (HOME, depot, environment, working directory) without the jail, for machines or
configurations that run unjailed.
"""
function agent_jail(cmd::Cmd; dir::AbstractString, home::AbstractString, depot::AbstractString,
                    writable::AbstractVector{<:AbstractString} = String[],
                    readonly::AbstractVector{<:AbstractString} = String[],
                    masks::AbstractVector{<:AbstractString} = String[],
                    binds::AbstractVector{<:Pair} = Pair{String,String}[],
                    ro_binds::AbstractVector{<:Pair} = Pair{String,String}[],
                    env::AbstractDict = Dict{String,String}(),
                    path::AbstractVector{<:AbstractString} = String[],
                    proxy::Union{Nothing,HostProxy} = nothing,
                    loopback::AbstractVector{<:Pair} = Pair{Int,String}[],
                    gpu::Bool = true, writable_dir::Bool = true, sandbox::Bool = true,
                    user_home::AbstractString = homedir())
    link_tools!(home; user_home)
    full = sandbox && full_agent_jail()
    h = full ? String(user_home) : String(home)           # HOME as the agent sees it
    sep = Sys.iswindows() ? ';' : ':'
    system = Sys.iswindows() ? [Sys.BINDIR] : ["/usr/bin", "/bin"]
    user_depot = joinpath(user_home, ".julia")
    vars = Dict{String,String}(
        "HOME" => h, "USER" => basename(user_home), "LOGNAME" => basename(user_home),
        "PATH" => join([joinpath(h, ".local", "bin"); String.(path); system], sep),
        "LANG" => "C.UTF-8", "TERM" => "dumb", "TMPDIR" => Sys.iswindows() ? tempdir() : "/tmp",
        # the trailing separator appends Julia's bundled depots (the precompiled standard library);
        # without it every jail compiled Logging, Dates, ... into its own depot again
        "JULIA_DEPOT_PATH" => join([depot, user_depot], sep) * sep)
    Sys.iswindows() || (vars["SHELL"] = "/bin/bash")
    merge!(vars, Dict{String,String}(String(k) => String(v) for (k, v) in env))
    sandbox || return setenv(cmd, vars; dir = String(dir))
    # a working folder it may not change is still its working folder: shown read only
    ro = String[user_depot; agent_tool_dirs(user_home); readonly; writable_dir ? String[] : [dir]]
    if full
        return jail(cmd; whitelist = String[depot; writable_dir ? [dir] : String[]; writable], readonly = ro, masks = String.(masks),
                    binds = Pair{String,String}[String(home) => String(user_home); binds], ro_binds = Pair{String,String}[ro_binds...],
                    setenv = vars, clearenv = true, isolate = true, chdir = String(dir), gpu, network = false,
                    proxy = proxy === nothing ? "" : proxy.path, loopback = Pair{Int,String}[loopback...])
    end
    (isempty(masks) && isempty(binds) && isempty(ro_binds)) ||
        error("agent_jail: masks and binds need bubblewrap (Linux); run with `sandbox = false` here")
    return setenv(jail(cmd; whitelist = String[depot; writable_dir ? [dir] : String[]; home; writable], readonly = ro, gpu, network = true),
                  vars; dir = String(dir))
end
