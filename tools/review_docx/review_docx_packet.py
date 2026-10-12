"""Read-only HTML projection of the existing bounded classic DOCX reader."""
from __future__ import annotations

from html import escape as html_escape

MAX_PACKET_BYTES = 32 * 1024 * 1024
MAX_QUOTE_PREVIEW = 2000

STYLE = """
:root { color-scheme: light; font-family: system-ui, sans-serif; color: #172c3b; }
body { margin: auto; max-width: 90rem; padding: 1.5rem; background: #f5f8fa; }
h1, h2, h3 { line-height: 1.25; } a { color: #075d96; }
a:focus-visible { outline: 3px solid #b24600; outline-offset: 3px; }
.notice { border-left: .3rem solid #b24600; padding: .8rem; background: #fff4e6; }
.layout { display: grid; grid-template-columns: minmax(0, 1fr) minmax(20rem, 1fr); gap: 1.5rem; }
section, article { background: white; padding: 1rem; border: 1px solid #cbd5de; border-radius: .3rem; }
article { margin-bottom: 1rem; } :target { outline: 3px solid #b24600; outline-offset: 3px; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 4; line-height: 1.6; }
code, dd { overflow-wrap: anywhere; } dt { font-weight: 650; } dd { margin: .1rem 0 .6rem; }
mark { background: #ffebad; color: inherit; } mark.overlap { background: #ffd08a; }
.marker { font: 700 .85rem system-ui, sans-serif; padding: .15rem; background: #e4f3ff; }
.muted { color: #475c6b; } nav li { margin: .3rem 0; } .quote { background: #f5f8fa; padding: .6rem; }
@media (max-width: 55rem) { .layout { display: block; } #comments { margin-top: 1rem; } }
@media print {
  body { background: white; padding: 0; } .layout { display: block; }
  article { break-inside: avoid; } #comments { margin-top: 1rem; }
  a { color: inherit; } pre { font-size: .85rem; }
}
"""


def escape(value: str) -> str:
    # HTML normalizes literal CR on parsing; a numeric reference retains the
    # logical character produced by XML character references such as &#13;.
    return html_escape(value).replace("\r", "&#13;")


class PacketError(ValueError):
    """The complete packet exceeds its output bound."""


