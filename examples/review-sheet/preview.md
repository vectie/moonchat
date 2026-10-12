# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    cafe-pilot-sheet

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-6-launch-editor, decision-6-launch-ops, decision-8-rollback-ops, decision-8-capacity-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-sheet/source.md

Source SHA-256:

    sha256:71a0904f2c7481f50db7e539b8d8ee7158aaebd7a094d44c64be8ddb481ab1a8

Source revision:

    pilot-r1

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

    2026-10-08T21:00:00Z

## Participants

### Participant 1

Name:

    Fixture assistant

ID:

    assistant

Kind:

    agent

### Participant 2

Name:

    Fixture editor

ID:

    editor

Kind:

    human

### Participant 3

Name:

    Fixture operations lead

ID:

    ops

Kind:

    human

## Conversation entries

### Entry 1

ID:

    entry-support

Kind:

    question

Author:

    editor

Body:

    Who will triage the pilot queue, and when?

Turn:

    turn-support

Client turn:

    client-support

Command:

    command-support

Evidence references:

    pilot/support-notes.md

### Entry 2

ID:

    entry-launch

Kind:

    proposal

Author:

    assistant

Body:

    Ship the café search fix to the pilot group on Monday.
    Cap the pilot at 25 users; show the "send feedback" link.

Turn:

    turn-launch

Client turn:

    client-launch

Command:

    command-launch

Evidence references:

    pilot/wording.md
    pilot/capacity.md

### Entry 3

ID:

    entry-rollback

Kind:

    objection

Author:

    ops

Body:

    Name the on-call rollback owner before inviting pilot users.

Turn:

    turn-rollback

Client turn:

    client-rollback

Command:

    command-rollback

Evidence references:

    pilot/rollback.md

### Entry 4

ID:

    entry-capacity

Kind:

    objection

Author:

    editor

Body:

    The support team has only one person available for the first hour.

Turn:

    turn-capacity

Client turn:

    client-capacity

Command:

    command-capacity

Evidence references:

    (none)

## Decisions

### Decision 1

ID:

    decision-6-launch-editor

Subject entry:

    entry-launch

Named reviewer:

    editor

Prompt:

    Is the pilot wording clear?

Decision outcome:

    awaiting receipt

### Decision 2

ID:

    decision-6-launch-ops

Subject entry:

    entry-launch

Named reviewer:

    ops

Prompt:

    Is a 25-user pilot manageable?

Decision outcome:

    awaiting receipt

### Decision 3

ID:

    decision-8-rollback-ops

Subject entry:

    entry-rollback

Named reviewer:

    ops

Prompt:

    Is a rollback owner available for the first hour?

Decision outcome:

    awaiting receipt

### Decision 4

ID:

    decision-8-capacity-ops

Subject entry:

    entry-capacity

Named reviewer:

    ops

Prompt:

    Can the pilot fit the support capacity?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-6-launch-editor
    decision-6-launch-ops
    decision-8-rollback-ops
    decision-8-capacity-ops

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

    pilot-r1

Decision:

    (none)

Body:

    Review opened for immutable source evidence.

Recorded at:

    2026-10-08T21:00:00Z

### Event 1

ID:

    entry-entry-support

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-support

Decision:

    (none)

Body:

    Who will triage the pilot queue, and when?

Recorded at:

    2026-10-08T21:00:00Z

### Event 2

ID:

    entry-entry-launch

Kind:

    entry_recorded

Actor:

    assistant

Subject:

    entry-launch

Decision:

    (none)

Body:

    Ship the café search fix to the pilot group on Monday.
    Cap the pilot at 25 users; show the "send feedback" link.

Recorded at:

    2026-10-08T21:00:00Z

### Event 3

ID:

    entry-entry-rollback

Kind:

    entry_recorded

Actor:

    ops

Subject:

    entry-rollback

Decision:

    (none)

Body:

    Name the on-call rollback owner before inviting pilot users.

Recorded at:

    2026-10-08T21:00:00Z

### Event 4

ID:

    entry-entry-capacity

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-capacity

Decision:

    (none)

Body:

    The support team has only one person available for the first hour.

Recorded at:

    2026-10-08T21:00:00Z

### Event 5

ID:

    required-decision-6-launch-editor

Kind:

    decision_required

Actor:

    editor

Subject:

    entry-launch

Decision:

    (none)

Body:

    Is the pilot wording clear?

Recorded at:

    2026-10-08T21:00:00Z

### Event 6

ID:

    required-decision-6-launch-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-launch

Decision:

    (none)

Body:

    Is a 25-user pilot manageable?

Recorded at:

    2026-10-08T21:00:00Z

### Event 7

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

    Is a rollback owner available for the first hour?

Recorded at:

    2026-10-08T21:00:00Z

### Event 8

ID:

    required-decision-8-capacity-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-capacity

Decision:

    (none)

Body:

    Can the pilot fit the support capacity?

Recorded at:

    2026-10-08T21:00:00Z

### Event 9

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    cafe-pilot-sheet

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-6-launch-editor, decision-6-launch-ops, decision-8-rollback-ops, decision-8-capacity-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-08T21:00:00Z


