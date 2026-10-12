# MoonChat review comparison

Verified snapshots, compared by stable IDs. This report does not establish ancestry, transfer approval, or replace either retained bundle. Removed objections remain visible below.

Source artifact:

    examples/review-sheet/source.md

Before review:

    cafe-pilot-sheet

After review:

    cafe-pilot-sheet

Before revision:

    pilot-r1

After revision:

    pilot-r2

Before SHA-256:

    sha256:71a0904f2c7481f50db7e539b8d8ee7158aaebd7a094d44c64be8ddb481ab1a8

After SHA-256:

    sha256:bf8565779da3b521702b4bc29a8a3a70292359ad8b2ce0581f28d8fb62d58b4f

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

    examples/review-comparison/before.json
    sha256:46172cc9d95662aac4f821e7c717ebb333de33375e0b5ca7d29922f330e1a72d

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


