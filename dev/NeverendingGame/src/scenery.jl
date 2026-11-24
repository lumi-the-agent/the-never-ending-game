# ── The stage: the world as a RayMakie scene ────────────────────────────────
#
# One `Stage` per view. The same code builds the live (raster) view, path
# traced screenshots and VideoEditor movies; `sync!` copies the world into it.

mutable struct Stage
    scene::Scene
    herds::Dict{String,Any}            # species => Herd plot
    members::Dict{String,Vector{Int32}} # species => creature ids in herd order
    statics::Vector{Any}               # props that do not move (rebuilt on change)
    berries::Any
    berry_pos::Vector{Point3f}
    ball::Any
    overlay::Any          # 2D pixel scene over the view (HUDs, labels), or nothing: see `label_overlay`
    labels::Any           # annotation: every creature on screen, its name and what it says
    props_version::UInt64
    show_names::Bool
    sun_dir::Vec3f        # last sun direction given to the renderer
    sun_intensity::Float32
end

# ── terrain ──────────────────────────────────────────────────────────────────

const SAND = RGBf(0.86, 0.78, 0.58)
const WET_SAND = RGBf(0.62, 0.56, 0.42)
const GRASS = RGBf(0.36, 0.56, 0.24)
const GRASS2 = RGBf(0.48, 0.62, 0.26)
const ROCK = RGBf(0.5, 0.48, 0.45)
const SEABED = RGBf(0.18, 0.4, 0.45)

function terrain_color(is::Island, x, y, h, slope)
    h < -0.05f0 && return Makie.lerp_oklab(WET_SAND, SEABED, smoothstep(-0.1f0, -1.2f0, h))
    h < 0.35f0 && return Makie.lerp_oklab(SAND, GRASS, smoothstep(0.2f0, 0.35f0, h))
    g = Makie.lerp_oklab(GRASS, GRASS2, fbm(x / 5, y / 5, is.seed + 99))
    return Makie.lerp_oklab(g, ROCK, smoothstep(0.55f0, 0.9f0, slope))
end

function terrain_mesh(is::Island; n::Int = 220, extent = 2.2f0 * is.radius)
    xs = range(-extent, extent; length = n)
    H = [terrain_height(is, x, y) for x in xs, y in xs]
    pts = vec([Point3f(x, y, H[i, j]) for (i, x) in enumerate(xs), (j, y) in enumerate(xs)])
    dx = step(xs)
    nrm = vec([begin
        hx = (H[min(i + 1, n), j] - H[max(i - 1, 1), j]) / (2dx)
        hy = (H[i, min(j + 1, n)] - H[i, max(j - 1, 1)]) / (2dx)
        normalize(Vec3f(-hx, -hy, 1))
    end for i in 1:n, j in 1:n])
    cols = [terrain_color(is, p[1], p[2], p[3], 1 - nm[3]) for (p, nm) in zip(pts, nrm)]
    idx(i, j) = (j - 1) * n + i
    fs = GLTriangleFace[]
    for j in 1:(n - 1), i in 1:(n - 1)
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.Mesh(pts, fs; normal = nrm), cols
end

# ── props ────────────────────────────────────────────────────────────────────

const TRUNK = Hikari.Diffuse(color = (0.42, 0.28, 0.17))
const FOLIAGE = Hikari.DiffuseTransmission(reflectance = (0.22, 0.48, 0.16), transmittance = (0.12, 0.3, 0.06))
const BUSH = Hikari.DiffuseTransmission(reflectance = (0.2, 0.42, 0.18), transmittance = (0.1, 0.25, 0.06))
const BERRY = Hikari.Plastic(color = (0.85, 0.08, 0.2), roughness = 0.1)
const STONE = Hikari.Diffuse(color = (0.55, 0.53, 0.5))
const STEM = Hikari.Diffuse(color = (0.3, 0.55, 0.2))

function flower_material(hue::Real)
    c = convert(RGB{Float32}, HSV(360hue, 0.75, 0.95))
    return Hikari.Plastic(color = (c.r, c.g, c.b), roughness = 0.5)
end

rot_z(a) = qrotation(Vec3f(0, 0, 1), Float32(a))

