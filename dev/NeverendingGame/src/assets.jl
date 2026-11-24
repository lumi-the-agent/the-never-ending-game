# ── Jobs and assets ─────────────────────────────────────────────────────────
#
# Slow GPU work (generating images and meshes, path traced stills) runs in the
# worker process (`run_worker()`, jailed, kept alive by the host), one job at
# a time, so neither the live game nor the agent's session waits for it.
#
#   id = submit_job(:asset; prompt = "a mossy stone lantern", tags = ["prop"])
#   job(id)["status"]        "queued" "running" "done" "failed"
#   wait_job(id)             blocks until done, returns the job
#   assets("lantern")        the catalog, filtered: reuse before generating
#
# Kinds:
#   :image   prompt → world/assets/<id>/image.png (Qwen-Image, cut out on a transparent background;
#            describe one object, no light or scenery: see `asset_prompt`, `cutout_problem`)
#   :mesh    image (a png path) → world/assets/<id>/mesh.jls (Trellis2: textured PBR mesh)
#   :asset   prompt → image → mesh, added to world/assets/catalog.json
#   :trace   a path traced still of the current world → path (samples, size; eye + target: a fixed camera)
#   :clip    a path traced mp4 of the game living on from the latest snapshot → path
#            (`script` + `call` + `kwargs`: a directed film from a script in world/, e.g. movies/cairn_release.jl)
#            (seconds, fps, samples, size, hour, warmup, rasterize; see `game_clip`)
#   :restart the worker exits after the jobs queued before it and the host starts it again: the
#            worker has no Revise, so engine edits to job code reach it this way
#
# How long each kind took is in `world/state/timing.json` (`estimate`).

jobs_dir(p::GamePaths) = p.jobs
job_path(p::GamePaths, id::AbstractString) = joinpath(jobs_dir(p), id * ".json")

"""
    submit_job(kind; params...) -> id

Queue a job for the worker. See the kinds above.
"""
function submit_job(kind::Symbol; root::AbstractString = game_root(), params...)
    p = GamePaths(root)
    id = Dates.format(Dates.now(), "yyyymmdd-HHMMSS-sss") * "-" * String(kind)
    # two jobs in the same millisecond: the second used to overwrite the first (todo #48)
    while isfile(job_path(p, id))
        sleep(0.002)
        id = Dates.format(Dates.now(), "yyyymmdd-HHMMSS-sss") * "-" * String(kind)
    end
    write_json(job_path(p, id), Dict{String,Any}("id" => id, "kind" => String(kind), "status" => "queued",
                                                 "params" => Dict{String,Any}(String(k) => v for (k, v) in params),
                                                 "created" => string(Dates.now())))
    return id
end

job(id::AbstractString; root::AbstractString = game_root()) = read_json(job_path(GamePaths(root), id))

function wait_job(id::AbstractString; timeout::Real = 3600, root::AbstractString = game_root())
    t0 = time()
    while time() - t0 < timeout
        j = job(id; root)
        j["status"] in ("done", "failed") && return j
        sleep(2)
    end
    error("job $id still $(job(id; root)["status"]) after $(timeout) s")
end

catalog_path(p::GamePaths) = joinpath(p.assets, "catalog.json")
load_catalog(p::GamePaths) = isfile(catalog_path(p)) ? read_json(catalog_path(p))["assets"] : Any[]

"""
    assets(query = "") -> Vector

Catalog entries whose prompt or tags contain every word of `query`.
"""
function assets(query::AbstractString = ""; root::AbstractString = game_root())
    words = lowercase.(split(query))
    return filter(load_catalog(GamePaths(root))) do a
        text = lowercase(a["prompt"] * " " * join(a["tags"], " "))
        all(w -> occursin(w, text), words)
    end
end

# ── the worker ──────────────────────────────────────────────────────────────

"Models a worker keeps loaded between jobs."
mutable struct WorkerState
    paths::GamePaths
    timing::TimingStats
    trellis::Any
end

