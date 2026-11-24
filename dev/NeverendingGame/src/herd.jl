# ── Herd: all creatures of one species as one plot ──────────────────────────
#
# Inputs are the per creature pose arrays (all recordable by VideoEditor):
#
#   pos     Vector{Point3f}   where it stands
#   motion  Vector{Vec3f}     (yaw, gait phase, mood)
#   state   Vector{Vec3f}     (action code, extra, seed)
#   time    Float32           sim time
#
# One meshscatter per body part, instanced over the herd, so the cost of a
# frame grows with species × parts, not with the number of creatures.

Makie.@recipe Herd (pos,) begin
    "The `Species` body plan."
    species = nothing
    "Per creature (yaw, gait phase, mood)."
    motion = Vec3f[]
    "Per creature (action code, extra, seed)."
    state = Vec3f[]
    "Sim time in seconds."
    time = 0.0f0
    Makie.mixin_generic_plot_attributes()...
end

Makie.conversion_trait(::Type{<:Herd}, args...) = Makie.NoConversion()

"The outputs of part `j`: where its instances are, how they turn and scale, and for a part that `paints` their uv transforms."
part_outputs(j::Int, part::Part) = paints(part.motion) ?
    (Symbol(:part, j, :_pos), Symbol(:part, j, :_rot), Symbol(:part, j, :_scale), Symbol(:part, j, :_uv)) :
    (Symbol(:part, j, :_pos), Symbol(:part, j, :_rot), Symbol(:part, j, :_scale))

function pose_herd(sp::Species, pos, motion, state, t)
    out = [(Point3f[], Quaternionf[], Vec3f[], Mat{2,3,Float32}[]) for _ in sp.parts]
    for i in eachindex(pos)
        yaw, phase, mood = motion[i]
        code, extra, seed = state[i]
        pose_parts!(out, sp, Point3f(pos[i]), yaw, action_name(round(Int, code)), phase, mood, extra, seed, Float32(t))
    end
    return out
end

function Makie.plot!(p::Herd)
    sp = p.species[]::Species
    outputs = Symbol[]
    foreach(((j, part),) -> append!(outputs, part_outputs(j, part)), enumerate(sp.parts))
    map!(p.attributes, [:pos, :motion, :state, :time], outputs) do pos, motion, state, t
        posed = pose_herd(sp, pos, motion, state, t)
        return Tuple(x for (part, o) in zip(sp.parts, posed) for x in (paints(part.motion) ? o : o[1:3]))
    end
    for (j, part) in enumerate(sp.parts)
        keys = part_outputs(j, part)
        uv = paints(part.motion) ? (; uv_transform = getproperty(p, keys[4])) : (;)
        meshscatter!(p, getproperty(p, keys[1]); rotation = getproperty(p, keys[2]), markersize = getproperty(p, keys[3]),
                     marker = shape(part.shape), material = part.material, visible = p.visible, uv..., part.attributes...)
    end
    return p
end

"Which creature (index into the herd) a picked meshscatter instance belongs to."
function herd_index(h::Herd, child::Plot, instance::Integer)
    j = findfirst(==(child), h.plots)
    j === nothing && return nothing
    return cld(instance, ncopies(h.species[].parts[j]))
end