"Static props: trees, bushes, rocks, flowers. Returns the plots."
function add_static_props!(scene::Scene, w::World)
    plots = Any[]
    trees = filter(p -> p.kind === :tree, w.props)
    if !isempty(trees)
        push!(plots, meshscatter!(scene, [p.pos for p in trees]; marker = shape(:cylinder), material = TRUNK,
                                  markersize = [Vec3f(0.18, 0.18, 2.2) .* p.scale for p in trees], name = :tree_trunks))
        canopy = Point3f[]; csize = Vec3f[]
        for p in trees, (o, r) in ((Vec3f(0, 0, 2.7), 1.25f0), (Vec3f(0.5, 0.3, 2.2), 0.95f0), (Vec3f(-0.45, -0.25, 2.3), 0.9f0))
            push!(canopy, p.pos + rot_z(p.yaw) * (o * p.scale)); push!(csize, Vec3f(r, r, 0.85r) * p.scale)
        end
        push!(plots, meshscatter!(scene, canopy; marker = shape(:sphere), material = FOLIAGE, markersize = csize,
                                  name = :tree_canopies))
    end
    bushes = filter(p -> p.kind === :bush, w.props)
    if !isempty(bushes)
        bp = Point3f[]; bs = Vec3f[]
        for p in bushes, (o, r) in ((Vec3f(0, 0, 0.35), 0.5f0), (Vec3f(0.3, 0.2, 0.28), 0.38f0), (Vec3f(-0.28, 0.15, 0.25), 0.36f0))
            push!(bp, p.pos + rot_z(p.yaw) * o); push!(bs, Vec3f(r))
        end
        push!(plots, meshscatter!(scene, bp; marker = shape(:sphere), material = BUSH, markersize = bs, name = :bushes))
    end
    rocks = filter(p -> p.kind === :rock, w.props)
    if !isempty(rocks)
        push!(plots, meshscatter!(scene, [p.pos for p in rocks]; marker = shape(:sphere), material = STONE,
                                  markersize = [Vec3f(0.8, 0.6, 0.45) * p.scale for p in rocks],
                                  rotation = [rot_z(p.yaw) * qrotation(Vec3f(1, 0, 0), 0.3f0 * sin(p.yaw)) for p in rocks],
                                  name = :rocks))
    end
    flowers = filter(p -> p.kind === :flower, w.props)
    if !isempty(flowers)
        push!(plots, meshscatter!(scene, [p.pos for p in flowers]; marker = shape(:cylinder), material = STEM,
                                  markersize = [Vec3f(0.012, 0.012, 0.25p.scale) for p in flowers], name = :flower_stems))
        for hue in unique(get(p.data, "hue", 0.0) for p in flowers)
            fs = filter(p -> get(p.data, "hue", 0.0) == hue, flowers)
            push!(plots, meshscatter!(scene, [p.pos + Point3f(0, 0, 0.25p.scale) for p in fs]; marker = shape(:sphere),
                                      material = flower_material(hue), markersize = [Vec3f(0.06, 0.06, 0.035) * p.scale for p in fs]))
        end
    end
    return plots
end

function berry_positions(w::World)
    pts = Point3f[]
    for p in w.props
        p.kind === :bush || continue
        for k in 1:get(p.data, "berries", 0)
            a = p.yaw + 1.1f0 * k
            push!(pts, p.pos + Point3f(0.42cos(a), 0.42sin(a), 0.3f0 + 0.08f0 * (k % 3)))
        end
    end
    return isempty(pts) ? [Point3f(0, 0, -10)] : pts
end

props_version(w::World) = hash([(p.id, p.kind) for p in w.props if p.kind !== :ball])

# ── light ────────────────────────────────────────────────────────────────────

"""
The exposure of every RayMakie screen (`RayMakie.Screen(...; exposure = FILM_EXPOSURE)`).
The sun is this much dimmer than RayMakie shows it: WGLMakie draws the sun as a
plain directional light, without exposure or tonemapping, so a sun as bright as
the tracer wants burns the browser view out.
"""
const FILM_EXPOSURE = 1.5f0

"Hours of the light's sunrise and sunset: the evening stays golden until the sunset plugin's sun sinks into the sea (~19:54)."
const LIGHT_RISE, LIGHT_SET = 6.0, 20.0

