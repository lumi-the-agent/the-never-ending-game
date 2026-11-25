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

"How long (s) a creature's pose blends from its last action into a new one (s76, goal 6: switching from a
wings-out `:proud` to `:idle` snapped a wing 1.5 m in one frame)."
const POSE_BLEND = 0.22f0

"Per species: each creature's action code and extra last frame, the code and extra it came from, and when it switched."
const POSE_MEMORY = Dict{String,Any}()

"Normalised lerp of two rotations (the short way round)."
function nlerp(a::Quaternionf, b::Quaternionf, w::Float32)
    da, db = a.data, b.data
    s = sum(da .* db) < 0 ? -1.0f0 : 1.0f0
    d = ntuple(k -> da[k] * (1 - w) + s * db[k] * w, 4)
    n = sqrt(sum(abs2, d))
    return Quaternionf(d[1] / n, d[2] / n, d[3] / n, d[4] / n)
end

function pose_herd(sp::Species, pos, motion, state, t)
    out = [(Point3f[], Quaternionf[], Vec3f[], Mat{2,3,Float32}[]) for _ in sp.parts]
    n = length(pos); tf = Float32(t)
    mem = get(POSE_MEMORY, sp.name, nothing)
    if mem === nothing || length(mem.code) != n      # a creature came or went: start afresh
        mem = (code = Float32[s[1] for s in state], extra = Float32[s[2] for s in state],
               from = Float32[s[1] for s in state], fextra = Float32[s[2] for s in state], since = fill(-1.0f6, n))
        POSE_MEMORY[sp.name] = mem
    end
    a = [(Point3f[], Quaternionf[], Vec3f[], Mat{2,3,Float32}[]) for _ in sp.parts]
    b = [(Point3f[], Quaternionf[], Vec3f[], Mat{2,3,Float32}[]) for _ in sp.parts]
    for i in 1:n
        yaw, phase, mood = motion[i]
        code, extra, seed = state[i]
        if code != mem.code[i]
            mem.from[i] = mem.code[i]; mem.fextra[i] = mem.extra[i]; mem.since[i] = tf; mem.code[i] = code
        end
        mem.extra[i] = extra
        u = (tf - mem.since[i]) / POSE_BLEND
        p = Point3f(pos[i])
        if 0 <= u < 1
            foreach(o -> foreach(empty!, o), a); foreach(o -> foreach(empty!, o), b)
            pose_parts!(a, sp, p, yaw, action_name(round(Int, mem.from[i])), phase, mood, mem.fextra[i], seed, tf)
            pose_parts!(b, sp, p, yaw, action_name(round(Int, code)), phase, mood, extra, seed, tf)
            w = Float32(u * u * (3 - 2u))
            for j in eachindex(sp.parts)
                A, B, O = a[j], b[j], out[j]
                for k in eachindex(B[1])
                    push!(O[1], A[1][k] + (B[1][k] - A[1][k]) * w)
                    push!(O[2], nlerp(A[2][k], B[2][k], w))
                    push!(O[3], A[3][k] + (B[3][k] - A[3][k]) * w)
                end
                append!(O[4], B[4])
            end
        else
            pose_parts!(out, sp, p, yaw, action_name(round(Int, code)), phase, mood, extra, seed, tf)
        end
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
