# ── The dashboard in a browser: the same figure, rendered by WGLMakie ──────
#
# There is one game and one dashboard figure. RayMakie renders it on this
# machine (a window, or offscreen for screenshots and tests); browsers render
# the same figure with WGLMakie, and their mouse and keyboard go into the same
# figure. The game's jail has no network: the Bonito server listens inside the
# jail on 127.0.0.1, `world/run/web.sock` leads to it, and the host forwards a
# LAN port to that socket. `url` is where browsers reach it (Bonito writes it
# into the page for assets and the websocket).

mutable struct WebView
    server::Bonito.Server
    socket::Sockets.PipeServer
    path::String
    port::Int
    colored::Set{UInt}       # plots already given a raster colour (see `fill_raster_colors!`)
end

# ── what WGLMakie draws for a Hikari material ───────────────────────────────

"""
The colour of a Hikari material for a rasterizer that does not read Hikari
(WGLMakie): RayMakie's own raster look of it. `nothing` for a textured one.
"""
function raster_color(material)
    look = RayMakie.raster_look(material)
    look === nothing && return nothing
    look.color isa Colorant || return nothing
    return RGBAf(look.color)
end

"""
    fill_raster_colors!(scene, done)

Give every plot under `scene` that was made with a Hikari `material` but no
`color` of its own the material's colour, so WGLMakie draws it as RayMakie
does. Plugins' plots are covered too; `done` remembers the plots seen.
"""
function fill_raster_colors!(scene::Scene, done::Set{UInt})
    foreach(p -> fill_raster_colors!(p, done), scene.plots)
    foreach(s -> fill_raster_colors!(s, done), scene.children)
end

function fill_raster_colors!(p::Plot, done::Set{UInt})
    id = objectid(p)
    if !(id in done)
        push!(done, id)
        kw = getfield(p, :kw)                    # what the plot was created with
        if haskey(kw, :material) && !haskey(kw, :color)
            c = raster_color(to_value(kw[:material]))
            c === nothing || (p.color = c)
        end
    end
    foreach(c -> fill_raster_colors!(c, done), p.plots)
end

web_socket(p::GamePaths) = joinpath(p.run, "web.sock")

"Lumi's own pages (written by the agent, like Pino's), served at `/lumi/` next to the dashboard."
site_dir(p::GamePaths) = joinpath(p.world, "site")

"Route `/lumi/…` of the dashboard's server to `world/site` (`index.html` for a folder); `/lumi` and the old `/sprout/…`, `/dandy/…` redirect there."
function serve_site!(server::Bonito.Server, p::GamePaths)
    Bonito.route!(server, r"/lumi/.*" => Bonito.FolderServer(site_dir(p)))
    Bonito.route!(server, "/lumi" => _ -> Bonito.HTTP.Response(301, ["Location" => "/lumi/"]))
    # s60: Sprout became Lumi; the old addresses still lead to the same page
    old_address(ctx) = Bonito.HTTP.Response(301, ["Location" => replace(ctx.request.target, r"^/(sprout|dandy)/?" => "/lumi/")])
    Bonito.route!(server, r"/sprout.*" => old_address)
    Bonito.route!(server, r"/dandy.*" => old_address)
    return server
end

"Copy `from` into `to` until either side ends, then close both (connections end with resets too)."
function pipe_closing(from::IO, to::IO)
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
    serve_web!(game; port = 8790, url = "") -> WebView

Serve the dashboard figure with WGLMakie at `127.0.0.1:port` inside the jail
and on the socket `world/run/web.sock` for the host to forward. `url` is the
address browsers use (the host's forward), empty for `http://127.0.0.1:port`.
"""
function serve_web!(g::Game; port::Int = 8790, url::AbstractString = "")
    fig = g.dash.fig
    app = Bonito.App(title = g.paths.instance === :live ? "The Neverending Game" : "The Neverending Game · sandbox") do
        return fig
    end
    server = Bonito.Server(app, "127.0.0.1", port; proxy_url = String(url))
    serve_site!(server, g.paths)
    path = web_socket(g.paths)
    mkpath(dirname(path))
    ispath(path) && rm(path)
    sock = Sockets.listen(path)
    errormonitor(@async while isopen(sock)
        conn = try
            accept(sock)
        catch e
            isopen(sock) || break    # closed by stop_web!
            rethrow()
        end
        inner = Sockets.connect("127.0.0.1", port)
        errormonitor(@async pipe_closing(conn, inner))
        errormonitor(@async pipe_closing(inner, conn))
    end)
    w = WebView(server, sock, path, port, Set{UInt}())
    fill_raster_colors!(fig.scene, w.colored)
    return w
end

function stop_web!(w::WebView)
    close(w.socket)
    ispath(w.path) && rm(w.path)
    close(w.server)
end
