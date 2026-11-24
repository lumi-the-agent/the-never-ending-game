# Linux backend. Two interchangeable tools:
#   :bwrap   — bubblewrap, a namespaces-based sandbox (default when present).
#   :landrun — Landlock LSM wrapper.
# Both implement the shared contract: build_jail_cmd(exe, wl, ro, cfg) -> Cmd.

default_backend() = Sys.which("bwrap") !== nothing ? :bwrap : :landrun

"True when running inside WSL2 (GPU is exposed via /dev/dxg, not /dev/dri+kfd)."
function is_wsl()
    isfile("/proc/version") || return false
    return occursin("microsoft", lowercase(read("/proc/version", String)))
end

"Best-effort list of GPU device nodes to expose, based on what actually exists."
function gpu_device_nodes()
    nodes = String[]
    if is_wsl()
        ispath("/dev/dxg") && push!(nodes, "/dev/dxg")            # WSL2 paravirtual GPU
    else
        ispath("/dev/dri") && push!(nodes, "/dev/dri")            # DRM / Vulkan (AMD, Intel, NV)
        ispath("/dev/kfd") && push!(nodes, "/dev/kfd")            # ROCm compute (AMD)
        for n in ("/dev/nvidia0", "/dev/nvidiactl", "/dev/nvidia-uvm",
                  "/dev/nvidia-uvm-tools", "/dev/nvidia-modeset")
            ispath(n) && push!(nodes, n)
        end
    end
    return nodes
end

"Read-only paths the GPU userspace driver needs (WSL ships its libs here)."
function gpu_support_paths()
    paths = String[]
    is_wsl() && isdir("/usr/lib/wsl") && push!(paths, "/usr/lib/wsl")
    return paths
end

function build_jail_cmd(exe::Vector{String}, whitelist::Vector{String},
                        readonly::Vector{String}, cfg::JailConfig)
    if cfg.backend === :bwrap
        return _build_bwrap(exe, whitelist, readonly, cfg)
    elseif cfg.backend === :landrun
        return _build_landrun(exe, whitelist, readonly, cfg)
    else
        error("Jail: unknown Linux backend $(cfg.backend) (use :bwrap or :landrun)")
    end
end

"""
One bwrap mount: `args` place something at `dst`. Sorted by destination depth
before they are emitted, so parents are mounted before what goes inside them.
"""
struct MountOp
    dst::String
    args::Vector{String}
end

mount_depth(m::MountOp) = (length(splitpath(m.dst)), m.dst)

"Where the proxy socket appears inside the jail."
const JAIL_PROXY_SOCKET = "/run/jail-proxy/proxy.sock"

