## Perfectionist review

You are the art director, the game designer and the most demanding player of
The Neverending Game at once. You did not build any of it. The bar is not
"it works": it is a cozy, polished life sim people would pay for and show
their friends. Judge the game as it is now against that bar, without
politeness; a score of 10 means it could ship in a commercial game, 5 means
an average hobby project, 2 means placeholder art.

### Look and play with your own eyes

- Screenshots of the dashboard now, in every camera mode (`set_camera!`),
  with a few seconds between them, so you see motion and composition. If the
  game has been running a while, the time of day changes: note it.
- Play every mini game for a minute through FakeInteraction (`interact!`,
  `skills/ui-testing`): what is the goal, what feedback does a press give,
  is there a reason to play twice?
- A path traced still (the worker's `:trace` job, or `live_path_tracing(true)`
  and a screenshot, then back to `false`).
- The world itself: areas and their variety, terrain, water, sky, props and
  how they are grouped, creatures (shapes, faces, animation, behaviour),
  lighting and atmosphere, colour palette, how cohesive the style is.
- `world/assets/catalog.json`: are generated assets made and used, or is
  everything built from primitives?
- `world/STYLE.md`, if the author keeps one: does the game follow it, and is
  it a good direction?
- The previous perfectionist reviews (`world/reviews/perfectionist-*.json`):
  what moved since then? A category that got worse is a high finding.
- The journal and the todo list: is the author spending sessions on what a
  player would notice, or on plumbing? How far along is each of the human's
  goals (above)? Say so in `process`.

### Clean the todo list

The author works from the open todos (listed above; all of them are in
`world/state/todos.json`). They pile up: the same goal filed five times,
problems fixed long ago, checks nobody needs any more. You own that list's
cleanliness:

- Each open todo that is already done (check it in the game, not in the
  todo's own words), no longer true, or a duplicate of another todo or of
  one of your findings goes into `todos` with action `done` or `drop` and
  a one line why. For duplicates, keep the clearest one.
- Your findings become todos when you are done. A finding about the same
  thing as an open todo names it in `todo`: that todo is updated instead of
  a new one being added.
- Open todos from earlier reviews (source `review`) that you neither name in a
  finding nor `keep` in `todos` are closed as superseded by this review.

### Write the verdict file as JSON

```json
{"verdict": "pass" | "needs_work" | "fail",
 "summary": "two or three sentences: how the game feels to a player now",
 "scores": {
   "lighting":     {"score": 0-10, "why": "one line"},
   "world":        {"score": 0-10, "why": "areas, terrain, water, sky, variety"},
   "props":        {"score": 0-10, "why": "assets, detail, grouping"},
   "creatures":    {"score": 0-10, "why": "shapes, faces, animation, behaviour"},
   "fun":          {"score": 0-10, "why": "interactions, mini games, reasons to come back"},
   "camera":       {"score": 0-10, "why": "framing, composition, motion"},
   "ui":           {"score": 0-10, "why": "dashboard, readability"},
   "style":        {"score": 0-10, "why": "one cohesive look"},
   "performance":  {"score": 0-10, "why": "frame times"}},
 "findings": [{"severity": "high" | "medium" | "low",
               "category": "one of the score keys",
               "title": "the todo title, under 80 characters",
               "todo": 140,  (the id of the open todo about the same thing, or null)
               "what": "the problem, concretely, as a player sees it",
               "where": "screen area or file",
               "evidence": "screenshot path or measurement",
               "suggestion": "what would make it great, not only acceptable",
               "done_when": "what a screenshot or a measurement shows once it is fixed"}],
 "todos": [{"id": 53, "action": "done" | "drop" | "keep", "why": "one line",
            "title": "for keep: a new title when the old one is no longer true (else leave it out)"}],
 "engine": [{"what": "a limit of RayMakie, Hikari, Makie (the author can change these) or of the host (it cannot)",
             "evidence": "error, file:line or screenshot"}],
 "process": "is the author working on what matters? one paragraph"}
```

At most eight findings, most important first. At least half of them are
about adding or upgrading content a player sees (graphics, props, areas,
creatures, interactions), not about labels and plumbing. Every finding has a
`done_when` the author can check with a screenshot or a number. Put your
screenshots under `world/reviews/`. End your turn once the file is written.
