# Selected candidate JSON edits

Draft content changes only. Every objection and named decision remains for fresh review.

Edit:

    disable-pending-review

Linked discussion entry:

    entry-scope

JSON Pointer (empty means root):

    /pilot/enabled

Expected typed value:

    true

Replacement typed value:

    false

Edit:

    bound-pilot

Linked discussion entry:

    entry-scope

JSON Pointer (empty means root):

    /pilot/max_users

Expected typed value:

    500

Replacement typed value:

    50

Edit:

    name-owner

Linked discussion entry:

    entry-owner

JSON Pointer (empty means root):

    /pilot/rollback_owner

Expected typed value:

    null

Replacement typed value:

    "Operations lead"

Edit:

    west-only

Linked discussion entry:

    entry-scope

JSON Pointer (empty means root):

    /regions

Expected typed value:

    [
      "west",
      "east"
    ]

Replacement typed value:

    [
      "west"
    ]

Complete candidate JSON:

    {
      "pilot": {
        "enabled": false,
        "max_users": 50,
        "rollback_owner": "Operations lead"
      },
      "regions": [
        "west"
      ],
      "allocation_id": 9007199254740993,
      "reference_ratio": 1.00000000000000001
    }


# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    pilot-config

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-5-scope-ops, decision-5-owner-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-json-edits/candidate-source.json

Source SHA-256:

    sha256:a0f0b7e0dd5701f875bbb86f706397de67969b77de58569a1402fb07309973a2

Source revision:

    r2

Previous bundle:

    examples/review-json-edits/review.json

Previous bundle SHA-256:

    sha256:87b94502e4e032a0f98bd204828c346f9d3b351d036741238faf81bcf471471b

Conversation:

    pilot-config-room

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moonchat.review-agenda.v1

Product:

    moonchat

Recorded at:

    2026-10-14T06:30:00Z

## Participants

### Participant 1

Name:

    Fixture editor

ID:

    editor

Kind:

    human

### Participant 2

Name:

    Fixture operations lead

ID:

    ops

Kind:

    human

## Conversation entries

### Entry 1

ID:

    entry-scope

Kind:

    objection

Author:

    editor

Body:

    The first pilot is too broad. Limit users and regions before review.

Turn:

    turn-scope

Client turn:

    client-scope

Command:

    command-scope

Evidence references:

    (none)

### Entry 2

ID:

    entry-owner

Kind:

    question

Author:

    editor

Body:

    Who owns rollback? Keep this question visible after editing.

Turn:

    turn-owner

Client turn:

    client-owner

Command:

    command-owner

Evidence references:

    (none)

## Decisions

### Decision 1

ID:

    decision-5-scope-ops

Subject entry:

    entry-scope

Named reviewer:

    ops

Prompt:

    Is the proposed pilot scope appropriate?

Decision outcome:

    awaiting receipt

### Decision 2

ID:

    decision-5-owner-ops

Subject entry:

    entry-owner

Named reviewer:

    ops

Prompt:

    Is rollback ownership adequately covered?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-5-scope-ops
    decision-5-owner-ops

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

    r2

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-14T06:30:00Z

### Event 1

ID:

    entry-entry-scope

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-scope

Decision:

    (none)

Body:

    The first pilot is too broad. Limit users and regions before review.

Recorded at:

    2026-10-14T06:30:00Z

### Event 2

ID:

    entry-entry-owner

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-owner

Decision:

    (none)

Body:

    Who owns rollback? Keep this question visible after editing.

Recorded at:

    2026-10-14T06:30:00Z

### Event 3

ID:

    required-decision-5-scope-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-scope

Decision:

    (none)

Body:

    Is the proposed pilot scope appropriate?

Recorded at:

    2026-10-14T06:30:00Z

### Event 4

ID:

    required-decision-5-owner-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-owner

Decision:

    (none)

Body:

    Is rollback ownership adequately covered?

Recorded at:

    2026-10-14T06:30:00Z

### Event 5

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    pilot-config

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-5-scope-ops, decision-5-owner-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-14T06:30:00Z
