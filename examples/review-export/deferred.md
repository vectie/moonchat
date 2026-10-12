# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    release-review

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (release-decision). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-export/source.md

Source SHA-256:

    sha256:d090cceea7b11d01416a320b07eadeaa9c4247695ee9fa754d6f6f0acc8324d4

Source revision:

    revision-1

Previous bundle:

    (none)

Previous bundle SHA-256:

    (none)

Conversation:

    release-room

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moontown.collaboration-review.v1

Product:

    moontown

Recorded at:

    2026-10-08T12:00:00Z

## Participants

### Participant 1

Name:

    Fixture collaborator

ID:

    fixture-agent

Kind:

    agent

### Participant 2

Name:

    Fixture reviewer

ID:

    fixture-human

Kind:

    human

## Conversation entries

### Entry 1

ID:

    release-proposal

Kind:

    proposal

Author:

    fixture-agent

Body:

    Ship the café search fix. 🌙
    Check the literal example:
    ```
    query = café
    ```

Turn:

    turn-1

Client turn:

    client-1

Command:

    command-1

Evidence references:

    evidence/unicode-test.txt

## Decisions

### Decision 1

ID:

    release-decision

Subject entry:

    release-proposal

Named reviewer:

    fixture-human

Prompt:

    Is this exact release source ready to hand off?

Decision outcome:

    defer

Receipt:

    fixture-deferred

Reviewer name:

    Fixture reviewer

Reviewer ID:

    fixture-human

Rationale:

    Synthetic example only; no real review authority.
    Outcome: defer

Receipt source SHA-256:

    sha256:d090cceea7b11d01416a320b07eadeaa9c4247695ee9fa754d6f6f0acc8324d4

Decided at:

    2026-10-08T12:05:00Z

Receipt evidence references:

    evidence/unicode-test.txt

Missing decisions:

    release-decision

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

    revision-1

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-08T12:00:00Z

### Event 1

ID:

    entry-release-proposal

Kind:

    entry_recorded

Actor:

    fixture-agent

Subject:

    release-proposal

Decision:

    (none)

Body:

    Ship the café search fix. 🌙
    Check the literal example:
    ```
    query = café
    ```

Recorded at:

    2026-10-08T12:00:00Z

### Event 2

ID:

    required-release-decision

Kind:

    decision_required

Actor:

    fixture-human

Subject:

    release-proposal

Decision:

    (none)

Body:

    Is this exact release source ready to hand off?

Recorded at:

    2026-10-08T12:00:00Z

### Event 3

ID:

    receipt-fixture-deferred

Kind:

    human_decision_recorded

Actor:

    fixture-human

Subject:

    release-decision

Decision:

    defer

Body:

    Synthetic example only; no real review authority.
    Outcome: defer

Recorded at:

    2026-10-08T12:05:00Z

### Event 4

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    release-review

Decision:

    pending_review

Body:

    A named-human decision is still needed (release-decision). Return to the producing application to complete it.

Recorded at:

    2026-10-08T12:00:00Z


