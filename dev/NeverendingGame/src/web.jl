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

"""
    scene_page(fig, view; title) -> Bonito.App

Only the 3D view of the dashboard figure `fig` (`view` is its scene), for pages that show the game
beside other things: the host's dashboard embeds it. It is the same figure as the full page, so
mouse and keyboard reach the game as they do there; everything outside the view's viewport is
clipped and the view is scaled to fit the window. The scale goes into WGLMakie's own `winscale`,
which sizes the canvas and maps the mouse (a CSS transform would move the picture but not the
mouse). A page that embeds it gets the view's size as a message (`{sceneSize: [w, h]}`), to give
it the view's proportions.
"""
function scene_page(fig::Figure, view::Scene; title::AbstractString)
    return Bonito.App(; title) do session
        rect = map(r -> [Int.(minimum(r))..., Int.(widths(r))...], session, viewport(view))
        box = Bonito.DOM.div(fig; style = "position:absolute; overflow:hidden")
        fit = Bonito.js"""
            const box = $(box), rect = $(rect);
            const fit = () => {
                const canvas = box.querySelector('canvas'), screen = canvas && canvas.wglmakie_screen;
                if (!screen) { setTimeout(fit, 100); return; }
                const [x, y, w, h] = rect.value, H = screen.renderer._height;
                const s = Math.min(window.innerWidth / w, window.innerHeight / h);
                screen.winscale = s;
                Object.assign(canvas.style, {position: 'absolute', width: s * screen.renderer._width + 'px',
                    height: s * H + 'px', left: -s * x + 'px', top: -s * (H - y - h) + 'px'});
                Object.assign(box.style, {width: s * w + 'px', height: s * h + 'px',
                    left: (window.innerWidth - s * w) / 2 + 'px', top: (window.innerHeight - s * h) / 2 + 'px'});
                if (window.parent !== window) window.parent.postMessage({sceneSize: [w, h]}, '*');
            };
            window.addEventListener('resize', fit);
            rect.on(fit);
            fit();
        """
        style = Bonito.DOM.style("html, body { margin: 0; height: 100%; overflow: hidden; background: #0b0d10; }")
        return Bonito.DOM.div(style, box, fit)
    end
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
    Bonito.route!(server, "/scene" => scene_page(fig, g.dash.view.scene; title = "The Neverending Game · the island"))
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