"""
The phase of the sun's light (0.25 sunrise, 0.5 its noon, 0.75 sunset) for the time of day. Until
s54 it was the plain `daytime`, which set the light at 18:00: at 18:24 the island was night-dark
while the evening sun still hung over the sea (review s53).
"""
function light_phase(w::World)
    h = 24 * daytime(w)
    LIGHT_RISE <= h <= LIGHT_SET && return 0.25 + 0.5 * (h - LIGHT_RISE) / (LIGHT_SET - LIGHT_RISE)
    return 0.75 + 0.5 * mod(h - LIGHT_SET, 24) / (24 - (LIGHT_SET - LIGHT_RISE))
end

"Sun direction and intensity for the time of day (the sun never quite sets: night is moonlit)."
function sun(w::World)
    d = light_phase(w)
    a = 2pi * (d - 0.25)                     # sunrise at 0.25, noon at 0.5
    elev = max(0.2f0 + 0.15f0 * night_factor(w), sin(a))   # moon stands high so night keeps top light; the evening sun sinks to ~11° (s54: a warmer sky; 7° left the grass dark)
    dir = normalize(Vec3f(cos(a), -0.45, elev))
    intensity = Float32(0.85 + 0.95 * smoothstep(0.0, 0.25, sin(a))) / FILM_EXPOSURE   # night darker than day, still cosy and readable (0.62 was murky at dusk)
    return dir, intensity * SUN_DIM[]
end

"""
Weather dims the sun (and its sky) by this factor: plugins/showers.jl greys the island while it
rains. Change it in a few big steps: every change of more than 0.03 re-bakes the sky (35 ms).
"""
const SUN_DIM = Ref(1.0f0)

"""
What the sky shows below the horizon: a soft sea haze. With the ground off it was black, and the
edge of the baked sky map (octahedral, so the horizon runs diagonally through its texels) drew a
jagged grey sawtooth along the sea horizon in the raster and in traced clips (todos #131, #171).
Brighter washes the island out (it also lights things from below); darker brings the band back.
s45: 0.45/0.55/0.65 -> 0.6/0.68/0.78 lifts the raster's shadows (eye-level pixels below 0.2:
2.3% -> 1.5%, mean 0.476 -> 0.477, the same hour; media/s45/alb2-compare.png); 0.7/0.78/0.85 also
held. The raster ignores AmbientLight: this bounce is its only shadow fill besides the sky.
"""
const SKY_GROUND = RGBf(0.6, 0.68, 0.78)

"""
The lights of a stage. RayMakie lights it with the sun and its sky; WGLMakie has
no sky, it draws the sun as a directional light plus the flat `AmbientLight`
fill, which RayMakie leaves out under a sky. So the fill only changes the
browser view.
"""
function stage_lights(w::World)
    dir, intensity = sun(w)
    return [Makie.SunSkyLight(dir; intensity, turbidity = 2.5f0, ground_enabled = true, ground_albedo = SKY_GROUND),
            Makie.AmbientLight(RGBf(0.34, 0.37, 0.45))]
end

"""
The sun's colour: white by day, golden around sunrise and sunset (the golden hour),
blue moonlight at night.
"""
function sun_color(w::World)
    s = sin(2pi * (light_phase(w) - 0.25))
    gold = Float32(smoothstep(-0.2, 0.0, s) * (1 - smoothstep(0.08, 0.5, s)))
    nf = night_factor(w)
    day = RGBf(1, 1 - 0.26f0 * gold, 1 - 0.58f0 * gold)   # s54: warmer evening (was 0.2, 0.45)
    return RGBf(day.r * (1 - 0.6f0nf), day.g * (1 - 0.42f0nf), day.b)
end

"0 by day, 1 in deep night (smooth), for the moon tint."
night_factor(w::World) = Float32(1 - smoothstep(-0.1, 0.25, sin(2pi * (light_phase(w) - 0.25))))

# ── building and syncing ─────────────────────────────────────────────────────

