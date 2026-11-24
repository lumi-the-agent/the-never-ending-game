# ── Progress shots: the same views after every session ──────────────────────
#
# The host asks for these after each work session (live command `views`), so
# the human, the author and the reviewers can put two sessions side by side
# and see what changed: the whole island from above, the island at eye level,
# and the dashboard as the human sees it. The cameras are fixed relative to the
# island, so only the world changes between two sets.

"Eye and target of each fixed view, relative to the island (radius `r`)."
function progress_cameras(is::Island)
    r = is.radius
    return [
        "overview" => (Vec3f(0.55r, -0.75r, 0.6r), Vec3f(0, 0, 0)),
        "eye-level" => (Vec3f(ground(is, (-0.7r, -0.2r))) + Vec3f(0, 0, 1.6), Vec3f(ground(is, (0.2r, 0.1r))) + Vec3f(0, 0, 1)),
    ]
end

"""
    progress_views!(game, dir) -> Vector{String}

The dashboard as the human sees it now, then from each fixed camera, into
`dir`. The game's own view is pointed at each camera and rendered: plugins
draw into its scene, so only it has everything. The game's camera takes over
again on the next frame. The host asks the sandbox, so the human's view never
jumps.
"""
function progress_views!(g::Game, dir::AbstractString)
    mkpath(dir)
    st = g.stage
    paths = String[]
    path = joinpath(dir, "dashboard.png")
    Makie.save(path, Makie.colorbuffer(g.screen))
    push!(paths, path)
    for (name, (eye, target)) in progress_cameras(g.world.island)
        update_cam!(st.scene, eye, target, Vec3f(0, 0, 1))
        sync_text!(st, g.world)
        path = joinpath(dir, name * ".png")
        Makie.save(path, Makie.colorbuffer(g.screen))
        push!(paths, path)
    end
    return paths
end

function live_command(g::Game, ::Val{:views}, msg)
    g.screen === nothing && return Dict{String,Any}("ok" => false, "error" => "the game runs headless")
    return Dict{String,Any}("ok" => true, "paths" => progress_views!(g, String(msg["dir"])))
end

# ── Lumi's eyes: what it sees, for its perception before a session ───────

"""
    lumi_eyes!(game, dir) -> Vector{String}

What Lumi sees now, from its eyes: ahead, to its left, behind and to its
right, into `dir` (the 3D view only, without the dashboard around it). The
game's own view is pointed there and rendered, like the progress shots; the
game's camera takes over again on the next frame. The host asks the sandbox,
a fresh copy of the human's world, before every work session.
"""
function lumi_eyes!(g::Game, dir::AbstractString)
    mkpath(dir)
    c = creature(g.world, "Lumi")
    sp = species_of(c)
    st = g.stage
    paths = String[]
    # the overlay (bubbles, hints) sits where the game's camera put it, not where Lumi looks
    shown = st.overlay.visible[]
    st.overlay.visible[] = false
    for (name, turn) in ("ahead" => 0.0f0, "left" => Float32(pi / 2), "behind" => Float32(pi), "right" => -Float32(pi / 2))
        a = c.yaw + sp.heading + turn
        d = Vec3f(cos(a), sin(a), 0)
        # just in front of the face, so Lumi's own head is not in the picture
        eye = c.pos + Point3f(0, 0, 0.8f0 * sp.height) + 0.5f0 * d
        look!(st.scene, eye, eye + 10f0 * d - Vec3f(0, 0, 1))
        sync_text!(st, g.world)
        path = joinpath(dir, name * ".png")
        Makie.save(path, view_pixels(g))
        push!(paths, path)
    end
    st.overlay.visible[] = shown
    return paths
end

"The 3D view's pixels out of a render of the whole dashboard (image rows run from the top)."
function view_pixels(g::Game)
    img = Makie.colorbuffer(g.screen)
    vp = g.dash.view.scene.viewport[]
    s = size(img, 2) / size(g.dash.fig.scene)[1]        # pixels per figure unit
    x0, y0 = round.(Int, s .* minimum(vp))
    w, h = round.(Int, s .* widths(vp))
    H = size(img, 1)
    return img[(H - y0 - h + 1):(H - y0), (x0 + 1):(x0 + w)]
end

function live_command(g::Game, ::Val{:eyes}, msg)
    g.screen === nothing && return Dict{String,Any}("ok" => false, "error" => "the game runs headless")
    return Dict{String,Any}("ok" => true, "paths" => lumi_eyes!(g, String(msg["dir"])))
end
