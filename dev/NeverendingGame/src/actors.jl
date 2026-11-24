# ── Actors: plugin defined things in the world ──────────────────────────────

"How the default renderer draws an actor type: one instanced mesh for all actors of the type."
struct ActorLook
    marker::Any            # a GeometryBasics mesh, or a shape name from shapes.jl (:sphere, :capsule, …)
    material::Any          # a Hikari material
    scale::Vec3f
end
ActorLook(; marker = :sphere, material = Hikari.Diffuse(color = (0.9, 0.9, 0.9)), scale = Vec3f(0.3)) =
    ActorLook(marker, material, Vec3f(scale))

actor_look(::Type{<:Actor}) = ActorLook()
actor_position(a::Actor) = a.pos
actor_rotation(::Actor) = QID
actor_scale(::Actor) = 1.0f0

"Keyboard events a mini game gets (Makie's own)."
const InputEvent = Makie.KeyEvent

"Name an actor type is saved under; stable across plugin reloads."
actor_kind(T::Type) = string(nameof(parentmodule(T)), ".", nameof(T))

# ── default renderer ────────────────────────────────────────────────────────

const HIDDEN = Point3f(0, 0, -100)

function visual(T::Type{<:Actor}, scene)
    l = actor_look(T)
    marker = l.marker isa Symbol ? shape(l.marker) : l.marker
    return meshscatter!(scene, [HIDDEN]; marker, material = l.material, markersize = [l.scale],
                        rotation = [QID], name = Symbol(actor_kind(T)))
end

function sync_visual!(plot, actors::Vector, game)
    if isempty(actors)
        Makie.update!(plot, [HIDDEN]; markersize = [Vec3f(0)], rotation = [QID])
        return
    end
    l = actor_look(typeof(first(actors)))
    Makie.update!(plot, Point3f[actor_position(a) for a in actors];
                  rotation = Quaternionf[actor_rotation(a) for a in actors],
                  markersize = Vec3f[l.scale * actor_scale(a) for a in actors])
end

# ── saving ──────────────────────────────────────────────────────────────────

to_json(x::Union{Real,AbstractString,Bool,Nothing}) = x
to_json(x::Symbol) = String(x)
to_json(x::Union{Point,Vec,Tuple}) = collect(x)
to_json(q::Quaternionf) = collect(q.data)
to_json(x::AbstractVector) = [to_json(v) for v in x]
to_json(x::AbstractDict) = Dict(string(k) => to_json(v) for (k, v) in x)
to_json(x) = error("actor field of type $(typeof(x)) cannot be saved by default; define `snapshot`/`restore` for the actor")

from_json(::Type{T}, v) where {T<:Real} = T(v)
from_json(::Type{String}, v) = String(v)
from_json(::Type{Symbol}, v) = Symbol(v)
from_json(::Type{T}, v) where {T<:Union{Point,Vec}} = T(v...)
from_json(::Type{Quaternionf}, v) = Quaternionf(v...)
from_json(::Type{Vector{T}}, v) where {T} = T[from_json(T, x) for x in v]
from_json(::Type{Dict{String,Any}}, v) = Dict{String,Any}(v)
from_json(::Type{Any}, v) = v

snapshot(a::Actor) = Dict{String,Any}(String(f) => to_json(getfield(a, f)) for f in fieldnames(typeof(a)))
restore(T::Type{<:Actor}, d::AbstractDict) = T((from_json(fieldtype(T, f), d[String(f)]) for f in fieldnames(T))...)

actor_dict(a::Actor) = Dict{String,Any}("kind" => actor_kind(typeof(a)), "data" => snapshot(a))

"""
    revive_actors!(world, types::Dict{String,DataType}) -> failures

Bring dormant actors back whose type is registered now. Returns
`kind => error` for those that could not be restored (they stay dormant).
"""
function revive_actors!(w::World, types::AbstractDict)
    failures = Pair{String,String}[]
    keep = Dict{String,Any}[]
    for d in w.dormant
        T = get(types, d["kind"], nothing)
        if T === nothing
            push!(keep, d)
            continue
        end
        a = try
            Base.invokelatest(restore, T, d["data"])
        catch e
            e isa InterruptException && rethrow()
            push!(failures, d["kind"] => sprint(showerror, e))
            nothing
        end
        a === nothing ? push!(keep, d) : push!(w.actors, a)
    end
    w.dormant = keep
    return failures
end

"Put the actors of type `T` to sleep as dicts (before their plugin is reloaded or unloaded)."
function suspend_actors!(w::World, T::Type)
    mine = filter(a -> a isa T, w.actors)
    filter!(a -> !(a isa T), w.actors)
    append!(w.dormant, [Base.invokelatest(actor_dict, a) for a in mine])
    return length(mine)
end

# ── spawning ────────────────────────────────────────────────────────────────

function spawn!(w::World, a::Actor)
    push!(w.actors, a)
    emit!(w, :actor_spawn; kind = actor_kind(typeof(a)))
    return a
end

function despawn!(w::World, a::Actor)
    filter!(x -> x !== a, w.actors)
    emit!(w, :actor_despawn; kind = actor_kind(typeof(a)))
    return a
end
