# ── Cameras, clips and screenshots ──────────────────────────────────────────

"""
A camera that moves smoothly. `mode`:
- `:follow`   behind `subject` (a creature id), or whoever is most interesting when 0
- `:orbit`    slowly around `center`
- `:fixed`    stays where it is put (the dashboard's free camera)
"""
mutable struct CameraRig
    mode::Symbol
    subject::Int32
    eye::Point3f
    target::Point3f
    center::Point3f
    angle::Float32
    smoothing::Float32     # seconds to close most of the gap
end
CameraRig(; mode = :follow, subject = 0, smoothing = 0.8f0) =
    CameraRig(mode, subject, Point3f(20, -20, 12), Point3f(0), Point3f(0), 0.0f0, smoothing)

"""
A plugin's `w -> creature id or nothing`: a moment worth watching (a race, a show) that the
follow camera turns to while nobody steers it. Set `CAMERA_FOCUS[] = f`, back to `nothing` to stop.
"""
const CAMERA_FOCUS = Ref{Any}(nothing)

"""
More moments worth watching, one per plugin: `CAMERA_MOMENTS["myplugin"] = w -> id or nothing`
(asked after `CAMERA_FOCUS`). Delete the key in the plugin's `stop!`.
"""
const CAMERA_MOMENTS = Dict{String,Any}()
"Moments asked before CAMERA_FOCUS and the others (the dict order is arbitrary): Lumi building what was just published (plugins/builder.jl), Lumi watering its patch (garden.jl, s56: another moment took the camera)."
const MOMENTS_FIRST = ("builder", "garden")

"""
Plugin scenery the cameras should not look through (reeds, fences): `CAMERA_BLOCKERS["myplugin"] =
(eye, target) -> penalty` (0 when clear, about 1 per blocked sample), added to `obstruction`.
Delete the key in the plugin's `stop!`.
"""
const CAMERA_BLOCKERS = Dict{String,Any}()

"""
Whole shots a plugin offers for quiet times (the night, when everyone sleeps):
`CAMERA_SHOTS["myplugin"] = w -> (eye, target) or nothing`. The follow camera with no subject
takes one when no moment, chat or speech is worth watching. Delete the key in `stop!`.
"""
const CAMERA_SHOTS = Dict{String,Any}()

"""
Groups a plugin wants framed together (two critters passing a ball, and the ball):
`CAMERA_GROUPS["myplugin"] = w -> (subject_id, points) or nothing`. When the follow camera with
no subject watches `subject_id`, it frames all `points` from the side instead of following
one creature from behind; `(subject_id, points, (eye, target))` takes that view instead.
Delete the key in `stop!`.
"""
const CAMERA_GROUPS = Dict{String,Any}()

"A side view that holds every point of `pts` (centre between them, back off with their spread)."
function group_view(w::World, c::Creature, pts)
    ctr = sum(Vec3f.(pts)) / length(pts)
    a, b = pts[1], pts[1]; far = 0.0f0
    for p in pts, q in pts
        d = hypot(p[1] - q[1], p[2] - q[2])
        d > far && (far = d; a = p; b = q)
    end
    ax = far > 0.1f0 ? atan(b[2] - a[2], b[1] - a[1]) : c.yaw + species_of(c).heading
    fake = Creature(c.id, c.name, c.species, Point3f(ctr), ax + 1.5708f0 - species_of(c).heading,
                    c.action, c.phase, c.mood, c.extra, c.seed, c.needs, c.traits, c.goal, false, String[])
    eye, target = follow_view(w, fake; distance = clamp(1.15f0 * far + 3.5f0, 5f0, 15f0), height = 1.6f0 + 0.25f0 * far, zoom = false, closer = false)
    # a steep or turned eye can still cut a player off the picture: back off along the view line until all are in
    # (the vertical half view is ~22°; full suite s32: one critter 31° off)
    for _ in 1:4
        fwd = normalize(Vec3f(target - eye))
        maximum(p -> acosd(clamp(dot(fwd, normalize(Vec3f(p - eye))), -1.0f0, 1.0f0)), pts) < 20 && break
        eye = target + 1.3f0 * (eye - target)
    end
    return eye, target
end

"The creature worth watching: a plugin's moment (`CAMERA_FOCUS`, `CAMERA_MOMENTS`), someone in an interaction or talking, else Lumi."
function interesting_subject(w::World)
    id = moment_subject(w)
    id === nothing || return id
    i = findfirst(c -> c.species == "Lumi", w.creatures)
    return i === nothing ? first(w.creatures).id : w.creatures[i].id