"""
    Stage(scene, world)

Fill `scene` (a 3D scene with a `SunSkyLight` as first light, see
`stage_scene`) with the island, props and creatures of `world`.
"""
function Stage(scene::Scene, w::World; show_names::Bool = true)
    m, cols = terrain_mesh(w.island)
    mesh!(scene, m; color = cols, material = Hikari.Diffuse(color = (1, 1, 1)), name = :terrain)
    # to the horizon: a 800 m sea showed its edge in traced stills. `color` is what the browser draws
    # (WGLMakie ignores the glass; without it the sea was near-white there), RayMakie uses the material.
    mesh!(scene, Rect3f(Vec3f(-3000, -3000, -0.02), Vec3f(6000, 6000, 0.02)); color = RGBAf(0.2, 0.45, 0.62, 1.0),
          material =Hikari.Glass(color = (0.62, 0.86, 0.9), ior = 1.33, roughness = 0.02), name = :sea)
    mesh!(scene, Rect3f(Vec3f(-3000, -3000, -1.5), Vec3f(6000, 6000, 0.01)); color = SEABED,
          material = Hikari.Diffuse(color = (SEABED.r, SEABED.g, SEABED.b)), name = :seabed)
    statics = add_static_props!(scene, w)
    berries = meshscatter!(scene, berry_positions(w); marker = shape(:sphere), material = BERRY,
                           markersize = Vec3f(0.06), name = :berries)
    ballp = something(findfirst(p -> p.kind === :ball, w.props), 0)
    ball = mesh!(scene, Sphere(Point3f(0), 0.25f0); material = Hikari.Plastic(color = (0.95, 0.25, 0.15), roughness = 0.15),
                 name = :ball, visible = ballp != 0)
    overlay = label_overlay(scene)
    labels = overlay === nothing || !show_names ? nothing :
        annotation!(overlay, Vec2f[], Point2f[]; text = Makie.RichText[], fontsize = 16, align = (:center, :bottom),
                    justification = :center, textcolor = LABEL_DAY, color = RGBAf(LABEL_DAY, 0.55))
    labels === nothing || push!(TAGS_AS_GIVEN, labels)
    st = Stage(scene, Dict{String,Any}(), Dict{String,Vector{Int32}}(), statics, berries, berry_positions(w), ball,
               overlay, labels, props_version(w), show_names, Vec3f(0), 0.0f0)
    sync!(st, w)
    return st
end

"A 3D scene ready for a `Stage`: sun and sky, camera."
function stage_scene(w::World; size = (1280, 720), kw...)
    scene = Scene(; size, lights = stage_lights(w), kw...)
    cam3d!(scene)
    return scene
end

function herd_for!(st::Stage, species::String)
    get!(st.herds, species) do
        st.members[species] = Int32[]
        herd!(st.scene, Point3f[]; species = SPECIES[species], motion = Vec3f[], state = Vec3f[],
              name = Symbol(lowercase(species)))
    end
end

"Copy the world into the stage. Cheap: a few array writes per species."
function sync!(st::Stage, w::World)
    t = Float32(w.t)
    groups = Dict{String,Vector{Creature}}()
    for c in w.creatures
        push!(get!(groups, c.species, Creature[]), c)
    end
    for (sp, cs) in groups
        h = herd_for!(st, sp)
        st.members[sp] = [c.id for c in cs]
        Makie.update!(h, [c.pos for c in cs]; motion = [Vec3f(c.yaw, c.phase, c.mood) for c in cs],
                      state = [Vec3f(action_code(c.action), c.extra, c.seed) for c in cs], time = t)
    end
    for (sp, h) in st.herds   # species with nobody left
        haskey(groups, sp) && continue
        isempty(st.members[sp]) && continue
        st.members[sp] = Int32[]
        Makie.update!(h, Point3f[]; motion = Vec3f[], state = Vec3f[])
    end
    v = props_version(w)
    if v != st.props_version
        foreach(p -> delete!(st.scene, p), st.statics)
        st.statics = add_static_props!(st.scene, w)
        st.props_version = v
    end
    bpos = berry_positions(w)
    if bpos != st.berry_pos
        st.berries[1] = bpos
        st.berry_pos = bpos
    end
    i = findfirst(p -> p.kind === :ball, w.props)
    if i !== nothing
        b = w.props[i]
        translate!(st.ball, b.pos + Point3f(0, 0, ball_radius(b)))
        dir = Float32(get(b.data, "dir", 0.0)); roll = Float32(get(b.data, "roll", 0.0))
        Makie.rotate!(st.ball, rot_z(dir) * qrotation(Vec3f(0, 1, 0), roll))
    end
    sync_text!(st, w)
    sync_sun!(st, w)
    return st
end

