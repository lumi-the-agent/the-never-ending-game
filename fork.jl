# Make this copy of The Never Ending Game your own:
#
#     julia fork.jl
#
# Installs the packages (every dependency is here as source, in dev/), fetches the
# files that are not in git (meshes, renders, films: setup/files.tsv), asks for
# your character's name and your GitHub repositories, and downloads RomeoDB's
# index of the Julia ecosystem (about 2.5 GB), which the agent searches before it
# writes anything new. See README.md.
import Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()
using NeverendingHost, RomeoDB
NeverendingHost.fork!(@__DIR__)
RomeoDB.ensure_index!(joinpath(@__DIR__, ".jail", "romeodb"))