end

"The subject of the first MOMENTS_FIRST moment that has one, else `nothing`."
function first_moment(w::World)
    for k in MOMENTS_FIRST
        g = get(CAMERA_MOMENTS, k, nothing)
        g === nothing && continue
        id = Base.invokelatest(g, w)
        id === nothing || return Int32(id)
    end
    return nothing
end

"Who is worth watching right now (a plugin's moment, a chat, someone talking), or `nothing`."
function moment_subject(w::World)
    id = first_moment(w)
    id === nothing || return id
    f = CAMERA_FOCUS[]
    if f !== nothing
        id = Base.invokelatest(f, w)
        id === nothing || return Int32(id)
    end
    for (k, g) in CAMERA_MOMENTS
        k in MOMENTS_FIRST && continue
        id = Base.invokelatest(g, w)
        id === nothing || return Int32(id)
    end
    isempty(w.interactions) || return first(w.interactions).a
    isempty(w.speech) || return last(w.speech).who
    return nothing
end

"A plugin's quiet-time shot `(eye, target)` when nothing is worth watching, else `nothing`."
function camera_shot(w::World)
    moment_subject(w) === nothing || return nothing
    any(c -> c.controlled, w.creatures) && return nothing      # a player is playing: watch them
    for f in values(CAMERA_SHOTS)
        v = Base.invokelatest(f, w)
        v === nothing || return v
    end
    return nothing
end

"The follow camera's own subject and since when (`w.t`): see `held_subject`."
const AUTO_SUBJECT = Ref((Int32(0), 0.0))
const SUBJECT_HOLD = 6.0     # seconds

"""
The creature the free follow camera watches: `interesting_subject`, but one it took stays for
`SUBJECT_HOLD` seconds (chats and speech switched it every second or two: perfectionist-0043).
While a player steers a creature (mini games) the subject changes at once.
"""
function held_subject(w::World)
    id = interesting_subject(w)
    # the biggest group moment (a dance ring, three or more) is the show: it beats chats and races
    # (perfectionist-0043: the panel said three critters dance, none was on screen; s44 probe: the
    # camera watched the ring in 8 of 21 samples)
    # ... but not over a MOMENTS_FIRST moment (Lumi building: s48, a dance ring kept the camera off the build)
    if !any(c -> c.controlled, w.creatures) && first_moment(w) === nothing
        n = 2
        for g in values(CAMERA_GROUPS)
            v = Base.invokelatest(g, w)
            v === nothing || length(v[2]) <= n || !any(c -> c.id == v[1], w.creatures) || (n = length(v[2]); id = Int32(v[1]))
        end
    end
    cur, since = AUTO_SUBJECT[]
    # a player is playing (a mini game's focus): no hold. The wild race's leader changes every
    # second or two, so its focus is held like any other moment.
    if id != cur && !any(c -> c.controlled, w.creatures) && 0 <= w.t - since < SUBJECT_HOLD && any(c -> c.id == cur, w.creatures)
        return cur
    end
    id == cur || (AUTO_SUBJECT[] = (id, w.t))
    return id
end

"""
A watched creature's view: its face from the front three-quarter, unless trees or bushes block
that clearly more than the view from behind (the front search alone left a bush in front of
Cumulus, obstruction 0.68 vs 0.15 from behind, s44).
"""
function face_view(w::World, c::Creature)
    f = follow_view(w, c; front = true)
    of = obstruction(w, f...)
    of <= 0.05f0 && return f
    b = follow_view(w, c)
    ob = obstruction(w, b...)
    best, ob = ob + 0.15f0 < of ? (b, ob) : (f, of)
    ob <= 0.3f0 && return best
    # both blocked (Lumi in a tree nook stayed behind a trunk at 0.58 for 12 s, s46): turn the front
    # view round the creature and take the clearest
    e, t = f
    v = e - c.pos
    for a in (1.05f0, -1.05f0, 2.1f0, -2.1f0)
        ca, sa = cos(a), sin(a)
        ev = c.pos + Point3f(ca * v[1] - sa * v[2], sa * v[1] + ca * v[2], v[3])
        tv = c.pos + Point3f(ca * (t - c.pos)[1] - sa * (t - c.pos)[2], sa * (t - c.pos)[1] + ca * (t - c.pos)[2], (t - c.pos)[3])
        ev = Point3f(ev[1], ev[2], max(ev[3], terrain_height(w.island, ev[1], ev[2]) + 0.6f0))
        o = obstruction(w, ev, tv)
        o + 0.1f0 < ob && ((best, ob) = ((ev, tv), o))
        ob <= 0.05f0 && break
    end
    return best
