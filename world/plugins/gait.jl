# Calmer gaits (session 76, goal 6): the crab and the sheep stepped so fast that, running, their bodies and legs
# turned back 10-12 times a second (the host's motion measure: "vibrating", media/eyes/session-0076/motion.png).
# Fewer, longer steps per metre. Only the gait rate changes; the bodies (makeover.jl, the engine's species) stay.
const NG = NeverendingGame

"Gait radians per metre (the engine's were Crabbit 16, Fluffkin 12, Snootle 10, Blorbo 14)."
const STRIDES = Dict("Crabbit" => 8f0, "Fluffkin" => 7f0, "Snootle" => 7f0, "Blorbo" => 9f0)
const LAST = Ref(-Inf)

struct Gait <: System end

"Put the calmer stride on each species again (makeover.jl registers new bodies with the engine's stride)."
function retune!()
    for (name, st) in STRIDES
        sp = get(NG.SPECIES, name, nothing)
        (sp === nothing || sp.stride == st) && continue
        NG.register_species!(NG.Species(sp.name, sp.blurb, sp.parts, sp.height, sp.speed, st, sp.heading, sp.sounds))
    end
end

function NG.step!(::Gait, game, dt)
    game.world.t - LAST[] < 2 && return
    LAST[] = game.world.t
    retune!()
end

NG.start!(::Gait, game) = (LAST[] = -Inf; retune!())

register!(Gait())
