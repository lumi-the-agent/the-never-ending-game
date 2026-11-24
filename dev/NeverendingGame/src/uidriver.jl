# ── Using the dashboard like a person: Makie's FakeInteraction, played live ──
#
# The events are Makie's own (`dev/Makie/docs/fake_interaction.jl`, the module
# Makie's docs record their interaction videos with): `MouseTo`, `LeftClick`,
# `TypeText`, `KeyPress`, `KeyDown`/`KeyUp`, `Scroll`, `Wait`, `WaitUntil`,
# `Lazy`, and `relative_pos(block, (x, y))` for a point on a block.
# `interact!` plays them into the running game frame by frame, the way
# `interaction_record` plays them into a recording, so a test moves the
# pointer, clicks and types through the same Makie events as a person.
#
#   uitest("Play starts Jump in") do game
#       interact!(game, [MouseTo(ui_pos(game, "Play")), LeftClick(), Wait(0.3)])
#       check(game.minigame isa NeverendingGame.JumpIn, "…")
#   end
#
# Finding things: `ui_elements(game)` lists the controls, `ui_pos(game, name)`
# is the middle of one (by what is written on it), `ui_option_pos(game, menu,
# option)` an option of an open menu.

"""
Makie's FakeInteraction module, loaded from the Makie checkout on first use.
Its `using GLMakie` is left out: the events, `relative_pos` and `record` need
only Makie, and GLMakie does not belong in a process that renders with RayMakie.
"""
function fake_interaction()
    isdefined(@__MODULE__, :FakeInteraction) && return getfield(@__MODULE__, :FakeInteraction)
    path = normpath(joinpath(dirname(pathof(Makie)), "..", "..", "docs", "fake_interaction.jl"))
    code = replace(read(path, String), r"^using GLMakie$"m => "")
    Base.include_string(@__MODULE__, code, path)
    return getfield(@__MODULE__, :FakeInteraction)
end

struct UIElement
    name::String          # what a person reads on it (label, menu text, placeholder)
    kind::Symbol          # :button :menu :textbox
    block::Any
    bbox::Rect2f          # figure units, origin bottom left
end

Base.show(io::IO, e::UIElement) =
    print(io, "UIElement(", e.kind, " \"", e.name, "\" at ", Tuple(round.(Int, minimum(e.bbox))), " size ",
          Tuple(round.(Int, widths(e.bbox))), ")")

ui_name(b::Button) = string(b.label[])
ui_name(b::Textbox) = string(b.placeholder[])
ui_name(m::Menu) = (sel = m.selection[]; sel === nothing ? string(m.prompt[]) : string(sel))

ui_kind(::Button) = :button
ui_kind(::Menu) = :menu
ui_kind(::Textbox) = :textbox

"Every clickable control on the dashboard."
function ui_elements(g::Game)
    g.dash === nothing && error("the game runs headless: no dashboard")
    return [UIElement(ui_name(b), ui_kind(b), b, Rect2f(b.layoutobservables.computedbbox[]))
            for b in g.dash.fig.content if b isa Union{Button,Menu,Textbox}]
end

"The control whose name starts with `name` (case insensitive)."
function ui_find(g::Game, name::AbstractString)
    els = ui_elements(g)
    i = findfirst(e -> startswith(lowercase(e.name), lowercase(name)), els)
    i === nothing && error("no control named \"$name\"; there are: " * join(("\"$(e.name)\"" for e in els), ", "))
    return els[i]
end

"A point on the control called `name`, `rel` from its bottom left (default: the middle)."
ui_pos(g::Game, name::AbstractString, rel = (0.5, 0.5)) = fake_interaction().relative_pos(ui_find(g, name).block, rel)

"Where option `option` of the OPEN menu called `menu` is (click the menu first)."
function ui_option_pos(g::Game, menu::AbstractString, option::AbstractString)
    m = ui_find(g, menu).block
    m isa Menu || error("\"$menu\" is not a menu")
    m.is_open[] || error("menu \"$menu\" is not open")
    opts = string.(m.options[])
    i = findfirst(o -> startswith(lowercase(o), lowercase(option)), opts)
    i === nothing && error("menu \"$menu\" has no option \"$option\"; it has: " * join(opts, ", "))
    menuscene = only(filter(s -> any(p -> p isa Poly, s.plots), m.blockscene.children))
    rect = first(filter(p -> p isa Poly, menuscene.plots))[1][][i]
    t = Makie.translation(menuscene)[]
    return Point2f(minimum(rect) .+ widths(rect) ./ 2) .+ Point2f(t[1], t[2])
end

"""
    interact!(game, events)

Play FakeInteraction `events` into the live dashboard, one frame at a time
(only inside a test: it waits for the game's frames). `Lazy(f)` gets the
dashboard figure; `WaitUntil(pred)` waits until `pred()` holds.

The pointer is virtual: in a window, RayMakie writes the real cursor position
into the events every frame, so the virtual one is put back before every
frame and every press, release and key. (Otherwise a click presses on the
button and releases wherever the real cursor is.)
"""
function interact!(g::Game, events::AbstractVector)
    g.driven += 1
    try
        drive!(g, events)
    finally
        g.driven -= 1
    end
    return nothing
end

function drive!(g::Game, events::AbstractVector)
    FI = fake_interaction()
    e = Makie.events(g.dash.fig.scene)
    e.hasfocus[] = true
    e.entered_window[] = true
    cursor = Ref(Point2f(e.mouseposition[]))
    put_cursor!() = Point2f(e.mouseposition[]) == cursor[] || (e.mouseposition[] = Tuple(Float64.(cursor[])))
    move!(p) = (cursor[] = Point2f(p); put_cursor!())
    button!(x) = (put_cursor!(); e.mousebutton[] = x)
    key!(x) = (put_cursor!(); e.keyboardbutton[] = x)
    dt = 1 / g.fps
    for ev0 in events
        ev = ev0 isa FI.Lazy ? Base.invokelatest(ev0.f, g.dash.fig) : ev0
        start = cursor[]
        dur = FI.duration(ev, start)
        foreach(button!, FI.mouseevents_start(ev))
        foreach(key!, FI.keyboardevents_start(ev))
        dropped = FI.droppedfiles_start(ev)
        isempty(dropped) || (e.dropped_files[] = dropped)
        foreach(move!, FI.mousepositions_start(ev, start))
        t = prev = 0.0
        while t < dur
            ev isa FI.WaitUntil && Base.invokelatest(ev.pred) && break
            put_cursor!()
            foreach(button!, FI.mouseevents_frame(ev, t))
            foreach(move!, FI.mousepositions_frame(ev, start, t))
            foreach(c -> (e.unicode_input[] = c), FI.unicode_inputs_frame(ev, t, prev))
            foreach(sc -> (e.scroll[] = sc), FI.scrollevents_frame(ev, t, prev))
            prev = t
            wait_frames(g, 1)
            t += dt
        end
        foreach(button!, FI.mouseevents_end(ev))
        foreach(key!, FI.keyboardevents_end(ev))
        foreach(move!, FI.mousepositions_end(ev, start))
    end
    return nothing
end
