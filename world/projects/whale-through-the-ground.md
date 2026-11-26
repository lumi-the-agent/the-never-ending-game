# A whale swims through the ground
Next: a traced 8 s clip from the SOUTH side of the path, head at s = 20-24 m (the brown path arches up like a bridge by the red cottage, media/s125-whale-e.png); keep the fir trees out of frame. Then props on the band ride it, and the breach (critic s125: a turf whale leaping out on a ballistic arc with soil particles that move the friends).

The idea (s124, the critic's strongest of three rounds, surprise 7, fun 6): at noon something big swims through the island as if the ground were sea.
You never see it, only the meadow heaving in a long rolling bulge with a rippling wake; whoever stands on it rides up and down, the friends surf its front.
Critic: it must not read as a shader: props, trees and bodies have to be really carried and thrown by it.

- plugins/groundwhale.jl (s124): 12:00-12:30 once a day, Main.GROUNDWHALE[:force]. Path (-26,-9) -> (26,7) at 1.6 m/s; heave 1.1 m high, 2.8 m long, 1.7 m wide, wake ripples behind.
  The :terrain mesh plot's vertices in a band round the path (4422) move each frame, normals tilted by the heave's slope. 4 nearest friends get :groundwhale goals (surf), riders pushed along on the front, say lines, event :whale_ride.
  Cost: 8.5 ms median a frame while it swims (normal_mesh over the whole terrain was 33 ms). Make it cheaper: update only the vertices near the head.
- Not yet seen: the live screenshot media/s124-groundwhale-live-1.png missed it (camera switched to free, trees and dayfall slabs in the way).

- s125 (free part): the s124 heave was invisible from every angle (media/s125-whale-a..d.png): 1.1 m x 2.8 m reads
  as a mole, and the brown path (:area_path) is its own mesh lying ON the terrain, so the whale swam under it unseen.
  Now: 1.5 m high, 5 m long, 2.6 m wide; plugins/groundwhale.jl lifts every mesh in GW_LAYERS (:terrain, :area_path,
  :workshop_ground; the yard is not on the path), band sorted by distance along the path, only the window at the head
  is touched. The path now humps up visibly (media/s125-whale-e.png). Cost went UP to 11.4 ms median (frame 14.8):
  the loop is small now, so the cost is rebuilding + uploading the whole terrain mesh every frame.
  North side of the path at s ~ 23 puts the lens inside the red cottage (media/s125-whale-a.png).
- s125 later: published; cost was the untyped gw_path() (Dict{Symbol,Any}) in every heave call, typed now: 1.6 ms median.
