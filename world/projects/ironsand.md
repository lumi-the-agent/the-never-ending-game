# Read the sand, find the stone

Goal: magnet stones lie buried at random under the beach. The player sprinkles iron sand, taps the ground, and the grains stand into the hidden field: a tuft over a standing stone, two lobes over one on its side, a wall between two that face each other. From the pattern the player reads where to dig, how deep and which way round the stone lies, then digs to check. Fun because every round is a new puzzle that the real field sets, and reading it is a skill that grows.

Next: (s151 the putting tray is in the game: plugins/magnetgolf.jl at (-3.5, 18.8), 8 putts, 9 sprinkles and taps iron sand, a groove shows the last putt's bend, the cup reveals the stone.) Then: friends take turns at the tray and react, the ball pushes the grains it rolls over, a par count per stone, the sand pattern sharper (needle grains).

## Where it is (s149)
- physics/ironsand.jl: every grain an induced soft-iron dipole (chi = 3) in the stone's field (physics/em.jl, any mesh/pose)
  plus its neighbours' dipole fields (cell grid, 2 Jacobi sweeps); F = chi V/(2 mu0) grad|B|^2 + dipole-dipole force;
  Coulomb friction mu 0.55 at rest, 0.04 during a tap; a tap = 40 ms flight (gamma = 2m/t, so the drift = F t^2/2m).
  `tap!` = 20 `substep!`s + `orient!`. 2500 grains: field grid 1.25 s (built off the frame thread), a tap 0.1 s CPU.
- plugins/ironsand.jl: patch at (-2.4, 18.8), 42 cm, 1500 grains. Jump in, stand there: 9 sprinkle, 9 tap, 0 dig
  (0.3 m ahead of Lumi). The dug stone shows where it lay; a new one is buried 6 s later (depth 5-14 cm, any yaw,
  35% standing). Camera from the sea side while Lumi is there (Main.LOCAL_CAMS). Published s149.
- movies/ironsand.jl: film (ironsand_parts for a sandbox look, ironsand_clip for the worker).
- Checked: media/ironsand-patterns-s149.png (4 poses/depths), play shots media/ironsand-play-*.png.
- s150: the film posted (site/films/iron-sand.mp4): grains go from scattered to lines fanning out from one spot in ~3 taps. The patch lies on GRASS (spot (-2.4,18.8) is past the sand line): move it onto the sand for the next film. The idea "Two stones under one patch" scored 5/10 alike (textbook filings picture); the guessing game with friends who dig is what made it new.
- s150 critic redo of the film: grains pre-laid in a sharp square (no sprinkle), no tap visible, turns all at once in
  one step then 8 s frozen, the stone never hinted, grains read as fat black bristles floating over grass. Stopgap:
  iron-sand-2.mp4 = first 4 s, caption says what shows. RETAKE needs: grains poured from Lumi's beak onto SAND
  (irregular patch), Lumi's foot stamping each tap with the grass/sand jolting, small tilts per tap so the build-up
  is gradual, grains 3x thinner and lying flat, and the stone dug up at the end so the cause is seen.


## Putting over buried stones: the honest numbers (s151, em.jl, lodestone Br 0.06 T, cylinder R 5 cm H 8 cm, axis up)
Lateral pull on a rolling soft-iron ball, a = 1.5 mu0 d|H|^2/dx / (1.4 rho): the SAME for any ball size (m = 3V H).
- stone top 1 cm under: 0.13 / 0.36 / 0.34 / 0.11 / 0.035 m/s^2 at 2 / 4 / 6 / 8 / 10 cm aside; 0.004 at 14 cm.
- 3 cm under: peak 0.10 m/s^2 at 4 cm; 6 cm under: peak 0.017.
- For scale: a 1 degree slope pulls 0.17 m/s^2. So a shallow stone is a 2-degree dimple ~15 cm wide: a putt at 0.5 m/s
  passing 5 cm from it bends ~7 degrees; a slow ball near the cup gets caught. A green of metres would roll straight.
  The honest game is a TRAY (a zen-garden-size sand table), marble-size ball, stones 1-3 cm down, slow putts.