def render_packet(catalog: dict, document_text: str, *, planning: dict | None = None) -> str:
    """Return an offline packet; optional draft planning data is prepared by the importer."""
    comments = catalog["comments"]
    output: list[str] = []
    size = 0

    def add(value: str) -> None:
        nonlocal size
        size += len(value.encode("utf-8"))
        if size > MAX_PACKET_BYTES:
            raise PacketError("DOCX HTML packet exceeds 32 MiB; no partial packet emitted")
        output.append(value)

    add('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
        'style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'">'
        '<title>MoonChat · ' + ('Word review planning packet' if planning else 'Word comment reading packet') +
        '</title><style>' + STYLE + '</style></head><body>')
    add('<header id="top"><h1>' + ('Word review planning packet' if planning else 'Word comments in context') + '</h1>'
        '<p>A local MoonChat reading packet of classic Word comments and logical document text.</p>'
        '<p class="notice"><strong>Evidence only.</strong> Displayed authors and dates are unverified '
        'document metadata. Comments, including words such as “approved,” are not human decision '
        'receipts. This packet neither validates a review bundle nor changes review status.</p>'
        '<p>This is logical text, not Word layout: formatting, numbering and hidden-text visibility '
        'are not rendered. All main-body text is included. Nothing is fetched or executed.</p><dl>')
    for label, value in (("Exact DOCX SHA-256", catalog["document_digest"]),
                         ("Document part", catalog["document_part"]),
                         ("Document XML SHA-256", catalog["document_xml_digest"]),
                         ("Comments part", catalog["comments_part"]),
                         ("Comments XML SHA-256", catalog["comments_xml_digest"]),
                         ("Offsets", catalog["offset_unit"])):
        add('<dt>' + label + '</dt><dd><code>' + escape(value) + '</code></dd>')
    add('</dl><p>' + str(len(comments)) + ' comments · ' + str(len(document_text)) +
        ' logical text characters. Every comment is included; none is filtered or resolved here.</p></header>')
    if planning:
        add('<p class="notice">Draft planning view. Proposed notes and decision prompts are linked to the exact source below. '
            '<a href="#planning">Read draft review plan</a>. No native review validation has run.</p>')
    add('<nav aria-label="Packet navigation"><a href="#document">Read document</a> · '
        '<a href="#comments">Read comments</a><ul>')
    for item in comments:
        identity = item["comment_id"]  # The existing reader requires canonical decimal IDs.
        label = item["author"] or "Author not recorded"
        add('<li><a href="#comment-' + identity + '">Comment ' + identity + '</a> · <bdi>' +
            escape(label) + '</bdi> · <a href="#source-' + identity + '">Source</a></li>')
    add('</ul></nav>')
    if planning:
        from review_docx_plan import render_planning
        add(render_planning(planning))
    add('<main class="layout"><section id="document" aria-labelledby="document-heading">'
        '<h2 id="document-heading">Document text</h2><p class="muted">Blue numbered links locate '
        'comment starts or point anchors. Gold text is annotated; darker gold indicates overlapping '
        'ranges. A point or empty range selects no text. Follow a number to its comment.</p>'
        '<pre id="document-text"><span></span>')

    # Split at every anchor boundary. Sweep active ranges so nested/crossing ranges
    # never produce invalid nested markup, and each source character appears once.
    starts: dict[int, list[dict]] = {}
    ends: dict[int, list[str]] = {}
    for item in comments:
        starts.setdefault(item["start_offset"], []).append(item)
        if item["end_offset"] > item["start_offset"]:
            ends.setdefault(item["end_offset"], []).append(item["comment_id"])
    boundaries = sorted({0, len(document_text), *starts, *ends})
    active: set[str] = set()
    for index, position in enumerate(boundaries):
        active.difference_update(ends.get(position, ()))
        for item in starts.get(position, ()):
            identity = item["comment_id"]
            kind = "range" if item["end_offset"] > position else (
                "point" if item["anchor_kind"] == "point" else "empty range")
            add('<a class="marker" id="source-' + identity + '" href="#comment-' + identity +
                '" aria-label="Comment ' + identity + ', ' + kind + ' at offset ' + str(position) +
                '">[' + identity + ']</a>')
            if item["end_offset"] > position:
                active.add(identity)
        if index + 1 == len(boundaries):
            continue
        content = escape(document_text[position:boundaries[index + 1]])
        if active:
            add('<mark' + (' class="overlap"' if len(active) > 1 else '') +
                ' title="Annotated passage: ' + str(len(active)) + ' active comment range(s)">' + content + '</mark>')
        else:
            add(content)
    add('</pre></section><section id="comments" aria-labelledby="comments-heading">'
        '<h2 id="comments-heading">Comments</h2><p class="muted">Listed in main-document '
        'comment-reference order, as in the existing catalog. IDs identify Word comments, '
        'not verified people or decisions.</p>')
    for item in comments:
        identity = item["comment_id"]
        begin, end = item["start_offset"], item["end_offset"]
        add('<article id="comment-' + identity + '" aria-labelledby="heading-' + identity +
            '"><h3 id="heading-' + identity + '">Comment ' + identity + '</h3>')
        if planning:
            target = planning['comment_links'].get(identity)
            add('<p><a href="#' + target + '">Read proposed review item and decisions</a></p>' if target else
                '<p>Not selected in this plan. This original comment is retained; omission is not resolution.</p>')
        add('<dl>')
        for label, key in (("Author metadata", "author"), ("Initials metadata", "initials"), ("Date metadata", "date")):
            add('<dt>' + label + '</dt><dd><bdi>' + escape(item[key] or "Not recorded") + '</bdi></dd>')
        add('<dt>Anchor</dt><dd>' + item["anchor_kind"] + ' · [' + str(begin) + ', ' + str(end) +
            ') · <a href="#source-' + identity + '">Go to source</a></dd></dl><h4>Comment text</h4>'
            '<pre class="comment-text"><span></span>' + escape(item["text"]) + '</pre>')
        if end > begin:
            add('<h4>Anchored passage</h4><pre class="quote"><span></span>' + escape(item["quote"]) + '</pre>')
            omitted = end - begin - len(item["quote"])
            if omitted:
                add('<p class="muted">Excerpt stops after ' + str(MAX_QUOTE_PREVIEW) +
                    ' characters; ' + str(omitted) + ' more remain in the full <a href="#source-' +
                    identity + '">source range [' + str(begin) + ', ' + str(end) + ')</a>.</p>')
        else:
            add('<p class="muted">No text selected: ' + ('point anchor' if item["anchor_kind"] == "point" else 'empty range') +
                '. Nearby words are context, not a quoted selection.</p>')
        add('<p><a href="#top">Back to packet header</a></p></article>')
    if planning:
        add('<p>Use the <a href="#planning">draft review plan</a> above to inspect curator notes and proposed decisions.</p>')
    add('</section></main><footer><p>Keep this reading packet with the exact original DOCX. '
        'A later Word save changes its digest and requires a new packet. Use the existing catalog '
        'and explicit selection plan to import comments into a pending agenda; this packet does '
        + ('not verify' if planning else 'not supply') + ' participants, decision owners or receipts.</p></footer></body></html>\n')
    return "".join(output)
