# A copper wire bent into a hook on a wooden jig (s144, project copper-wire). physics/wire.jl bends it quasi-statically:
# a pin holds the bend, a wooden lever turns round the pin and pushes the wire; where the lever lets go the wire springs
# back a little and keeps the rest. Two bends make a hook. The board is the tops board (5.6, -13), the view checked
# clear in s144 (the tops plugin's big board and top are hidden).
#   submit_job(:clip; path, script = "movies/wire.jl", call = "wire_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "wire.jl"))

"The bending plan as a list of (time, angles, lever) keyframes: each bend loads, then releases (springback)."
function wire_plan(; fps = 24, seconds = 7.0)
    w = Wire()
    plan = [(40, 46, deg2rad(100)), (88, 96, deg2rad(150))]
    frames = Tuple{Vector{Float64},Int,Float64}[]          # joint angles, lever joint, lever angle
    hold(n, lv) = for _ in 1:n; push!(frames, (copy(w.th), lv...)); end
    hold(round(Int, 0.6fps), (46, 0.0))
    for (i0, i1, phi) in plan
        nb = round(Int, 1.6fps)
        for k in 1:nb
            bend!(w, i0, i1, phi / nb; steps = 2)
            push!(frames, (copy(w.th), i1, sum(w.th[i0:i1])))
        end
        hold(round(Int, 0.25fps), (i1, sum(w.th[i0:i1])))
        release!(w)
        hold(round(Int, 0.6fps), (i1, sum(w.th[i0:i1])))
    end
    while length(frames) < round(Int, seconds * fps); hold(1, (plan[end][2], sum(w.th[plan[end][1]:plan[end][2]]))); end
    return frames, w
end

function wire_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 7.0,
                   hour = 16.6, spot = (5.6f0, -13.0f0))
    frames, wfin = wire_plan(; fps, seconds)
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot)
        P = Point3f(g[1], g[2], g[3] + 0.05f0)
        S[:P] = P
        board = GeometryBasics.normal_mesh(Rect3f(P - Point3f(0.09f0, 0.07f0, 0.03f0), Vec3f(0.2f0, 0.14f0, 0.03f0)))
        mesh!(gm.stage.scene, board; color = RGBf(0.55, 0.38, 0.22), name = :wire_board,
              material = NG.Hikari.Diffuse(color = (0.55, 0.38, 0.22), roughness = 0.5f0))
        S[:o] = P - Point3f(0.06f0, 0.03f0, 0)                       # where the wire starts
        S[:w] = Wire()
        S[:mw] = mesh!(gm.stage.scene, wire_tube(S[:w], frames[1][1], S[:o]); color = RGBf(0.85, 0.45, 0.3),
                       material = NG.Hikari.Copper(), name = :wire_copper)
        S[:pin] = mesh!(gm.stage.scene, GeometryBasics.normal_mesh(Cylinder(Point3f(0), Point3f(0, 0, 0.012f0), 0.003f0));
                        color = RGBf(0.3, 0.2, 0.12), name = :wire_pin, material = NG.Hikari.Diffuse(color = (0.3, 0.2, 0.12)))
        S[:lever] = mesh!(gm.stage.scene, GeometryBasics.normal_mesh(Rect3f(Point3f(0, -0.004f0, 0.0f0), Vec3f(0.05f0, 0.008f0, 0.006f0)));
                          color = RGBf(0.75, 0.6, 0.4), name = :wire_lever, material = NG.Hikari.Diffuse(color = (0.75, 0.6, 0.4), roughness = 0.4f0))
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 6 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile, :tops_live_board, :tops_live_top) || startswith(string(p.attributes[:name][]), "paperpage_")) && (p.visible[] = false)
        end
        k = clamp(round(Int, t * fps) + 1, 1, length(frames))
        th, lv, la = frames[k]
        S[:mw][1][] = wire_tube(S[:w], th, S[:o])
        Pw = shape(S[:w]; angles = th)
        i0 = lv - 6                                               # the pin sits at the start of the bending span
        pin = S[:o] + Vec3f(Pw[i0][1], Pw[i0][2], 0)
        a0 = atan(Pw[i0][2] - Pw[i0-1][2], Pw[i0][1] - Pw[i0-1][1])
        Makie.translate!(S[:pin], pin + Vec3f(-sin(a0), cos(a0), 0) * 0.0035f0)
        al = atan(Pw[lv+8][2] - Pw[lv+7][2], Pw[lv+8][1] - Pw[lv+7][1])   # the lever lies along the bent arm, on its far side
        Makie.translate!(S[:lever], S[:o] + Vec3f(Pw[lv+2][1], Pw[lv+2][2], 0.0f0) + Vec3f(sin(al), -cos(al), 0) * 0.006f0)
        Makie.rotate!(S[:lever], Makie.qrotation(Vec3f(0, 0, 1), al))
        P = S[:P]
        rig.mode = :fixed
        rig.eye = Point3f(P[1] + 0.01f0, P[2] - 0.17f0, P[3] + 0.15f0)
        rig.target = Point3f(P[1] + 0.005f0, P[2] + 0.0f0, P[3])
        return nothing
    end
    r = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(r, (; path, bend1_kept = rad2deg(sum(wfin.thp[40:46])), bend2_kept = rad2deg(sum(wfin.thp[88:96]))))
end