"""
Re-aim the sun only once it moved 1°: every new direction re-bakes the sky
(35 ms on 32 threads), so a sun following every frame would drop frames.
"""
function sync_sun!(st::Stage, w::World)
    dir, intensity = sun(w)
    if dot(dir, st.sun_dir) < cosd(1.0f0) || abs(intensity - st.sun_intensity) > 0.03f0
        Makie.set_light!(st.scene, 1; direction = dir, intensity = intensity, color = sun_color(w))
        st.sun_dir = dir; st.sun_intensity = intensity
    end
    return st
end

head_point(w::World, c::Creature) = c.pos + Point3f(0, 0, species_of(c).height)

const LABEL_DAY = RGBf(0.07, 0.08, 0.1)
const LABEL_NIGHT = RGBf(0.93, 0.94, 0.98)

"""
    label_overlay(scene) -> Scene or nothing

A 2D pixel scene over the 3D `scene`'s viewport, for its labels and for HUDs.
It is a child of the figure's root scene, drawn after the 3D view: RayMakie
traces the 3D scene and draws 2D scenes over it, but not a 2D child of the
traced scene. A 3D scene that is a root itself (`stage_scene`) gets none.
"""
function label_overlay(scene::Scene)
    root = Makie.root(scene)
    root === scene && return nothing
    return Scene(root; viewport = scene.viewport, camera = campixel!, clear = false)
end

"Where `p` is in `scene`'s viewport in pixels, or `nothing` when it is behind the camera or too near the border for a label."
function on_screen(scene::Scene, p::Point3f)
    c = Makie.project(scene, :data, :clip, p)
    # keep a margin: a name pinned to the border would be cut off by the viewport
    (abs(c[1]) <= 0.82 && -0.9 <= c[2] <= 0.9 && -1 <= c[3] <= 1) || return nothing
    return Point2f(Makie.project(scene, :data, :pixel, p))
end

"A creature's label: its name, and below it what it is saying."
function creature_label(c::Creature, said::Union{Nothing,Speech})
    name = rich(c.name; font = :bold)
    return said === nothing ? rich(name) : rich(name, "\n", rich(said.text; fontsize = 15))
end

"""
Label the few creatures nearest the camera with Makie's `annotation`, each tag
right above its own head (`tag_spots`), with a line to the head when a tag had
to move up past another.
"""
function sync_text!(st::Stage, w::World)
    st.labels === nothing && return st
    targets = Point2f[]
    texts = Makie.RichText[]
    plain = String[]        # the same, for the tags' sizes
    # only the few creatures close to the camera (and whoever talks) get a tag: ten names over
    # the scene hid the trees and each other. Talking ones first, then the nearest.
    eye = Point3f(st.scene.camera.eyeposition[])
    cands = Tuple{Float32,Int}[]
    for (i, c) in enumerate(w.creatures)
        d = norm(Vec3f(c.pos - eye))
        talking = any(s -> s.who == c.id, w.speech)
        # the creature you steer or the camera watches places its tag first, right on its own head (s59 tester:
        # a nearer creature's tag sat on Lumi's head and Lumi's floated 80 px up)
        hero = c.controlled || c.id == AUTO_SUBJECT[][1]
        (talking || hero ? d < 22.0f0 : d < 13.0f0) || continue
        push!(cands, (hero ? d - 1000.0f0 : talking ? d - 100.0f0 : d, i))
    end
    sort!(cands)
    sleepers = 0
    for (_, i) in cands
        length(targets) >= 3 && break
        c = w.creatures[i]
        hero = c.controlled || c.id == AUTO_SUBJECT[][1]
        # a heap of sleepers under four tags hid them (perfectionist-0030): one sleeper's name is enough
        (c.action === :sleep || c.goal.kind === :sleep) && (sleepers += 1) > 1 && continue   # also the ones on their way to bed
        hp = head_point(w, c)
        px = on_screen(st.scene, hp)
        px === nothing && continue
        # a tag over a tree crown with nobody in view (perfectionist-0064): a creature hidden behind a
        # trunk, crown or bush gets no tag (the one you steer or the camera watches keeps its own: its head
        # often shows over a bush that `obstruction` counts in full)
        hero || obstruction(w, eye, hp) < 0.6f0 || continue
        said = findfirst(s -> s.who == c.id, w.speech)
        push!(targets, px)
        push!(texts, creature_label(c, said === nothing ? nothing : w.speech[said]))
        push!(plain, said === nothing ? c.name : c.name * "\n" * w.speech[said].text)
    end
    # light text with a dark outline: readable on sky, grass and dark tree crowns, by day and by night
    st.labels in TAGS_AS_GIVEN || fixed_tags!(st)
    txt = st.labels.plots[1]
    txt.strokewidth[] == 3 || (txt.strokewidth[] = 3; txt.strokecolor[] = RGBAf(0.06, 0.07, 0.1, 0.95))
    col = LABEL_NIGHT
    Makie.update!(st.labels, tag_spots(targets, plain), targets; text = texts, textcolor = col, color = RGBAf(0.06, 0.07, 0.1, 0.6))
    return st
