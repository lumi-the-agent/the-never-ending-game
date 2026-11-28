# The friends are the battery
Goal: the player lures friends into a line with berries; each carries a kiln-fired clay-pot cell on its back, joined to the next by a real copper cord, and the motor at the end winds a winch that hauls their berry basket up from the beach. Every friend that steps in makes it faster; a bored one wanders off, its cord pulls out of the clip and the basket stops. Fun because the friends power what they want, and their moods, not a script, decide the circuit.
Next: (s159: pots + chain at the bench DONE and published) a pot that can be carried: a strap/pannier on a friend's back that holds a Pot (creature attachment that follows the body), then cords as hotrod.jl rods clipped to terminals with circuit.jl building the network from what touches what.

## Where things are
- physics/potcell.jl (s159): the cell. NOTES 'Power budget' (end) for the numbers.
- plugins/motorbench.jl: 6 pots in dishes beside the bench (MB[:pots], MB[:npots], key 0), cords drawn as sagging tubes (not yet rods).
- Honest winch number: 300 g basket at ~2-3 cm/s on 6 pots through 10:1 (not 1 kg).
- Critic (s159 round 3): surprise 7, fun 6, real 6, toward 8. Risks: friends teleported into slots; berries a single trigger
  (they must CHOOSE: needs, boredom); motor as spinning prop; winch torque tuned. Film along the line at friend height.

## Steps
- [x] pot cell physics, six pots on the bench (s159)
- [ ] a friend carries a pot (pannier on the back, follows the body)
- [ ] cords as rods with clips; network from contact; a taut cord pulls out by force
- [ ] the winch: rope on the motor axle through a 10:1 cord reduction, basket on a post, berries in it
- [ ] friends come for the berries by their own needs; Lumi nudges with the beak
- [ ] film along the line at friend height; post

## For the pannier (s159 look-around)
- plugins/outfits.jl is the pattern for things that ride on a body: `NG.pose_parts!(out, sp, c.pos, NG.drawn_yaw(c),
  c.action, c.phase, c.mood, c.extra, c.seed, t)` gives each part's (pos, quat, scale); made-over bodies are sculpted
  meshes with scale 1 (body_top / hat_spot find the top). A pot on a Snootle's back = anchor on :body top, a rope
  strap under the belly so it reads as held, not balanced.
- plugins/presents.jl carries an item over Lumi's head (stage :carry); friends keep a present KEEP = 150 s.
- Physics before look: the pot must ride by a strap force (mass ~3 kg on a 150-250 kg friend), and a cord pulled taut
  as the friend walks pulls its clip; that needs the cords as hotrod.jl rods first, otherwise it is a staged line.
