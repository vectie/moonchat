"""Source-linked draft planning view for the existing DOCX comment importer.

This is preparation, not a Python implementation of native review validation.
The exact same import candidate is constructed; only its reading projection is new.
"""
from __future__ import annotations

import re

from review_docx import (IntakeError, MAX_IMPORTED_TEXT, _read_docx, digest, import_comments,
                         load_json, required_text)
from review_docx_packet import MAX_PACKET_BYTES, MAX_QUOTE_PREVIEW, PacketError, escape, render_packet

AGENDA_FIELDS = {"review_id", "conversation_id", "source_artifact_ref", "source_revision_id",
                 "recorded_at", "participants", "items"}
ITEM_FIELDS = {"key", "kind", "author", "body", "evidence_refs", "decisions"}


def check_shape(agenda: dict) -> None:
    """Check what we display, without claiming the native contract has passed."""
    if set(agenda) != AGENDA_FIELDS:
        raise IntakeError("planning view requires the exact editable agenda fields, not a review bundle")
    for field in AGENDA_FIELDS - {"participants", "items"}:
        required_text(agenda, field)
    if not isinstance(agenda["participants"], list) or not agenda["participants"]:
        raise IntakeError("planning view requires a participant array")
    roster = {}
    for person in agenda["participants"]:
        if not isinstance(person, dict) or set(person) != {"participant_id", "display_name", "participant_kind"}:
            raise IntakeError("planning participant requires id, display name and kind")
        identity = required_text(person, "participant_id")
        required_text(person, "display_name")
        if identity in roster or person["participant_kind"] not in ("human", "agent"):
            raise IntakeError("planning participant IDs must be unique and kinds human or agent")
        roster[identity] = person
    if not isinstance(agenda["items"], list):
        raise IntakeError("planning items must be an array")
    keys = set()
    for item in agenda["items"]:
        if not isinstance(item, dict) or set(item) != ITEM_FIELDS:
            raise IntakeError("planning items require the exact editable agenda fields")
        key = required_text(item, "key")
        if key in keys or not re.fullmatch(r"[A-Za-z0-9_.-]+", key):
            raise IntakeError("planning item keys must be unique safe identifiers")
        keys.add(key)
        author = required_text(item, "author")
        required_text(item, "body")
        if item["kind"] not in ("question", "objection", "proposal") or author not in roster:
            raise IntakeError("planning items need a known kind and an existing author")
        refs = item["evidence_refs"]
        if not isinstance(refs, list) or any(not isinstance(ref, str) or not ref.strip() for ref in refs):
            raise IntakeError("planning evidence references must be nonempty strings")
        decisions = item["decisions"]
        if not isinstance(decisions, list):
            raise IntakeError("planning decisions must be an array")
        if item["kind"] == "objection" and not decisions:
            raise IntakeError("planning objection requires an explicit decision request")
        reviewers = set()
        for decision in decisions:
            if not isinstance(decision, dict) or set(decision) != {"reviewer", "prompt"}:
                raise IntakeError("planning decisions require reviewer and prompt")
            reviewer = required_text(decision, "reviewer")
            required_text(decision, "prompt")
            if reviewer in reviewers or reviewer not in roster or roster[reviewer]["participant_kind"] != "human":
                raise IntakeError("planning decision reviewers must be distinct existing humans per item")
            reviewers.add(reviewer)


def planning_packet(agenda_bytes: bytes, document: bytes, plan_bytes: bytes) -> str:
    """Read exact snapshots once and render the importer candidate with its source."""
    agenda, plan = load_json(agenda_bytes), load_json(plan_bytes)
    check_shape(agenda)
    catalog, text = _read_docx(document, quote_limit=MAX_QUOTE_PREVIEW)
    # Only selected comments need the importer's complete provenance quote.
    # Unselected overlapping ranges must not duplicate a megabyte each.
    selections = plan.get("comments", [])
    selected_ids = {choice.get("comment_id") for choice in selections
                    if isinstance(choice, dict) and isinstance(choice.get("comment_id"), str)} if isinstance(selections, list) else set()
    quote_bytes = 0
    for comment in catalog["comments"]:
        if comment["comment_id"] in selected_ids:
            quote = text[comment["start_offset"]:comment["end_offset"]]
            quote_bytes += len(quote.encode("utf-8"))
            if quote_bytes > MAX_IMPORTED_TEXT:
                raise IntakeError("selected comment evidence exceeds 16 MiB; select fewer ranges")
            comment["quote"] = quote
    candidate = import_comments(agenda, plan, catalog)
    check_shape(candidate)
    choices = {choice["key"]: choice for choice in plan["comments"]}
    # Source/metadata remain in the shared original-comment view. Display the
    # curator's note separately instead of duplicating the importer's JSON body.
    items = []
    for index, item in enumerate(candidate["items"]):
        choice = choices.get(item["key"])
        items.append({**item, "anchor": "plan-item-" + str(index + 1),
                      "note": choice["note"] if choice else item["body"],
                      "comment_id": choice["comment_id"] if choice else None})
    planning = {"agenda": candidate, "items": items, "agenda_digest": digest(agenda_bytes),
                "plan_digest": digest(plan_bytes), "selected_count": len(choices),
                "comment_links": {item["comment_id"]: item["anchor"] for item in items
                                  if item["comment_id"] is not None}}
    for comment in catalog["comments"]:
        comment["quote"] = comment["quote"][:MAX_QUOTE_PREVIEW]
    try:
        return render_packet(catalog, text, planning=planning)
    except PacketError as error:
        raise IntakeError(str(error)) from error


