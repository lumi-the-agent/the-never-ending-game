# ── The jail of each role, built with BonitoAgents' `Jail` ──────────────────
#
# Every role sees the system read only, its own HOME (at the real HOME path,
# so Julia's depot and compile caches resolve as outside), the user's depot
# read only with a writable depot in front, the GPU, and the host's run
# directory read only at /run/neverending. `.jail/` itself is masked.
#
#   :game    world writable, code read only, no network
#   :worker  world writable, code read only, network through the proxy
#   :agent   world, the environment and the engine checkouts (`WRITABLE_DEV`) writable,
#            other checkouts read only, network through the proxy
#   :review  read only except world/reviews, network through the proxy
#
# The jail is bubblewrap, so Linux only, and optional (`[jail] mode`): without it
# every role runs as a plain process of the user, with its own HOME and the same
# environment, but nothing it may not read, write or reach.

"BonitoAgents' worker config in the depot (server credential); only its `harnesses` (the ACP adapters) stay visible."
const BONITOWORKER_SCRATCH = "98909ed9-6989-4829-81af-73688ee23085"

"Where agent CLIs live outside the depot; mounted read only when present."
agent_tool_dirs(h::AbstractString) =
    filter(ispath, [joinpath(h, ".local", "share", "claude"), joinpath(h, ".opencode", "bin"),
                    joinpath(h, ".kimi-code", "bin"), joinpath(h, ".mimocode", "bin"), "/usr/local/bin"])

julia_binary() = joinpath(Sys.BINDIR, "julia")

"Each role's `~/.local/bin`: `julia` (and `claude`, which claude-agent-acp may look for)."
function prepare_home!(jp::JailPaths, role::Symbol)
    bin = joinpath(home(jp, role), ".local", "bin")
    mkpath(bin)
    links = ["julia" => julia_binary()]
    claude = joinpath(jp.user_home, ".local", "bin", "claude")
    ispath(claude) && push!(links, "claude" => realpath(claude))
    for (name, target) in links
        link = joinpath(bin, name)
        islink(link) && readlink(link) == target && continue
        rm(link; force = true)
        symlink(target, link)
    end
    return bin
end

# the game's engine and its renderer: improving materials, RayMakie and Hikari is the agent's work too
const WRITABLE_DEV = ("NeverendingGame", "Makie", "Hikari", "Raycore", "Lava")

"The published plugins the human's game runs (NeverendingGame `GamePaths(root, :live).plugins`)."
live_dir(jp::JailPaths) = joinpath(jp.world, "live")

function role_mounts(jp::JailPaths, role::Symbol)
    h = jp.user_home
    depot = joinpath(h, ".julia")
    scratch = joinpath(depot, "scratchspaces", BONITOWORKER_SCRATCH, "config")
    readonly = String[depot, agent_tool_dirs(h)...]
    whitelist = String[jp.depot]
    masks = String[jp.state]
    if isdir(scratch)
        push!(masks, scratch)
        harness = joinpath(scratch, "harnesses")
        isdir(harness) && push!(readonly, harness)
    end
    dev = joinpath(jp.root, "dev")
    if role === :agent
        push!(whitelist, jp.root, jp.romeodb)
        for d in readdir(dev)
            d in WRITABLE_DEV || push!(readonly, joinpath(dev, d))
        end
        push!(readonly, joinpath(jp.root, "setup"))
        isfile(goals_path(jp)) && push!(readonly, goals_path(jp))     # the human's
        # what the human's game runs: only `publish` (the game itself) changes it
        isdir(live_dir(jp)) && push!(readonly, live_dir(jp))
    elseif role === :review
        push!(readonly, jp.root)
        push!(whitelist, joinpath(jp.world, "reviews"), joinpath(jp.world, "run"), game_run(jp, :sandbox), jp.romeodb)
    else   # :game, :worker
        push!(readonly, jp.root)
        push!(whitelist, jp.world)
    end
    return (; whitelist, readonly, masks)
end

