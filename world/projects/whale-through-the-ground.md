# A whale swims through the ground
Next: SEE the heave: a traced 8 s clip (movies/groundwhale.jl, copy movies/glassrain.jl's shot) from low and to the side of the path, away from the dayfall slabs; then props and trees on the band ride it too, and the fluke breaks out of the turf at the end.

The idea (s124, the critic's strongest of three rounds, surprise 7, fun 6): at noon something big swims through the island as if the ground were sea.
You never see it, only the meadow heaving in a long rolling bulge with a rippling wake; whoever stands on it rides up and down, the friends surf its front.
Critic: it must not read as a shader: props, trees and bodies have to be really carried and thrown by it.

- plugins/groundwhale.jl (s124): 12:00-12:30 once a day, Main.GROUNDWHALE[:force]. Path (-26,-9) -> (26,7) at 1.6 m/s; heave 1.1 m high, 2.8 m long, 1.7 m wide, wake ripples behind.
  The :terrain mesh plot's vertices in a band round the path (4422) move each frame, normals tilted by the heave's slope. 4 nearest friends get :groundwhale goals (surf), riders pushed along on the front, say lines, event :whale_ride.
  Cost: 8.5 ms median a frame while it swims (normal_mesh over the whole terrain was 33 ms). Make it cheaper: update only the vertices near the head.
- Not yet seen: the live screenshot media/s124-groundwhale-live-1.png missed it (camera switched to free, trees and dayfall slabs in the way).
