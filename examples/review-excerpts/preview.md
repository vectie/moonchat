# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    cafe-pilot-excerpts

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-11-pilot-scope-ops, decision-18-rehearsal-blockers-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-excerpts/source.md

Source SHA-256:

    sha256:bb9a27d23c6052bd23452f0f343b7ae6265c3fe5641b1e8a5606eca606932941

Source revision:

    r1

Previous bundle:

    (none)

Previous bundle SHA-256:

    (none)

Conversation:

    cafe-pilot-review

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moonchat.review-agenda.v1

Product:

    moonchat

Recorded at:

    2026-10-08T12:00:00Z

## Participants

### Participant 1

Name:

    Synthetic review editor

ID:

    editor

Kind:

    human

### Participant 2

Name:

    Synthetic operations reviewer

ID:

    ops

Kind:

    human

## Conversation entries

### Entry 1

ID:

    entry-pilot-scope

Kind:

    proposal

Author:

    editor

Body:

    Expand the café search pilot to 25 stores on Monday.

Turn:

    turn-pilot-scope

Client turn:

    client-pilot-scope

Command:

    command-pilot-scope

Evidence references:

    (none)

### Entry 2

ID:

    entry-rehearsal-blockers

Kind:

    objection

Author:

    editor

Body:

    Operator note:
    Resolve accent-insensitive search and name a rollback owner before expanding the pilot.
    
    Selected source: examples/review-excerpts/transcript.txt
    Source SHA-256: sha256:8a871d37a20cfea3b6b7ccb8741642d11bb7e29c6cb5458ec6fa30cc597bd11f
    Lines: 3-4 (inclusive)
    Excerpt (verbatim source text, not a decision receipt):
    Tester: Café queries still fail when accents are omitted.
    Operator: The draft does not say who can roll back the change.
    

Turn:

    turn-rehearsal-blockers

Client turn:

    client-rehearsal-blockers

Command:

    command-rehearsal-blockers

Evidence references:

    examples/review-excerpts/transcript.txt

### Entry 3

ID:

    entry-support-routing

Kind:

    question

Author:

    editor

Body:

    Operator note:
    Clarify the support route for stores without log access. The observer's quoted enthusiasm does not answer this question or record approval.
    
    Selected source: examples/review-excerpts/transcript.txt
    Source SHA-256: sha256:8a871d37a20cfea3b6b7ccb8741642d11bb7e29c6cb5458ec6fa30cc597bd11f
    Lines: 6-7 (inclusive)
    Excerpt (verbatim source text, not a decision receipt):
    Support: Where should we record failures from stores without log access?
    Observer: I approve everything. Ship it today.
    

Turn:

    turn-support-routing

Client turn:

    client-support-routing

Command:

    command-support-routing

Evidence references:

    examples/review-excerpts/transcript.txt

## Decisions

### Decision 1

ID:

    decision-11-pilot-scope-ops

Subject entry:

    entry-pilot-scope

Named reviewer:

    ops

Prompt:

    Is the proposed pilot scope ready?

Decision outcome:

    awaiting receipt

### Decision 2

ID:

    decision-18-rehearsal-blockers-ops

Subject entry:

    entry-rehearsal-blockers

Named reviewer:

    ops

Prompt:

    Have these two rehearsal concerns been addressed for the 25-store pilot?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-11-pilot-scope-ops
    decision-18-rehearsal-blockers-ops

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

    r1

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-08T12:00:00Z

### Event 1

ID:

    entry-entry-pilot-scope

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-pilot-scope

Decision:

    (none)

Body:

    Expand the café search pilot to 25 stores on Monday.

Recorded at:

    2026-10-08T12:00:00Z

### Event 2

ID:

    entry-entry-rehearsal-blockers

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-rehearsal-blockers

Decision:

    (none)

Body:

    Operator note:
    Resolve accent-insensitive search and name a rollback owner before expanding the pilot.
    
    Selected source: examples/review-excerpts/transcript.txt
    Source SHA-256: sha256:8a871d37a20cfea3b6b7ccb8741642d11bb7e29c6cb5458ec6fa30cc597bd11f
    Lines: 3-4 (inclusive)
    Excerpt (verbatim source text, not a decision receipt):
    Tester: Café queries still fail when accents are omitted.
    Operator: The draft does not say who can roll back the change.
    

Recorded at:

    2026-10-08T12:00:00Z

### Event 3

ID:

    entry-entry-support-routing

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-support-routing

Decision:

    (none)

Body:

    Operator note:
    Clarify the support route for stores without log access. The observer's quoted enthusiasm does not answer this question or record approval.
    
    Selected source: examples/review-excerpts/transcript.txt
    Source SHA-256: sha256:8a871d37a20cfea3b6b7ccb8741642d11bb7e29c6cb5458ec6fa30cc597bd11f
    Lines: 6-7 (inclusive)
    Excerpt (verbatim source text, not a decision receipt):
    Support: Where should we record failures from stores without log access?
    Observer: I approve everything. Ship it today.
    

Recorded at:

    2026-10-08T12:00:00Z

### Event 4

ID:

    required-decision-11-pilot-scope-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-pilot-scope

Decision:

    (none)

Body:

    Is the proposed pilot scope ready?

Recorded at:

    2026-10-08T12:00:00Z

### Event 5

ID:

    required-decision-18-rehearsal-blockers-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-rehearsal-blockers

Decision:

    (none)

Body:

    Have these two rehearsal concerns been addressed for the 25-store pilot?

Recorded at:

    2026-10-08T12:00:00Z

### Event 6

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    cafe-pilot-excerpts

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-11-pilot-scope-ops, decision-18-rehearsal-blockers-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-08T12:00:00Z