def render_planning(planning: dict) -> str:
    """Internal projection of the checked preparation data, with fragment links only."""
    output, size = [], 0

    def add(value):
        nonlocal size
        size += len(value.encode("utf-8"))
        if size > MAX_PACKET_BYTES:
            raise PacketError("DOCX planning packet exceeds 32 MiB; no partial packet emitted")
        output.append(value)

    agenda, items = planning["agenda"], planning["items"]
    roster = {person["participant_id"]: person for person in agenda["participants"]}

    def name(identity):
        person = roster[identity]
        return escape(person["display_name"]) + ' (' + escape(identity) + ', ' + person["participant_kind"] + ')'

    add('<section id="planning" aria-labelledby="planning-heading"><h2 id="planning-heading">'
        'Draft review plan</h2><p class="notice"><strong>Preparation only; not a validated review.</strong> '
        'These are proposed discussion items and decision requests. No decisions have been collected or '
        'inferred. Native review_compose validation, human identity verification and receipt capture '
        'remain separate. A named human here is the planner’s assignment, not an authenticated reviewer.</p><dl>')
    for label, value in (("Review ID", agenda["review_id"]), ("Conversation ID", agenda["conversation_id"]),
                         ("Portable source reference", agenda["source_artifact_ref"]),
                         ("Planned source revision", agenda["source_revision_id"]),
                         ("Planner-provided recorded time", agenda["recorded_at"]),
                         ("Exact input agenda SHA-256", planning["agenda_digest"]),
                         ("Exact selection plan SHA-256", planning["plan_digest"])):
        add('<dt>' + label + '</dt><dd><code>' + escape(value) + '</code></dd>')
    count = sum(len(item["decisions"]) for item in items)
    add('</dl><p>' + str(len(items)) + ' planned items · ' + str(count) + ' proposed decision requests · ' +
        str(planning["selected_count"]) + ' selected Word comments. All original comments are retained below.</p>')
    add('<h3>People named in this plan</h3><ul>')
    for person in agenda["participants"]:
        add('<li><bdi>' + name(person["participant_id"]) + '</bdi></li>')
    add('</ul><nav aria-label="Proposed decisions by reviewer"><h3>What is each reviewer being asked?</h3>')
    requests_by_reviewer = {}
    for item in items:
        for decision in item["decisions"]:
            requests_by_reviewer.setdefault(decision["reviewer"], []).append((item, decision))
    assigned = False
    for person in agenda["participants"]:
        identity = person["participant_id"]
        requests = requests_by_reviewer.get(identity, [])
        if not requests:
            continue
        assigned = True
        add('<h4><bdi>' + name(identity) + '</bdi> · ' + str(len(requests)) + ' request(s)</h4><ul>')
        for item, decision in requests:
            add('<li><a href="#' + item["anchor"] + '">' + escape(item["key"]) + '</a>: ' +
                '<span class="prompt-summary">' + escape(decision["prompt"]) + '</span></li>')
        add('</ul>')
    if not assigned:
        add('<p>No decision requests are proposed. This is not evidence of completed review.</p>')
    add('</nav><h3>Planned discussion, in import order</h3>')
    for item in items:
        add('<article id="' + item["anchor"] + '"><h4>' + escape(item["key"]) + ' · ' + item["kind"] +
            '</h4><p>Proposed author: <bdi>' + name(item["author"]) + '</bdi></p>')
        identity = item["comment_id"]
        if identity is None:
            add('<p>Existing agenda item. No Word anchor has been asserted for this item.</p>')
        else:
            add('<p>Selected Word comment ' + identity + ': <a href="#source-' + identity +
                '">Read anchored passage</a> · <a href="#comment-' + identity + '">Read original comment and metadata</a>.</p>')
        add('<h5>' + ('Existing item body' if identity is None else 'Curator note') +
            '</h5><pre class="plan-note"><span></span>' + escape(item["note"]) + '</pre>')
        add('<h5>Proposed decision requests</h5>')
        if item["decisions"]:
            add('<ul>')
            for decision in item["decisions"]:
                add('<li><bdi>' + name(decision["reviewer"]) + '</bdi><pre class="decision-prompt"><span></span>' +
                    escape(decision["prompt"]) + '</pre></li>')
            add('</ul>')
        else:
            add('<p>No decision requested for this item. It is discussion only.</p>')
        add('<h5>Evidence references (not fetched)</h5><ul>')
        for ref in item["evidence_refs"]:
            add('<li><code>' + escape(ref) + '</code></li>')
        add('</ul><p><a href="#planning">Back to review plan</a></p></article>')
    add('<p>Continue with the same agenda, DOCX and selection plan using the importer’s agenda, preview '
        'or bundle command and a trusted native composer. This page is not importable evidence and '
        'does not authorize sending it to anyone. Keep the original input files.</p></section>')
    return ''.join(output)
