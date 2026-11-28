# The cart that runs on yesterday's wind

Lumi builds an electric cart from what the island has, and the island's real limits decide the build: sea-water cells give a lemon battery's milliwatts, so Lumi fires clay pots for proper cells, winds an iron-cored motor, and stores a whole windy day in lead plates; that evening the cart carries three pony-sized friends along the plank track it laid and runs out of charge on the dune where the numbers say it will.

Play: Every part is a choice the physics answers. Copper in its own blue salt behind a kiln-fired clay wall gives 0.3 W a pot where the sea-water cell gave 1.5 mW (the motor that would not twitch now spins). Wind more turns on the iron stator and it pulls harder but heats. Turn the windmill into the wind, choose sail area, and the lead plates fizz as they charge; a stormy day charges them in an hour, a calm one never does. Lay planks where the sand is softest: on planks the cart needs a twentieth of the push it needs in dry sand. Too few charged plates and it stops halfway up with the friends aboard; braking down the far side charges them back. You come back every day to see how far yesterday's wind will carry them.

The moment people share: Dusk after a gale: Lumi pulls the switch, the commutator sparks blue in the dark, the cart creaks off the plank track with three friends on board and grinds up the dune, slowing, slowing, and stops one plank short of the top. The friends get off and push.

## Road

- [x] Done: magnet fields (em.jl), 3-pole drum motor, feet+wheels in sand, power budget (cart 550 W)
- [x] Done: potcell.jl six pots drive the bench (s159); pots sag and recover (s180); iron drum rotor, sparks, L 8 mH (s172-175); winch on oak cogs (s176); sand keeps ruts and planks rest on it (s160); stick force in damp sand (s171); fence wind in 3D (s161-162); sail force and telltales from the solved flow (s163-164)
- [ ] A circuit solver from what touches what, with cells that polarise (limiting current from the ions that reach the plate)
- [ ] The clay-pot cell: copper in blue salt inside a kiln-fired porous pot, iron in brine outside; copper grows on the plate, the blue fades
  - [ ] The friends carry the pots, cords clip by contact, the motor winds their berry basket (projects/friends-battery.md)
- [ ] The bench motor runs on four clay pots, turning the potter's wheel
- [ ] An iron-cored wound stator (electromagnet): the motor gets strong enough for a wheel
  - [ ] Wind the field coil yourself (shelf/fieldcoil.md; s179 solved, 1/9 of the stones on six pots; the drum still runs on the stones' table)
- [ ] The motor run backwards: a windmill generator that lights a wire
  - [ ] Land yacht: the cart sails on the flow around its own sail, a dynamo on its axle charges the pots (projects/landyacht.md, todo #763)
    - [ ] Sail it yourself: sheet, tiller, friends leaning out, over-sheeting stalls (sails in Jump in s167; next: Lumi seated, ruts, film)
- [ ] Lead plates in acid that store what the windmill makes (Plante's accumulator: charge, fizz, discharge)
  - [ ] Form the plates the way Plante did (projects/plante.md; s182: plante.jl kinetics, hourly swaps hold 0.25 Ah, left on 0; film; next: fast plugin, swap by hand)
  - [ ] Cast the plates in beach sand: stamp, pour, it freezes, dig it out (casting.md; s170 foot 942 g; s171 lead look)
- [ ] Wheels, axle and a wooden frame on a plank track and in sand; the friends push it
  - [ ] The plank road on the dune: player lays planks in Jump in, friends push the empty cart (todo #755)
    - [ ] Lay the plank road yourself: planks are PrintSim bodies on the sand (projects/planks.md; s181 first drop, global step bound freezes falling planks)
  - [ ] Stuck in the sand: dig/plank/push it free (#773; s169 in game: sinks, Q push, R dig; next: planks, film)
  - [ ] Sand fences: the solved wind builds drifts the player shapes into the cart's ramp (projects/wind.md)
- [ ] The cart: accumulator, motor and switch on the frame; it drives because the parts do, and stops when the charge runs out
  - [ ] The cart drives itself on a long cord (projects/cartcord.md; s180: pale thick cord, retake renders; next: drawn pots = real pots)
  - [ ] The cart runs on the formed plates: capacity from Plante.capacity, it stops where the charge ends
- [ ] Gears for the dune, braking that charges the plates, friends ride along
  - [ ] The cart takes the dune (projects/dune.md; s178: downhill charges the pots, -0.27 A at 8%; belt slips on the face)
