# MoonChat review comparison

Verified snapshots, compared by stable IDs. This report does not establish ancestry, transfer approval, or replace either retained bundle. Removed objections remain visible below.

Source artifact:

    pilot/source.md

Before review:

    cafe-pilot-sheet

After review:

    cafe-pilot-sheet

Before revision:

    pilot-r1

After revision:

    pilot-r2

Before SHA-256:

    sha256:7e76dcb166cb34c67508861ca35c04d49be79d9ee3c10d1bcde3765e7dfeaabe

After SHA-256:

    sha256:8c8caa0343852d24e0a21959070d9ec4a5f31677216380c9b9a5bc13047d4856

Source bytes:

    changed; prior receipts cover only their original digest

Before status:

    pending_review

After status:

    pending_review

Before recorded at:

    2026-10-08T21:00:00Z

After recorded at:

    2026-10-08T21:00:00Z

Before previous bundle:

    
    

After previous bundle:

    examples/review-source-comparison/before.json
    sha256:e3b3f326adc008b53ef7ea95bf6b2149fcdeaecc2fd0a95aef697549e596d451

## Source text changes

13 before lines; 14 after lines; 3 added; 2 removed. Context: 1 unchanged lines per side.

Literal physical lines, including their terminators, are compared exactly. Rows show change (= context, - removed, + added), before line, after line, and a JSON string. Escapes expose tabs, CR/LF and controls; \uFEFF exposes a BOM. Empty sources have zero lines.

2 unchanged lines omitted.

### Source hunk 1

    change | before | after | exact line
    = | 3 | 3 | "Audience: invited pilot users.\n"
    - | 4 | - | "Traffic cap: all 100 invitees.\n"
    + | - | 4 | "Traffic cap: 25 users.\n"
    = | 5 | 5 | "Launch: Monday morning.\n"

5 unchanged lines omitted.

### Source hunk 2

    change | before | after | exact line
    = | 11 | 11 | "\n"
    - | 12 | - | "Rollback owner: not assigned.\n"
    + | - | 12 | "Rollback owner: operations lead.\n"
    + | - | 13 | "Fallback: pause invitations until the on-call owner is present.\n"
    = | 13 | 14 | "Rehearsal: complete before launch.\n"

## Participants

0 added; 0 changed; 0 removed; 3 unchanged.

## Typed entries and evidence

### Changed

ID:

    entry-launch

Before:

    Kind: proposal
    Author: assistant
    Turn: turn-launch
    Client turn: client-launch
    Command: command-launch
    Body:
    Ship the café search fix to the pilot group on Monday.
    Evidence references:
    

After:

    Kind: proposal
    Author: assistant
    Turn: turn-launch
    Client turn: client-launch
    Command: command-launch
    Body:
    Ship the café search fix to the pilot group on Monday.
    Cap the pilot at 25 users; show the "send feedback" link.
    Evidence references:
    pilot/wording.md
    pilot/capacity.md

### Changed

ID:

    entry-rollback

Before:

    Kind: objection
    Author: assistant
    Turn: turn-rollback
    Client turn: client-rollback
    Command: command-rollback
    Body:
    The source does not name a rollback owner.
    Evidence references:
    

After:

    Kind: objection
    Author: ops
    Turn: turn-rollback
    Client turn: client-rollback
    Command: command-rollback
    Body:
    Name the on-call rollback owner before inviting pilot users.
    Evidence references:
    pilot/rollback.md

### Changed

ID:

    entry-support

Before:

    Kind: question
    Author: editor
    Turn: turn-support
    Client turn: client-support
    Command: command-support
    Body:
    Where should support collect failed searches?
    Evidence references:
    

After:

    Kind: question
    Author: editor
    Turn: turn-support
    Client turn: client-support
    Command: command-support
    Body:
    Who will triage the pilot queue, and when?
    Evidence references:
    pilot/support-notes.md

### Added

ID:

    entry-capacity

After:

    Kind: objection
    Author: editor
    Turn: turn-capacity
    Client turn: client-capacity
    Command: command-capacity
    Body:
    The support team has only one person available for the first hour.
    Evidence references:
    

1 added; 3 changed; 0 removed; 0 unchanged.

Before order:

    entry-launch
    entry-rollback
    entry-support

After order:

    entry-support
    entry-launch
    entry-rollback
    entry-capacity

## Required decisions

### Changed

ID:

    decision-6-launch-editor

Before:

    Subject: entry-launch
    Reviewer: editor
    Prompt:
    Is the release wording ready?

After:

    Subject: entry-launch
    Reviewer: editor
    Prompt:
    Is the pilot wording clear?

### Changed

ID:

    decision-6-launch-ops

Before:

    Subject: entry-launch
    Reviewer: ops
    Prompt:
    Is the pilot rollout ready?

After:

    Subject: entry-launch
    Reviewer: ops
    Prompt:
    Is a 25-user pilot manageable?

### Changed

ID:

    decision-8-rollback-ops

Before:

    Subject: entry-rollback
    Reviewer: ops
    Prompt:
    Is rollback ownership adequately covered?

After:

    Subject: entry-rollback
    Reviewer: ops
    Prompt:
    Is a rollback owner available for the first hour?

### Added

ID:

    decision-8-capacity-ops

After:

    Subject: entry-capacity
    Reviewer: ops
    Prompt:
    Can the pilot fit the support capacity?

1 added; 3 changed; 0 removed; 0 unchanged.

Before order:

    decision-6-launch-editor
    decision-6-launch-ops
    decision-8-rollback-ops

After order:

    decision-6-launch-editor
    decision-6-launch-ops
    decision-8-rollback-ops
    decision-8-capacity-ops

## Decision receipts

0 added; 0 changed; 0 removed; 0 unchanged.


