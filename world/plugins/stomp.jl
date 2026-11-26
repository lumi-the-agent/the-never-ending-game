# One stomp bounces the whole island (s125). I jump and stomp, and the meadow rings like a drum skin: a ring of
# ground rolls outward and throws whoever it passes; everyone thrown lands with a thump that starts a ring of
# their own, the rings cross and spike, and a chain reaction runs over the island until the last one lands.
# Nothing is scripted: a 2D wave equation on a grid under the island (fixed where the ground meets the sea, so
# rings bounce back off the shore) lifts the terrain and path meshes; a creature on ground that rises faster
# than SP_THROW is thrown ballistically, and its landing is a new source.
#   Lumi stomps once a morning (10:00-10:30). Jumped in as Lumi: L stomps.
#   Main.STOMP[:force] = true   stomp now (films, tests); [:at] = (x, y) where Lumi stomps
const NG = NeverendingGame
isdefined(Main, :STOMP) || Core.eval(Main, :(const STOMP = Dict{Symbol,Any}()))
const SP = Main.STOMP

const SP_FROM_H = 10.0
const SP_TO_H = 10.5
const SP_R = 26f0            # the grid covers [-SP_R, SP_R]^2
const SP_DX = 0.4f0          # m per cell
const SP_N = round(Int, 2SP_R / SP_DX) + 1
const SP_C = 6.5f0           # m/s, how fast a ring runs
const SP_DAMP = 0.3f0        # 1/s
const SP_SIGMA = 1.3f0       # m, the width of a thump
const SP_LUMI = 42f0         # m/s of ground speed my stomp puts in
const SP_CHAIN = 4.5f0       # a landing at impact speed v puts in SP_CHAIN * v * SP_FADE^thumps
const SP_FADE = 0.95f0       # each thump of a chain a little weaker, so the chain dies down
const SP_THROW = 0.9f0       # m/s rising ground that throws someone
const SP_MAXU = 2.2f0        # m, the ground never lifts more than this
const SP_REST = 1.2          # s after landing before the ground can throw you again
const SP_GRAV = 9.8f0
const SP_LAYERS = (:terrain, :area_path, :wordsand)   # wordsand redraws itself: re-read at each fresh stomp
const SP_LINES = ("WHEEE!", "Not again!", "Boing!", "Who did that?!", "I can see my house!", "Incoming!", "Hup!")
push!(NG.BUSY_GOALS, :stomp)

mutable struct Flyer
    vel::Vec3f
    z::Float32
    air::Bool
    rest::Float64       # world time before which the ground cannot throw it again
end

mutable struct StompRing <: System
    day::Int
    u::Matrix{Float32}      # how far the ground is lifted, m
    v::Matrix{Float32}      # how fast it rises, m/s
    land::BitMatrix         # cells over dry ground; the shore holds the skin fixed
    fly::Dict{Int32,Flyer}
    active::Bool
    quiet::Float64          # seconds the skin has been still
    sources::Int            # thumps this chain so far
end

