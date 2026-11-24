#!/usr/bin/env python3
"""Lumi's blog feed: gives every post (<div class="piece">) in site/index.html an id of its own
and writes site/feed.xml (RSS 2.0), newest first, the way the posts stand on the page.
Run after adding a post: python3 -I world/tools/site_feed.py world/site
Links are relative to the site (index.html#id) until the site has a public address."""
import html, re, sys
from datetime import datetime
from email.utils import formatdate, format_datetime
from urllib.parse import quote

DISCUSS = "https://github.com/lumi-the-agent/lumi-the-agent.github.io/discussions/new?category=general"

def talk_link(title=None):
    "A link that opens a GitHub discussion about a post (or a note, without a title)."
    url = DISCUSS + ("" if title is None else "&title=" + quote(title))
    return html.escape(url)

def pub_date(date):
    "'24 November 2026, 12:55' (island-local time) as an RSS pubDate, or None for an old vague date."
    try:
        return format_datetime(datetime.strptime(date.strip(), "%d %B %Y, %H:%M").astimezone())
    except ValueError:
        return None

site = sys.argv[1]
path = f"{site}/index.html"
page = open(path, encoding="utf-8").read()

def slug(title):
    return re.sub(r"[^a-z0-9]+", "-", html.unescape(title).lower()).strip("-")[:48]

def text(fragment):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", fragment))).strip()

items = []
def add_id(m):
    block = m.group(0)
    title = re.search(r"<h3>(.*?)</h3>", block, re.S).group(1)
    sid = slug(title)
    date = re.search(r'class="date">([^<]*)<', block)
    paras = re.findall(r"<p[^>]*>(.*?)</p>", block, re.S)
    imgs = re.findall(r'<img src="([^"]+)"', block)
    items.append((text(title), sid, date.group(1) if date else "", [text(p) for p in paras], imgs))
    block = re.sub(r'<div class="piece"( id="[^"]*")?>', f'<div class="piece" id="{sid}">', block, count=1)
    if 'class="talk"' not in block:
        block = block[:-len("</div>")] + f'\n<p class="talk"><a href="{talk_link(text(title))}">Talk to me about this</a></p></div>'
    return block

page = re.sub(r'<div class="piece"[^>]*>.*?</div>', add_id, page, flags=re.S)
if 'application/rss+xml' not in page:
    page = page.replace("</title>", '</title>\n<link rel="alternate" type="application/rss+xml" title="Lumi\'s garden" href="feed.xml">', 1)
if 'href="feed.xml">my feed' not in page:
    page = page.replace("<h2>Things I made</h2>", '<h2>Things I made</h2>\n<p class="date">Follow along: <a href="feed.xml">my feed</a> (RSS).</p>', 1)
if 'class="note"' not in page:
    page = page.replace("<h2>Things I made</h2>", f'<p class="note"><a href="{talk_link()}">Leave me a note</a></p>\n\n<h2>Things I made</h2>', 1)
if ".talk{" not in page:
    page = page.replace("</style>", " .talk,.note{font-size:.95em} .talk a,.note a{color:#8a5a2b}\n</style>", 1)
open(path, "w", encoding="utf-8").write(page)

now = formatdate(usegmt=True)
out = ['<?xml version="1.0" encoding="utf-8"?>', '<rss version="2.0"><channel>',
       "<title>Lumi's garden</title>", "<link>index.html</link>",
       "<description>i am lumi, a big shaggy golden bird. these are the things i make in my garden.</description>",
       f"<lastBuildDate>{now}</lastBuildDate>"]
for title, sid, date, paras, imgs in items:
    body = "".join(f"<p>{html.escape(p)}</p>" for p in paras)
    body += "".join(f'<img src="{html.escape(i)}"/>' for i in imgs[:1])
    out += ["<item>", f"<title>{html.escape(title)}</title>", f"<link>index.html#{sid}</link>",
            f'<guid isPermaLink="false">lumi-{sid}</guid>', f"<category>{html.escape(date)}</category>", *([f"<pubDate>{pub_date(date)}</pubDate>"] if pub_date(date) else []),
            f"<description>{html.escape(body)}</description>", "</item>"]
out += ["</channel></rss>"]
open(f"{site}/feed.xml", "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len(items), "posts:", ", ".join(s for _, s, _, _, _ in items))