"The module of a package of the game environment, loaded on first use (the runners are heavy)."
function runner(name::AbstractString)
    id = Base.identify_package(name)
    id === nothing && error("$name is not in the environment")
    return Base.require(id)
end

"""
What Qwen-Image is asked for an asset: the whole object, centred with room
around it, cut out. Its alpha is a real matte, but only when the prompt asks
for a transparent background, and a prompt about light or a place gets a
painted background instead.
"""
asset_prompt(prompt::AbstractString) =
    string(rstrip(prompt, ['.', ' ']), ". The whole object, centred, with empty space around it, isolated on a transparent background.")

"""
Why `alpha` is no cut-out a mesh can be made from, or `nothing`. Trellis2 builds
what it sees: a painted background becomes part of the object, and an object
that touches the border comes out cut off.
"""
function cutout_problem(alpha::AbstractMatrix)
    clear = count(<(0.05), alpha) / length(alpha)
    clear < 0.2 && return "the background is not transparent (only $(round(Int, 100clear))% of the image is clear)"
    border = vcat(alpha[1, :], alpha[end, :], alpha[:, 1], alpha[:, end])
    touching = count(>(0.5), border) / length(border)
    touching > 0.01 && return "the object touches the image border ($(round(Int, 100touching))% of it), so it is cut off"
    return nothing
end

function run_job(::Val{:image}, ws::WorkerState, id, params)
    dir = joinpath(ws.paths.assets, id)
    mkpath(dir)
    path = joinpath(dir, "image.png")
    Qwen = runner("QwenImageRunner")
    seed = get(params, "seed", 42)
    problems = String[]
    for attempt in 0:2       # another seed when the model paints a background or crops the object
        a = Base.invokelatest(Qwen.generate, asset_prompt(params["prompt"]);
                              width = get(params, "width", 1024), height = get(params, "height", 1024),
                              steps = get(params, "steps", 40), seed = seed + attempt)
        W, H = size(a, 1), size(a, 2)
        # Qwen's alpha has a noise floor of a few /255: cut it so the object's bounds are clean
        img = [RGBA{Colors.N0f8}(clamp(a[x, y, 1], 0, 1), clamp(a[x, y, 2], 0, 1), clamp(a[x, y, 3], 0, 1),
                                 a[x, y, 4] < 0.03 ? 0 : clamp(a[x, y, 4], 0, 1)) for y in 1:H, x in 1:W]
        Makie.save(path, img)
        problem = cutout_problem(alpha.(img))
        problem === nothing && return Dict{String,Any}("image" => path, "seed" => seed + attempt)
        push!(problems, "seed $(seed + attempt): $problem")
    end
    error("no usable cut-out for \"$(params["prompt"])\" in 3 tries ($(join(problems, "; "))); the last one is $path. " *
          "Describe a single object, without light, scenery or background in the prompt.")
end

function run_job(::Val{:mesh}, ws::WorkerState, id, params)
    dir = joinpath(ws.paths.assets, id)
    mkpath(dir)
    T2 = runner("Trellis2Runner")
    ws.trellis === nothing && (ws.trellis = Base.invokelatest(T2.Trellis2; cascade = true))
    img = Makie.FileIO.load(params["image"])          # (H, W) of colours
    H, W = size(img)
    rgba = Array{UInt8}(undef, 4, W, H)
    for y in 1:H, x in 1:W
        c = RGBA{Colors.N0f8}(img[y, x])
        rgba[:, x, y] .= reinterpret.((red(c), green(c), blue(c), alpha(c)))
    end
    # the runner was loaded during this job: every call into it goes through the latest world
    noise = Base.invokelatest(T2.Noise, get(params, "seed", 42))
    mesh = Base.invokelatest(T2.generate, ws.trellis, rgba; noise,
                             texture = get(params, "texture", 2048), decimation = get(params, "faces", 40_000))
    path = joinpath(dir, "mesh.jls")
    Serialization.serialize(path, mesh)
    return Dict{String,Any}("mesh" => path, "faces" => length(GeometryBasics.faces(mesh)))
end