sp_lumi(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
sp_hour(w) = 24 * NG.daytime(w)
sp_cell(x) = (x + SP_R) / SP_DX + 1f0

"Bilinear sample of grid `a` at (x, y); 0 off the grid."
function sp_sample(a, x, y)
    fx, fy = sp_cell(x), sp_cell(y)
    i, j = floor(Int, fx), floor(Int, fy)
    (1 <= i < SP_N && 1 <= j < SP_N) || return 0f0
    tx, ty = fx - i, fy - j
    return (1 - tx) * (1 - ty) * a[i, j] + tx * (1 - ty) * a[i+1, j] + (1 - tx) * ty * a[i, j+1] + tx * ty * a[i+1, j+1]
end

"A thump at (x, y): a Gaussian kick of upward speed `amp` (m/s) into the skin."
function sp_thump!(sys::StompRing, x, y, amp)
    ci, cj = sp_cell(x), sp_cell(y)
    r = ceil(Int, 3SP_SIGMA / SP_DX)
    for i in max(1, floor(Int, ci) - r):min(SP_N, floor(Int, ci) + r), j in max(1, floor(Int, cj) - r):min(SP_N, floor(Int, cj) + r)
        sys.land[i, j] || continue
        d2 = ((i - ci)^2 + (j - cj)^2) * SP_DX^2
        sys.v[i, j] -= amp * exp(-d2 / SP_SIGMA^2)    # pushed DOWN: the ring that runs out is the rebound
    end
    sys.active = true; sys.quiet = 0.0; sys.sources += 1
end

function sp_wave!(sys::StompRing, dt)
    u, v, land = sys.u, sys.v, sys.land
    n = 3; h = Float32(dt / n); k = SP_C^2 / SP_DX^2
    for _ in 1:n
        @inbounds for j in 2:SP_N-1, i in 2:SP_N-1
            land[i, j] || continue
            lap = u[i+1, j] + u[i-1, j] + u[i, j+1] + u[i, j-1] - 4u[i, j]
            v[i, j] += h * (k * lap - SP_DAMP * v[i, j])
        end
        @inbounds for j in 2:SP_N-1, i in 2:SP_N-1
            land[i, j] || continue
            u[i, j] = clamp(u[i, j] + h * v[i, j], -SP_MAXU, SP_MAXU)
        end
    end
end

# --- the meshes that ride the skin ---------------------------------------------------------------------------

mutable struct SPLayer
    plot::Any
    p0::Vector{Point3f}
    n0::Vector{Vec3f}
    pts::Vector{Point3f}
    nrm::Vector{Vec3f}
    faces::Any
    idx::Vector{Int}        # vertices over the grid
    ci::Vector{Int32}       # their grid cell (lower corner) and the bilinear weights in it, fixed at build
    cj::Vector{Int32}
    tx::Vector{Float32}
    ty::Vector{Float32}
    lifted::BitVector       # idx[k] is off its flat place (so it must be put back when the skin is still there)
end

function sp_build!(sys::StompRing, game)
    sc = game.stage.scene
    layers = SPLayer[]
    for name in SP_LAYERS
        i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] == name, sc.plots)
        i === nothing && continue
        pl = sc.plots[i]; m = pl[1][]
        p0 = Point3f.(GeometryBasics.coordinates(m)); faces = GeometryBasics.faces(m)
        n0 = hasproperty(m, :normal) ? Vec3f.(m.normal) : Vec3f.(GeometryBasics.normals(p0, faces))
        idx = [k for (k, p) in enumerate(p0) if abs(p[1]) < SP_R - 2SP_DX && abs(p[2]) < SP_R - 2SP_DX]
        fx = [sp_cell(p0[k][1]) for k in idx]; fy = [sp_cell(p0[k][2]) for k in idx]
        ci = Int32.(floor.(fx)); cj = Int32.(floor.(fy))
        push!(layers, SPLayer(pl, p0, n0, copy(p0), copy(n0), faces, idx, ci, cj, Float32.(fx .- ci), Float32.(fy .- cj),
                              falses(length(idx))))
    end
    SP[:layers] = layers
    SP[:scene] = sc
    SP[:gx] = zeros(Float32, SP_N, SP_N); SP[:gy] = zeros(Float32, SP_N, SP_N)
    is = game.world.island
    for j in 1:SP_N, i in 1:SP_N
        x, y = -SP_R + (i - 1) * SP_DX, -SP_R + (j - 1) * SP_DX
        sys.land[i, j] = 1 < i < SP_N && 1 < j < SP_N && NG.terrain_height(is, x, y) > 0.08f0
    end
end

@inline sp_bil(a, i, j, tx, ty) = @inbounds (1 - tx) * (1 - ty) * a[i, j] + tx * (1 - ty) * a[i+1, j] +
                                            (1 - tx) * ty * a[i, j+1] + tx * ty * a[i+1, j+1]