end

"Label plots that take their tags where `tag_spots` puts them (two point vectors)."
const TAGS_AS_GIVEN = Base.IdSet{Any}()

"Replace a stage's labels with ones placed as given: a stage built before s59 had a repelling layout."
function fixed_tags!(st::Stage)
    old = st.labels
    st.labels = annotation!(st.overlay, Vec2f[], Point2f[]; text = Makie.RichText[], fontsize = 16, align = (:center, :bottom),
                            justification = :center, textcolor = LABEL_DAY, color = RGBAf(LABEL_DAY, 0.55),
                            visible = old.visible[])
    delete!(st.overlay, old)
    push!(TAGS_AS_GIVEN, st.labels)
    return st
end

"""
Where each tag goes: right above its own creature's head (perfectionist-0058: a repelling layout
pushed the tags onto bushes and other creatures' heads). The steered or watched creature first, then nearest; a tag that would cover one
already placed moves up just past it. Sizes are estimated from the text (bold 16 px).
"""
function tag_spots(targets::Vector{Point2f}, texts)
    placed = Rect2f[]
    spots = Vec2f[]          # offsets from the heads (the annotation's labelspace is :relative_pixel)
    for (p, t) in zip(targets, texts)
        lines = split(t, '\n')
        w = 8.5f0 * maximum(length, lines) + 12f0
        h = 20f0 * length(lines) + 6f0
        y = p[2] + 14f0
        for _ in 1:length(placed) + 1
            hit = findfirst(r -> abs(r.origin[1] + r.widths[1] / 2 - p[1]) < (r.widths[1] + w) / 2 &&
                                 r.origin[2] < y + h && y < r.origin[2] + r.widths[2], placed)
            hit === nothing && break
            y = placed[hit].origin[2] + placed[hit].widths[2] + 2f0
        end
        push!(placed, Rect2f(p[1] - w / 2, y, w, h))
        push!(spots, Vec2f(0, y - p[2]))
    end
    return spots
end

"Point the camera of `scene` from `eye` at `target`."
look!(scene::Scene, eye, target) = update_cam!(scene, Vec3f(eye), Vec3f(target), Vec3f(0, 0, 1))

"How close the segment `a`→`b` passes to point `p`."
function segment_distance(a, b, p)
    ab = Vec3f(b - a)
    t = clamp(dot(Vec3f(p - a), ab) / max(dot(ab, ab), 1.0f-6), 0, 1)
    return norm(Vec3f(a + t * ab - p))
end