end

function camera_goal(rig::CameraRig, w::World)
    # asked twice a frame (camcut.jl, then update_camera!) and up to 60 obstruction checks each:
    # one answer per frame (s61: 2 × 100 ms with Lumi in a tree nook, p95 218 ms)
    key = (objectid(w), w.t, rig.mode, rig.subject, rig.eye, rig.target, rig.angle)
    c = GOAL_CACHE[]
    c !== nothing && c[1] == key && return c[2]
    v = camera_goal_uncached(rig, w)
    GOAL_CACHE[] = (key, v)
    return v
end
const GOAL_CACHE = Ref{Any}(nothing)

function camera_goal_uncached(rig::CameraRig, w::World)
    if rig.mode === :follow
        if rig.subject == 0
            shot = camera_shot(w)
            shot === nothing || return shot
        end
        id = rig.subject == 0 ? held_subject(w) : rig.subject
        c = creature(w, id)
        if rig.subject == 0
            for g in values(CAMERA_GROUPS)
                v = Base.invokelatest(g, w)
                # a third element is the plugin's own view `(eye, target)` (the sunset bench: from behind, out to sea)
                v !== nothing && Int32(v[1]) == id && length(v) >= 3 && v[3] !== nothing && return v[3]
                v !== nothing && Int32(v[1]) == id && length(v[2]) > 1 && return group_view(w, c, v[2])
            end
        end
        if !isempty(w.interactions) && first(w.interactions).a == id
            it = first(w.interactions)
            b = creature(w, it.b)
            return group_view(w, c, [c.pos, b.pos])     # both talkers from the side, further back the further apart
        end
        c.controlled && return follow_view(w, c)
        return face_view(w, c)
    elseif rig.mode === :orbit
        # a slow low turn from just off the shore, looking across the island (the old 0.6r high view
        # was the same picture as the free camera, perfectionist-0030)
        r = 1.05f0 * w.island.radius
        target = rig.center + Point3f(0, 0, 2.5f0)
        eye = rig.center + Point3f(r * cos(rig.angle), r * sin(rig.angle), 0.24f0r)
        # a shore tree in front of the lens: crane up over it
        obstruction(w, eye, target) > 0.5f0 && (eye = Point3f(eye[1], eye[2], 0.42f0r))
        return eye, target
    end
    return rig.eye, rig.target
end

function update_camera!(rig::CameraRig, w::World, scene::Scene, dt::Real; snap::Bool = false)
    rig.mode === :orbit && (rig.angle += 0.05f0 * dt)
    eye, target = camera_goal(rig, w)
    k = snap ? 1.0f0 : Float32(1 - exp(-3dt / rig.smoothing))
    rig.eye += k * (eye - rig.eye)
    rig.target += k * (target - rig.target)
    look!(scene, rig.eye, rig.target)
    return rig
end

"""
    record_clip(path, w, st, screen; seconds, fps, rig, simulate = true) -> stats

Run the world for `seconds`, rendering every frame through `screen` into an
mp4 at `path`. Returns frame time statistics (sim, sync, render in ms).
"""
function record_clip(path::AbstractString, w::World, st::Stage, screen; seconds::Real = 10, fps::Int = 30,
                     rig::CameraRig = CameraRig(), simulate::Bool = true)
    n = round(Int, seconds * fps)
    dt = 1 / fps
    times = (sim = Float64[], sync = Float64[], render = Float64[])
    update_camera!(rig, w, st.scene, dt; snap = true)
    first_img = Makie.colorbuffer(screen)
    h, wd = size(first_img)
    buf = Matrix{RGB{Colors.N0f8}}(undef, h, wd)
    VideoIO.open_video_out(path, eltype(buf), (h, wd); framerate = fps,
                           encoder_options = (crf = 22, preset = "fast")) do writer
        for _ in 1:n
            t0 = time_ns()
            simulate && step!(w, dt)
            t1 = time_ns()
            sync!(st, w)
            update_camera!(rig, w, st.scene, dt)
            t2 = time_ns()
            img = Makie.colorbuffer(screen)
            t3 = time_ns()
            buf .= RGB{Colors.N0f8}.(img)
            write(writer, buf)
            push!(times.sim, (t1 - t0) / 1e6); push!(times.sync, (t2 - t1) / 1e6); push!(times.render, (t3 - t2) / 1e6)
        end
    end
    return frame_stats(times)