function sp_layer_draw!(ly::SPLayer, u::Matrix{Float32}, gx::Matrix{Float32}, gy::Matrix{Float32}, flat::Bool)
    moved = false
    @inbounds for k in eachindex(ly.idx)
        v = ly.idx[k]
        h = flat ? 0f0 : sp_bil(u, ly.ci[k], ly.cj[k], ly.tx[k], ly.ty[k])
        if abs(h) < 1f-4
            ly.lifted[k] || continue
            ly.pts[v] = ly.p0[v]; ly.nrm[v] = ly.n0[v]; ly.lifted[k] = false; moved = true
            continue
        end
        hx = sp_bil(gx, ly.ci[k], ly.cj[k], ly.tx[k], ly.ty[k])
        hy = sp_bil(gy, ly.ci[k], ly.cj[k], ly.tx[k], ly.ty[k])
        p = ly.p0[v]; n = ly.n0[v]
        ly.pts[v] = Point3f(p[1], p[2], p[3] + h)
        ly.nrm[v] = normalize(Vec3f(n[1] - hx, n[2] - hy, n[3]))
        ly.lifted[k] = true; moved = true
    end
    moved && Makie.update!(ly.plot; arg1 = GeometryBasics.Mesh(ly.pts, ly.faces; normal = ly.nrm))
end

function sp_draw!(sys::StompRing; flat = false)
    u = sys.u; gx = SP[:gx]::Matrix{Float32}; gy = SP[:gy]::Matrix{Float32}
    if !flat
        @inbounds for j in 2:SP_N-1, i in 2:SP_N-1
            gx[i, j] = (u[i+1, j] - u[i-1, j]) / 2SP_DX
            gy[i, j] = (u[i, j+1] - u[i, j-1]) / 2SP_DX
        end
    end
    for ly in get(SP, :layers, SPLayer[])
        sp_layer_draw!(ly, u, gx, gy, flat)
    end
end

# --- bodies --------------------------------------------------------------------------------------------------

sp_ground(sys, w, x, y) = NG.terrain_height(w.island, x, y) + sp_sample(sys.u, x, y)

function sp_throw!(sys::StompRing, w, c, vz, vx = 0f0, vy = 0f0)
    f = get!(sys.fly, c.id) do
        Flyer(Vec3f(0), c.pos[3], false, 0.0)
    end
    f.air = true; f.z = c.pos[3]; f.vel = Vec3f(vx, vy, vz)
    c.controlled || (c.goal = NG.Goal(:stomp, c.pos, :gasp, 30.0, w.t + 30, true, 0, false))
end

function sp_bodies!(sys::StompRing, game, dt)
    w = game.world
    for c in w.creatures
        f = get(sys.fly, c.id, nothing)
        if f !== nothing && f.air
            x = c.pos[1] + f.vel[1] * dt; y = c.pos[2] + f.vel[2] * dt
            # never thrown into the sea
            if !NG.on_land(w.island, x, y; margin = 0.4f0)
                x, y = c.pos[1], c.pos[2]
                f.vel = Vec3f(0, 0, f.vel[3])
            end
            f.vel = Vec3f(f.vel[1], f.vel[2], f.vel[3] - SP_GRAV * dt)
            f.z += f.vel[3] * dt
            g = sp_ground(sys, w, x, y)
            if f.z <= g && f.vel[3] < 0
                impact = -f.vel[3]
                f.air = false; f.rest = w.t + SP_REST
                c.pos = Point3f(x, y, g)
                sp_thump!(sys, x, y, c.name == "Lumi" && sys.sources == 0 ? SP_LUMI : SP_CHAIN * impact * SP_FADE^sys.sources)
                NG.emit!(w, :stomp_land; who = c.name, impact = round(impact; digits = 1))
                c.controlled || (c.goal = NG.Goal())
            else
                c.pos = Point3f(x, y, f.z)
            end
            continue
        end
        # standing: ride the skin, and get thrown when it rises fast under you
        sys.active || continue
        x, y = c.pos[1], c.pos[2]
        u = sp_sample(sys.u, x, y)
        abs(u) > 0.01f0 && (c.pos = Point3f(x, y, NG.terrain_height(w.island, x, y) + u))
        rest = f === nothing ? 0.0 : f.rest
        vz = sp_sample(sys.v, x, y)
        if vz > SP_THROW && u > 0.05f0 && w.t > rest
            gx = (sp_sample(sys.u, x + SP_DX, y) - sp_sample(sys.u, x - SP_DX, y)) / 2SP_DX
            gy = (sp_sample(sys.u, x, y + SP_DX) - sp_sample(sys.u, x, y - SP_DX)) / 2SP_DX
            out = clamp(2.2f0 * hypot(gx, gy), 0f0, 3f0)
            l = max(hypot(gx, gy), 1f-4)
            sp_throw!(sys, w, c, clamp(3.2f0 * vz, 4.5f0, 11f0), -gx / l * out, -gy / l * out)
            NG.say!(w, c, rand(w.rng, SP_LINES))
            NG.emit!(w, :stomp_throw; who = c.name)
        end
    end
