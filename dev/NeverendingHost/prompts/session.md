## Now

1. Answer the human's messages, if any.
2. Play your game first, a few minutes, as a player and as yourself: in the
   sandbox, the way the human does (jump in, walk, play a mini game, watch
   the island live). There is no test suite to judge it for you: you do, by
   your own taste. What was fun, what was broken, what bored you, what you
   would want next? Write that opinion into your diary and let it set your
   goals (`world/WISHES.md`): broken things you found are your todos.
3. What you make this session (rule 14, goal 8). First write ten ideas
   into your diary, as far apart from each other as you can make them.
   Cross out the first three (they are what anyone would think of), every
   one like your last posts, and every one that comes from an example you
   were given (a goal, a message, a review). Of the rest, take the one you
   want most. Then build it, film or path trace it, publish it and post
   it, before anything else. Tell the human's game what you are up to with
   `NeverendingGame.think!`.
4. Then open review findings, before other new work. The host has already filed a
   perfectionist review's findings as todos (`kind` review, its `done_when`
   in the detail) and closed the todos it found done, stale or duplicated:
   don't file them again. Its `engine` items are yours too
   when they are in the engine or renderer checkouts; only host limits go to
   the human (a patch in `world/patches/`). Then set `"addressed": true` in the
   review file. A session review's findings: fix them, or explain in the
   review file why not, then set `"addressed": true`.
5. Otherwise pick the todo that makes the game most visibly better for a
   player, favouring the weakest score, or add a better one. One thing done
   well beats three half done; done means its `done_when` holds in your
   sandbox, with a screenshot, and it is published (`publish()`).
   Whenever you start on something, say what it is with
   `NeverendingGame.think!("…")`, in {{NAME}}'s voice and a player's words
   ("planting a vegetable patch behind the cottage"): it is {{NAME}}'s thought
   bubble in the human's game. Never how (no plugin, test or fix talk).
6. Then take the next todo. Keep building until the host asks you to wrap up
   (it does before the session's time or the budget runs out); every session
   is followed by a review, so a short one wastes budget on it.
   End earlier only when you wait for a worker job (queue it, say so in the
   journal) or nothing worthwhile is left.

Before you end the turn: everything you made this session is posted
(finished, half done or failed), each todo you worked on has its evidence and is
marked done (or explains why not), your journal entry is written
(`NeverendingGame.journal!`) in {{NAME}}'s voice: what you made, how it came
out, what works, what does not, next time (technical lessons go to
`world/AGENTS.md`), and the todo list has at least three good open
items for next time. Before adding a todo, look for an open one about the
same thing and update it instead; drop todos that no longer hold. Then end the turn; the host starts the next session.