end

function frame_stats(times)
    med(v) = isempty(v) ? 0.0 : sort(v)[cld(length(v), 2)]
    p95(v) = isempty(v) ? 0.0 : sort(v)[ceil(Int, 0.95length(v))]
    total = times.sim .+ times.sync .+ times.render
    return (; frames = length(total), median_ms = med(total), p95_ms = p95(total), fps = 1000 / med(total),
            sim_ms = med(times.sim), sync_ms = med(times.sync), render_ms = med(times.render))
end

# ── denoising the path traced stills and films ─────────────────────────────

"""
JuliaVision's Open Image Denoise (OIDNRunner, on the GPU) as a Hikari denoiser:
RayMakie runs it on the film's linear radiance with the first-hit albedo and
normal guides, before exposure and tone mapping. The film is height by width,
OIDNRunner's images width by height.
"""
struct GPUOIDN <: Hikari.Denoiser
    denoiser::OIDNRunner.OIDNDenoiser
end

function Hikari.denoise!(film::Hikari.Film, c::GPUOIDN)
    color = permutedims(Array(film.framebuffer))
    albedo = permutedims(Array(film.albedo))
    normal = permutedims(Array(film.normal))
    out = OIDNRunner.denoise(c.denoiser, color; albedo, normal)
    copyto!(film.framebuffer, permutedims(rgb_image(out)))
    return nothing
end

"OIDNRunner's output as an RGB matrix (it is planar, width × height × 3, for planar input)."
rgb_image(out::AbstractMatrix{<:RGB}) = RGB{Float32}.(out)
rgb_image(out::AbstractArray{<:Real,3}) = RGB{Float32}.(view(out, :, :, 1), view(out, :, :, 2), view(out, :, :, 3))

"""
A path tracing screen for the worker's stills and films; `denoise`: OIDN on the
GPU (`GPUOIDN`), so a frame needs far fewer samples for a clean picture.
"""
function traced_screen(root_scene::Scene; denoise::Bool, max_depth::Int)
    oidn = denoise ? GPUOIDN(OIDNRunner.OIDNDenoiser()) : nothing
    return RayMakie.Screen(root_scene; visible = false, rasterize = false, exposure = FILM_EXPOSURE, max_depth,
                           denoise, denoise_config = oidn), oidn
end

"Give the denoiser's GPU memory back (the screen is closed by its caller)."
release_denoiser!(::Nothing) = nothing
release_denoiser!(c::GPUOIDN) = OIDNRunner.release!(c.denoiser)

"""
    game_still(path; root, size, samples, max_depth, rig, steps, denoise) -> path

Path trace what a player sees: a quiet copy of the game (latest world snapshot, every
plugin loaded, its systems started and stepped `steps` frames) on a stage of its own,
without dashboard or labels. The worker's `:trace` job uses it, so traced stills show
the generated trees, flowers, lamps and the cottage, not only the engine's primitives.
`denoise`: OIDN on the GPU (`GPUOIDN`).
"""
function game_still(path::AbstractString; root::AbstractString = game_root(), size = (1280, 720), samples::Int = 128,
                    max_depth::Int = 8, rig::CameraRig = CameraRig(), steps::Int = 3, denoise::Bool = true)
    g = Game(root; quiet = true)
    w = g.world
    # like the dashboard: the 3D view is a child of a root scene, so plugins get their 2D overlay (HUDs, emotes)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = stage_lights(w))
    cam3d!(scene)
    g.stage = Stage(scene, w; show_names = false)
    for _ in 1:steps
        Base.invokelatest(step_systems!, g, 1 / 30)
        sync!(g.stage, w)
        sync_actors!(g)
    end
    foreach(p -> (p.visible[] = false), g.stage.overlay.plots)   # a clean still: no HUD text over the picture
    sync_sun!(g.stage, w)
    update_camera!(rig, w, scene, 0.0; snap = true)
    screen, oidn = traced_screen(root_scene; denoise, max_depth)
    img = Makie.colorbuffer(screen; samples)
    close(screen)
    release_denoiser!(oidn)
    Makie.save(path, img)
    return path
end

