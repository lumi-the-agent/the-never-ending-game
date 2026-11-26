# ── the world outside: what the workbench draws from beyond the island ──────────
#
# The workbench (curiosity.jl) drew from the island's own world only: Julia
# packages, JuliaVision's models, the character's diary. Asked for something new
# with nothing else to go on than that and its own record of what it had made,
# the character went abstract (sessions 102-113: the island drifting off,
# remembering its drafts, watching itself on a television). Now the host also
# draws from outside, at random: Wikipedia articles, an artwork of the Cleveland
# Museum of Art's open access collection, an arXiv paper, and the world news of
# the day. The host fetches them into `run/workbench/` (the character reads them
# at /run/neverending/workbench), so the jail's network stays as it was: the
# character can read all of it and write nowhere.

"How the host names itself to the public sources it draws from."
const OUTSIDE_AGENT = "NeverendingGame-workbench/0.1"

"Random Wikipedia articles drawn per session; the `WIKI_PICK` longest are shown (most random ones are stubs)."
const WIKI_DRAW = 20
const WIKI_PICK = 2

"How many of the day's news are shown."
const NEWS_PICK = 3

"How many shown news links are remembered, so the same story is not shown twice."
const NEWS_MEMORY = 300

const ART_API = "https://openaccess-api.clevelandart.org/api/artworks/?has_image=1&limit=1"
const WIKI_API = "https://en.wikipedia.org/w/api.php?action=query&format=json&formatversion=2"
const NEWS_FEED = "https://feeds.bbci.co.uk/news/world/rss.xml"

"Where the host puts the session's draws (read only in the jail at `/run/neverending/workbench`)."
workbench_dir(jp::JailPaths) = joinpath(jp.run, "workbench")

function fetch_text(url::AbstractString)
    io = IOBuffer()
    Downloads.download(url, io; headers = ["User-Agent" => OUTSIDE_AGENT], timeout = 30)
    return String(take!(io))
end

fetch_json(url::AbstractString) = JSON.parse(fetch_text(url))

"Download `url` into `dir` as `name` with the url's extension; the file's name."
function fetch_file(url::AbstractString, dir::AbstractString, name::AbstractString)
    file = name * lowercase(splitext(first(split(url, '?')))[2])
    Downloads.download(url, joinpath(dir, file); headers = ["User-Agent" => OUTSIDE_AGENT], timeout = 60)
    return file
end

"Text from an API that may be `null`."
text_or_empty(x) = x isa AbstractString ? String(x) : ""

"Markup as plain text: tags dropped, the common entities resolved, whitespace collapsed."
plain(s::AbstractString) =
    strip(replace(replace(s, r"<[^>]*>" => " "), "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"",
                  "&#39;" => "'", "&nbsp;" => " ", r"\s+" => " "))

"The text of the first `<tag>` in `xml`, CDATA unwrapped, as plain text; empty without one."
function xml_tag(xml::AbstractString, tag::AbstractString)
    m = match(Regex("<$tag(?:\\s[^>]*)?>(.*?)</$tag>", "s"), xml)
    m === nothing && return ""
    return plain(replace(m[1], r"<!\[CDATA\[(.*?)\]\]>"s => s"\1"))
end

"""
    wikipedia_finds(dir) -> Vector{Dict}

The `WIKI_PICK` longest of `WIKI_DRAW` random Wikipedia articles, each written whole into `dir`
with its lead picture, if it has one.
"""
function wikipedia_finds(dir::AbstractString)
    q = fetch_json("$WIKI_API&generator=random&grnnamespace=0&grnlimit=$WIKI_DRAW&prop=info|pageimages&inprop=url&pithumbsize=800")
    pages = first(sort!(collect(q["query"]["pages"]); by = p -> p["length"], rev = true), WIKI_PICK)
    return map(enumerate(pages)) do (i, p)
        x = fetch_json("$WIKI_API&prop=extracts&explaintext=1&exsectionformat=plain&pageids=$(p["pageid"])")
        text = text_or_empty(get(only(x["query"]["pages"]), "extract", nothing))
        file = "wikipedia-$i.txt"
        write(joinpath(dir, file), p["title"], "\n", p["fullurl"], "\n\n", text)
        find = Dict{String,Any}("name" => p["title"], "summary" => first_sentence(text), "file" => file)
        haskey(p, "thumbnail") && (find["picture"] = fetch_file(p["thumbnail"]["source"], dir, "wikipedia-$i"))
        find
    end
end

"""
    art_finds(dir) -> Vector{Dict}

One artwork with a picture from the Cleveland Museum of Art's open access collection, at random:
what the museum says about it written into `dir`, with the picture.
"""
function art_finds(dir::AbstractString)
    total = fetch_json("$ART_API&skip=0")["info"]["total"]
    a = only(fetch_json("$ART_API&skip=$(rand(0:total-1))")["data"])
    by = join(filter(!isempty, [text_or_empty(get(c, "description", nothing)) for c in get(a, "creators", Any[])]), "; ")
    what = join(filter(!isempty, [text_or_empty(get(a, k, nothing)) for k in ("type", "technique", "culture")]), ", ")
    about = plain(text_or_empty(something(get(a, "wall_description", nothing), get(a, "description", nothing), Some(nothing))))
    date = text_or_empty(get(a, "creation_date", nothing))
    write(joinpath(dir, "art.txt"), a["title"], "\n", join(filter(!isempty, [by, date, what]), "\n"), "\n",
          text_or_empty(get(a, "url", nothing)), "\n\n", about)
    find = Dict{String,Any}("name" => a["title"], "by" => by, "date" => date, "what" => what,
                            "summary" => first_sentence(about), "file" => "art.txt")
    find["picture"] = fetch_file(a["images"]["web"]["url"], dir, "art")
    return [find]
