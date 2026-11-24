# ── a work session in the character's dashboard chat ────────────────────────
#
# With `[agent] chat = true` a work session is not the host's own ACP client but
# turns in the character's BonitoAgents chat (dashboard.jl), where the human
# watches it and can write to it at any time. Each session starts a fresh agent
# conversation in that chat (its history stays on the page). The host sends the
# session's prompt, a follow-up when a turn ends early (the same ones as ever:
# the human's messages, posts, boredom, keep going), the wrap-up into the running
# turn five minutes before the end or when the budget runs low, and stops the
# turn at the deadline.

"A work session run in the dashboard chat: the fields the follow-ups and the status read, as `AgentRun` has them."
mutable struct ChatRun
    role::Symbol
    label::String
    settings::AgentSettings
    model::BonitoAgents.ChatModel
    started::Float64
    deadline::Float64
    wrap_up_since::Float64
    interrupted::String
    stop_reason::String
    first_msg::Int          # where the session's messages start in the chat
end

"The character's chat in the dashboard."
character_model(d) = d.server.chat_models[d.chat.id]

"A fresh agent conversation in the chat: its next turn starts a new session; the history stays on the page."
function fresh_conversation!(d)
    d.chat.resume_session_id = nothing
    @lock d.server.lock BonitoAgents.save_projects!(d.server)
    BonitoAgents.restart_chat_session!(character_model(d))
    return d
end

"""
    send_turn!(model, text; mode = :done, timeout = 120)

`text` as the chat's next message (`:done` once the running turn is over, `:next` into it), and
wait until the chat has taken it up, so a check for the end of the turn that follows does not see
the old, idle state.
"""
function send_turn!(model, text::AbstractString; mode::Symbol = :done, timeout::Real = 120)
    s = BonitoAgents.shared(model)
    seq = s.turn_seq[]
    BonitoAgents.send_message!(model, text; mode)
    t0 = time()
    while s.turn_seq[] == seq && !s.busy_active[] && time() - t0 < timeout
        sleep(0.2)
    end
    return model
end

"The chat's messages that are tool calls, from `first` on."
tool_count(model, first::Int) = count(m -> occursin("Tool", string(typeof(m))),
                                      @view BonitoAgents.shared(model).msgs_store[first:end])

"The tool calls a run made so far."
tools(run::ChatRun) = tool_count(run.model, run.first_msg)
tools(run::AgentRun) = run.tools

"A message into the running turn (the steering the ACP runs do with `try_steer!`)."
function try_steer!(run::ChatRun, text::AbstractString)
    BonitoAgents.send_message!(run.model, text; mode = :next)
    return true
end

"Stop the run's turn (the host is stopping, or the session's time is up)."
cancel_run!(run::ChatRun) = BonitoAgents.handle_command!(BonitoAgents.shared(run.model), nothing, BonitoAgents.CancelCommand())
cancel_run!(run::AgentRun) = ACP.cancel!(run.client)

"""
    run_chat_session!(host, label, settings, prompt; followups) -> ChatRun

The work session `label` in the dashboard chat (see the top of this file). `followups(run)` is
what to send when a turn ends before the session does (`nothing`: the session is over).
"""
function run_chat_session!(host, label::AbstractString, settings::AgentSettings, prompt::AbstractString; followups)
    d = host.dashboard
    model = character_model(d)
    fresh_conversation!(d)
    run = ChatRun(:agent, label, settings, model, time(), time() + 60settings.session_minutes, 0.0, "", "",
                  length(BonitoAgents.shared(model).msgs_store) + 1)
    host.current = run
    record!(host.activity, label, "host", "started in the dashboard chat")
    try
        send_turn!(model, prompt)
        while true
            left = run.deadline - time()
            b = update_budget!(host.budget)
            reason = b["state"] == "exhausted" ? "the budget is used up" : b["state"] == "low" ? "the budget is running low" :
                     left < 300 ? "the session time is nearly up" : ""
            if !isempty(reason) && run.wrap_up_since == 0
                run.wrap_up_since = time()
                problem = post_problems(host.jp, run)
                try_steer!(run, "Host: $reason. Finish what you are doing, commit it, write your journal entry and end the turn " *
                                "within a few minutes." * (problem === nothing ? "" : " " * problem * " Fix it before you end."))
                record!(host.activity, label, "host", "asked to wrap up ($reason)")
            end
            if left < 0
                run.interrupted = "session time limit"
                record!(host.activity, label, "host", "cancelled: $(run.interrupted)")
                cancel_run!(run)
                BonitoAgents.wait_idle(model; timeout = 120)
                break
            end
            BonitoAgents.wait_idle(model; timeout = clamp(left, 1.0, 10.0)) || continue
            next = followups(run)                   # the turn ended before the session did
            if next === nothing
                run.stop_reason = "end_turn"
                break
            end
            send_turn!(model, next)
        end
    finally
        host.current = nothing
    end
    record!(host.activity, label, "host", @sprintf("ended (%s) after %.1f min, %d tool calls",
                                                   isempty(run.interrupted) ? run.stop_reason : run.interrupted,
                                                   (time() - run.started) / 60, tools(run)))
    return run
end
