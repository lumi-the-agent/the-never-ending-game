"""
The trusted half of the Neverending Game. It runs outside the jail and never
loads game code (`NeverendingGame` and the world's plugins are the agent's to
change, so they only ever run jailed). Built on BonitoAgents' parts:

- `Jail`: the bubblewrap sandbox and the allowlisting network proxy (optional:
  bubblewrap is Linux only, everything else runs anywhere);
- `AgentProviders` + `AgentClientProtocol`: the agents, any ACP provider
  (Claude Code, Codex, OpenCode with an OpenRouter model, Kimi, MiMo);
- `BonitoWorker`: where the managed ACP adapters are installed;
- `BonitoMCP`: the agents' Julia tools (persistent sessions with Revise),
  started by the agent inside the jail.

What it does: keeps the jailed game and asset worker running, runs agent work
sessions one after another within a token budget, has every session reviewed
by agents that did not do the work, publishes the character's blog and the
whole game (one commit per session, for anyone to fork) to GitHub, and
forwards a LAN port to the game's dashboard (browsers draw it with WGLMakie).

    host = NeverendingHost.start("/path/to/game")
    NeverendingHost.status(host)
    NeverendingHost.tell!(host, "please make the speech bubbles readable")
    NeverendingHost.stop!(host)
"""
module NeverendingHost

using Dates, Printf, Sockets
import Downloads, SHA
using FileWatching: Pidfile
import JSON, TOML
import Jail
using Jail: HostProxy, PortForward
import AgentProviders
import AgentClientProtocol as ACP
import BonitoWorker

include("config.jl")
include("jail.jl")
include("procs.jl")
include("budget.jl")
include("world_files.jl")
include("agent.jl")
include("review.jl")
include("mood.jl")
include("github.jl")
include("site.jl")
include("snapshot.jl")
include("fork.jl")
include("host.jl")

end