end

"""
    arxiv_finds(dir; tries = 5) -> Vector{Dict}

One arXiv paper at random (a random number in a random month since 2015), its abstract written into
`dir`. Empty when `tries` numbers in a row do not exist.
"""
function arxiv_finds(dir::AbstractString; tries::Int = 5)
    for t in 1:tries
        t > 1 && sleep(3)                  # arXiv asks for three seconds between requests
        month = rand(Date(2015, 1):Month(1):(today() - Month(1)))
        id = Dates.format(month, "yymm") * "." * lpad(rand(1:9999), 5, '0')
        m = match(r"<entry>(.*?)</entry>"s, fetch_text("https://export.arxiv.org/api/query?id_list=$id"))
        m === nothing && continue
        title, abstract = xml_tag(m[1], "title"), xml_tag(m[1], "summary")
        (isempty(abstract) || title == "Error") && continue
        cat = match(r"primary_category[^>]*term=\"([^\"]+)\"", m[1])
        field = cat === nothing ? "" : cat[1]
        write(joinpath(dir, "arxiv.txt"), title, "\nhttps://arxiv.org/abs/$id ($field)\n\n", abstract)
        return [Dict{String,Any}("name" => title, "field" => field, "summary" => first_sentence(abstract), "file" => "arxiv.txt")]
    end
    return Dict{String,Any}[]
end

"""
    news_finds(seen) -> Vector{Dict}

`NEWS_PICK` of today's world news (BBC World's feed) not shown before (`seen`, their links), at random.
"""
function news_finds(seen)
    items = [(title = xml_tag(i[1], "title"), text = xml_tag(i[1], "description"), link = first(split(xml_tag(i[1], "link"), '?')))
             for i in eachmatch(r"<item>(.*?)</item>"s, fetch_text(NEWS_FEED))]
    fresh = shuffle!(filter(i -> !isempty(i.title) && !(i.link in seen), items))
    return [Dict{String,Any}("name" => i.link, "title" => i.title, "summary" => i.text) for i in first(fresh, NEWS_PICK)]
end

"`f()`, or nothing found when `source` cannot be reached (said in the host's log)."
function reached(f, source::AbstractString)
    try
        return f()
    catch e
        e isa Downloads.RequestError || rethrow()
        @warn "The workbench could not reach $source" exception = e
        return Dict{String,Any}[]
    end
end

"""
    outside_finds!(jp, seen) -> Dict

This session's draws from outside (see the top of this file), fetched into a fresh `workbench_dir`;
the news shown are remembered in `seen["news"]`.
"""
function outside_finds!(jp::JailPaths, seen::AbstractDict)
    dir = workbench_dir(jp)
    rm(dir; recursive = true, force = true)
    mkpath(dir)
    news_seen = get!(seen, "news", Any[])
    finds = Dict{String,Any}("wikipedia" => reached(() -> wikipedia_finds(dir), "Wikipedia"),
                             "art" => reached(() -> art_finds(dir), "the Cleveland Museum of Art"),
                             "arxiv" => reached(() -> arxiv_finds(dir), "arXiv"),
                             "news" => reached(() -> news_finds(news_seen), "the BBC's news feed"))
    append!(news_seen, [n["name"] for n in finds["news"]])
    seen["news"] = last(news_seen, NEWS_MEMORY)
    return finds
end

"The workbench's lines for what was drawn from outside."
function outside_lines(io::IO, finds::AbstractDict)
    path(file) = "`$(joinpath(JAIL_RUN, "workbench", file))`"
    at(f) = haskey(f, "picture") ? "$(path(f["file"])), picture $(path(f["picture"]))" : path(f["file"])
    if !isempty(finds["wikipedia"])
        println(io, "From Wikipedia:")
        foreach(w -> println(io, "- $(w["name"]): $(w["summary"]) ($(at(w)))"), finds["wikipedia"])
    end
    if !isempty(finds["art"])
        println(io, "In a museum (the Cleveland Museum of Art's open collection):")
        for a in finds["art"]
            about = join(filter(!isempty, [a["by"], a["date"], a["what"]]), ", ")
            println(io, "- \"$(a["name"])\"", isempty(about) ? "" : ", $about", isempty(a["summary"]) ? "" : ": $(a["summary"])",
                    " ($(at(a)))")
        end
    end
    if !isempty(finds["arxiv"])
        println(io, "On arXiv:")
        foreach(p -> println(io, "- $(p["name"])", isempty(p["field"]) ? "" : " ($(p["field"]))", ": $(p["summary"]) ($(at(p)))"), finds["arxiv"])
    end
    if !isempty(finds["news"])
        println(io, "In the news today (BBC World):")
        foreach(n -> println(io, "- $(n["title"])", isempty(n["summary"]) ? "" : ": $(n["summary"])"), finds["news"])
    end
end
