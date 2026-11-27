# Sparks from stones

Lumi finds a magnet stone on the beach and green rock in the cliff, and from them builds electricity by hand: copper smelted and drawn into wire, a coil wound turn by turn, a battery from two metals in brine, and whatever you put together pulls, spins, buzzes or burns by the real fields it makes, nothing scripted.

Play: Tinkering that never runs out: gather, smelt, draw, wind, connect, switch on, and the island's one field solver decides what happens. More turns pull harder, thin wire glows and melts, a magnet the wrong way round kicks the rotor backwards, a nail by the stone flies to it. Every build is different because the player chooses the parts, their materials and where they sit, and builds nobody planned work too (a compass from a needle, a coil that throws a nail, a wire that spins on a cell). Then the parts drive what was made before: the potter's wheel, the log boat's paddle, the paper glider's launcher.

The moment people share: The first motor wound from beach copper, put together by Lumi's beak part by part, coughs, stalls, then whirs and pushes the log boat out across the bay, or a misbuilt one wrenches itself off the bench and the friends scatter.

## Road

- [ ] A magnet stone with a real field: carry it and every iron thing on the island (nails, the anchor chain) feels it by distance and pose, and jumps to it
  - [x] Field of any magnet mesh, force and torque on magnets and currents (physics/em.jl, checked against the closed form) (s147)
  - [x] The magnet stone on the north beach: carried with 5 in Jump in, iron spikes slide, turn and jump to it by its field (plugins/magnetstone.jl, published s147)
  - [ ] Iron magnetises iron: spikes hang from each other in chains (a volume solve), the anchor chain
  - [x] A compass bowl: a magnetised spike on a lily pad turns to north and to the stone by m x B (plugins/compassbowl.jl, s147)
- [ ] One materials table on the island (copper, iron, magnet stone, wood, brine): conductivity, permeability, magnetisation, density, melting point, read by every system
  - [x] First table in physics/em.jl (EM.MATERIALS: Br, density, resistivity, mu_r); melting point and brine still missing (s147)
- [ ] Copper from green rock: smelt it in the kiln and draw it through a stone die into wire that keeps every bend (wire.jl)
- [ ] A circuit from what touches what: two metals in brine make a cell, current flows through whatever wire connects them, thin wire heats and melts
- [ ] A coil wound by turning a spindle with the beak: its field from its own turns lifts nails, it is an electromagnet
- [ ] Coil, magnet stone, axle and brushes fitted by hand: the push on every bit of wire turns real bodies, and it spins, buzzes or stalls by how it was built
- [ ] The motor drives the wheel, the paddle and the launcher; turned backwards by the treadwheel it lights a lamp (induction from the same fields)
