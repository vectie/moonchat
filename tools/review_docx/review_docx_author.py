"""Local authoring projection. The unchanged importer/native composer owns consumption."""
from __future__ import annotations

from array import array
import json
from pathlib import Path

from review_docx import (IntakeError, MAX_IMPORTED_TEXT, _read_docx, digest,
                         import_comments, load_json)
from review_docx_packet import MAX_QUOTE_PREVIEW, PacketError, render_packet
from review_docx_plan import check_shape, render_planning


def script_json(value: dict) -> str:
    # Also escape U+2028/2029 (ensure_ascii) and HTML terminators in hostile metadata.
    return json.dumps(value, ensure_ascii=True, allow_nan=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')


def authoring_packet(agenda_bytes: bytes, document: bytes, plan_bytes: bytes | None = None) -> str:
    agenda = load_json(agenda_bytes)
    check_shape(agenda)
    try:
        json.dumps(agenda, ensure_ascii=False).encode("utf-8")
    except UnicodeError as error:
        raise IntakeError("authoring input requires valid Unicode scalar values") from error
    catalog, text = _read_docx(document, quote_limit=MAX_QUOTE_PREVIEW)
    plan = {"format": "moonchat.docx-review.v1", "document_digest": catalog["document_digest"], "comments": []}
    if plan_bytes is not None:
        plan = load_json(plan_bytes)
        try:
            json.dumps(plan, ensure_ascii=False).encode("utf-8")
        except UnicodeError as error:
            raise IntakeError("authoring input requires valid Unicode scalar values") from error
        # The ordinary importer validates seeded choices with complete evidence.
        selected = {c.get('comment_id') for c in plan.get('comments', []) if isinstance(c, dict) and isinstance(c.get('comment_id'), str)} if isinstance(plan.get('comments'), list) else set()
        size = 0
        for item in catalog['comments']:
            if item['comment_id'] in selected:
                item['quote'] = text[item['start_offset']:item['end_offset']]
                size += len(item['quote'].encode('utf-8'))
                if size > MAX_IMPORTED_TEXT:
                    raise IntakeError('selected comment evidence exceeds 16 MiB; select fewer ranges')
        check_shape(import_comments(agenda, plan, catalog))
    # Compute exact serialized evidence costs in O(source + comment metadata),
    # without duplicating long overlapping quotes. Same JSON settings as importer.
    prefix = array('I', [0])
    for char in text:
        prefix.append(prefix[-1] + len(json.dumps(char, ensure_ascii=False).encode('utf-8')) - 2)
    comments = []
    for item in catalog['comments']:
        evidence = {"document_ref": agenda['source_artifact_ref'],
                    **{k: catalog[k] for k in ('document_digest', 'document_part', 'comments_part',
                                               'document_xml_digest', 'comments_xml_digest')}, **item, 'quote': ''}
        cost = len(('\n\nWord comment evidence (quoted metadata, not reviewer authority):\n' +
                    json.dumps(evidence, ensure_ascii=False, indent=2, allow_nan=False)).encode('utf-8'))
        cost += prefix[item['end_offset']] - prefix[item['start_offset']]
        comments.append({**{key: item[key] for key in ('comment_id', 'anchor_kind', 'start_offset', 'end_offset')}, 'evidence_bytes': cost})
        item['quote'] = item['quote'][:MAX_QUOTE_PREVIEW]
    bootstrap = {'agenda': agenda, 'plan': plan, 'comments': comments}
    script = '(function () {\n"use strict";\nconst input = ' + script_json(bootstrap) + ';\n' + Path(__file__).with_name('review_docx_author.js').read_text(encoding='utf-8') + '\n})();'
    original = {'agenda': agenda, 'items': [{**item, 'anchor': 'plan-item-' + str(i + 1),
                 'note': item['body'], 'comment_id': None} for i, item in enumerate(agenda['items'])],
                'agenda_digest': digest(agenda_bytes), 'plan_digest': digest(plan_bytes) if plan_bytes else 'No initial selection recipe',
                'selected_count': 0, 'comment_links': {}}
    try:
        original_markup = render_planning(original)
    except PacketError as error:
        raise IntakeError(str(error)) from error
    markup = ('<section id="authoring"><h2>Author a Word-comment review</h2>'
              '<p class="notice">Local draft preparation only. Select comments below, author discussion and propose named-human requests. '
              'No decisions, receipts, source edits, currentness checks or network requests. Nothing is saved automatically; '
              'download the recipe before closing. A browser may not warn before navigation.</p>'
              '<p>The read-only original agenda and all original comments remain below. Selected comments append after existing agenda items. '
              'The downloaded recipe requires the same original agenda and exact DOCX, then native composer validation.</p>'
              '<noscript>Authoring requires JavaScript. The complete source and original agenda remain readable.</noscript>'
              '<p id="author-status" role="status" aria-live="polite">Select a comment to begin.</p>'
              '<ol id="author-items"></ol><section id="author-editor" hidden><h3 id="author-heading">Edit selection</h3>'
              '<p><a id="author-source" href="#document">Read anchored source</a> · '
              '<a id="author-comment" href="#comments">Read original comment</a></p>'
              '<div class="author-compose-layout"><aside><h4>Original comment (unverified metadata)</h4>'
              '<pre id="author-original"></pre><h4>Anchored passage</h4><p id="author-anchor"></p>'
              '<pre id="author-quote"></pre></aside><div><label>Stable item key <input id="author-key" type="text"></label>'
              '<label>Discussion kind <select id="author-kind"><option value="question">Question</option>'
              '<option value="objection">Objection</option><option value="proposal">Proposal</option></select></label>'
              '<label>Proposed author <select id="author-person"></select></label>'
              '<label>Curator note <textarea id="author-note" rows="5"></textarea></label>'
              '<h4>Proposed human decision requests</h4><div id="author-decisions"></div>'
              '<button id="author-add-decision" type="button">Add decision request</button></div></div> '
              '<button id="author-apply" type="button">Apply selection</button> '
              '<button id="author-cancel" type="button">Cancel item edit</button></section>'
              '<button id="author-preview" type="button">Preview selection recipe</button> '
              '<button id="author-download" type="button" disabled>Download selections.json</button>'
              '<pre id="author-preview-text" aria-label="Exact recipe preview"></pre></section>'
              '<details><summary>Read-only original agenda and exact input identity</summary>' + original_markup + '</details>')
    try:
        return render_packet(catalog, text, authoring={'markup': markup, 'script': script})
    except PacketError as error:
        raise IntakeError(str(error)) from error
