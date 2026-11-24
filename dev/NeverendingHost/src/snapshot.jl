# ── the whole game on GitHub, one commit per session: the dough people fork ──
#
# After every session the host copies the game into a git working copy outside
# the world (`.jail/game`) and pushes it to `cfg.game_repo` as one commit, tagged
# `session-<n>`. A fork starts exactly there and owns all of it, like a piece of
# Hermann dough: no one else's branch to follow, its own blog. Every file of the
# game has one of three places (`place`):
#
#   :git    in the commit. The code: the engine, the host, the plugins, and every
#           checkout the environment develops from dev/ (Makie with RayMakie and
#           WGLMakie, Mantle, Metal, Lava, Hikari, Raycore, JuliaVision,
#           VideoEditor, BonitoAgents, and what the character forked in) as plain
#           source, uncommitted work included. The character's notes and memory
#           (journal, todos, wishes, style, reviews), the world's state, its mood
#           and session count. And the generated assets the game uses
#           (world/assets, `used_assets`).
#   :pages  the blog's pictures, films and sounds (binary files in world/site):
#           served by the blog's GitHub Pages, where the host publishes them
#           (`publish_blog!`); `setup/files.tsv` lists them, `fork.jl` fetches them.
#   :local  stays on this machine and out of every fork, named in the snapshot's
#           `.gitignore`: what runs (world/run, log, sandbox), the human's
#           conversation (inbox, outbox), the character's own renders,
#           screenshots and takes (world/media, and any other binary file outside
#           assets and site), assets nothing uses and mesh backups. That is this
#           copy's own character; a fork grows its own.

game_dir(jp::JailPaths) = joinpath(jp.state, "game")

"World folders that stay on this machine (see the top of this file)."
const LOCAL_WORLD = ("run", "log", "sandbox", "inbox", "outbox", "media")

"The host's state a fork goes on from; the rest of `.jail` belongs to this machine."
const SNAPSHOT_STATE = ("config.toml", "mood.json", "sessions.jsonl")

"Where the game's code names the assets it loads (by their folder in world/assets)."
const GAME_CODE = ("world/plugins", "world/live/plugins", "world/state", "dev/NeverendingGame/src")

"GitHub takes no file of 100 MB or more: such a file stays local (and `snapshot!` says so)."
const GIT_MAX = 95_000_000

"Files of the snapshot the host writes itself (see `write_generated!`)."
const GENERATED = ("README.md", "fork.jl", ".gitignore", "setup/files.tsv")

"""
    dev_checkouts(root) -> Vector{String}

The folders of dev/ the environment develops packages from (paths in the Manifest): the ones a
fork needs, the character's own forks of packages included. Others (references) stay here.
"""
function dev_checkouts(root::AbstractString)
    dev = joinpath(root, "dev")
    used = Set{String}()
    for m in eachmatch(r"^path = \"(.*)\"$"m, read(joinpath(root, "Manifest.toml"), String))
        p = normpath(isabspath(m[1]) ? m[1] : joinpath(root, m[1]))
        startswith(p, dev * "/") && push!(used, first(splitpath(relpath(p, dev))))
    end
    return sort!(collect(used))
end

"""
    tree_files(root, dir; skip = ()) -> Vector{String}

The files below `root/dir`, relative to `root`, skipping the top level folders `skip`: what git
tracks or would track (ignored files left out) when `dir` is a checkout of its own, else all
of them. Symbolic links count as files.
"""
function tree_files(root::AbstractString, dir::AbstractString; skip = ())
    full = joinpath(root, dir)
    if isdir(joinpath(full, ".git"))
        out = read(`git -C $full ls-files -z --cached --others --exclude-standard`, String)
        return [joinpath(dir, f) for f in split(out, '\0'; keepempty = false)
                if islink(joinpath(full, f)) || isfile(joinpath(full, f))]
    end
    files = String[]
    for (r, dirs, fs) in walkdir(full)
        rel = relpath(r, root)
        r == full && filter!(d -> !(d in skip), dirs)
        filter!(d -> d != ".git", dirs)
        foreach(d -> islink(joinpath(r, d)) && push!(files, joinpath(rel, d)), dirs)
        foreach(f -> push!(files, joinpath(rel, f)), fs)
    end
    return files
end

"""
    snapshot_files(root) -> Vector{String}

Every file of the game that is not local by its folder (`LOCAL_WORLD`), relative to `root`.
"""
function snapshot_files(root::AbstractString)
    files = filter(f -> isfile(joinpath(root, f)), ["Project.toml", "Manifest.toml", "LocalPreferences.toml"])
    foreach(d -> append!(files, tree_files(root, joinpath("dev", d))), dev_checkouts(root))
    append!(files, tree_files(root, "world"; skip = LOCAL_WORLD))
    foreach(f -> isfile(joinpath(root, ".jail", f)) && push!(files, joinpath(".jail", f)), SNAPSHOT_STATE)
    return files
