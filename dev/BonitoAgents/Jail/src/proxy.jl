# An HTTPS CONNECT proxy with a host allowlist, served on a unix socket. Pass
# its path as `JailConfig.proxy`: the jail then has no network but this proxy,
# so a jailed program reaches exactly the hosts listed here (port 443 only)
# and nothing else. Every decision is counted per host.

"""
    HostProxy(path; allow, log = nothing) -> HostProxy

Start a CONNECT proxy on the unix socket `path`. `allow` lists host names;
`"*.example.com"` matches any subdomain. Tunnels only port 443. `log` is a file
that gets a line per first denial of a host and per failed upstream connect.
Stop it with `close`.
"""
mutable struct HostProxy
    path::String
    allow::Vector{String}
    server::Sockets.PipeServer
    task::Task
    allowed::Dict{String,Int}
    denied::Dict{String,Int}
    log::Union{Nothing,String}
end

function HostProxy(path::AbstractString; allow::AbstractVector{<:AbstractString},
                   log::Union{Nothing,AbstractString} = nothing)
    ispath(path) && rm(path)
    mkpath(dirname(path))
    server = Sockets.listen(path)
    p = HostProxy(String(path), String.(allow), server, Task(nothing), Dict{String,Int}(), Dict{String,Int}(),
                  log === nothing ? nothing : String(log))
    p.task = errormonitor(@async accept_loop(p))
    return p
end

function Base.close(p::HostProxy)
    close(p.server)
    ispath(p.path) && rm(p.path)
    return nothing
end

Base.isopen(p::HostProxy) = isopen(p.server)

"Does `host` match the allowlist (`example.com` exactly, `*.example.com` for subdomains)?"
function host_allowed(allow::AbstractVector{<:AbstractString}, host::AbstractString)
    h = lowercase(host)
    for pat in allow
        q = lowercase(pat)
        if startswith(q, "*.")
            endswith(h, q[2:end]) && return true
        elseif h == q
            return true
        end
    end
    return false
end

