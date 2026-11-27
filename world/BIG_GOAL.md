# Sparks from stones

Lumi finds a magnet stone on the beach and green rock in the cliff, and from them builds electricity by hand: copper smelted and drawn into wire, a coil wound turn by turn, a battery from two metals in brine, and whatever you put together pulls, spins, buzzes or burns by the real fields it makes, nothing scripted.

Play: Tinkering that never runs out: gather, smelt, draw, wind, connect, switch on, and the island's one field solver decides what happens. More turns pull harder, thin wire glows and melts, a magnet the wrong way round kicks the rotor backwards, a nail by the stone flies to it. Every build is different because the player chooses the parts, their materials and where they sit, and builds nobody planned work too (a compass from a needle, a coil that throws a nail, a wire that spins on a cell). Then the parts drive what was made before: the potter's wheel, the log boat's paddle, the paper glider's launcher.

The moment people share: The first motor wound from beach copper, put together by Lumi's beak part by part, coughs, stalls, then whirs and pushes the log boat out across the bay, or a misbuilt one wrenches itself off the bench and the friends scatter.

## Road

- [ ] A magnet stone every iron thing feels by distance and pose, and jumps to
  - [x] Done s147: field of any magnet mesh (physics/em.jl), the stone on the north beach (5 in Jump in), the compass bowl
  - [ ] Iron magnetises iron: spikes hang in chains (physics/softiron.jl solved s148: 2 hold, the 3rd at the edge)
  - [ ] The anchor chain and other iron on the island feel it too
  - [x] A spinning top floats over a ring magnet by the field alone (physics/levitron.jl, s148; playable next)
  - [x] Iron sand shows any field: tap it and read where a buried stone lies, then dig (s149, plugins/ironsand.jl)
  - [ ] Sand grains as needles that turn only where the field beats friction; two stones under one patch
- [ ] One materials table read by every system (copper, iron, magnet stone, wood, brine)
  - [x] First table in EM.MATERIALS (s147); melting point and brine still missing
- [ ] Copper from green rock: smelted in the kiln, drawn into wire that keeps its bends
- [ ] A circuit from what touches what: two metals in brine make a cell, thin wire heats and melts
- [ ] A coil wound by turning a spindle with the beak lifts nails: an electromagnet
  - [x] The coil's own field: Biot-Savart over every wound turn, core and spikes solved together (physics/coilcrane.jl, s150)
  - [ ] The scrap crane: lowered into a spike pile, lifted, switched off over a friend (film)
- [ ] Coil, stone, axle and brushes fitted by hand spin, buzz or stall by how they were built
- [ ] The motor drives the wheel, the paddle and the launcher; turned backwards it lights a lamp