function _build_bwrap(exe, whitelist, readonly, cfg::JailConfig)
    bwrap = Sys.which("bwrap")
    bwrap === nothing && error("Jail: `bwrap` not found. Install bubblewrap or pass backend=:landrun.")

    a = String[bwrap, "--die-with-parent", "--new-session", "--unshare-pid", "--proc", "/proc"]
    cfg.isolate && append!(a, ["--unshare-ipc", "--unshare-uts", "--unshare-cgroup-try",
                               "--hostname", "jail", "--cap-drop", "ALL"])
    # The variables go into bwrap's own environment, which it passes on, not into
    # its arguments: any user can read a process's arguments (`ps`), only its
    # owner its environment, and `setenv` carries tokens. `clearenv` is then an
    # environment of exactly `setenv`.
    env = cfg.clearenv ? Dict{String,String}() : Dict{String,String}(ENV)
    merge!(env, cfg.setenv)

    # Build /dev first, THEN add GPU nodes: device binds after `--dev /dev`,
    # otherwise the fresh devtmpfs shadows them (containers/bubblewrap#248).
    append!(a, ["--dev", "/dev"])
    if cfg.gpu
        for n in gpu_device_nodes()
            append!(a, ["--dev-bind-try", n, n])
        end
    end

    ops = MountOp[]
    for d in cfg.system_ro
        push!(ops, MountOp(d, ["--ro-bind-try", d, d]))
    end
    if cfg.gpu
        # Vulkan finds its devices through sysfs: without it RADV & co. are not
        # listed and only a CPU driver (llvmpipe) remains.
        push!(ops, MountOp("/sys", ["--ro-bind-try", "/sys", "/sys"]))
        for p in gpu_support_paths()
            push!(ops, MountOp(p, ["--ro-bind-try", p, p]))
        end
    end
    push!(ops, MountOp("/tmp", ["--tmpfs", "/tmp"]))

    for d in whitelist
        # A whitelist dir that doesn't exist yet must NOT abort the whole launch
        # (R6): `--bind` errors hard if the source is missing. Create it (the
        # whitelist is read-write, so the caller intends to use it) and bind it;
        # if creation fails (e.g. a parent we can't write), fall back to
        # `--bind-try` so bwrap skips it gracefully instead of dying.
        if isdir(d)
            push!(ops, MountOp(d, ["--bind", d, d]))        # read-write
        else
            made = try
                mkpath(d); true
            catch e
                @warn "Jail: could not create whitelist dir; binding best-effort" dir=d exception=e
                false
            end
            push!(ops, MountOp(d, [made ? "--bind" : "--bind-try", d, d]))
        end
    end
    for d in readonly
        push!(ops, MountOp(d, ["--ro-bind-try", d, d])) # read-only
    end
    for (src, dst) in cfg.binds
        push!(ops, MountOp(dst, ["--bind", src, dst]))
    end
    for (src, dst) in cfg.ro_binds
        push!(ops, MountOp(dst, ["--ro-bind", src, dst]))
    end
    for d in cfg.masks
        push!(ops, MountOp(d, ["--tmpfs", d]))
    end
    if !isempty(cfg.proxy)
        ispath(cfg.proxy) || error("Jail: proxy socket $(cfg.proxy) does not exist; start a HostProxy first")
        dir = dirname(JAIL_PROXY_SOCKET)
        push!(ops, MountOp(dir, ["--tmpfs", dir]))
        push!(ops, MountOp(JAIL_PROXY_SOCKET, ["--ro-bind", cfg.proxy, JAIL_PROXY_SOCKET]))
    end
    sort!(ops; by = mount_depth)
    foreach(m -> append!(a, m.args), ops)

    (cfg.network && isempty(cfg.proxy)) || push!(a, "--unshare-net")
    chdir = isempty(cfg.chdir) ? (isempty(whitelist) ? "" : first(whitelist)) : cfg.chdir
    isempty(chdir) || append!(a, ["--chdir", chdir])

    if isempty(cfg.proxy)
        append!(a, exe)
    else
        socat = Sys.which("socat")
        socat === nothing && error("Jail: `proxy` needs `socat` on the host (it bridges the proxy socket to a port inside)")
        url = "http://127.0.0.1:$(cfg.proxy_port)"
        for k in ("HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy")
            env[k] = url
        end
        env["NO_PROXY"] = env["no_proxy"] = "localhost,127.0.0.1,::1"
        bridge = "$(socat) TCP-LISTEN:$(cfg.proxy_port),bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:$(JAIL_PROXY_SOCKET) 2>/dev/null & exec \"\$@\""
        append!(a, ["/bin/sh", "-c", bridge, "jail"])
        append!(a, exe)
    end
    return Cmd(Cmd(a); env)
end

function _build_landrun(exe, whitelist, readonly, cfg::JailConfig)
    landrun = Sys.which("landrun")
    landrun === nothing && error("Jail: `landrun` not found. Install it or pass backend=:bwrap.")

    # --ldd / --add-exec auto-grant the binary + its shared libs.
    # --best-effort degrades gracefully and covers Landlock ioctl gating on
    # kernels >= 6.10 (ABI v5), which can otherwise block GPU ioctls.
    a = String[landrun, "--best-effort", "--add-exec", "--ldd"]

    for d in cfg.system_ro
        isdir(d) && append!(a, ["--rox", d])
    end
    if cfg.gpu
        for n in gpu_device_nodes()
            append!(a, ["--rw", n])
        end
        for p in gpu_support_paths()
            append!(a, ["--rox", p])
        end
    end

    for d in whitelist
        append!(a, ["--rw", d])
    end
    for d in readonly
        append!(a, ["--ro", d])
    end

    cfg.network && push!(a, "--unrestricted-network")
    for e in cfg.env
        append!(a, ["--env", e])
    end

    append!(a, exe)
    return Cmd(a)
end