end

"I jump and come down hard at (x, y)."
function sp_lumi_stomp!(sys::StompRing, game)
    w = game.world
    me = sp_lumi(w)
    me === nothing && return
    sys.active || game.stage === nothing || sp_build!(sys, game)   # the sand drifted since: take the ground as it is now
    if haskey(SP, :at)
        a = SP[:at]
        me.pos = NG.ground(w.island, (Float32(a[1]), Float32(a[2])))
    end
    sp_throw!(sys, w, me, 6.5f0)
    NG.say!(w, me, "STOMP!")
    NG.emit!(w, :stomp; who = "Lumi")
    sys.sources = 0
end

function NG.start!(sys::StompRing, game)
    game.stage === nothing || sp_build!(sys, game)
end

function NG.step!(sys::StompRing, game, dt)
    w = game.world
    SP[:sys] = sys
    game.stage === nothing || get(SP, :scene, nothing) === game.stage.scene || sp_build!(sys, game)
    dt = Float32(clamp(dt, 0.0, 0.05))
    dt <= 0 && return
    whale = isdefined(Main, :GROUNDWHALE) && haskey(Main.GROUNDWHALE, :sys) && Main.GROUNDWHALE[:sys].on
    me = sp_lumi(w)
    lumi_free = me !== nothing && !(get(sys.fly, me.id, Flyer(Vec3f(0), 0f0, false, 0.0)).air)
    # jumped in as Lumi: L stomps (on the press)
    ldown = Makie.Keyboard.l in game.keys_down
    if ldown && !get(SP, :ldown, false) && me !== nothing && me.controlled && lumi_free && !whale
        sp_lumi_stomp!(sys, game)
    end
    SP[:ldown] = ldown
    if get(SP, :force, false) && lumi_free && !sys.active && !whale
        SP[:force] = false
        sp_lumi_stomp!(sys, game)
    end
    day = floor(Int, w.t / w.day_length)
    if day != sys.day && SP_FROM_H <= sp_hour(w) < SP_TO_H && lumi_free && !whale && game.minigame === nothing &&
       me !== nothing && me.action !== :sleep && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 3f0)
        sys.day = day
        sp_lumi_stomp!(sys, game)
    end
    if sys.active
        sp_wave!(sys, dt)
        quiet = maximum(abs, sys.u) < 0.01f0 && !any(f -> f.air, values(sys.fly))
        sys.quiet = quiet ? sys.quiet + dt : 0.0
        if sys.quiet > 1.0
            sys.active = false
            fill!(sys.u, 0f0); fill!(sys.v, 0f0)
            sp_draw!(sys; flat = true)
            NG.emit!(w, :stomp_still; thumps = sys.sources)
        else
            sp_draw!(sys)
        end
    end
    sp_bodies!(sys, game, dt)
    return
end

function NG.stop!(sys::StompRing, game)
    sys.active && sp_draw!(sys; flat = true)
    for c in game.world.creatures
        c.goal.kind == :stomp && (c.goal = NG.Goal())
    end
end

register!(StompRing(-1, zeros(Float32, SP_N, SP_N), zeros(Float32, SP_N, SP_N), falses(SP_N, SP_N),
                    Dict{Int32,Flyer}(), false, 0.0, 0))