"""
The environment of `role`. `h` is its HOME as it sees it: the real HOME path in the jail (its own
home is mounted there), its own home folder without one.
"""
function role_env(jp::JailPaths, cfg::HostConfig, role::Symbol, extra::AbstractDict, path_extra::AbstractString;
                  h::AbstractString = jp.user_home, run::AbstractString = JAIL_RUN)
    bin = joinpath(h, ".local", "bin")
    path = join(filter(!isempty, [bin, path_extra, "/usr/bin", "/bin"]), ":")
    env = Dict{String,String}(
        "HOME" => h, "USER" => basename(h), "LOGNAME" => basename(h), "PATH" => path,
        "LANG" => "C.UTF-8", "TERM" => "dumb", "SHELL" => "/bin/bash", "TMPDIR" => "/tmp",
        "JULIA_DEPOT_PATH" => jp.depot * ":" * joinpath(jp.user_home, ".julia"),
        "JULIA_NUM_THREADS" => string(cfg.threads),
        "NEVERENDING_ROOT" => jp.root, "NEVERENDING_RUN" => run, "NEVERENDING_ROLE" => String(role),
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" => "1", "DISABLE_AUTOUPDATER" => "1")
    return merge(env, Dict{String,String}(String(k) => String(v) for (k, v) in extra))
end

"""
The X server of the user's desktop (XWayland on KDE/Wayland): its display
number and cookie file. The game opens its RayMakie window through it; GLFW on
Wayland itself hung in its event polling.
"""
struct XDisplay
    number::Int
    xauthority::String
end

x_socket(d::XDisplay) = "/tmp/.X11-unix/X$(d.number)"

"The running XWayland server of user `uid` as an `XDisplay`, or `nothing` without a desktop session (or off Linux)."
function x_display(uid::Integer = ccall(:getuid, Cuint, ()))
    Sys.islinux() || return nothing
    for pid in filter(f -> all(isdigit, f), readdir("/proc"))
        args = cmdline(pid)
        (args === nothing || isempty(args) || !endswith(first(args), "Xwayland")) && continue
        stat("/proc/$pid").uid == uid || continue
        i = findfirst(==("-auth"), args)
        n = findfirst(a -> startswith(a, ":"), args)
        (i === nothing || n === nothing) && continue
        d = XDisplay(parse(Int, args[n][2:end]), args[i + 1])
        issocket(x_socket(d)) && isfile(d.xauthority) && return d
    end
    return nothing
end

"A process's arguments, or `nothing` when it ended while we looked."
function cmdline(pid::AbstractString)
    return try
        split(read("/proc/$pid/cmdline", String), '\0'; keepempty = false)
    catch e
        e isa SystemError || rethrow()
        nothing
    end
end

"""
    jailed(jp, cfg, role, argv; cwd, env, proxy, path, display) -> Cmd

`argv` run as `role` in its jail. `proxy` (a `HostProxy`) gives it the hosts
that proxy allows; without one it has no network. `path` is put on PATH
before the system directories. `display` (an `XDisplay`, from `x_display`)
lets it open windows on the desktop: only the X socket and its cookie are
mounted. With `cfg.jail` off, the same process without the jail (see the top).
"""
function jailed(jp::JailPaths, cfg::HostConfig, role::Symbol, argv::Vector{String};
                cwd::AbstractString = jp.world, env::AbstractDict = Dict{String,String}(),
                proxy::Union{Nothing,HostProxy} = nothing, path::AbstractString = "",
                display::Union{Nothing,XDisplay} = nothing)
    prepare_home!(jp, role)
    if !cfg.jail
        env = Dict{String,String}(env)
        display === nothing || (env["DISPLAY"] = ":$(display.number)"; env["XAUTHORITY"] = display.xauthority)
        return setenv(Cmd(argv), role_env(jp, cfg, role, env, path; h = home(jp, role), run = jp.run); dir = String(cwd))
    end
    m = role_mounts(jp, role)
    ro_binds = [jp.run => JAIL_RUN]
    # the games' and the worker's own output, read only at its real path in the masked `.jail`, so an
    # agent finds out why its game does not start; the agents' logs stay hidden (reviews are blind)
    if role in (:agent, :review)
        for name in ("game", "sandbox", "worker")
            isfile(log_path(jp, name)) && push!(ro_binds, log_path(jp, name) => log_path(jp, name))
        end
    end
    env = Dict{String,String}(env)
    if display !== nothing
        push!(ro_binds, x_socket(display) => x_socket(display), display.xauthority => display.xauthority)
        env["DISPLAY"] = ":$(display.number)"
        env["XAUTHORITY"] = display.xauthority
    end
    return Jail.jail(Cmd(argv); whitelist = m.whitelist, readonly = m.readonly, masks = m.masks,
                     binds = [home(jp, role) => jp.user_home], ro_binds,
                     setenv = role_env(jp, cfg, role, env, path), clearenv = true, isolate = true,
                     chdir = String(cwd), gpu = true, network = false,
                     proxy = proxy === nothing ? "" : proxy.path)
end

"A Julia command line in the game environment."
julia_argv(jp::JailPaths, code::AbstractString; threads::Int = 8) =
    String["julia", "--project=$(jp.root)", "--startup-file=no", "--threads=$(threads)", "-e", code]
