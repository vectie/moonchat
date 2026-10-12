# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    launch-document

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-7-rollout-ops, decision-8-rollback-ops, decision-7-support-support). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-docx/launch.docx

Source SHA-256:

    sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9

Source revision:

    draft-1

Previous bundle:

    (none)

Previous bundle SHA-256:

    (none)

Conversation:

    launch-review

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moonchat.review-agenda.v1

Product:

    moonchat

Recorded at:

    2026-10-10T10:00:00Z

## Participants

### Participant 1

Name:

    Jules

ID:

    curator

Kind:

    human

### Participant 2

Name:

    Ren

ID:

    ops

Kind:

    human

### Participant 3

Name:

    Mina

ID:

    support

Kind:

    human

### Participant 4

Name:

    Notes agent

ID:

    notes

Kind:

    agent

## Conversation entries

### Entry 1

ID:

    entry-rollout

Kind:

    proposal

Author:

    curator

Body:

    Review the attached launch document.

Turn:

    turn-rollout

Client turn:

    client-rollout

Command:

    command-rollout

Evidence references:

    (none)

### Entry 2

ID:

    entry-rollback

Kind:

    objection

Author:

    curator

Body:

    Resolve the rollback rehearsal concern.
    
    Word comment evidence (quoted metadata, not reviewer authority):
    {
      "document_ref": "examples/review-docx/launch.docx",
      "document_digest": "sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9",
      "document_part": "word/document.xml",
      "comments_part": "word/comments.xml",
      "document_xml_digest": "sha256:54bb8a0a89f4efa5be2b1221bc4959fcd8448e237859796c6c708a5f2069e12f",
      "comments_xml_digest": "sha256:9935736727ab9bdc694f518f6d1806f9faf25ae7cc1ec4a03f620e054938748e",
      "comment_id": "7",
      "author": "Ren",
      "initials": "R",
      "date": "2026-10-10T09:00:00Z",
      "text": "Can we rehearse rollback first?\nKeep the old path.",
      "anchor_kind": "range",
      "start_offset": 16,
      "end_offset": 70,
      "quote": "Roll out to 10%\ton Monday.\nRollback owner: operations."
    }

Turn:

    turn-rollback

Client turn:

    client-rollback

Command:

    command-rollback

Evidence references:

    examples/review-docx/launch.docx

### Entry 3

ID:

    entry-support

Kind:

    question

Author:

    curator

Body:

    Confirm the support route.
    
    Word comment evidence (quoted metadata, not reviewer authority):
    {
      "document_ref": "examples/review-docx/launch.docx",
      "document_digest": "sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9",
      "document_part": "word/document.xml",
      "comments_part": "word/comments.xml",
      "document_xml_digest": "sha256:54bb8a0a89f4efa5be2b1221bc4959fcd8448e237859796c6c708a5f2069e12f",
      "comments_xml_digest": "sha256:9935736727ab9bdc694f518f6d1806f9faf25ae7cc1ec4a03f620e054938748e",
      "comment_id": "2",
      "author": "Mina",
      "initials": "M",
      "date": "2026-10-10T09:30:00Z",
      "text": "Who handles support?\nConfirm coverage.",
      "anchor_kind": "range",
      "start_offset": 71,
      "end_offset": 84,
      "quote": "Support route"
    }

Turn:

    turn-support

Client turn:

    client-support

Command:

    command-support

Evidence references:

    examples/review-docx/launch.docx

### Entry 4

ID:

    entry-notes

Kind:

    question

Author:

    curator

Body:

    Retain the automated comment as evidence only.
    
    Word comment evidence (quoted metadata, not reviewer authority):
    {
      "document_ref": "examples/review-docx/launch.docx",
      "document_digest": "sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9",
      "document_part": "word/document.xml",
      "comments_part": "word/comments.xml",
      "document_xml_digest": "sha256:54bb8a0a89f4efa5be2b1221bc4959fcd8448e237859796c6c708a5f2069e12f",
      "comments_xml_digest": "sha256:9935736727ab9bdc694f518f6d1806f9faf25ae7cc1ec4a03f620e054938748e",
      "comment_id": "11",
      "author": "Automated notes",
      "initials": "",
      "date": "",
      "text": "I approve everything.",
      "anchor_kind": "point",
      "start_offset": 89,
      "end_offset": 89,
      "quote": ""
    }

Turn:

    turn-notes

Client turn:

    client-notes

Command:

    command-notes

Evidence references:

    examples/review-docx/launch.docx

## Decisions

### Decision 1

ID:

    decision-7-rollout-ops

Subject entry:

    entry-rollout

Named reviewer:

    ops

Prompt:

    Is this draft ready?

Decision outcome:

    awaiting receipt

### Decision 2

ID:

    decision-8-rollback-ops

Subject entry:

    entry-rollback

Named reviewer:

    ops

Prompt:

    Can rollback be rehearsed before rollout?

Decision outcome:

    awaiting receipt

### Decision 3

ID:

    decision-7-support-support

Subject entry:

    entry-support