function run_job(::Val{:asset}, ws::WorkerState, id, params)
    t0 = time()
    img = run_job(Val(:image), ws, id, params)
    m = run_job(Val(:mesh), ws, id, merge(params, img))
    # tree crowns come out of Trellis2 as torn hollow shells: filled (meshrepair.jl)
    any(in(HOLLOW_TAGS), get(params, "tags", String[])) && fill_hollow!(m["mesh"])
    entry = Dict{String,Any}("id" => id, "prompt" => params["prompt"], "tags" => get(params, "tags", String[]),
                             "image" => img["image"], "mesh" => m["mesh"], "faces" => m["faces"],
                             "created" => string(Dates.now()), "seconds" => round(time() - t0))
    cat = load_catalog(ws.paths)
    push!(cat, entry)
    write_json(catalog_path(ws.paths), Dict("assets" => cat))
    return entry
end

function run_job(::Val{:trace}, ws::WorkerState, id, params)
    path = get(params, "path", joinpath(media_dir(ws.paths), "trace-$(stamp()).png"))
    sz = Tuple(get(params, "size", [1280, 720]))
    if get(params, "plugins", true)      # what a player sees, plugins and generated assets included
        # a camera of its own (a moment seen in the live game: its rig's eye and target), else the follow view
        rig = CameraRig()
        if haskey(params, "eye")
            rig.mode = :fixed; rig.eye = Point3f(params["eye"]...); rig.target = Point3f(params["target"]...)
        end
        Base.invokelatest(game_still, path; root = ws.paths.root, size = sz, samples = get(params, "samples", 128), rig)
    else                                 # the engine's own scene only
        screenshot(path, load_snapshot(latest_world(ws.paths)); size = sz, samples = get(params, "samples", 128))
    end
    return Dict{String,Any}("path" => path)
end

function run_job(::Val{:clip}, ws::WorkerState, id, params)
    path = get(params, "path", joinpath(media_dir(ws.paths), "clips", "clip-$(stamp()).mp4"))
    if haskey(params, "script")       # a directed film: world/<script> defines `call(path; kwargs...)` (movies/cairn_release.jl)
        m = Module(:ClipScript)
        Base.include(m, joinpath(ws.paths.world, params["script"]))
        kw = Dict{Symbol,Any}(Symbol(k) => (v isa AbstractVector ? Tuple(v) : v) for (k, v) in get(params, "kwargs", Dict()))
        f = Base.invokelatest(getglobal, m, Symbol(params["call"]))   # defined in a newer world than this call
        r = Base.invokelatest(f, path; kw...)
        return Dict{String,Any}(string(k) => v for (k, v) in pairs(r))
    end
    r = Base.invokelatest(game_clip, path; root = ws.paths.root, size = Tuple(get(params, "size", [1280, 720])),
                          seconds = get(params, "seconds", 8), fps = get(params, "fps", 24),
                          samples = get(params, "samples", 48), hour = get(params, "hour", nothing),
                          warmup = get(params, "warmup", 20), rasterize = get(params, "rasterize", false))
    return Dict{String,Any}(string(k) => v for (k, v) in pairs(r))
end

run_job(::Val{:restart}, ws::WorkerState, id, params) = Dict{String,Any}("restarted" => string(Dates.now()))

run_job(::Val{K}, ws::WorkerState, id, params) where {K} = error("unknown job kind $(K)")

function next_job(p::GamePaths)
    files = sort!(filter(f -> endswith(f, ".json"), readdir(jobs_dir(p))))
    for f in files
        j = read_json(joinpath(jobs_dir(p), f))
        j["status"] == "queued" && return j
    end
    return nothing
end

