# The cart that runs on yesterday's wind

Lumi builds an electric cart from what the island has, and the island's real limits decide the build: sea-water cells give a lemon battery's milliwatts, so Lumi fires clay pots for proper cells, winds an iron-cored motor, and stores a whole windy day in lead plates; that evening the cart carries three pony-sized friends along the plank track it laid and runs out of charge on the dune where the numbers say it will.

Play: Every part is a choice the physics answers. Copper in its own blue salt behind a kiln-fired clay wall gives 0.3 W a pot where the sea-water cell gave 1.5 mW (the motor that would not twitch now spins). Wind more turns on the iron stator and it pulls harder but heats. Turn the windmill into the wind, choose sail area, and the lead plates fizz as they charge; a stormy day charges them in an hour, a calm one never does. Lay planks where the sand is softest: on planks the cart needs a twentieth of the push it needs in dry sand. Too few charged plates and it stops halfway up with the friends aboard; braking down the far side charges them back. You come back every day to see how far yesterday's wind will carry them.

The moment people share: Dusk after a gale: Lumi pulls the switch, the commutator sparks blue in the dark, the cart creaks off the plank track with three friends on board and grinds up the dune, slowing, slowing, and stops one plank short of the top. The friends get off and push.

## Road

- [x] Done: any magnet's field (em.jl), the 3-pole drum motor that starts from every angle, wheels and feet in sand (wheelsand.jl), the power budget (s159: sea cells 1.5 mW, bench 1 W, loaded cart 550 W)
- [ ] A circuit solver from what touches what, with cells that polarise (limiting current from the ions that reach the plate)
- [ ] The clay-pot cell: copper in blue salt inside a kiln-fired porous pot, iron in brine outside; copper grows on the plate, the blue fades
  - [x] potcell.jl (Nernst, wall from firing, polarisation, Faraday); six pots drive the bench (s159, published)
  - [ ] The friends carry the pots, cords clip by contact, the motor winds their berry basket (projects/friends-battery.md)
- [ ] The bench motor runs on four clay pots, turning the potter's wheel
- [ ] An iron-cored wound stator (electromagnet): the motor gets strong enough for a wheel
- [ ] The motor run backwards: a windmill generator that lights a wire
- [ ] Lead plates in acid that store what the windmill makes (Plante's accumulator: charge, fizz, discharge)
- [ ] Wheels, axle and a wooden frame on a plank track and in sand; the friends push it
- [ ] The cart: accumulator, motor and switch on the frame; it drives because the parts do, and stops when the charge runs out
- [ ] Gears for the dune, braking that charges the plates, friends ride along
