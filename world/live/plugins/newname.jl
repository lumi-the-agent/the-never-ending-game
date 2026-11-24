# Lumi's name (s60, the human chose it; before that Sprout the bean, and Lumi was Dandy for an hour):
# a game that was running when the name changed still has the old creature and a herd built for that
# species. This renames it once (engine `rename_hero!`, the loader does the same for saved worlds), lets
# the next sync! build Lumi's herd and fixes the dashboard's side header.
const NG = NeverendingGame

struct NewName <: System end

const OLD = ("Sprout", "Dandy")

function NG.step!(::NewName, game, dt)
    w = game.world
    any(c -> c.species in OLD, w.creatures) || return
    isdefined(NG, :lumi) || return
    NG.register_species!(Base.invokelatest(NG.lumi))
    Base.invokelatest(NG.rename_hero!, w)
    st = game.stage
    for name in OLD
        if st !== nothing && haskey(st.herds, name)
            delete!(st.scene, st.herds[name])
            delete!(st.herds, name)
        end
    end
    relabel!(game)
    isdefined(Main, :PRESENTS) && haskey(Main.PRESENTS, :likes) && foreach(n -> delete!(Main.PRESENTS[:likes], n), OLD)
    NG.emit!(w, :renamed; to = "Lumi")
    return
end

"The dashboard's side header was written with the old name when the game started."
function relabel!(game)
    game.dash === nothing && return
    for b in game.dash.fig.content
        b isa NG.Label && b.text[] in OLD && (b.text[] = "Lumi")
    end
    return
end

register!(NewName())
