# ── making a copy of the game your own ──────────────────────────────────────
#
# A snapshot (`snapshot.jl`) is the whole game. `julia fork.jl` in it installs the
# packages and calls `fork!`: it fetches the blog's pictures and films from its
# GitHub Pages, names the character, and points the host's publishing at the
# forker's own repositories, so the fork grows its own way with its own blog.

read_tsv(path) = isfile(path) ? [split(l, '\t') for l in eachline(path) if !isempty(l)] : Vector{SubString{String}}[]

"""
    fetch_files!(root) -> number of files fetched

The blog's files of the snapshot in `root` (`setup/files.tsv`: path, size, sha256, url), from
the blog's GitHub Pages. A file the blog changed after that session is kept as the blog has it
now, and said so. Those already here in full are kept.
"""
function fetch_files!(root::AbstractString)
    rows = filter(r -> r[1] != "path", read_tsv(joinpath(root, "setup", "files.tsv")))
    todo = filter(r -> !(isfile(joinpath(root, r[1])) && filesize(joinpath(root, r[1])) == parse(Int, r[2])), rows)
    mb = sum(r -> parse(Int, r[2]), todo; init = 0) / 1e6
    println("fetching $(length(todo)) of the blog's $(length(rows)) files ($(round(Int, mb)) MB)")
    for (i, (rel, _, sha, url)) in enumerate(todo)
        path = joinpath(root, rel)
        mkpath(dirname(path))
        Downloads.download(url, path)
        changed = bytes2hex(open(SHA.sha256, path)) == sha ? "" : " (the blog changed it since)"
        println("  [$i/$(length(todo))] $rel$changed")
    end
    return length(todo)
end

"""
    relocate_catalog!(jp)

The asset catalog's paths (`mesh`, `image`) at this copy's world: the worker writes them absolute.
"""
function relocate_catalog!(jp::JailPaths)
    path = joinpath(jp.world, "assets", "catalog.json")
    entries = read_json(path)["assets"]
    for e in entries, k in ("mesh", "image")
        haskey(e, k) && (e[k] = joinpath(jp.world, "assets", e["id"], basename(e[k])))
    end
    write_json(path, Dict("assets" => entries))
    return path
end

"The GitHub repository (\"owner/name\") the game in `root` was cloned from, or \"\"."
function origin_repo(root::AbstractString)
    isdir(joinpath(root, ".git")) || return ""
    url = readchomp(ignorestatus(`git -C $root remote get-url origin`))
    m = match(r"github\.com[:/]([^/]+/[^/]+?)(\.git)?$", url)
    return m === nothing ? "" : String(m[1])
end

"`content` in a new file only this user can read."
function private_write(path::AbstractString, content::AbstractString; mode = 0o600)
    touch(path)
    chmod(path, mode)
    write(path, content)
    return path
end

"""
    github_credentials!(jp, token)

The host's GitHub login (`github_dir`): the token, git's password prompt for it and curl's
header, readable by this user only and outside every jail.
"""
function github_credentials!(jp::JailPaths, token::AbstractString)
    dir = mkpath(github_dir(jp))
    chmod(dir, 0o700)
    t = strip(token)
    private_write(joinpath(dir, "github_token"), t)
    private_write(joinpath(dir, "github_auth_header"), "Authorization: Bearer $t\n")
    private_write(joinpath(dir, "askpass.sh"), """
        #!/bin/sh
        # git's password prompt for the host's pushes: the token, from beside this script
        tr -d '\\n\\r ' < "\$(dirname "\$0")/github_token"
        """; mode = 0o700)
    return dir
end

"""
    fork!(root; name, game, blog, email, token)

Make the copy of the game in `root` yours (`julia fork.jl` calls it once the packages are
installed): fetch the files that are not in git, name your character, and point the host's
publishing at your GitHub repositories: `game`, your fork of the game ("owner/name"; every
session becomes a commit there), and `blog` ("owner/owner.github.io"; the character's pages),
with `email` as the commits' author and the `token` of the account they belong to (made for the
character, not your own: the host publishes in its name). What is not given is asked; an empty
answer leaves that out.
"""
function fork!(root::AbstractString; name = nothing, game = nothing, blog = nothing, email = nothing, token = nothing)
    jp = JailPaths(root)
    fetch_files!(root)
    relocate_catalog!(jp)
    ask(question, default) = something(Base.prompt(question; default), default)
    name = something(name, ask("Your character's name", character_name(jp)))
    write(name_path(jp), strip(name))
    game = something(game, ask("Your fork of the game on GitHub (owner/name; empty: not published)", origin_repo(root)))
    blog = something(blog, ask("Its blog on GitHub Pages (owner/owner.github.io; empty: none)", ""))
    email = isempty(game) && isempty(blog) ? "" :
            something(email, ask("The commits' author address (the account's GitHub noreply address)", ""))
    if token === nothing && !(isempty(game) && isempty(blog)) && !isfile(joinpath(github_dir(jp), "github_token"))
        secret = Base.getpass("The token of that GitHub account (classic, repo scope)")
        token = read(secret, String)
        Base.shred!(secret)
    end
    token === nothing || github_credentials!(jp, token)
    write(config_path(jp), with_github(read(config_path(jp), String), Dict("game" => game, "blog" => blog, "email" => email)))
    cfg = load_config(jp)
    println("""

        $(strip(name)) lives in $(abspath(root)) now.
        - $(cfg.jail ? "Every role runs jailed (bubblewrap)." :
            "No jail here ([jail] in .jail/config.toml): the agents can read and write whatever you can.")
        - The agent: $(cfg.agent.provider) ($(isempty(cfg.agent.model) ? "its default model" : cfg.agent.model)), see [agent]
          in .jail/config.toml. Claude Code uses your login on Linux; elsewhere put a token from
          `claude setup-token` into .jail/secrets/env/CLAUDE_CODE_OAUTH_TOKEN.
        - Your wishes for the game go into world/GOALS.md.
        - Start it:  julia --project=dev/NeverendingHost/host -e 'using Revise, NeverendingHost; NeverendingHost.serve(".")'
          and play at http://localhost:$(cfg.web_port)
        """)
    return jp
end
