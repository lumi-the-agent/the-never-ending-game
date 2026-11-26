# Lit from below (s116): in the evening the sun sinks into the sea and keeps shining from under the
# water. The sky goes dark (NG.SUN_DIM) and the light comes up through the waves: the undersides of the
# tree crowns, the eaves and the friends' chins are lit, like faces over a torch.
# Traced (films, game.dash === nothing): an Emission ring lying on the water around the island, so the
# light reaches the crowns and chins from below without passing the sea's surface (the sea is left as it
# is). Live raster: a warm glowing skin on the water, the sun turned to below and the dark sky.
const NG = NeverendingGame

isdefined(Main, :UNDERLIGHT) || Core.eval(Main, :(const UNDERLIGHT = Dict{Symbol,Any}()))
const U = Main.UNDERLIGHT

const FROM_H = 19.0          # the sun goes under at this hour of the island clock
const TO_H = 20.2            # and comes back up (then the ordinary night)
const RAMP = 12.0            # seconds (real) to sink or to rise
const GLOW = RGBf(1.0, 0.72, 0.38)
const UNDER_DIR = normalize(Vec3f(-0.25, 0.85, -0.45))   # live raster: towards the sun, below the north sea
const LINES = ("The sun fell in!", "It's under the water!", "My chin is warm", "Is it coming back?",
               "Look, it's shining up!", "Don't step on it!", "Ooh, it tickles", "Sun soup!")

struct Underlight <: System end

hour_of(w) = 24 * NG.daytime(w)
wanted(w) = get(U, :force, false) || FROM_H <= hour_of(w) < TO_H

"A flat ring between radii r0 and r1 at height z, its faces up; `alpha(r)` for the vertex colours."
function ring_mesh(r0, r1, z; n = 96, m = 6)
    pts = Point3f[]; faces = GLTriangleFace[]; rs = Float32[]
    for j in 0:m, i in 0:n-1
        r = r0 + (r1 - r0) * (j / m)^1.6
        a = 2pi * i / n
        push!(pts, Point3f(r * cos(a), r * sin(a), z)); push!(rs, r)
    end
    idx(i, j) = j * n + mod(i, n) + 1
    for j in 0:m-1, i in 0:n-1
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.Mesh(pts, faces), rs
end

function skin_colors(rs, r0, r1, u)
    return [RGBAf(GLOW.r, GLOW.g, GLOW.b, Float32(u * 0.75 * (1 - clamp((r - r0) / (r1 - r0), 0, 1))^1.5)) for r in rs]
end

function find_sea(game)
    for p in game.stage.scene.plots
        haskey(p.attributes, :name) && p.attributes[:name][] === :sea && return p
    end
    return nothing
end

function build!(game)
    for k in (:skin, :emitter)
        haskey(U, k) && U[k] isa Makie.AbstractPlot && (delete!(U[k].parent, U[k]); delete!(U, k))
    end
    sc = game.stage.scene
    R = Float32(game.world.island.radius)
    U[:r0] = 0.8f0 * R; U[:r1] = 2.6f0 * R
    if game.dash === nothing                    # traced: a real light under a sea that lets it through
        m, _ = ring_mesh(U[:r0], U[:r1], 0.012f0; n = 28, m = 2)   # every emissive triangle is an area light: keep few (1152 ran the worker out, s116)
        # a film that asks for it from the start gets it visible from the start: a visibility switched
        # after the scene was built did not reach the trace (s116, the first take stayed dark)
        f = get(U, :force, false)
        U[:emitter] = mesh!(sc, m; color = GLOW, visible = f, name = :underlight_emitter,
                            material = NG.Hikari.Emission(color = (GLOW.r, GLOW.g, GLOW.b), strength = get(U, :strength, 2.5)))
        # the emitter lies ON the water: under the glass sea (MediumInterface shadows = 1.33) the worker's GPU
        # was lost twice mid-film (VK_ERROR_DEVICE_LOST, s116)
    else                                        # live raster: no Emission there (it becomes a flat area light)
        m, rs = ring_mesh(U[:r0], U[:r1], 0.03f0)
        U[:rs] = rs
        U[:skin] = mesh!(sc, m; color = skin_colors(rs, U[:r0], U[:r1], 0.0), shading = Makie.NoShading,
                         transparency = true, visible = false, name = :underlight_skin)
    end
    U[:u] = get(U, :force, false) ? 1.0 : 0.0; U[:shown] = -1.0; U[:dim] = 1.0f0
    U[:scene] = sc
end

function NG.start!(::Underlight, game)
    game.stage === nothing && return
    build!(game)
end

function NG.step!(::Underlight, game, dt)
    game.stage === nothing && return
    get(U, :scene, nothing) === game.stage.scene || build!(game)
    w = game.world
    on = wanted(w)
    u = clamp(U[:u] + (on ? 1 : -1) * dt / (get(U, :force, false) ? 0.5 : RAMP), 0.0, 1.0)
    was = U[:u]; U[:u] = u
    (u == 0 && was == 0) && return
    # the sky: in steps of 0.1 (every change re-bakes it)
    dim = Float32(round((1 - 0.96 * u) * 10) / 10)
    dim = max(dim, 0.04f0)
    if abs(dim - U[:dim]) > 0.05f0
        NG.SUN_DIM[] = dim; U[:dim] = dim
    end
    u == 0 && (NG.SUN_DIM[] = 1.0f0; U[:dim] = 1.0f0)
    if haskey(U, :emitter)
        vis = u > 0.5
        if U[:emitter].visible[] != vis
            U[:emitter].visible[] = vis
        end
    elseif haskey(U, :skin) && abs(u - U[:shown]) > 0.02
        U[:skin].visible[] = u > 0
        U[:skin].color[] = skin_colors(U[:rs], U[:r0], U[:r1], u)
        U[:shown] = u
    end
    game.dash === nothing || raster_light!(game, u > 0.5)
    if on && was < 0.5 <= u && !get(U, :force, false)   # the friends notice
        cs = [c for c in w.creatures if c.species != "Lumi" && c.action != :sleep]
        for (k, c) in enumerate(cs[1:min(3, end)])
            NG.say!(w, c, LINES[mod1(rand(1:100) + k, length(LINES))]; duration = 3.5)
        end
    end
    return
end

"""
The live raster has no Emission light, so there the sun itself is turned to shine from under the
north sea (up into the tree crowns). The engine re-aims the sun once it moves 1° (sync_sun!): then
it is turned under again. Back on: the ordinary sun.
"""
function raster_light!(game, under)
    st = game.stage
    if under && (!get(U, :lit, false) || st.sun_dir != U[:sundir])
        Makie.set_light!(st.scene, 1; direction = UNDER_DIR, intensity = 1.6f0, color = GLOW)
        U[:lit] = true; U[:sundir] = st.sun_dir
    elseif !under && get(U, :lit, false)
        dir, inten = NG.sun(game.world)
        Makie.set_light!(st.scene, 1; direction = dir, intensity = inten, color = NG.sun_color(game.world))
        st.sun_dir = dir; st.sun_intensity = inten
        U[:lit] = false
    end
    return
end

function NG.stop!(::Underlight, game)
    game.stage !== nothing && game.dash !== nothing && raster_light!(game, false)
    for k in (:skin, :emitter)
        haskey(U, k) && U[k] isa Makie.AbstractPlot && (delete!(U[k].parent, U[k]); delete!(U, k))
    end
    get(U, :dim, 1.0f0) != 1.0f0 && (NG.SUN_DIM[] = 1.0f0)
    delete!(U, :scene)
    return
end

register!(Underlight())