"""
    game_clip(path; root, size, seconds, fps, samples, hour, warmup, rig, rasterize) -> stats

A clip of what a player sees, path traced frame by frame: a quiet copy of the game (latest
snapshot, every plugin running) lives on from `hour` (moved forward only, 0..24, `nothing`
keeps the snapshot's time) for `warmup` seconds unrecorded, then `seconds` are written to
the mp4 at `path` with the follow camera (`rig`). `rasterize = true` gives a quick raster
preview of the same clip. Nothing is logged: the live world and its logs are untouched.
`setup(g)` stages a moment once; `shot(g, rig, t)` directs every frame (set `rig.eye`/`rig.target`
of a `:fixed` rig for cuts and dollies; return a number to end the clip at that second);
`fade` seconds fade in from and out to black. `denoise`: every traced frame through OIDN on the
GPU (`GPUOIDN`, spatial: each frame on its own).
"""
function game_clip(path::AbstractString; root::AbstractString = game_root(), size = (1280, 720), seconds::Real = 8,
                   fps::Int = 24, samples::Int = 48, max_depth::Int = 6, hour = nothing, warmup::Real = 20,
                   rig::CameraRig = CameraRig(), rasterize::Bool = false, setup = nothing,
                   shot = nothing, fade::Real = 0, denoise::Bool = true)
    g = Game(root; quiet = true)
    w = g.world
    hour === nothing || skip_to_hour!(w, hour)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = stage_lights(w))
    cam3d!(scene)
    g.stage = Stage(scene, w; show_names = false)
    setup === nothing || Base.invokelatest(setup, g)      # set up a moment (a critter sent off to do something)
    function advance!(dt)
        step!(w, dt)
        Base.invokelatest(step_actors!, g, dt)
        Base.invokelatest(step_systems!, g, dt)
        sync!(g.stage, w)
        sync_actors!(g)
        sync_sun!(g.stage, w)
        update_camera!(rig, w, scene, dt)
    end
    for _ in 1:round(Int, warmup * 30)
        Base.invokelatest(advance!, 1 / 30)   # plugins were loaded after this call began
    end
    screen, oidn = rasterize ? (RayMakie.Screen(root_scene; visible = false, rasterize, exposure = FILM_EXPOSURE), nothing) :
                   traced_screen(root_scene; denoise, max_depth)
    rasterize || (g.screen = screen)        # plugins see a path traced screen: no re-pushed glowing plots (OOM)
    n = round(Int, seconds * fps)
    times = Float64[]
    mkpath(dirname(path))
    buf = nothing
    writer = nothing
    i = 0
    while i < n
        i += 1
        t0 = time()
        Base.invokelatest(advance!, 1 / fps)
        # a director: `shot(g, rig, t)` moves a :fixed rig (cuts, dollies); a number it returns is
        # the clip's new end in seconds (so the fade out lands on the end once the moment is over)
        if shot !== nothing
            stop = Base.invokelatest(shot, g, rig, (i - 1) / fps)
            stop isa Real && (n = clamp(round(Int, stop * fps), i, n))
            update_camera!(rig, w, scene, 0.0; snap = true)
        end
        foreach(p -> (p.visible[] = false), g.stage.overlay.plots)   # no HUD text over the picture
        img = Makie.colorbuffer(screen; samples)
        if fade > 0                              # fade in from and out to black
            k = clamp(min((i - 1) / fps, (n - i) / fps) / fade, 0, 1)
            k < 1 && (img = img .* Float32(k))
        end
        if writer === nothing
            buf = Matrix{RGB{Colors.N0f8}}(undef, Base.size(img)...)
            writer = VideoIO.open_video_out(path, eltype(buf), Base.size(buf); framerate = fps,
                                            encoder_options = (crf = 18, preset = "slow"))
        end
        buf .= RGB{Colors.N0f8}.(img)
        write(writer, buf)
        push!(times, time() - t0)
    end
    VideoIO.close_video_out!(writer)
    close(screen)
    release_denoiser!(oidn)
    return (; path, frames = n, seconds_per_frame = sum(times) / max(n, 1), hour = 24daytime(w))
end

"""
    screenshot(path, w; size, samples, rig) -> path

Path trace the world as it is now into a png, in its own scene (the live view
is untouched).
"""
function screenshot(path::AbstractString, w::World; size = (1280, 720), samples::Int = 128, max_depth::Int = 8,
                    rig::CameraRig = CameraRig())
    scene = stage_scene(w; size)
    st = Stage(scene, w)
    update_camera!(rig, w, scene, 0.0; snap = true)
    screen = RayMakie.Screen(scene; visible = false, rasterize = false, exposure = FILM_EXPOSURE, max_depth)
    img = Makie.colorbuffer(screen; samples)
    close(screen)
    Makie.save(path, img)
    return path
end