"How much is in the way from `eye` to `target`: tree crowns and trunks on the line or right at the eye, hills. 0 = clear view."
function obstruction(w::World, eye, target)
    o = 0.0f0
    for p in w.props
        p.kind === :tree || continue
        # the crown as two balls (generated trees: leaves from ~1.4 to 3.7 m at scale 1)
        for z in (2.0f0, 2.9f0)
            crown = p.pos + Point3f(0, 0, z * p.scale)
            o += max(0.0f0, 1.25f0 * p.scale + 0.2f0 - segment_distance(eye, target, crown))
            o += 0.5f0 * max(0.0f0, 1.25f0 * p.scale + 1.0f0 - norm(Vec3f(eye - crown)))   # leaves filling the picture
        end
        o += 2 * max(0.0f0, 0.5f0 - segment_distance(eye, target, p.pos + Point3f(0, 0, 1.0p.scale)))
    end
    # bushes and other creatures right in front of the lens (a pig's back filled a third of the follow view)
    for p in w.props
        p.kind === :bush || continue
        b = p.pos + Point3f(0, 0, 0.45f0 * p.scale)
        norm(Vec3f(b - target)) < 1.2f0 && continue
        o += max(0.0f0, 0.75f0 * p.scale - segment_distance(eye, target, b))
    end
    for c in w.creatures
        h = species_of(c).height
        m = c.pos + Point3f(0, 0, 0.5f0 * h)
        # the subject itself: a friend right beside it still blocks when it stands in front of the lens
        # (a pig's back filled the ball rally view, s31)
        hypot(c.pos[1] - target[1], c.pos[2] - target[2]) < 0.35f0 && continue
        o += max(0.0f0, 0.6f0 * h + 0.15f0 - segment_distance(eye, target, m))
        o += max(0.0f0, 0.5f0 * h + 1.0f0 - norm(Vec3f(eye - m)))      # a back right at the lens (s32 day sheet)
    end
    for s in range(0.1f0, 0.9f0; length = 9)
        q = eye + s * (target - eye)
        terrain_height(w.island, q[1], q[2]) > q[3] && (o += 2)
    end
    # pier planks just under the lens filled half the follow view (perfectionist s27, camera)
    for s in (0.0f0, 0.15f0, 0.3f0, 0.45f0)
        q = eye + s * (target - eye)
        h = walkway_height(q[1], q[2])
        h !== nothing && q[3] < h + 1.3f0 && (o += 1)
    end
    for f in values(CAMERA_BLOCKERS)   # plugin scenery (the pond's reeds)
        o += Float32(Base.invokelatest(f, eye, target))
    end
    return o
end

"Does anything big (tree canopy or trunk, terrain) block the view from `eye` to `target`?"
blocked(w::World, eye, target) = obstruction(w, eye, target) > 0

"""
    follow_view(w, c; distance, height) -> (eye, target)

A view of creature `c` from behind and above (`front`: from the front side, its face),
turned around it until no tree or hill is in the way.
"""
function follow_view(w::World, c::Creature; distance = 4.6f0, height = 1.5f0, zoom::Bool = true, closer::Bool = true,
                     front::Bool = false)
    # close and low (a 7 m / 4 m high view made the subject a small blob, perfectionist-0024)
    sh = species_of(c).height
    target = c.pos + Point3f(0, 0, 0.6f0 * sh)
    z = zoom ? clamp(sh / 1.2f0, 0.6f0, 1.2f0) : 1f0     # small creatures get a closer camera, so they fill as much of the view
    distance *= z; height *= z
    heading = c.yaw + species_of(c).heading
    # never steeper than ~34° (tan = 0.68): the 4x-high fallback and the 3x-height step looked straight
    # down on heads (perfectionist-0064, todo #239)
    best = (Inf32, target + Point3f(-distance * cos(heading), -distance * sin(heading), 0.6f0 * distance))
    k = 0
    # no eye closer than 0.85 distance: at 0.6 a head filled half the view (perfectionist-0055, todo #239)
    # a step back at about the same height before any high view (high views look down on heads, s56)
    # `front`: a three-quarter view of the face (watching, not steering: perfectionist-0043 found the
    # follow camera showing backs). Every face-side angle at every distance comes before a turn round
    # to the side or back (s56: trying all turns at one distance first showed backs half the time).
    near = front ? (0.8f0, -0.8f0, 0.4f0, -0.4f0, 1.2f0, -1.2f0, 0.0f0) : (0.35f0, -0.35f0, 0.9f0, -0.9f0)
    far = front ? (1.6f0, -1.6f0, 2.4f0, -2.4f0, 3.14f0) : (1.6f0, -1.6f0, 2.4f0, -2.4f0, 3.14f0)
    for turns in (near, far), (d, h) in ((distance, height), (0.85f0 * distance, 0.7f0 * height), (1.25f0 * distance, 1.2f0 * height),
                   (distance, 2height), (1.2f0 * distance, 3height)), turn in turns
        !closer && d < distance && continue      # a group view: a closer eye cuts players off the picture
        a = front ? heading + turn : heading + Float32(pi) + turn
        eye = target + Point3f(d * cos(a), d * sin(a), min(h + 0.15f0 * d, 0.68f0 * d))
        score = obstruction(w, eye, target) + 0.02f0 * k     # a clear view, the earlier (closer, lower) the better
        score < best[1] && (best = (score, eye))
        score <= 0.02f0 * k && break
        k += 1
    end
    return best[2], target
end
