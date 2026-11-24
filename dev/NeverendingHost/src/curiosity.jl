# ── curiosity: what the character stumbles on beyond its island ─────────────
#
# Boredom (mood.jl) says *that* something new has to happen; this is where new
# ideas come from. Before each session the host shows the character a few things
# it has not tried, the way you stumble on something in a shop window:
#
# - packages of the Julia ecosystem from RomeoDB's index, in the areas a game can
#   play with (sound, physics, generative art, simulation, language, ...), used by
#   enough people to work, not yet in the environment and not shown before;
# - JuliaVision's models (dev/JuliaVision, on the GPU) that the game has never used:
#   depth, segmentation, slow motion, stem separation, inpainting, ...
#
# Each is shown once until all have been: the character may take one up, a new
# dependency included, or let it pass.

"Words in a package's summary that make it something a game could play with."
const CURIOUS = ("sound", "audio", "music", "synth", "midi", "physic", "simulat", "particle", "fluid", "procedural", "noise",
                 "fractal", "terrain", "animat", "shader", "ray trac", "render", "mesh", "geometr", "game", "generative",
                 "cellular", "l-system", "flock", "boid", "weather", "ocean", "wave", "plant", "evolution", "genetic",
                 "speech", "language model", "image", "video", "color", "colour", "poem", "story", "chaos", "dynamical system",
                 "robot", "astronom", "planet", "crowd", "agent-based", "puzzle", "maze", "graph drawing", "font", "voxel")

"Words for physics, of which every session sees one package (the human's goal: things to play with)."
const PHYSICS = ("physic", "fluid", "particle", "rigid bod", "collision", "cloth", "soft bod", "hydrodynamic", "lattice boltzmann",
                 "wave", "granular", "elastic", "fracture", "n-body", "flow")

"How many people a package needs, so that it is likely to work."
const CURIOUS_USERS = 30

"Package names the game's environment already has (its Manifest)."
env_packages(jp::JailPaths) =
    Set(m[1] for m in eachmatch(r"^\[\[deps\.([^\]]+)\]\]"m, read(joinpath(jp.root, "Manifest.toml"), String)))

"""
    ecosystem_finds(jp, seen; n = 3) -> Vector{Dict}

`n` packages from RomeoDB's index the character has not been shown (`seen`), at random among
those in a `CURIOUS` area with `CURIOUS_USERS` or more users, outside the environment, one of
them about physics (`PHYSICS`). None without an index (a fresh fork fetches it on the first search).
"""
function ecosystem_finds(jp::JailPaths, seen; n::Int = 3)
    file = joinpath(jp.romeodb, "romeo.sqlite")
    isfile(file) || return Dict{String,Any}[]
    db = SQLite.DB(file)
    rows = try
        # a query's rows are valid only while it is iterated: copied as they come
        [(name = String(r.name), summary = String(r.summary), users = Int(r.users), gpu = r.gpu == 1) for r in SQLite.DBInterface.execute(db, """
            SELECT p.name AS name, p.summary AS summary, p.gpu AS gpu, COALESCE(d.users, 0) AS users FROM packages p
            LEFT JOIN downloads d ON d.uuid = p.uuid
            WHERE p.status = 'ok' AND p.name NOT LIKE '%_jll' AND COALESCE(d.users, 0) >= $CURIOUS_USERS""")]
    finally
        SQLite.close(db)
    end
    have = env_packages(jp)
    pool = [Dict{String,Any}("name" => r.name, "summary" => first_sentence(r.summary), "users" => r.users, "gpu" => r.gpu) for r in rows
            if !(r.name in have) && !(r.name in seen) && any(w -> occursin(w, lowercase(r.summary)), CURIOUS) &&
               !occursin(r"component of|monorepo|subpackage|internal|deprecated", lowercase(r.summary))]
    shuffle!(pool)
    i = findfirst(p -> any(w -> occursin(w, lowercase(p["summary"])), PHYSICS), pool)
    i === nothing || pushfirst!(pool, popat!(pool, i))
    return first(pool, n)
end