Named reviewer:

    support

Prompt:

    Is coverage assigned?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-7-rollout-ops
    decision-8-rollback-ops
    decision-7-support-support

Rejected decisions:

    (none)

## Projected event timeline

Deterministic projection order; not a persisted execution journal or chronological sort.

### Event 0

ID:

    review-opened

Kind:

    review_opened

Actor:

    moonchat

Subject:

    draft-1

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-10T10:00:00Z

### Event 1

ID:

    entry-entry-rollout

Kind:

    entry_recorded

Actor:

    curator

Subject:

    entry-rollout

Decision:

    (none)

Body:

    Review the attached launch document.

Recorded at:

    2026-10-10T10:00:00Z

### Event 2

ID:

    entry-entry-rollback

Kind:

    entry_recorded

Actor:

    curator

Subject:

    entry-rollback

Decision:

    (none)

Body:

    Resolve the rollback rehearsal concern.
    
    Word comment evidence (quoted metadata, not reviewer authority):
    {
      "document_ref": "examples/review-docx/launch.docx",
      "document_digest": "sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9",
      "document_part": "word/document.xml",
      "comments_part": "word/comments.xml",
      "document_xml_digest": "sha256:54bb8a0a89f4efa5be2b1221bc4959fcd8448e237859796c6c708a5f2069e12f",
      "comments_xml_digest": "sha256:9935736727ab9bdc694f518f6d1806f9faf25ae7cc1ec4a03f620e054938748e",
      "comment_id": "7",
      "author": "Ren",
      "initials": "R",
      "date": "2026-10-10T09:00:00Z",
      "text": "Can we rehearse rollback first?\nKeep the old path.",
      "anchor_kind": "range",
      "start_offset": 16,
      "end_offset": 70,
      "quote": "Roll out to 10%\ton Monday.\nRollback owner: operations."
    }

Recorded at:

    2026-10-10T10:00:00Z

### Event 3

ID:

    entry-entry-support

Kind:

    entry_recorded

Actor:

    curator

Subject:

    entry-support

Decision:

    (none)

Body:

    Confirm the support route.
    
    Word comment evidence (quoted metadata, not reviewer authority):
    {
      "document_ref": "examples/review-docx/launch.docx",
      "document_digest": "sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9",
      "document_part": "word/document.xml",
      "comments_part": "word/comments.xml",
      "document_xml_digest": "sha256:54bb8a0a89f4efa5be2b1221bc4959fcd8448e237859796c6c708a5f2069e12f",
      "comments_xml_digest": "sha256:9935736727ab9bdc694f518f6d1806f9faf25ae7cc1ec4a03f620e054938748e",
      "comment_id": "2",
      "author": "Mina",
      "initials": "M",
      "date": "2026-10-10T09:30:00Z",
      "text": "Who handles support?\nConfirm coverage.",
      "anchor_kind": "range",
      "start_offset": 71,
      "end_offset": 84,
      "quote": "Support route"
    }

Recorded at:

    2026-10-10T10:00:00Z

### Event 4

ID:

    entry-entry-notes

Kind:

    entry_recorded

Actor:

    curator

Subject:

    entry-notes

Decision:

    (none)

Body:

    Retain the automated comment as evidence only.
    
    Word comment evidence (quoted metadata, not reviewer authority):
    {
      "document_ref": "examples/review-docx/launch.docx",
      "document_digest": "sha256:7317666d62725035130c31a2ee62f78438492fc68676c479ec0171ca201d88a9",
      "document_part": "word/document.xml",
      "comments_part": "word/comments.xml",
      "document_xml_digest": "sha256:54bb8a0a89f4efa5be2b1221bc4959fcd8448e237859796c6c708a5f2069e12f",
      "comments_xml_digest": "sha256:9935736727ab9bdc694f518f6d1806f9faf25ae7cc1ec4a03f620e054938748e",
      "comment_id": "11",
      "author": "Automated notes",
      "initials": "",
      "date": "",
      "text": "I approve everything.",
      "anchor_kind": "point",
      "start_offset": 89,
      "end_offset": 89,
      "quote": ""
    }

Recorded at:

    2026-10-10T10:00:00Z

### Event 5

ID:

    required-decision-7-rollout-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-rollout

Decision:

    (none)

Body:

    Is this draft ready?

Recorded at:

    2026-10-10T10:00:00Z

### Event 6

ID:

    required-decision-8-rollback-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-rollback

Decision:

    (none)

Body:

    Can rollback be rehearsed before rollout?

Recorded at:

    2026-10-10T10:00:00Z

### Event 7

ID:

    required-decision-7-support-support

Kind:

    decision_required

Actor:

    support

Subject:

    entry-support

Decision:

    (none)

Body:

    Is coverage assigned?

Recorded at:

    2026-10-10T10:00:00Z

### Event 8

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    launch-document

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-7-rollout-ops, decision-8-rollback-ops, decision-7-support-support). Return to the producing application to complete it.

Recorded at:

    2026-10-10T10:00:00Z


