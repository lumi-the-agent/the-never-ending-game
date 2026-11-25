# ── curiosity: the workbench, things never touched ───────────────────────────
#
# Boredom (mood.jl) says *that* something new has to happen; this is where new
# ideas come from. Before each session the host lays out a few things the
# character has never touched, at random, for the time it has to look around
# before choosing what to make (step 3 of `prompts/session.md`), never as
# suggestions:
#
# - packages of the Julia ecosystem from RomeoDB's index, in the areas a game can
#   play with (sound, physics, generative art, simulation, language, ...), used by
#   enough people to work, not yet in the environment;
# - functions from such packages with an example in their docs: something that
#   runs in a few lines;
# - JuliaVision's models (dev/JuliaVision, on the GPU) the game has never used;
# - a page from the character's own diary, days old.
#
# Each is shown once until all have been. Shown as "what could happen on the
# island with it" (until session 99), the finds were passed by or turned into one
# more thing happening there.

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

"Whether a package's summary puts it in an area a game can play with (and not in industry or a package's internals)."
curious(summary::AbstractString) =
    (s = lowercase(summary); any(w -> occursin(w, s), CURIOUS) &&
     !occursin(r"component of|monorepo|subpackage|internal|deprecated|power system|financ|econom|actuar|trading|clinical|pharmac", s))

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
            if !(r.name in have) && !(r.name in seen) && curious(r.summary)]
    shuffle!(pool)
    i = findfirst(p -> any(w -> occursin(w, lowercase(p["summary"])), PHYSICS), pool)
    i === nothing || pushfirst!(pool, popat!(pool, i))
    return first(pool, n)
end

"""
    function_finds(jp, seen; n = 2) -> Vector{Dict}

`n` exported functions with an example in their docs (something that runs in a few lines), each
from another package in a `CURIOUS` area with `CURIOUS_USERS` or more users, at random, not shown
before (`seen`, as `Package.function`).
"""
function function_finds(jp::JailPaths, seen; n::Int = 2)
    file = joinpath(jp.romeodb, "romeo.sqlite")
    isfile(file) || return Dict{String,Any}[]
    db = SQLite.DB(file)
    finds = Dict{String,Any}[]
    try
        pkgs = [(id = Int(r.id), name = String(r.name)) for r in SQLite.DBInterface.execute(db, """
            SELECT p.id AS id, p.name AS name, p.summary AS summary FROM packages p LEFT JOIN downloads d ON d.uuid = p.uuid
            WHERE p.status = 'ok' AND p.name NOT LIKE '%_jll' AND COALESCE(d.users, 0) >= $CURIOUS_USERS""") if curious(r.summary)]
        for p in shuffle!(pkgs)
            fs = [(name = String(r.name), signature = String(r.signature), doc = String(r.doc)) for r in SQLite.DBInterface.execute(db, """
                SELECT d.name AS name, d.signature AS signature, d.doc AS doc FROM defs d
                WHERE d.package = ? AND d.kind = 'function' AND length(d.doc) > 120
                  AND (d.doc LIKE '%xample%' OR d.doc LIKE '%jldoctest%')
                  AND EXISTS (SELECT 1 FROM exports e WHERE e.package = d.package AND e.name = d.basename)
                ORDER BY random() LIMIT 1""", (p.id,))]
            isempty(fs) && continue
            f = only(fs)
            key = "$(p.name).$(f.name)"
            key in seen && continue
            push!(finds, Dict{String,Any}("name" => key, "signature" => first(replace(f.signature, r"\s+" => " "), 120),
                                          "summary" => doc_summary(f.doc, last(split(f.name, '.')))))
            length(finds) == n && break
        end
    finally
        SQLite.close(db)
    end
    return finds
end

"A docstring's first sentence of prose: signature lines (calls of `name`), code and `\$(SIGNATURES)` skipped."
function doc_summary(doc::AbstractString, name::AbstractString)
    para = String[]
    for l in split(doc, '\n')
        s = strip(l)
        prose = !isempty(s) && !startswith(l, "    ") && !startswith(s, "```") && !startswith(s, "#") && !occursin("\$(", s) &&
                !startswith(s, name * "(")
        prose ? push!(para, s) : (isempty(para) || break)
    end
    return first_sentence(replace(join(para, " "), r"\[([^\]]+)\]\([^)]+\)" => s"\1", "`" => ""))
end

"""
    diary_finds(jp, seen; n = 1) -> Vector{Dict}

`n` entries of the character's own diary (`world/journal`), at least two days old, at random, not
shown before (`seen`, as `date HH:MM`): its heading and how it begins.
"""
function diary_finds(jp::JailPaths, seen; n::Int = 1)
    dir = joinpath(jp.world, "journal")
    isdir(dir) || return Dict{String,Any}[]
    pool = Dict{String,Any}[]
    for f in readdir(dir)
        m = match(r"^(\d{4}-\d{2}-\d{2})\.md$", f)
        (m === nothing || Date(m[1]) > today() - Day(2)) && continue
        for e in eachmatch(r"^## (\d{1,2}:\d{2}) · (.+)\n+((?:(?!^## ).*\n?)*)"m, read(joinpath(dir, f), String))
            key = "$(m[1]) $(e[1])"
            key in seen && continue
            push!(pool, Dict{String,Any}("name" => key, "title" => String(strip(e[2])),
                                         "text" => first_sentence(replace(strip(e[3]), r"\s+" => " "))))
        end
    end
    return first(shuffle!(pool), n)
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
    seen = get!(m, "stumbled", Dict{String,Any}())
    finds = Dict{String,Any}()
    for (key, find) in (("packages", ecosystem_finds), ("functions", function_finds), ("vision", vision_finds), ("diary", diary_finds))
        got = find(jp, get!(seen, key, Any[]))
        isempty(got) && (seen[key] = Any[]; got = find(jp, seen[key]))     # all shown: from the start
        append!(seen[key], [g["name"] for g in got])
        finds[key] = got
    end
    save_mood!(jp, m)
    return finds
end

"The prompt's workbench: what the host drew for the character this session, empty when it found nothing."
function stumble_lines(finds::AbstractDict, name::AbstractString)
    all(isempty, values(finds)) && return ""
    io = IOBuffer()
    println(io, "## $name's workbench (drawn at random from what you never touched; not suggestions)")
    pk, fs, vi, di = finds["packages"], finds["functions"], finds["vision"], finds["diary"]
    if !isempty(pk)
        println(io, "Packages (RomeoDB `package_info` tells more; `Pkg.add` brings one in):")
        foreach(p -> println(io, "- $(p["name"]) ($(p["users"]) users", p["gpu"] ? ", runs on GPUs" : "", "): $(p["summary"])"), pk)
    end
    if !isempty(fs)
        println(io, "Functions (RomeoDB `search` finds their docs and examples):")
        foreach(f -> println(io, "- `$(f["signature"])` ($(f["name"])): $(f["summary"])"), fs)
    end
    if !isempty(vi)
        println(io, "Models in JuliaVision (dev/JuliaVision, on the GPU):")
        foreach(v -> println(io, "- $(v["name"])", v["in_env"] ? "" : " (not in the environment yet: `Pkg.develop(path = \"dev/JuliaVision/$(v["name"])\")`)",
                              ": $(v["summary"])"), vi)
    end
    if !isempty(di)
        println(io, "From your own diary:")
        foreach(d -> println(io, "- $(d["name"]), \"$(d["title"])\": $(d["text"])"), di)
    end
    return String(take!(io))
end
