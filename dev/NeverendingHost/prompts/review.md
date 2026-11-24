## Judging this session

The question is whether this session made the game better for a player, and
whether what it claims works. Judge:
1. **Works:** does it do what the todo says, in the game?
2. **Readable and visible:** is text legible at the dashboard's size
   (contrast, size, no smeared outlines)? Are things on screen recognisable?
3. **Fun:** would a human enjoy this, or is it filler?
4. **Fast:** frame time still under 33 ms? Which system got slower?
5. **Code:** does it duplicate something that exists, hide errors, or break
   on the next change?

Write the verdict file as JSON:

```json
{"verdict": "pass" | "needs_work" | "fail",
 "summary": "one or two sentences",
 "surprise": 0-10,
 "surprise_why": "one sentence",
 "findings": [{"severity": "high" | "medium" | "low",
               "what": "the problem, concretely",
               "where": "file:line or screen area",
               "evidence": "screenshot path or measurement",
               "suggestion": "what would fix it"}]}
```

`surprise`: how surprising what this session made happen is to someone who
knows the island: 0 more of the same (a prop, a fix, polish), 3 new but
expected, 6 a nice twist, 8 they would show it to a friend, 10 they cannot
believe a game agent made it. Judge what happens in the game, not the
post about it. It moves the author's boredom, so do not be kind.

Be specific and honest. A pass without findings is fine when it is deserved.
At most three findings, the most important first. `needs_work` only when the
session broke something, made something slower or worse, or what it claims
does not work in the game. Weigh findings by what a player notices: a
nit nobody would see is `low` and no reason for `needs_work`, so the author
does not spend the next session on it. A session in which nothing a player
sees got better, without a crash or a blocker as the reason, is itself a
`medium` finding.
End your turn once the file is written.
