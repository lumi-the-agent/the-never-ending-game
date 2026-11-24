# ── GitHub, as the character's account, from outside every jail ─────────────
#
# The host publishes for the character (its pages, the game snapshots) with a
# token the jails never see; the character itself never writes online (RULES 12).

"""
The host's GitHub credentials, outside every jail (each role mounts a home of its own):
`github_token`, `askpass.sh` (hands it to git as the password) and `github_auth_header`
(curl's `Authorization` header for the API).
"""
github_dir(jp::JailPaths) = joinpath(jp.user_home, ".config", "neverending")

"""
    host_git(jp, dir, args...) -> Cmd

`git` in the working copy `dir`, authenticated with the token in `github_dir`. No credential
helper: the human's own GitHub login (a global helper) would answer before askpass, and the
first push went out as the human (refused, luckily).
"""
host_git(jp::JailPaths, dir::AbstractString, args...) =
    addenv(`git -C $dir -c credential.helper= $args`, "GIT_ASKPASS" => joinpath(github_dir(jp), "askpass.sh"),
           "GIT_TERMINAL_PROMPT" => "0")

"""
    working_copy!(jp, dir, repo) -> dir

The host's git working copy of `repo` ("owner/name") at `dir`, made on first use. A repository
that has a history goes on from it: its last commit becomes the index, so the first commit from
here holds only what changed.
"""
function working_copy!(jp::JailPaths, dir::AbstractString, repo::AbstractString)
    isdir(joinpath(dir, ".git")) && return dir
    mkpath(dir)
    git(args...) = host_git(jp, dir, args...)
    run(git("init", "-q", "-b", "main"))
    run(git("remote", "add", "origin", "https://$(first(split(repo, '/')))@github.com/$(repo).git"))
    success(git("fetch", "-q", "--tags", "origin", "main")) && run(git("reset", "-q", "--soft", "origin/main"))
    return dir
end

# ── nothing secret goes out ─────────────────────────────────────────────────

"""
Secrets never go public: GitHub tokens, API keys and private keys by their form, and the host's
own secrets and the human's Claude login by their value. `(patterns, fixed strings)` for `grep`.
"""
function secret_patterns(jp::JailPaths)
    forms = ["gh[pousr]_[A-Za-z0-9]{30,}", "github_pat_[A-Za-z0-9_]{40,}", "sk-ant-[a-z]{3}[0-9]{2}-[A-Za-z0-9_-]{20,}",
             "sk-proj-[A-Za-z0-9_-]{20,}", "sk-or-v1-[0-9a-f]{40,}", "-----BEGIN [A-Z ]*PRIVATE KEY-----",
             "AKIA[0-9A-Z]{16}", "xox[baprs]-[A-Za-z0-9-]{10,}"]
    values = String[]
    token = joinpath(github_dir(jp), "github_token")
    isfile(token) && push!(values, strip(read(token, String)))
    login = joinpath(jp.user_home, ".claude", ".credentials.json")      # the human's own Claude login
    if isfile(login)
        o = read_json(login)["claudeAiOauth"]
        push!(values, o["accessToken"], o["refreshToken"])
    end
    env = joinpath(jp.secrets, "env")
    foreach(f -> push!(values, strip(read(joinpath(env, f), String))), readdir(env))
    return forms, filter(v -> length(v) >= 12, values)
end

"The files of `dir` (its git history aside) that hold a secret; it must stay empty."
function secret_files(jp::JailPaths, dir::AbstractString)
    forms, values = secret_patterns(jp)
    found = String[]
    mktemp() do path, io
        for (flag, pats) in (("-E", forms), ("-F", values))
            isempty(pats) && continue
            seekstart(io); truncate(io, 0); write(io, join(pats, '\n')); flush(io)
            out = read(ignorestatus(`grep -rIl $flag --exclude-dir=.git -f $path $dir`), String)
            append!(found, split(out, '\n'; keepempty = false))
        end
    end
    return unique!(relpath.(found, dir))
end
