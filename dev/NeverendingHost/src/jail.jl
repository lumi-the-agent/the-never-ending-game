# ── The jail of each role, built with BonitoAgents' `Jail` ──────────────────
#
# Every role sees the system read only, its own HOME (at the real HOME path,
# so Julia's depot and compile caches resolve as outside), the user's depot
# read only with a writable depot in front, the GPU, and the host's run
# directory read only at /run/neverending. `.jail/` itself is masked.
#
#   :game    world writable, code read only, no network
#   :worker  world writable, code read only, network through the proxy
#   :agent   the whole game folder writable but the host's own code (`HOST_DEV`), the
#            human's goals and the human's game; network through the proxy
#   :review  read only except world/reviews, network through the proxy
#
# Every role runs in the Jail package's agent jail (`Jail.agent_jail`: its own
# HOME, a writable depot in front of the user's, a clean environment, the GPU,
# the network only through the proxy); this file says only what each role may
# write and read, and what of the host it sees. The jail is bubblewrap, so Linux
# only, and optional (`[jail] mode`): without it every role runs as a plain
# process of the user with the same HOME and environment, but nothing it may not
# read, write or reach.

"BonitoAgents' worker config in the depot (server credential); only its `harnesses` (the ACP adapters) stay visible."
const BONITOWORKER_SCRATCH = "98909ed9-6989-4829-81af-73688ee23085"

"""
The checkouts the host itself runs, outside every jail: an edit there would run with the human's
rights (the host revises its code), so they stay read only. Every other checkout in dev/ is the
agent's to change, and so is any package it forks in.
"""
const HOST_DEV = ("NeverendingHost", "BonitoAgents")

"The published plugins the human's game runs (NeverendingGame `GamePaths(root, :live).plugins`)."
live_dir(jp::JailPaths) = joinpath(jp.world, "live")

"""
What `role` may write and read beyond what every agent jail gives (its folder, HOME, depot and
tools), and what it must not see: the host's own state, and BonitoAgents' worker config (its
server credential; only the ACP adapters in it stay readable).
"""
function role_mounts(jp::JailPaths, role::Symbol)
    scratch = joinpath(jp.user_home, ".julia", "scratchspaces", BONITOWORKER_SCRATCH, "config")
    readonly = String[]
    whitelist = String[]
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
            d in HOST_DEV && push!(readonly, joinpath(dev, d))
        end
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
The variables of `role` on top of what every agent jail sets (HOME, PATH, the depot, ...): where
the game is, the host's run directory as `role` sees it (`run`), and what the agents need.
"""
function role_env(jp::JailPaths, cfg::HostConfig, role::Symbol, extra::AbstractDict; run::AbstractString = JAIL_RUN)
    env = Dict{String,String}(
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
    env = Dict{String,String}(env)
    ro_binds = Pair{String,String}[jp.run => JAIL_RUN]
    # the games' and the worker's own output, read only at its real path in the masked `.jail`, so an
    # agent finds out why its game does not start; the agents' logs stay hidden (reviews are blind)
    if role in (:agent, :review)
        for name in ("game", "sandbox", "worker")
            isfile(log_path(jp, name)) && push!(ro_binds, log_path(jp, name) => log_path(jp, name))
        end
    end
    if display !== nothing
        push!(ro_binds, x_socket(display) => x_socket(display), display.xauthority => display.xauthority)
        env["DISPLAY"] = ":$(display.number)"
        env["XAUTHORITY"] = display.xauthority
    end
    m = role_mounts(jp, role)
    return Jail.agent_jail(Cmd(argv); dir = cwd, home = home(jp, role), depot = jp.depot,
                           writable = m.whitelist, readonly = m.readonly, masks = m.masks,
                           ro_binds = cfg.jail ? ro_binds : Pair{String,String}[],
                           env = role_env(jp, cfg, role, env; run = cfg.jail ? JAIL_RUN : jp.run),
                           path = isempty(path) ? String[] : String[path], proxy, gpu = true,
                           writable_dir = role !== :review, sandbox = cfg.jail, user_home = jp.user_home)
end

"A Julia command line in the game environment."
julia_argv(jp::JailPaths, code::AbstractString; threads::Int = 8) =
    String["julia", "--project=$(jp.root)", "--startup-file=no", "--threads=$(threads)", "-e", code]