end

"Whether a file is binary (a NUL byte in its first 8000, as git decides)."
binary(path::AbstractString) = 0x00 in open(io -> read(io, 8000), path)

"""
    used_assets(root) -> Set{String}

The generated assets the game uses: the folders of world/assets that its code or saved state
names (`GAME_CODE`), as placed props, plugin constants or engine defaults.
"""
function used_assets(root::AbstractString)
    dir = joinpath(root, "world", "assets")
    code = IOBuffer()
    for d in GAME_CODE, (r, _, fs) in walkdir(joinpath(root, d)), f in fs
        endswith(f, ".jl") || endswith(f, ".json") || continue
        write(code, read(joinpath(r, f)))
    end
    text = String(take!(code))
    return Set(filter(id -> isdir(joinpath(dir, id)) && occursin(id, text), readdir(dir)))
end

"""
    place(root, f, used) -> :git, :pages or :local

Where the file `f` (relative to `root`) goes: see the top of this file.
"""
function place(root::AbstractString, f::AbstractString, used::Set{String})
    p = joinpath(root, f)
    islink(p) && return :git
    filesize(p) >= GIT_MAX && return :local
    parts = splitpath(f)
    parts[1] == "world" || return :git
    if parts[2] == "assets"
        length(parts) == 3 && return :git                          # the catalog
        return parts[3] in used && parts[end] != "mesh_raw.jls" ? :git : :local
    end
    binary(p) || return :git
    return parts[2] == "site" ? :pages : :local
end

"""
    sync_tree!(src, dst, files)

`dst` holds exactly `files` of `src` (and the `GENERATED` ones), copying only what changed since
the last sync: a copy is newer than its source until the source changes again.
"""
function sync_tree!(src::AbstractString, dst::AbstractString, files)
    for f in files
        s, d = joinpath(src, f), joinpath(dst, f)
        if islink(s)
            islink(d) && readlink(d) == readlink(s) && continue
            mkpath(dirname(d))
            rm(d; force = true)
            symlink(readlink(s), d)
        elseif islink(d) || !isfile(d) || filesize(d) != filesize(s) || mtime(s) >= mtime(d)
            mkpath(dirname(d))
            cp(s, d; force = true)
        end
    end
    keep = union(Set(files), GENERATED)
    for (r, dirs, fs) in walkdir(dst)
        filter!(d -> !(r == dst && d == ".git"), dirs)
        for f in [fs; filter(d -> islink(joinpath(r, d)), dirs)]
            relpath(joinpath(r, f), dst) in keep || rm(joinpath(r, f))
        end
    end
    return dst
end

"Where GitHub Pages serves the blog repository `repo` (\"owner/name\")."
function pages_url(repo::AbstractString)
    owner, name = split(repo, '/')
    return name == "$owner.github.io" ? "https://$name" : "https://$owner.github.io/$name"
end

"The Manifest with the checkouts' paths relative to the game, as a fork has them."
relative_manifest(text::AbstractString, root::AbstractString) = replace(text, "path = \"$(rstrip(root, '/'))/" => "path = \"")

"""
    with_github(config, values) -> config

The host's config text with the keys `values` of its `[github]` section set (where it publishes).
"""
function with_github(text::AbstractString, values::AbstractDict)
    section = ""
    lines = map(split(text, '\n')) do l
        m = match(r"^\[([^\]]+)\]", l)
        m === nothing || (section = m[1])
        k = match(r"^(\w+) = ", l)
        section == "github" && k !== nothing && haskey(values, k[1]) ? "$(k[1]) = $(repr(String(values[k[1]])))" : l
    end
    return join(lines, '\n')
end

"The host's config without where this character publishes: a fork sets its own (`fork!`)."
fork_config(text::AbstractString) = with_github(text, Dict("blog" => "", "game" => "", "email" => ""))

"The asset catalog with the assets a fork gets (`used`) only."
function used_catalog(path::AbstractString, used::Set{String})
    entries = filter(e -> e["id"] in used, read_json(path)["assets"])
    return JSON.json(Dict("assets" => entries); pretty = true)
end

"`.gitignore` patterns for paths below the game: git's special characters escaped."
ignore_line(path::AbstractString) = "/" * replace(path, r"([\[\]*?!#\\ ])" => s"\\\1")

