# "On the island now": a live line per creature in the right panel (who chats with whom, who is
# dancing, chasing the ball, asleep). The panel was half empty and showed a changelog line
# (perfectionist s33, ui): a player wants to know what the critters are up to, to go and join in.
const NG = NeverendingGame

struct OnTheIsland <: Panel end
NG.panel_title(::OnTheIsland) = "On the island now"

const MAX_LINES = 5

"What `c` is up to, in a few words, and how interesting that is (lower first)."
function doing(w, c)
    g = c.goal.kind; a = c.action
    for it in w.interactions
        (it.a == c.id || it.b == c.id) || continue
        o = NG.creature(w, it.a == c.id ? it.b : it.a)
        o === nothing || return ("and $(o.name) are chatting", it.a == c.id ? 1 : 99)     # one line per pair
    end
    g === :circle && return ("is dancing in the circle", 1)
    if g === :rain                                                                  # plugins/showers.jl
        a in (:walk, :run) && return ("runs for shelter from the rain", 1)
        a === :jump && return ("is splashing in the puddles", 1)
        a === :dance && return ("is dancing in the rain", 1)
        a === :idle && return ("hides from the rain under a tree", 1)
        return ("sits in the rain, nose up", 1)
    end
    g in (:fetch, :rally_wait) && return ("is playing ball", 1)
    if g === :tag                                                                   # plugins/tag.jl
        tg = isdefined(Main, :TAG_STATE) ? Main.TAG_STATE[:game] : nothing
        return tg !== nothing && tg[:it] == c.id ? ("is it! (playing tag)", 0) : ("is playing tag", 1)
    end
    g === :seek_friend && return ("goes to see a friend", 2)                       # plugins/feelings.jl
    g === :keep_company && return ("sits with a friend", 2)
    g === :explore && return ("is exploring", 3)
    g === :follow && return ("is following Lumi", 1)
    g === :hide && return ("is hiding somewhere... hee hee", 1)                    # plugins/hideseek.jl
    g === :found && return ("was found and follows Lumi", 1)
    walking = a in (:walk, :run)
    g === :beachcomb && return walking ? ("is off to the beach", 4) : ("hunts for shells on the beach", 2)   # plugins/beach.jl
    g === :sunbathe && return walking ? ("is off to the beach", 4) : ("sunbathes on the warm sand", 2)
    g === :fish && return walking ? ("is off to the pier", 4) : ("is fishing off the pier", 2)          # plugins/areas.jl
    g === :splash && return walking ? ("runs to the pond", 4) : ("splashes in the pond", 2)
    g === :build && return walking ? ("carries something new over", 0) : ("is building something new", 0)   # plugins/builder.jl
    g === :tend && return walking ? ("is off to the vegetable patch", 0) : ("waters the vegetable patch", 0)   # plugins/garden.jl
    g === :sunset && return walking ? ("is off to the lookout bench", 1) : ("watches the sunset from the bench", 0)   # plugins/lookout.jl
    g === :invite && return ("asks a friend along", 1)                              # plugins/presents.jl
    if g === :present                                                               # plugins/presents.jl
        j = isdefined(Main, :PRESENTS) ? get(Main.PRESENTS, :job, nothing) : nothing
        to = j === nothing ? nothing : NG.creature(w, j[:to])
        to === nothing && return ("is wrapping a present", 0)
        return j[:stage] === :fetch ? ("gets a present for $(to.name) from the crates", 0) : ("brings $(to.name) a present", 0)
    end
    if isdefined(Main, :PRESENTS) && haskey(get(Main.PRESENTS, :kept, Dict()), c.id) && !walking && g ∉ (:sleep,)
        return ("shows off a present from Lumi", 1)
    end
    g === :tinker && return walking ? ("is off to work", 1) : ("is tinkering", 1)
    if g === :choir                                                                 # plugins/choir.jl
        c.name == "Lumi" && return ("conducts the island choir", 0)
        return walking ? ("hurries to choir practice", 1) : a === :laugh ? ("laughs at the sour note", 1) : ("sings in the choir", 0)
    end
    a === :dance && return ("is dancing", 2)
    a === :talk && return ("is chatting", 2)
    a === :eat && return ("is eating berries", 3)
    a === :swim && return ("is swimming", 3)
    a === :sleep && return ("is asleep", 9)
    a in (:walk, :run) && g === :sleep && return ("is off to bed", 5)
    a in (:walk, :run) && g === :eat && return ("is off to the berry bushes", 4)
    a === :sit && return ("is sitting in the grass", 6)
    a === :jump && return ("is hopping about", 4)
    a in (:walk, :run) && return ("is wandering about", 7)
    return ("is looking around", 8)
end

NG.build_panel!(p::OnTheIsland, layout, game) =
    (Main.ISLANDNOW[:label] = Label(layout[1, 1], ""; fontsize = 15, color = RGBf(0.93, 0.94, 0.96),
                                    halign = :left, justification = :left, tellwidth = false); nothing)

function NG.update_panel!(p::OnTheIsland, game)
    w = game.world
    rows = [(c.controlled ? ("(you)", 0) : doing(w, c), c.name) for c in w.creatures]
    sort!(rows; by = r -> (r[1][2], r[2]))
    asleep = count(r -> r[1][2] == 9, rows)
    filter!(r -> r[1][2] != 99, rows)          # the other half of a chat
    shown = filter(r -> r[1][2] < 9, rows)
    lines = ["$(name) $(d[1])" for (d, name) in first(shown, MAX_LINES)]
    rest = length(shown) - length(lines)
    rest > 0 && push!(lines, "...and $(rest) more out and about")
    asleep > 0 && push!(lines, asleep == length(rows) ? "Everyone is asleep. Shh." : "$(asleep) asleep")
    Main.ISLANDNOW[:label].text[] = join(lines, "\n")
    return
end

isdefined(Main, :ISLANDNOW) || Core.eval(Main, :(const ISLANDNOW = Dict{Symbol,Any}()))
register!(OnTheIsland())
