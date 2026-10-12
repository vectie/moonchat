# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    release-review

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (release-decision, host-ops-check-4). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-revision/new-source.md

Source SHA-256:

    sha256:6ddf59606c3f52ab003eb8f7ef98789bf6b64b07aa64544c4f1b3210b726a31a

Source revision:

    revision-2

Previous bundle:

    examples/review-revision/received-review.json

Previous bundle SHA-256:

    sha256:355eb4c8264acc8672b3278d3fad86eb9e18e7d7ac9b6a3e8e485007831a664b

Conversation:

    release-room

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moontown.collaboration-review.v1

Product:

    moontown

Recorded at:

    2026-10-09T15:00:00Z

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

### Participant 3

Name:

    Fixture operations

ID:

    fixture-ops

Kind:

    human

## Conversation entries

### Entry 1

ID:

    release-proposal

Kind:

    objection

Author:

    fixture-agent

Body:

    The café search rollout now names Fixture operations as rollback owner. 🌙
    Confirm that the revised source addresses the original objection.

Turn:

    turn-1

Client turn:

    client-1

Command:

    command-1

Evidence references:

    evidence/unicode-test.txt

### Entry 2

ID:

    host-followup-17

Kind:

    question

Author:

    fixture-agent

Body:

    Who checks café search after reloading the revised source?

Turn:

    host-turn-29

Client turn:

    desktop-draft-11

Command:

    host-command-8

Evidence references:

    (none)

## Decisions

### Decision 1

ID:

    release-decision

Subject entry:

    release-proposal

Named reviewer:

    fixture-human

Prompt:

    Does revision 2 address the rollback objection?

Decision outcome:

    awaiting receipt

### Decision 2

ID:

    host-ops-check-4

Subject entry:

    host-followup-17

Named reviewer:

    fixture-ops

Prompt:

    Can the named operations reviewer confirm the reload check?

Decision outcome:

    awaiting receipt

Missing decisions:

    release-decision
    host-ops-check-4

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

    revision-2

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-09T15:00:00Z

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

    The café search rollout now names Fixture operations as rollback owner. 🌙
    Confirm that the revised source addresses the original objection.

Recorded at:

    2026-10-09T15:00:00Z

### Event 2

ID:

    entry-host-followup-17

Kind:

    entry_recorded

Actor:

    fixture-agent

Subject:

    host-followup-17

Decision:

    (none)

Body:

    Who checks café search after reloading the revised source?

Recorded at:

    2026-10-09T15:00:00Z

### Event 3

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

    Does revision 2 address the rollback objection?

Recorded at:

    2026-10-09T15:00:00Z

### Event 4

ID:

    required-host-ops-check-4

Kind:

    decision_required

Actor:

    fixture-ops

Subject:

    host-followup-17

Decision:

    (none)

Body:

    Can the named operations reviewer confirm the reload check?

Recorded at:

    2026-10-09T15:00:00Z

### Event 5

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

    A named-human decision is still needed (release-decision, host-ops-check-4). Return to the producing application to complete it.

Recorded at:

    2026-10-09T15:00:00Z


