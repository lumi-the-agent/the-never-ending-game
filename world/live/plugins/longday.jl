# Longer day (todo #23, perfectionist-0046): an in-game hour lasted a minute and every mini game round
# slid into night. The engine's day is now NG.DAY_LENGTH s (5 h) with a warped clock (slow
# midday, quick night: daytime = p + 0.7 sin(2πp)/2π). Worlds saved with the old 1440 s day get the
# new length here, keeping the time of day (the clock only moves forward).
const NG = NeverendingGame

struct LongDay <: System end

function NG.step!(::LongDay, game, dt)
    w = game.world
    w.day_length == NG.DAY_LENGTH && return
    h0 = 24NG.daytime(w)
    NG.set_day_length!(w, NG.DAY_LENGTH)
    NG.emit!(w, :day_length; seconds = w.day_length, hour_before = h0, hour_after = 24NG.daytime(w))
    return
end

register!(LongDay())
