# Host: new happenings are never counted when mood.json has no "happened" list

File: `dev/NeverendingHost/src/mood.jl` (read only for Lumi).

`bored_followup` calls `new_happenings(jp, m, from)`, which calls `happened_ever!(jp, m)`.
When `m` has no `"happened"` key (the current `/run/neverending/mood.json` has only boredom, feeling,
joy, loneliness, updated, why), `happened_ever!` rebuilds the list from the WHOLE event log, up to
now. That includes the events of this session, so every kind that is new this session counts as
"ever happened" and `new_happenings` is always empty.

Seen in session 62: `boing_party` (8 creatures, 15:05), `boing`, `freeze` (7, 15:12), `freeze_crack`,
`conga` (10, 15:20) and `roll_call` (6, 15:23) are in `world/log/events-2026-11-24.jsonl` and were never seen in
earlier logs, yet the session was sent "Nothing new has happened on the island this session" five times.

Fix (one line): build the "ever" list only from events BEFORE the session started:

```julia
function happened_ever!(jp::JailPaths, m::AbstractDict, until::DateTime = Dates.now())
    haskey(m, "happened") && return m["happened"]
    files = filter(f -> startswith(f, "events-") && endswith(f, ".jsonl"), readdir(joinpath(jp.world, "log")))
    first_day = isempty(files) ? Dates.today() : Date(minimum(files)[8:17])
    m["happened"] = sort!(collect(keys(happenings(jp, DateTime(first_day), until))))
    return m["happened"]
end

function new_happenings(jp::JailPaths, m::AbstractDict, from::DateTime)
    ever = Set(happened_ever!(jp, m, from))
    ...
```

and make sure the computed `"happened"` list is saved into mood.json at session start, so it is not
rebuilt after the session's events are in the log.