"""
    run_worker(; root)

Work through queued jobs, one at a time, until a `:restart` job. A failing
job is marked failed with its error; the worker goes on with the next.
"""
function run_worker(; root::AbstractString = game_root())
    p = GamePaths(root)
    ws = WorkerState(p, TimingStats(joinpath(p.state, "timing.json")), nothing)
    # a job that was running when the worker stopped runs once more (a host restart killed a
    # 12 minute render); stopped a second time it may be what kills the worker: failed
    for f in filter(f -> endswith(f, ".json"), readdir(jobs_dir(p)))
        j = read_json(joinpath(jobs_dir(p), f))
        j["status"] == "running" || continue
        j["interrupted"] = get(j, "interrupted", 0) + 1
        if j["interrupted"] == 1
            j["status"] = "queued"
        else
            j["status"] = "failed"; j["error"] = "the worker stopped twice while running it"
        end
        write_json(joinpath(jobs_dir(p), f), j)
    end
    while true
        j = next_job(p)
        if j === nothing
            sleep(2)
            continue
        end
        id = j["id"]
        j["status"] = "running"; j["started"] = string(Dates.now())
        write_json(job_path(p, id), j)
        t0 = time()
        try
            j["result"] = run_job(Val(Symbol(j["kind"])), ws, id, j["params"])
            j["status"] = "done"
            record!(ws.timing, "job:" * j["kind"], time() - t0)
        catch e
            e isa InterruptException && rethrow()
            # the job failed, not the worker: record why and go on
            j["status"] = "failed"
            j["error"] = first(sprint(showerror, e, catch_backtrace()), 8000)
        end
        j["finished"] = string(Dates.now())
        j["seconds"] = round(time() - t0; digits = 1)
        write_json(job_path(p, id), j)
        j["kind"] == "restart" && return    # the host starts a fresh worker with the current code
    end
end

# ── generated assets in the world ───────────────────────────────────────────

"A generated asset placed in the world (built in, no plugin needed)."
mutable struct AssetActor <: Actor
    asset::String          # catalog id
    pos::Point3f
    yaw::Float32
    scale::Float32
end

"`place_asset(game, id, pos; yaw, scale)` (in `live_eval`): put a catalog asset into the live world."
function place_asset(g, id::AbstractString, pos; yaw::Real = 0, scale::Real = 1)
    a = AssetActor(String(id), ground(g.world.island, pos), Float32(yaw), Float32(scale))
    spawn!(g.world, a)
    return a
end

"""
    asset_color(image; size = 256) -> Matrix

An asset's base colour texture at most `size` pixels a side (box filtered), for
a plot's `color`: RayMakie's raster and WGLMakie draw it, and WGLMakie sends
every plot's texture to each browser that opens the page, as float colours
(2048² is 67 MB). The path tracer reads the full texture from the material.
Pass a larger `size` for a hero piece seen up close.
"""
function asset_color(image::AbstractMatrix{<:Colorant}; size::Integer = 256)
    k = cld(maximum(Base.size(image)), size)
    k == 1 && return image
    h, w = Base.size(image) .÷ k
    return [RGBA{Colors.N0f8}(mapreduce(c -> RGBA{Float32}(c), +, view(image, (k * (i - 1) + 1):(k * i), (k * (j - 1) + 1):(k * j))) / k^2)
            for i in 1:h, j in 1:w]
end

"""
    AssetModel(metamesh; material = its glTF material, size = 256)

A generated asset ready to draw: its mesh with the lowest point at z = 0 (it
stands where it is placed), the raster colour (`asset_color`) and the traced
material (`material`, a glTF material dict as Trellis2 bakes it; pass a
changed copy to tint or brighten it). Load it once and draw every copy with
`asset_instances!`.
"""
struct AssetModel
    mesh::GeometryBasics.Mesh
    color::Matrix
    material::Hikari.Material
end

function AssetModel(mm::GeometryBasics.MetaMesh; material::AbstractDict = only(values(mm[:materials])), size::Integer = 256)
    m = mm.mesh
    pos = GeometryBasics.coordinates(m)
    zmin = minimum(p -> p[3], pos)
    mesh = GeometryBasics.Mesh([p - Point3f(0, 0, zmin) for p in pos], GeometryBasics.faces(m); normal = m.normal, uv = m.uv)
    color = asset_color(material["diffuse map"]["image"]; size)
    # An opaque glTF material ignores the texture's alpha, and Trellis2 leaves noise there; the raster
    # read it and drew filled tree crowns (meshrepair.jl) as green glass.
    get(material, "alpha mode", "OPAQUE") == "OPAQUE" && (color = map(c -> RGBA{Colors.N0f8}(red(c), green(c), blue(c), 1), color))
    return AssetModel(mesh, color, RayMakie.glb_material_to_hikari(material).material)
