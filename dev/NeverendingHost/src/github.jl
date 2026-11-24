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