"A summary's first sentence, at most 200 characters."
first_sentence(text::AbstractString) = first(first(split(strip(text), r"(?<=[.!?])\s"; limit = 2)), 200)

"What a JuliaVision runner does, from its README's first paragraph or its module docstring."
function runner_summary(dir::AbstractString)
    readme = joinpath(dir, "README.md")
    text = ""
    if isfile(readme)
        para = String[]
        for l in eachline(readme)
            s = strip(l)
            if isempty(s) || startswith(s, "#") || startswith(s, "[!") || startswith(s, "![")
                isempty(para) || break
                continue
            end
            push!(para, s)
        end
        text = join(para, " ")
    end
    if isempty(text)
        src = joinpath(dir, "src", basename(dir) * ".jl")
        m = isfile(src) ? match(r"\"\"\"\n\s*(.+)", read(src, String)) : nothing
        text = m === nothing ? "" : m[1]
    end
    text = replace(text, r"\[([^\]]+)\]\([^)]+\)" => s"\1", "**" => "")      # links and bold as plain text
    return first_sentence(text)
end

"""
    vision_finds(jp, seen; n = 2) -> Vector{Dict}

`n` of JuliaVision's runners the game's code has never named (`world/plugins`, `world/tools`,
`world/skills`, the engine) and the character has not been shown (`seen`), at random.
"""
function vision_finds(jp::JailPaths, seen; n::Int = 2)
    vision = joinpath(jp.root, "dev", "JuliaVision")
    isdir(vision) || return Dict{String,Any}[]
    runners = filter(d -> endswith(d, "Runner") && isdir(joinpath(vision, d)), readdir(vision))
    code = IOBuffer()
    for d in ("world/plugins", "world/tools", "world/skills", "dev/NeverendingGame/src"), (r, _, fs) in walkdir(joinpath(jp.root, d)), f in fs
        (endswith(f, ".jl") || endswith(f, ".md")) && write(code, read(joinpath(r, f)))
    end
    text = String(take!(code))
    have = env_packages(jp)
    pool = [Dict{String,Any}("name" => r, "summary" => runner_summary(joinpath(vision, r)), "in_env" => r in have)
            for r in runners if !occursin(r, text) && !(r in seen)]
    return first(shuffle!(pool), n)
end

"""
    stumble!(jp) -> Dict

What the character stumbles on before a session (see the top of this file), remembered in its
mood as shown; when everything has been shown, it is shown again.
"""
function stumble!(jp::JailPaths)
    m = load_mood(jp)
    seen = get!(m, "stumbled", Dict{String,Any}("packages" => Any[], "vision" => Any[]))
    finds = Dict{String,Any}()
    for (key, find) in (("packages", ecosystem_finds), ("vision", vision_finds))
        got = find(jp, seen[key])
        isempty(got) && (seen[key] = Any[]; got = find(jp, seen[key]))     # all shown: from the start
        append!(seen[key], [g["name"] for g in got])
        finds[key] = got
    end
    save_mood!(jp, m)
    return finds
end

"The prompt's section on what the character stumbled on, empty when it found nothing."
function stumble_lines(finds::AbstractDict, name::AbstractString)
    pk, vi = finds["packages"], finds["vision"]
    isempty(pk) && isempty(vi) && return ""
    io = IOBuffer()
    println(io, "## What $name stumbled on (curiosity: take one up, or let it pass)")
    if !isempty(pk)
        println(io, "In the Julia ecosystem (RomeoDB `package_info` tells more; `Pkg.add` brings one in):")
        foreach(p -> println(io, "- $(p["name"]) ($(p["users"]) users", p["gpu"] ? ", runs on GPUs" : "", "): $(p["summary"])"), pk)
    end
    if !isempty(vi)
        println(io, "In JuliaVision (dev/JuliaVision, models on the GPU), never used on the island yet:")
        foreach(v -> println(io, "- $(v["name"])", v["in_env"] ? "" : " (not in the environment yet: `Pkg.develop(path = \"dev/JuliaVision/$(v["name"])\")`)",
                              ": $(v["summary"])"), vi)
    end
    print(io, "What could happen on the island with it, that never happened there?")
    return String(take!(io))
end
