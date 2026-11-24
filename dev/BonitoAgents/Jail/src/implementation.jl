# Cross-platform layer. Knows nothing OS-specific itself — it normalises the
# caller's inputs and hands them to the backend's `build_jail_cmd`. The only
# names it borrows from the backend (`default_backend`, `build_jail_cmd`) are
# resolved at call time, so this file can be included before the backend.

"""
    JailConfig(; kwargs...)

Configuration for a single [`jail`](@ref) call. Cross-platform fields apply
everywhere; the OS-specific fields are consumed only by their own backend and
ignored elsewhere. OS-specific *defaults* that need to probe the system (e.g. a
Sandboxie install path) are left empty here and resolved lazily inside the
backend, so constructing a `JailConfig` never touches another OS's tooling.

Cross-platform:
  * `backend`  — which sandbox tool to use (defaults to the OS's best available).
  * `gpu`      — expose the GPU device/driver stack (default `true`).
  * `network`  — allow network access (default `true`).

Linux:
  * `env`        — env vars forwarded into the sandbox (matters for landrun,
                   which clears the environment; bwrap inherits it).
  * `system_ro`  — host paths exposed read-only so the program + linker + GPU
                   userspace load.

Linux, bwrap only (an error on any other backend when set):
  * `binds`      — `host => jail` pairs mounted read-write at a different path
                   inside (e.g. a private folder as the jail's `HOME`).
  * `ro_binds`   — the same, read-only.
  * `masks`      — jail paths covered by an empty tmpfs (hide a folder that a
                   whitelisted parent would expose; bind parts of it back with
                   `binds`).
  * `proxy`      — host path of a [`HostProxy`](@ref) socket. Cuts the network
                   (whatever `network` says) except for that proxy, reachable
                   inside at `127.0.0.1:proxy_port` and set as `HTTPS_PROXY`.
                   Needs `socat` on the host.
  * `setenv`     — variables set inside; with `clearenv = true` the only ones
                   (plus the proxy variables).
  * `chdir`      — working directory inside (default: the first whitelist dir).
  * `isolate`    — also unshare IPC, UTS and cgroup namespaces and drop all
                   capabilities.

Mounts are applied parents first (sorted by destination depth), so a read-only
or masked path inside a whitelisted folder stays read-only or masked whatever
order the lists come in.

Windows uses a native integrity-level sandbox (see `windows.jl`); it has no
extra config — the whitelist is granted by labelling dirs Low, writes are
denied by default, and reads are unrestricted.
"""
Base.@kwdef struct JailConfig
    backend::Symbol            = default_backend()
    gpu::Bool                  = true
    network::Bool              = true
    # Linux
    env::Vector{String}        = ["PATH", "HOME", "TERM", "LANG", "LC_ALL"]
    system_ro::Vector{String}  = ["/usr", "/bin", "/lib", "/lib64", "/sbin", "/etc"]
    # Linux, bwrap only
    binds::Vector{Pair{String,String}}    = Pair{String,String}[]
    ro_binds::Vector{Pair{String,String}} = Pair{String,String}[]
    masks::Vector{String}                 = String[]
    proxy::String                         = ""
    proxy_port::Int                       = 3128
    setenv::Dict{String,String}           = Dict{String,String}()
    clearenv::Bool                        = false
    chdir::String                         = ""
    isolate::Bool                         = false
end

"True when `cfg` uses options only the bwrap backend implements."
uses_bwrap_options(cfg::JailConfig) =
    !isempty(cfg.binds) || !isempty(cfg.ro_binds) || !isempty(cfg.masks) || !isempty(cfg.proxy) ||
    !isempty(cfg.setenv) || cfg.clearenv || !isempty(cfg.chdir) || cfg.isolate

"""
    jail(cmd::Cmd; whitelist=[], readonly=[], kwargs...) -> Cmd

Return a sandboxed version of `cmd`. `whitelist` dirs are read-write, `readonly`
dirs are read-only, everything else is denied. Paths are made absolute and
`expanduser`'d. Extra `kwargs` are forwarded to [`JailConfig`](@ref) (e.g.
`gpu=false`, `network=false`, `backend=:landrun`).

The returned `Cmd` is composable with `run`, `success`, `pipeline`, etc.
"""
function jail(cmd::Cmd;
              whitelist::AbstractVector{<:AbstractString} = String[],
              readonly::AbstractVector{<:AbstractString}  = String[],
              kwargs...)
    cfg = JailConfig(; kwargs...)
    cfg.backend === :bwrap || !uses_bwrap_options(cfg) ||
        error("Jail: binds/ro_binds/masks/proxy/setenv/clearenv/chdir/isolate need backend = :bwrap (got $(cfg.backend))")
    exe = collect(String, cmd.exec)
    wl  = String[abspath(expanduser(d)) for d in whitelist]
    ro  = String[abspath(expanduser(d)) for d in readonly]
    return build_jail_cmd(exe, wl, ro, cfg)
end
