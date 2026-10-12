# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    cafe-release

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-6-launch-editor, decision-6-launch-ops, decision-8-rollback-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-agenda/source.md

Source SHA-256:

    sha256:f16ed8766b8b89b1cb1bc2154d6e5d57214c7521cbdcde79c31ed97fc4572d27

Source revision:

    r1

Previous bundle:

    examples/review-agenda/review.json

Previous bundle SHA-256:

    sha256:fd02bfbc2b493369d7c7fd22e94cb81eb054f252dc3d28ba3db33ef229d95411

Conversation:

    cafe-release-room

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

    entry-launch

Kind:

    proposal

Author:

    assistant

Body:

    Ship the café search fix to the pilot group on Tuesday, after the support briefing.

Turn:

    turn-launch

Client turn:

    client-launch

Command:

    command-launch

Evidence references:

    (none)

### Entry 2

ID:

    entry-rollback

Kind:

    objection

Author:

    assistant

Body:

    The source does not name a rollback owner.

Turn:

    turn-rollback

Client turn:

    client-rollback

Command:

    command-rollback

Evidence references:

    (none)

### Entry 3

ID:

    entry-support

Kind:

    question

Author:

    editor

Body:

    Where should support collect failed searches?

Turn:

    turn-support

Client turn:

    client-support

Command:

    command-support

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

    Is the release wording ready?

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

    Is the pilot rollout ready?

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

    Is rollback ownership adequately covered?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-6-launch-editor
    decision-6-launch-ops
    decision-8-rollback-ops

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

    Ship the café search fix to the pilot group on Tuesday, after the support briefing.

Recorded at:

    2026-10-08T12:00:00Z

### Event 2

ID:

    entry-entry-rollback

Kind:

    entry_recorded

Actor:

    assistant

Subject:

    entry-rollback

Decision:

    (none)

Body:

    The source does not name a rollback owner.

Recorded at:

    2026-10-08T12:00:00Z

### Event 3

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

    Where should support collect failed searches?

Recorded at:

    2026-10-08T12:00:00Z

### Event 4

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

    Is the release wording ready?

Recorded at:

    2026-10-08T12:00:00Z

### Event 5

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

    Is the pilot rollout ready?

Recorded at:

    2026-10-08T12:00:00Z

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

    Is rollback ownership adequately covered?

Recorded at:

    2026-10-08T12:00:00Z

### Event 7

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    cafe-release

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-6-launch-editor, decision-6-launch-ops, decision-8-rollback-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-08T12:00:00Z


