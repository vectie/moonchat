# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    cafe-parallel-edit

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-6-launch-editor, decision-6-launch-ops, decision-8-rollback-ops, decision-8-coverage-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-sheet-merge/source.md

Source SHA-256:

    sha256:4ca2cbd21baa77d38285bb4cac4f1f2ed54937972fb232281448ddbdc6d9941e

Source revision:

    pilot-r1

Previous bundle:

    (none)

Previous bundle SHA-256:

    (none)

Conversation:

    cafe-parallel-room

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moonchat.review-agenda.v1

Product:

    moonchat

Recorded at:

    2026-10-10T11:00:00Z

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

    Where should support collect failed searches?

Turn:

    turn-support

Client turn:

    client-support

Command:

    command-support

Evidence references:

    (none)

### Entry 2

ID:

    entry-launch

Kind:

    proposal

Author:

    assistant

Body:

    Stage the café search fix for ten pilot teams.
    Keep the "rollback" owner on call.

Turn:

    turn-launch

Client turn:

    client-launch

Command:

    command-launch

Evidence references:

    pilot/rollout-checklist.md
    pilot/support-notes.md

### Entry 3

ID:

    entry-rollback

Kind:

    objection

Author:

    assistant

Body:

    The rollback owner and backup still need names.

Turn:

    turn-rollback

Client turn:

    client-rollback

Command:

    command-rollback

Evidence references:

    (none)

### Entry 4

ID:

    entry-pilot-size

Kind:

    question

Author:

    editor

Body:

    Should the second cohort wait for the first-day report?

Turn:

    turn-pilot-size

Client turn:

    client-pilot-size

Command:

    command-pilot-size

Evidence references:

    (none)

### Entry 5

ID:

    entry-coverage

Kind:

    objection

Author:

    ops

Body:

    The Tuesday backup shift is uncovered.

Turn:

    turn-coverage

Client turn:

    client-coverage

Command:

    command-coverage

Evidence references:

    pilot/staffing.md

## Decisions

### Decision 1

ID:

    decision-6-launch-editor

Subject entry:

    entry-launch

Named reviewer:

    editor

Prompt:

    Does the announcement state the pilot limit clearly?

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

    Is the staged rollout staffed for Monday?

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

### Decision 4

ID:

    decision-8-coverage-ops

Subject entry:

    entry-coverage

Named reviewer:

    ops

Prompt:

    Is backup coverage sufficient?

Decision outcome:

    awaiting receipt

Missing decisions:

    decision-6-launch-editor
    decision-6-launch-ops
    decision-8-rollback-ops
    decision-8-coverage-ops

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

    2026-10-10T11:00:00Z

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

    Where should support collect failed searches?

Recorded at:

    2026-10-10T11:00:00Z

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

    Stage the café search fix for ten pilot teams.
    Keep the "rollback" owner on call.

Recorded at:

    2026-10-10T11:00:00Z

### Event 3

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

    The rollback owner and backup still need names.

Recorded at:

    2026-10-10T11:00:00Z

### Event 4

ID:

    entry-entry-pilot-size

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-pilot-size

Decision:

    (none)

Body:

    Should the second cohort wait for the first-day report?

Recorded at:

    2026-10-10T11:00:00Z

### Event 5

ID:

    entry-entry-coverage

Kind:

    entry_recorded

Actor:

    ops

Subject:

    entry-coverage

Decision:

    (none)

Body:

    The Tuesday backup shift is uncovered.

Recorded at:

    2026-10-10T11:00:00Z

### Event 6

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

    Does the announcement state the pilot limit clearly?

Recorded at:

    2026-10-10T11:00:00Z

### Event 7

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

    Is the staged rollout staffed for Monday?

Recorded at:

    2026-10-10T11:00:00Z

### Event 8

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

    2026-10-10T11:00:00Z

### Event 9

ID:

    required-decision-8-coverage-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-coverage

Decision:

    (none)

Body:

    Is backup coverage sufficient?

Recorded at:

    2026-10-10T11:00:00Z

### Event 10

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    cafe-parallel-edit

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-6-launch-editor, decision-6-launch-ops, decision-8-rollback-ops, decision-8-coverage-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-10T11:00:00Z