end

"The catalog asset `id` as an `AssetModel`."
function load_asset(p::GamePaths, id::AbstractString; kw...)
    entry = only(filter(e -> e["id"] == id, load_catalog(p)))
    return AssetModel(Serialization.deserialize(entry["mesh"]); kw...)
end

"""
    asset_instances!(scene, model, positions; rotation, markersize, kw...) -> plot

Every copy of one asset as ONE instanced plot (a meshscatter): one mesh and one
texture for all of them, on the GPU and in every browser that opens the page.
`rotation` (e.g. `rot_z(yaw)`) and `markersize` (a scale, `Vec3f`) per copy;
hide a copy with markersize 0 rather than with a plot of its own. One plot per
copy sends the mesh and the texture once per copy: forty trees made the page
take minutes to open.
"""
asset_instances!(scene, model::AssetModel, positions; kw...) =
    meshscatter!(scene, positions; marker = model.mesh, color = model.color, material = model.material, kw...)

"""
    lifted_asset(paths, id) -> AssetModel

The asset with its raster texture brightened towards the generated image it came from: the
baked texture comes out much darker (the cottage's median brightness 0.23 against 0.55 in
its image), so placed props looked muddy next to everything else. Gain at most 1.8, never darker.
"""
function lifted_asset(p::GamePaths, id::AbstractString)
    m = load_asset(p, id)
    file = joinpath(p.world, "assets", id, "image.png")
    isfile(file) || return m
    img = Makie.FileIO.load(file)
    l(c) = 0.3f0 * Float32(red(c)) + 0.59f0 * Float32(green(c)) + 0.11f0 * Float32(blue(c))
    # the image's object pixels (not the purple cut-out backdrop) against the texture's used texels
    fg = [l(c) for c in img if !(red(c) > 0.5 && blue(c) > 0.6 && green(c) < 0.35)]
    tex = [l(c) for c in m.color if l(c) > 0.04]
    (isempty(fg) || isempty(tex)) && return m
    med(v) = sort(v)[cld(length(v), 2)]
    gain = clamp(med(fg) / med(tex), 1.0f0, 1.8f0)
    gain < 1.05f0 && return m
    col = map(c -> typeof(c)(min(1, red(c) * gain), min(1, green(c) * gain), min(1, blue(c) * gain), alpha(c)), m.color)
    return AssetModel(m.mesh, col, m.material)
end

"The placed assets: one instanced plot per catalog asset (see `asset_instances!`)."
mutable struct AssetView
    scene::Any
    plots::Dict{String,Any}       # asset id => its instanced plot
end

visual(::Type{AssetActor}, scene) = AssetView(scene, Dict{String,Any}())

function sync_visual!(v::AssetView, actors::Vector, game)
    groups = Dict{String,Vector{AssetActor}}()
    foreach(a -> push!(get!(() -> AssetActor[], groups, a.asset), a), actors)
    for (id, copies) in groups
        pos = [Point3f(a.pos) for a in copies]
        rot = [rot_z(a.yaw) for a in copies]
        sz = [Vec3f(a.scale) for a in copies]
        plot = get(v.plots, id, nothing)
        if plot === nothing
            v.plots[id] = asset_instances!(v.scene, lifted_asset(game.paths, id), pos; rotation = rot, markersize = sz)
        elseif plot[1][] != pos || plot.rotation[] != rot || plot.markersize[] != sz
            Makie.update!(plot, pos; rotation = rot, markersize = sz)
        end
    end
    for id in collect(keys(v.plots))
        haskey(groups, id) || delete!(v.scene, pop!(v.plots, id))
    end
end
