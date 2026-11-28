# The cart that runs on yesterday's wind

Lumi builds an electric cart from what the island has, and the island's real limits decide the build: sea-water cells give a lemon battery's milliwatts, so Lumi fires clay pots for proper cells, winds an iron-cored motor, and stores a whole windy day in lead plates; that evening the cart carries three pony-sized friends along the plank track it laid and runs out of charge on the dune where the numbers say it will.

Play: Every part is a choice the physics answers. Copper in its own blue salt behind a kiln-fired clay wall gives 0.3 W a pot where the sea-water cell gave 1.5 mW (the motor that would not twitch now spins). Wind more turns on the iron stator and it pulls harder but heats. Turn the windmill into the wind, choose sail area, and the lead plates fizz as they charge; a stormy day charges them in an hour, a calm one never does. Lay planks where the sand is softest: on planks the cart needs a twentieth of the push it needs in dry sand. Too few charged plates and it stops halfway up with the friends aboard; braking down the far side charges them back. You come back every day to see how far yesterday's wind will carry them.

The moment people share: Dusk after a gale: Lumi pulls the switch, the commutator sparks blue in the dark, the cart creaks off the plank track with three friends on board and grinds up the dune, slowing, slowing, and stops one plank short of the top. The friends get off and push.

## Road

- [x] Done: magnet fields (em.jl), 3-pole drum motor, feet+wheels in sand, power budget (cart 550 W)
- [ ] A circuit solver from what touches what, with cells that polarise (limiting current from the ions that reach the plate)
- [ ] The clay-pot cell: copper in blue salt inside a kiln-fired porous pot, iron in brine outside; copper grows on the plate, the blue fades
  - [x] potcell.jl (Nernst, wall from firing, polarisation, Faraday); six pots drive the bench (s159, published)
  - [ ] The friends carry the pots, cords clip by contact, the motor winds their berry basket (projects/friends-battery.md)
- [ ] The bench motor runs on four clay pots, turning the potter's wheel
- [ ] An iron-cored wound stator (electromagnet): the motor gets strong enough for a wheel
  - [x] Round iron drum rotor: 2 coils, no cogging, its brushes SPARK (s172-173); field solved by Newton, L 8 mH (s175)
  - [ ] The winch: the drum on a rope hauls the empty cart up the planks (#780; oak 6:1 gear, filling drum, friends run it)
    - [ ] Set the brushes for the load: Lumi's hand on the rocker (projects/brushes.md, #785)
- [ ] The motor run backwards: a windmill generator that lights a wire
  - [ ] Land yacht: the cart sails on the flow around its own sail, a dynamo on its axle charges the pots (projects/landyacht.md, todo #763)
    - [x] Sail force from the solved flow, no lift curve: a plate swept through angle of attack stalls by itself (physics/sailflow.jl)
    - [x] A cambered sail luffs by itself in the solved flow (2D: lift -0.2 at 0 deg, 0.6-0.95 at 5 deg, s163)
    - [ ] Sail it yourself: sheet, tiller, friends leaning out, over-sheeting stalls (sails in Jump in s167; next: Lumi seated, ruts, film)
    - [ ] Telltales: threads stream in the sail's solved flow, the player trims by them
      - [x] The threads read the trim in the solved 3D flow: windward lifts when it luffs, lee when it stalls (s164)
- [ ] Lead plates in acid that store what the windmill makes (Plante's accumulator: charge, fizz, discharge)
  - [ ] Cast the plates in beach sand: stamp, pour, it freezes, dig it out (casting.md; s170 foot 942 g; s171 lead look)
- [ ] Wheels, axle and a wooden frame on a plank track and in sand; the friends push it
  - [x] Sand that keeps ruts and berms, slumps to repose; planks rest and see-saw on it (sandfield.jl, s160)
  - [ ] The plank road on the dune: player lays planks in Jump in, friends push the empty cart (todo #755)
  - [ ] Stuck in the sand: wheels in the sand field, dig/plank/push it free (#773; s169 in game: sinks, Q a friend pushes, R digs; next: planks, film)
    - [x] Stick force in sand + damp sand from the water table, checked (soiltool.jl, sandwater.jl, s171)
  - [ ] Sand fences: the solved wind builds drifts the player shapes into the cart's ramp (projects/wind.md)
    - [x] The wind over a fence solved in 3D (WaterLily): wake, corner jets, lee eddy; sand blown by it (s161)
    - [x] WaterLily on the GPU matches the CPU (Lava strided-GEP fix, 5 ms/step, s162)
- [ ] The cart: accumulator, motor and switch on the frame; it drives because the parts do, and stops when the charge runs out
  - [ ] The cart drives itself on a long cord (projects/cartcord.md; s177 IN THE GAME: 16:1 cogs+belt, level planks; next: push back, film)
- [ ] Gears for the dune, braking that charges the plates, friends ride along