"""
    write_generated!(jp, dir, n, repo, pages, ignored, used)

The snapshot's own files: the README (`fork/README.md` of this package), `fork.jl`, the blog's
files on GitHub Pages (`pages`: path, size, sha256, url), a `.gitignore` that keeps them and
everything local (`ignored`) out of a fork's git, and the Manifest, config and asset catalog as
a fork needs them.
"""
function write_generated!(jp::JailPaths, dir::AbstractString, n::Int, repo::AbstractString, pages, ignored, used)
    tmpl = joinpath(@__DIR__, "..", "fork")
    julia = match(r"^julia_version = \"(\d+\.\d+)"m, read(joinpath(jp.root, "Manifest.toml"), String))[1]
    readme = replace(read(joinpath(tmpl, "README.md"), String), "{{NAME}}" => character_name(jp), "{{SESSION}}" => string(n),
                     "{{REPO}}" => repo, "{{JULIA}}" => julia, "{{DATE}}" => Dates.format(Dates.now(), "yyyy-mm-dd HH:MM"))
    write(joinpath(dir, "README.md"), readme)
    cp(joinpath(tmpl, "fork.jl"), joinpath(dir, "fork.jl"); force = true)
    mkpath(joinpath(dir, "setup"))
    open(joinpath(dir, "setup", "files.tsv"), "w") do io
        println(io, "path\tsize\tsha256\turl")
        foreach(r -> println(io, join(r, '\t')), pages)
    end
    open(joinpath(dir, ".gitignore"), "w") do io
        println(io, "# written by the host: what stays on each machine, and the blog's files (setup/files.tsv)")
        foreach(d -> println(io, "/world/$d/"), LOCAL_WORLD)
        println(io, "/.jail/*")
        foreach(f -> println(io, "!/.jail/$f"), SNAPSHOT_STATE)
        println(io, "/world/assets/*/mesh_raw.jls")
        assets = joinpath(jp.world, "assets")
        foreach(id -> println(io, ignore_line("world/assets/$id/")), filter(id -> isdir(joinpath(assets, id)) && !(id in used), readdir(assets)))
        foreach(f -> println(io, ignore_line(f)), filter(f -> !startswith(f, "world/assets/"), ignored))
        foreach(r -> println(io, ignore_line(r[1])), pages)
    end
    write(joinpath(dir, "Manifest.toml"), relative_manifest(read(joinpath(jp.root, "Manifest.toml"), String), jp.root))
    write(joinpath(dir, ".jail", "config.toml"), fork_config(read(config_path(jp), String)))
    write(joinpath(dir, "world", "assets", "catalog.json"), used_catalog(joinpath(jp.world, "assets", "catalog.json"), used))
    return dir
end

"""
    snapshot!(jp, cfg, n) -> (url or nothing, files too big for git)

The game after session `n` as one commit of `cfg.game_repo`, tagged `session-<n>` (see the top of
this file). `nothing` when nothing changed. A character without a blog keeps its pages' files local.
"""
function snapshot!(jp::JailPaths, cfg::HostConfig, n::Int)
    root, repo, tag = jp.root, cfg.game_repo, "session-$n"
    dir = working_copy!(jp, game_dir(jp), repo)
    git(args...) = host_git(jp, dir, args...)
    files = snapshot_files(root)
    used = used_assets(root)
    places = Dict(f => place(root, f, used) for f in files)
    isempty(cfg.blog_repo) && foreach(f -> places[f] === :pages && (places[f] = :local), files)
    sync_tree!(root, dir, filter(f -> places[f] === :git, files))
    site = joinpath("world", "site")
    pages = sort!([(f, filesize(joinpath(root, f)), bytes2hex(open(SHA.sha256, joinpath(root, f))),
                    pages_url(cfg.blog_repo) * "/" * join(splitpath(relpath(f, site)), '/'))
                   for f in files if places[f] === :pages])
    ignored = sort!(filter(f -> places[f] === :local, files))
    write_generated!(jp, dir, n, repo, pages, ignored, used)
    leaked = secret_files(jp, dir)
    isempty(leaked) || error("the game snapshot holds secrets, not published: " * join(leaked, ", "))
    # not forced: what this user never commits (their global git ignore: local settings, .env) stays out
    run(git("add", "-A"))
    big = filter(f -> filesize(joinpath(root, f)) >= GIT_MAX, ignored)
    isempty(read(git("status", "--porcelain"), String)) && return nothing, big
    name = character_name(jp)
    run(git("-c", "user.name=$name", "-c", "user.email=$(cfg.github_email)", "commit", "-q", "-m", "$name after session $n"))
    run(git("tag", "-f", tag))
    run(git("push", "-q", "origin", "main"))
    run(git("push", "-q", "-f", "origin", tag))
    return "https://github.com/$repo/tree/$tag", big
end

"""
    publish_game!(host, n)

The game after session `n` on GitHub (`cfg.game_repo`), for anyone to fork: see `snapshot!`.
"""
function publish_game!(host, n::Int)
    isempty(host.cfg.game_repo) && return nothing
    url, big = snapshot!(host.jp, host.cfg, n)
    url === nothing || record!(host.activity, "session $n", "host", "the game after session $n: $url")
    isempty(big) || record!(host.activity, "session $n", "error",
                            "too big for git (GitHub takes less than 100 MB), left out of the game: " * join(big, ", "))
    return nothing
end
