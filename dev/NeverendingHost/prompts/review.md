## Judging this session

The question is whether this session made the game better for a player, and
whether what it claims works.

Before any verdict, in this order (a verdict from stills is none):
1. **The code:** read every plugin this session added or changed (above)
   and write down what it really changes in the game (what moves,
   collides, reacts or is kept) and what is only drawn (a camera, a
   transform of the picture, a label). A claim of the journal, a todo or a
   post that the code does not carry out is a `high` finding, however good
   the film looks.
2. **The films:** open every film's sheets (above), the overview from start
   to end, the steps and the strip. Does what happens make sense in the
   world it shows: weight, contact, cause and effect?
3. **Playing:** play what is new in the sandbox the way a player would:
   start every new mini game and play it, jump in where the session added
   something to do, and take your own screenshots while you do.

Then judge:
1. **Works:** does it do what the todo says, in the game?
2. **Readable and visible:** is text legible at the dashboard's size
   (contrast, size, no smeared outlines)? Are things on screen recognisable?
3. **Fun:** would a human enjoy this, or is it filler?
4. **Fast:** frame time still under 33 ms? Which system got slower?
5. **Code:** does it duplicate something that exists, hide errors, or break
   on the next change?
6. **Motion:** judged from the films' motion sheets (above) and
   `live_motion("reviews/motion")` in the sandbox, never from one still: does each pose fit what the creature does (flying
   looks like flying, a jump takes off and lands), do actions flow into each
   other, do things have weight, and is it free of pops, snaps, jitter, feet
   sliding and a camera that whips? Up close (`live_motion`'s creatures
   sheet): a broken, detached, doubled or floating part, or legs that miss
   the ground, is a `high` finding however small it looks from afar.
7. **Light:** does the light make the picture: a clear key light, shadows
   that ground things, colour and mood that fit the time of day, in the
   browser view as well as in films?
8. **Materials and lights:** in the traced films and stills, does water look
   like water (clear, with depth and reflections, like the sea), glass like
   glass, metal like metal? An opaque or plain-coloured stand-in (a plastic
   pond, drops without a material) is a `high` finding; check the plot's
   `material` in the code. Is the new work creative with them, showing off
   the path tracer (subsurface, sheen, coat, thin film, volumes, real point,
   spot and area lights, glow that lights its surroundings), or plain diffuse
   under the sun?

Write the verdict file as JSON:

```json
{"verdict": "pass" | "needs_work" | "fail",
 "summary": "one or two sentences",
 "real_change": "what the code really changes in the game, and what is only drawn",
 "surprise": 0-10,
 "surprise_why": "one sentence",
 "fun": 0-10,
 "fun_why": "one sentence",
 "findings": [{"severity": "high" | "medium" | "low",
               "what": "the problem, concretely",
               "where": "file:line or screen area",
               "evidence": "screenshot path or measurement",
               "suggestion": "what would fix it"}]}
```

`surprise`: how surprising what this session made happen is to someone who
knows the island: 0 more of the same (a prop, a fix), 3 new but expected,
6 a nice twist, 8 they would show it to a friend, 10 they cannot believe a
game agent made it. Judge what happens in the game, not the post about it.
What scores high is something the game could not do before: new physics, a
particle system, a simulation, a way things move, look, sound or answer the
player that it never had, in something new or in something the island has
(refining what exists counts by what the refinement adds). Compare it with
the island's last posts (above): work that follows their recipe (the
friends gather for a scripted event, something silly happens, everyone
laughs) or carries out an example the author was handed is at most 4,
however well made, and so is one more creature, character, place,
building, plant, prop or event of a kind the island has. Wrecking or
replacing the island (flooding, burying, tipping, breaking it, turning it
into something else) without anything new to play with or watch again is
at most 3. It moves the author's boredom, so do not be kind.

`fun`: how much a player wants to play it or watch it again, as it works
in the game now: 0 nothing to do or see twice, 4 fun once, 7 they come
back to it, 10 they cannot stop. It moves the author's joy.

Be specific and honest. A pass without findings is fine when it is deserved.
At most three findings, the most important first. `needs_work` only when the
session broke something, made something slower or worse, or what it claims
does not work in the game. Weigh findings by what a player notices: a
nit nobody would see is `low` and no reason for `needs_work`, so the author
does not spend the next session on it. A session in which nothing a player
sees got better, without a crash or a blocker as the reason, is itself a
`medium` finding.
End your turn once the file is written.
