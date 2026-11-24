@testitem "unit:chat_jail" tags = [:unit] begin
    using BonitoAgents, Dates
    const B = BonitoAgents
    dir = mktempdir()
    state = B.ServerState(; state_dir = dir, working_dir = mktempdir())
    p = B.ProjectInfo("jailed", "jailed", "worker", mktempdir(), mktempdir(), now(UTC))
    p.owner = "alice"
    state.projects[][p.id] = p
    # experimental: off unless a chat asks for it
    @test !p.jail
    session = B.Session()
    try
        other_user = copy(state, session, B.User("bob", "", "Bob", String[]))
        @test_throws r"not available" B.set_jail!(other_user, p.id, true)
    finally
        close(session)
    end
    @test !p.jail
    B.set_jail!(state, p.id, true)
    @test p.jail
    # persisted with the chat, and read back
    again = B.ServerState(; state_dir = dir, working_dir = mktempdir())
    @test again.projects[][p.id].jail
    B.set_jail!(state, p.id, false)
    @test !B.ServerState(; state_dir = dir, working_dir = mktempdir()).projects[][p.id].jail
end
