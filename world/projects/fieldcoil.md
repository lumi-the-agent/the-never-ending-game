# Wind the field coil yourself
Goal: (passed s179, round 2: surprise 7 fun 7 real 7 toward 8) The player takes the black lodestones out of the drum motor and winds copper round soft-iron pole pieces instead, choosing the turns (and the wire, and how much copper): few turns and the field is weak and the cart crawls; many and the long wire eats the pots' voltage; too much field and the iron saturates. Every winding is an experiment the cart answers on the planks; getting the most out of what the island has is a craft. The human's s172 order puts the iron stator motor FIRST.
Next: (s179: field SOLVED on the round 52 mm core, winding laid turn by turn in physics/fieldcoil.jl: on six pots it is starved, best 7.7 mN m vs the stones' 67) 1) DONE s179: the ARCH yoke (Geo(arch = true): back bars + one top bar ztop .05..+24 mm) fits the bench and is the table now; 2) DONE s179 (published, off by default; traced media/s179-wound-field-a/b.png: turns read close up, the yoke is a flat dark block that needs a real cast-iron look) the wound poles behind ID[:field] = :wound (default :stones), cores along world +-y from 36 to 72 mm off the axle at c (irondrum.jl ~l.217), the coil = mtube(FieldCoil.path(w)) mapped local x -> +-y, radius d/2 (4805 points a pole at seg 24: try seg 16 for the raster); 3) the motor's kt from the wound table (drive(NIf) x I), the cart on the planks stones vs wound, side by side in a film; 4) a copper budget in Jump in: thick wire and many layers cost copper the player has made.

## s179: the wound field in the motor's own FEM (physics/motor2d.jl, Geo(field = true, NIf))
The stones' blocks become soft-iron pole pieces (mu_r 2000, saturating Js 1.7 T, Newton), an iron yoke frame (12 mm,
outer half-width 75 mm in z) closes the flux, a field coil on each pole (copper 10 mm beside each flank) carries NIf
ampere-turns per pole. Armature 80 A-turns, theta = 90 deg, Arkkio torque (2-D, L 72 mm), tools/magnet2d env, ~6 s a solve:
  stones (ferrite Br 0.38 T): 71.9 mN m
  NIf    0: 0      150: 20.1    300: 40.0    600: 79.6    1200: 157.2    2400: 252.3 (saturating)    4800: 318.3 mN m
So the two stones are worth ~550 A-turns per pole; the iron's knee is ~1500 A-turns per pole.
Series-wound on the six pots (4.68 V, 3.0 Ohm) with the 80-turn armature (2.03 Ohm), 0.8 mm wire, ~0.32 m a turn:
  Nf 25: 2.4 mN m stall   50: 3.9   100: 5.7   150: 6.4   200: 6.7 (best)   300: 6.6   400: 6.3   (stones: 66.9)
  At the best, only ~100 A-turns: the long wire's resistance starves the current long before the iron saturates.
Why (a law, not a fit): holding NI ampere-turns in a copper window A_cu costs P = rho * l_turn * (NI)^2 / A_cu per coil.
Both coils at 600 A-turns with the ~216 mm^2 of copper beside each flank (1.2 kg of copper): 18 W. Six clay pots give at
most V^2 / 4R = 1.8 W. A field as strong as the stones needs ten times the copper (~12 kg) or a ten times stronger source.

## s179 late: physics/fieldcoil.jl, the winding laid turn by turn (wire length, R and copper mass FROM the turns)
FieldCoil.winding(turns, d, rc = 26 mm core, len = 36 mm) -> layers; FieldCoil.stall(w) series-wound on six pots,
torque from data/fieldcoil-torque.csv (the FEM table). Per pole, both poles counted in R and copper:
  200 turns 0.8 mm: 5 layers, 315 g Cu, 0.63 A, 126 A-turns, 10.6 mN m stall    300 x 1.2 mm: 1.2 kg, 18.6 mN m
  500 turns 1.2 mm: 17 layers (46 mm outer), 2.3 kg Cu, 20.4 mN m (stones 67)   thin 0.5 mm wire never beats 5 mN m
The player's real trade: COPPER MASS buys field (thick wire, many layers), turns alone do not. This is the game in it.
FIXED the same session: the FEM pole is now the ROUND 52 mm core (Geo(field = true, stone_w = 0.026, wc = 0.008,
L = 0.052)), the table in data/fieldcoil-torque.csv re-solved: NIf 150: 14.5, 300: 28.9, 600: 57.5, 1200: 113.5,
2400: 182.5 (saturating), 4800: 256.2 mN m. Consistent stalls on six pots: 200 x 0.8 mm 7.7 mN m (315 g Cu),
300 x 1.2 mm 13.5 (1.2 kg), 500 x 1.2 mm 14.7 (2.3 kg). Stones 67. The block numbers above are superseded.

## s179 the arch yoke (fits the bench: nothing below the cores)
Geo(field = true, arch = true, stone_w = 0.026, wc = 0.008, L = 0.052): NIf 150: 14.4, 300: 28.7, 600: 57.0, 1200: 112.3,
2400: 157.3 (frame 182.5), 4800: 177.6 (frame 256.2) mN m. The gap sets the field below ~1200 A-turns, so the arch is
as good as the closed frame there; its single top bar saturates first above. Stalls on six pots: 100 x 0.8 mm 5.5,
200 x 0.8 mm 7.6, 300 x 1.2 mm 13.4, 500 x 1.2 mm 14.6 mN m. data/fieldcoil-torque.csv holds the ARCH table.
