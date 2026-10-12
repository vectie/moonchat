"""Two-snapshot editorial comparison in the existing DOCX intake workflow."""
from __future__ import annotations

from review_docx import IntakeError, _read_docx, digest
from review_docx_packet import MAX_QUOTE_PREVIEW, STYLE, escape

MAX_COMPARISON_BYTES = 32 * 1024 * 1024
FIELDS = ("author", "initials", "date", "text", "anchor_kind", "start_offset", "end_offset", "quote_digest")


def compare_docx(before: bytes, after: bytes) -> dict:
    """Pair explicit Word IDs; never infer continuity, resolution or approval."""
    def snapshot(data):
        catalog, text = _read_docx(data, quote_limit=MAX_QUOTE_PREVIEW)
        for item in catalog["comments"]:
            passage = text[item["start_offset"]:item["end_offset"]]
            item["quote_digest"] = digest(passage.encode("utf-8"))
            item["quote_characters"] = len(passage)
            item["quote_omitted_characters"] = len(passage) - len(item["quote"])
        catalog["logical_text"] = text
        catalog["logical_text_digest"] = digest(text.encode("utf-8"))
        return catalog

    old, new = snapshot(before), snapshot(after)
    old_items = {item["comment_id"]: item for item in old["comments"]}
    new_items = {item["comment_id"]: item for item in new["comments"]}
    order = [*old_items, *(key for key in new_items if key not in old_items)]
    changes, counts = [], {key: 0 for key in ("added", "removed", "changed", "unchanged")}
    for key in order:
        left, right = old_items.get(key), new_items.get(key)
        fields = [field for field in FIELDS if left and right and left[field] != right[field]]
        status = "added" if left is None else "removed" if right is None else "changed" if fields else "unchanged"
        counts[status] += 1
        # Keep comment data once, in the original ordered catalogs. Rows refer by ID.
        changes.append({"comment_id": key, "status": status, "changed_fields": fields})
    old_common = [key for key in old_items if key in new_items]
    new_common = [key for key in new_items if key in old_items]
    return {"format": "moonchat.docx-comparison.v1", "before": old, "after": new,
            "archive_changed": old["document_digest"] != new["document_digest"],
            "logical_text_changed": old["logical_text"] != new["logical_text"],
            "common_comment_order_changed": old_common != new_common,
            "counts": counts, "changes": changes}


def render_comparison(report: dict) -> str:
    """Bounded, inert HTML with complete logical sources and retained dissent."""
    pieces, size = [], 0

    def add(value):
        nonlocal size
        size += len(value.encode("utf-8"))
        if size > MAX_COMPARISON_BYTES:
            raise IntakeError("DOCX comparison exceeds 32 MiB; no partial output emitted")
        pieces.append(value)

    add('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
        'style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'">'
        '<title>MoonChat · Word revision comparison</title><style>' + STYLE +
        '</style></head><body><header id="top"><h1>Word revision comparison</h1>'
        '<p class="notice">Evidence only. Matching Word IDs are a comparison convenience, '
        'not proof of thread continuity. Removed comments are not resolved objections. '
        'No decisions, approval, participants or receipts are transferred.</p>'
        '<p>You selected these two snapshots. Their relationship and author metadata are '
        'unverified. Full logical source text is retained below; Word formatting is not rendered.</p>')
    add('<dl>')
    for side in ("before", "after"):
        for field in ("document_digest", "document_part", "document_xml_digest", "comments_part", "comments_xml_digest", "logical_text_digest"):
            add('<dt>' + side.title() + ' ' + field.replace('_', ' ') + '</dt><dd><code>' +
                escape(report[side][field]) + '</code></dd>')
    add('</dl><p>' + ' · '.join(str(count) + ' ' + key for key, count in report["counts"].items()) + '</p>')
    for key in ("archive_changed", "logical_text_changed", "common_comment_order_changed"):
        add('<p>' + key.replace('_', ' ').capitalize() + ': ' + ('yes' if report[key] else 'no') + '</p>')
    add('</header><nav aria-label="Comparison navigation"><a href="#source-before">Before source</a> · '
        '<a href="#source-after">After source</a><ul>')
    for row in report["changes"]:
        add('<li><a href="#change-' + row["comment_id"] + '">Comment ' + row["comment_id"] +
            ': ' + row["status"] + '</a></li>')
    add('</ul></nav><main><h2>Comment changes</h2>')
    indexes = {side: {item["comment_id"]: item for item in report[side]["comments"]} for side in ("before", "after")}
    for row in report["changes"]:
        key = row["comment_id"]
        add('<article id="change-' + key + '"><h3>Comment ' + key + ' · ' + row["status"] + '</h3>')
        if row["changed_fields"]:
            add('<p>Changed: ' + ', '.join(row["changed_fields"]).replace('quote_digest', 'anchored passage') + '</p>')
        if row["status"] == 'removed':
            add('<p class="notice">Absent from the later snapshot. Original dissent remains below; absence is not resolution.</p>')
        add('<div class="layout">')
        for side in ("before", "after"):
            item = indexes[side].get(key)
            add('<section><h4>' + side.title() + '</h4>')
            if item is None:
                add('<p>Not present in this snapshot.</p></section>')
                continue
            add('<dl>')
            for field in ("author", "initials", "date", "anchor_kind", "start_offset", "end_offset", "quote_digest"):
                add('<dt>' + field.replace('_', ' ') + '</dt><dd>' + escape(str(item[field]) or 'Not recorded') + '</dd>')
            add('</dl><h5>Comment text</h5><pre><span></span>' + escape(item["text"]) +
                '</pre><h5>Anchored passage</h5><pre><span></span>' + escape(item["quote"]) + '</pre>')
            if item["quote_omitted_characters"]:
                add('<p>Excerpt omits ' + str(item["quote_omitted_characters"]) +
                    ' characters. Comparison uses the complete passage digest.</p>')
            if item["quote_characters"] == 0:
                add('<p>No text selected. No neighboring words are inferred.</p>')
            add('<p><a href="#source-' + side + '">Full ' + side + ' source</a>: Unicode code-point offsets [' +
                str(item["start_offset"]) + ', ' + str(item["end_offset"]) + ').</p></section>')
        add('</div><p><a href="#top">Back to summary</a></p></article>')
    for side in ("before", "after"):
        add('<section id="source-' + side + '"><h2>' + side.title() + ' complete logical source</h2><pre><span></span>' +
            escape(report[side]["logical_text"]) + '</pre></section>')
    add('</main><footer><p>Keep both original DOCX files. Use catalog on the later file and create a new explicit '
        'selection plan for the existing agenda importer. New bytes need new source binding; earlier decisions '
        'do not carry forward. This report neither edits an agenda nor establishes a hosted review journey.</p></footer></body></html>\n')
    return ''.join(pieces)
