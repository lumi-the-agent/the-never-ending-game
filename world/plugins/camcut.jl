# Camera cuts: when the follow camera's goal jumps (a new subject, a chat starts, a night shot
# changes), the camera CUTS to the new view instead of sliding there. The slide took about a
# second with the creature 12-50° off the middle of the frame, often at the edge or cut off
# (review s44: "the subject is often pushed to the edge or corner"; s45 probe: 50° just after a
# switch, 1-4° once settled). Small goal moves (a walking subject) still glide.
const NG = NeverendingGame

const CUT_TARGET = 1.5f0   # m the goal's look point jumps in one frame
const CUT_EYE = 3f0        # m the goal's eye jumps in one frame

const LAST = Ref{Any}(nothing)
const CUTS = Ref(0)
const BLOCK_CUTS = Ref(0)
const LAST_BLOCK_CUT = Ref(-Inf)
const BLOCKED = 0.4f0      # obstruction of the view on screen that cuts to a clear goal view (s45 suite: 0.58 while gliding)

struct CamCut <: System end

NG.start!(::CamCut, game) = (LAST[] = nothing; nothing)
NG.stop!(::CamCut, game) = (LAST[] = nothing; nothing)

function NG.step!(::CamCut, game, dt)
    rig = game.rig
    if game.stage === nothing || rig.mode !== :follow || rig.subject != 0 || any(c -> c.controlled, game.world.creatures)
        LAST[] = nothing
        return
    end
    eye, target = NG.camera_goal(rig, game.world)
    # a new subject, or a new quiet-night shot (its look point stays put during a shot)
    shot = NG.camera_shot(game.world)
    who = shot === nothing ? NG.AUTO_SUBJECT[][1] : shot[2]
    last = LAST[]
    LAST[] = (eye, target, who)
    last === nothing && return
    # only a new subject cuts: a view that flips sides on one subject (face or back, a bush moving
    # into the line) glides, or the camera cut every 1.5 s (s45 probe: 20 cuts in 30 s)
    if who != last[3] && (norm(target - last[2]) > CUT_TARGET || norm(eye - last[1]) > CUT_EYE)
        rig.eye = eye; rig.target = target
        CUTS[] += 1
        return
    end
    # a glide that passes behind trees or a hill (a side flip on one subject): cut to the clear goal view
    # instead of showing a trunk for a second (s45 suite: obstruction 0.58, goal view clear, eye 3.5 m away)
    w = game.world
    if norm(rig.eye - eye) > 1.5f0 && game.world.t - LAST_BLOCK_CUT[] > 2 &&
       NG.obstruction(w, rig.eye, rig.target) > BLOCKED && NG.obstruction(w, eye, target) < 0.15f0
        rig.eye = eye; rig.target = target
        BLOCK_CUTS[] += 1
        LAST_BLOCK_CUT[] = w.t
    end
    # a side flip glides through the space above the subject and looks down on heads for a moment
    # (s65: 48° in a 90 s sample, review 0064): cut to the goal view once the glide gets that steep
    steep(e, t) = (d = t - e; atand(-d[3], hypot(d[1], d[2])) > 36)
    if steep(rig.eye, rig.target) && !steep(eye, target)
        rig.eye = eye; rig.target = target
        CUTS[] += 1
    end
    return
end

register!(CamCut())