function proxy_log(p::HostProxy, msg::AbstractString)
    p.log === nothing && return
    open(p.log, "a") do io
        println(io, Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS"), " ", msg)
    end
end

function accept_loop(p::HostProxy)
    while isopen(p.server)
        client = try
            accept(p.server)
        catch e
            # `close(p)` ends the loop through the failing accept
            isopen(p.server) || break
            rethrow()
        end
        # latest world: a long running proxy picks up edits to the handler (Revise)
        errormonitor(@async Base.invokelatest(handle_client, p, client))
    end
end

const MAX_HEAD = 8192

"The request head (lines up to the empty one), or `nothing` when it is too long or the client left."
function read_head(io::IO)
    lines = String[]
    total = 0
    while !eof(io)
        line = readline(io)
        total += sizeof(line)
        total > MAX_HEAD && return nothing
        isempty(line) && return lines
        push!(lines, line)
    end
    return nothing
end

function reply_and_close(client::IO, status::AbstractString)
    write(client, "HTTP/1.1 $status\r\nContent-Length: 0\r\n\r\n")
    close(client)
end

function handle_client(p::HostProxy, client::IO)
    try
        serve_client(p, client)
    catch e
        # the client hung up mid request (connection pools do): nothing to answer
        e isa Base.IOError || e isa EOFError || rethrow()
        close(client)
    end
    return nothing
end

function serve_client(p::HostProxy, client::IO)
    head = read_head(client)
    (head === nothing || isempty(head)) && return close(client)
    m = match(r"^CONNECT ([A-Za-z0-9.\-]+):(\d+) HTTP/1\.[01]$", head[1])
    m === nothing && return reply_and_close(client, "405 Method Not Allowed")
    host, port = m.captures[1], parse(Int, m.captures[2])
    if port != 443 || !host_allowed(p.allow, host)
        n = p.denied[host] = get(p.denied, host, 0) + 1
        n == 1 && proxy_log(p, "denied $host:$port")
        return reply_and_close(client, "403 Forbidden")
    end
    upstream = try
        Sockets.connect(host, port)
    catch e
        e isa Base.IOError || e isa Sockets.DNSError || rethrow()
        proxy_log(p, "upstream $host: $(sprint(showerror, e))")
        return reply_and_close(client, "502 Bad Gateway")
    end
    p.allowed[host] = get(p.allowed, host, 0) + 1
    write(client, "HTTP/1.1 200 Connection Established\r\n\r\n")
    up = @async tunnel(client, upstream)
    tunnel(upstream, client)
    wait(up)
    return nothing
end

"Copy `from` into `to` until either side ends, then close both. Tunnels often end with a reset."
function tunnel(from::IO, to::IO)
    try
        while !eof(from)
            write(to, readavailable(from))
        end
    catch e
        e isa Base.IOError || e isa EOFError || rethrow()
    finally
        close(to)
        close(from)
    end
end

"""
    PortForward(host, port, socket) -> PortForward

Make a server inside a jail (listening on the unix socket `socket`, in a
folder the jail shares) reachable at `host:port`: every TCP connection is
piped to the socket. A jail without network can serve this way. Stop it with
`close`.
"""
mutable struct PortForward
    server::Sockets.TCPServer
    socket::String
    task::Task
end

function PortForward(host::AbstractString, port::Integer, socket::AbstractString)
    server = Sockets.listen(Sockets.getaddrinfo(host), port)
    f = PortForward(server, String(socket), Task(nothing))
    f.task = errormonitor(@async while isopen(server)
        client = try
            accept(server)
        catch e
            isopen(server) || break     # closed by `close(f)`
            rethrow()
        end
        errormonitor(@async Base.invokelatest(forward_client, f, client))
    end)
    return f
end

function forward_client(f::PortForward, client::IO)
    inner = try
        Sockets.connect(f.socket)
    catch e
        # nothing listens inside (the jailed server is restarting): drop the connection
        e isa Base.IOError || rethrow()
        return close(client)
    end
    up = @async tunnel(client, inner)
    tunnel(inner, client)
    wait(up)
    return nothing
end

Base.close(f::PortForward) = close(f.server)
Base.isopen(f::PortForward) = isopen(f.server)

"""
    LoopbackBridge(port, path) -> LoopbackBridge

The reverse of [`PortForward`](@ref): make the host's loopback port `port` (a
local server, such as a worker's relay) reachable from a jail without network.
It serves the unix socket `path`, and pipes every connection to
`127.0.0.1:port`. Pass `port => path` in `JailConfig.loopback`: inside, the
jail's own `127.0.0.1:port` leads here. Stop it with `close`.
"""
mutable struct LoopbackBridge
    port::Int
    path::String
    server::Sockets.PipeServer
    task::Task
end

function LoopbackBridge(port::Integer, path::AbstractString)
    ispath(path) && rm(path)
    mkpath(dirname(path))
    server = Sockets.listen(path)
    b = LoopbackBridge(Int(port), String(path), server, Task(nothing))
    b.task = errormonitor(@async while isopen(server)
        client = try
            accept(server)
        catch e
            isopen(server) || break     # closed by `close(b)`
            rethrow()
        end
        errormonitor(@async Base.invokelatest(bridge_client, b, client))
    end)
    return b
end

function bridge_client(b::LoopbackBridge, client::IO)
    local_server = try
        Sockets.connect(Sockets.localhost, b.port)
    catch e
        # nothing listens on the port (the server restarts): drop the connection
        e isa Base.IOError || rethrow()
        return close(client)
    end
    up = @async tunnel(client, local_server)
    tunnel(local_server, client)
    wait(up)
    return nothing
end

function Base.close(b::LoopbackBridge)
    close(b.server)
    ispath(b.path) && rm(b.path)
    return nothing
end
Base.isopen(b::LoopbackBridge) = isopen(b.server)
