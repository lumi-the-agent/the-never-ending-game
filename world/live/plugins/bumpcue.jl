# Bump cue (s48, perfectionist-0046 / session-0047 review: "Lumi gives no cue when blocked"): when the
# player holds W but Lumi has made no headway for a moment (a bush, a lantern, the pond edge), Lumi
# shows a "?" and says it is stuck, with the way out: turn with A or D. Once per bump, not every frame.
const NG = NeverendingGame

struct BumpCue <: System end

const STUCK_AFTER = 1.2      # s of holding W with no headway
const HEADWAY = 0.3f0        # m ahead that count as getting somewhere in that time
const CUE_GAP = 6.0          # s between two cues
const LINES = ("Oof! Something's in the way. Turn with A or D!", "Bonk! Let's go round: A or D.",
               "Stuck! Steer round it with A or D.")

isdefined(Main, :BUMPCUE) || Core.eval(Main, :(const BUMPCUE = Dict{Symbol,Any}(:from => nothing, :last => -Inf, :count => 0)))
const BC = Main.BUMPCUE

function NG.step!(::BumpCue, game, dt)
    w = game.world
    i = findfirst(c -> c.controlled, w.creatures)
    if i === nothing
        BC[:from] = nothing
        return
    end
    c = w.creatures[i]
    # W let go (or a wave, a jump) for a moment: start over. A blocked walker flickers to :idle for a frame or
    # two (Separation pushes it back), so short gaps do not count.
    c.action in (:walk, :run) && (BC[:walked] = w.t)
    # the bump shows on the face too: a short gasp (todo #325; feel! leaves a steered creature alone, so the
    # action is set here, after the engine's step, for 0.9 s)
    w.t < get(BC, :gasp_until, -Inf) && (c.action = :gasp)
    if w.t - get(BC, :walked, -Inf) > 0.5
        BC[:from] = nothing
        return
    end
    from = BC[:from]
    # headway is progress in the walking direction: sliding sideways along a trunk W points into is not getting there
    ahead = from === nothing ? 0f0 : (c.pos[1] - from[1][1]) * cos(c.yaw) + (c.pos[2] - from[1][2]) * sin(c.yaw)
    if from === nothing || ahead > HEADWAY
        BC[:from] = (c.pos, w.t)              # getting somewhere: measure from here
        return
    end
    w.t - from[2] < STUCK_AFTER && return
    BC[:from] = (c.pos, w.t)
    w.t - BC[:last] < CUE_GAP && return
    BC[:last] = w.t
    BC[:count] += 1
    BC[:gasp_until] = w.t + 0.9
    isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], c.id, :what)
    NG.say!(w, c, LINES[mod1(BC[:count], length(LINES))]; duration = 2.5)
    NG.emit!(w, :bump_cue; who = c.name)
    return
end

register!(BumpCue())
