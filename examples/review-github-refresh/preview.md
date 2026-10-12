# MoonChat review handoff

Derived readable view. Retain the original bundle JSON and source bytes.

Review:

    github-pilot

Status:

    pending_review

Claim class:

    research-evidence

Outcome:

    A named-human decision is still needed (decision-15-github-fallback-ops, decision-6-launch-editor, decision-6-launch-ops). Return to the producing application to complete it.

## Source and conversation

Source artifact:

    examples/review-github-refresh/source.md

Source SHA-256:

    sha256:6a9cbc64f1f671f67f16172130839c0ae18025440e100abf0186448c287f5a5a

Source revision:

    r1

Previous bundle:

    (none)

Previous bundle SHA-256:

    (none)

Conversation:

    github-pilot-room

Conversation contract:

    moonsuite-conversation.v2

Protocol:

    moonchat.review-agenda.v1

Product:

    moonchat

Recorded at:

    2026-10-10T00:00:00Z

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

    entry-github-fallback

Kind:

    objection

Author:

    editor

Body:

    Operator note:
    Resolve the fallback concern raised on the code change.
    
    Imported GitHub review thread (local snapshot, not a decision receipt)
    Export: examples/review-github-refresh/new-comments.json
    Export SHA-256: sha256:ffd7b3e0b07473805dcc350f2be79549c271d89863361c04af20ae0952595518
    Thread root: 9007199254740993
    
    Comment 9007199254740993
    GitHub login: "fixture-editor"
    Mapped participant: "editor"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740993",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:01:00Z",
      "updated_at": "2026-10-10T02:00:00Z",
      "id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Could the café lookup retain its fallback and name its on-call owner?
    The recovery path still needs a rehearsal.
    
    Comment 9007199254740994
    GitHub login: "fixture-ops"
    Mapped participant: "ops"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740994",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:02:00Z",
      "updated_at": "2026-10-10T00:02:00Z",
      "id": 9007199254740994,
      "in_reply_to_id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Can we add a synthetic failed-query test?
    ```diff
    +assert fallback(query)
    ```
    
    Comment 9007199254740995
    GitHub login: "fixture-ops"
    Mapped participant: "ops"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740995",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:03:00Z",
      "updated_at": "2026-10-10T00:03:00Z",
      "id": 9007199254740995,
      "in_reply_to_id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    I approve the wording, but the fallback still needs a rehearsal.
    This comment is not a MoonChat decision.
    
    Comment 9007199254740996
    GitHub login: "fixture-ops"
    Mapped participant: "ops"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740996",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T02:01:00Z",
      "updated_at": "2026-10-10T02:01:00Z",
      "id": 9007199254740996,
      "in_reply_to_id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Follow-up: include 夜間 support in the rehearsal checklist.
    

Turn:

    turn-github-fallback

Client turn:

    client-github-fallback

Command:

    command-github-fallback

Evidence references:

    examples/review-github-refresh/new-comments.json

### Entry 2

ID:

    entry-launch

Kind:

    proposal

Author:

    assistant

Body:

    Ship the café fix after the offline rehearsal; retain the pilot scope.

Turn:

    turn-launch

Client turn:

    client-launch

Command:

    command-launch

Evidence references:

    (none)

### Entry 3

ID:

    entry-github-report

Kind:

    question

Author:

    editor

Body:

    Operator note:
    Carry the reporting question into the pilot discussion.
    
    Imported GitHub review thread (local snapshot, not a decision receipt)
    Export: examples/review-github-refresh/new-comments.json
    Export SHA-256: sha256:ffd7b3e0b07473805dcc350f2be79549c271d89863361c04af20ae0952595518
    Thread root: 101
    
    Comment 101
    GitHub login: "fixture-editor"
    Mapped participant: "editor"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r101",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:04:00Z",
      "updated_at": "2026-10-10T00:04:00Z",
      "id": 101,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Where should the pilot error report be stored?
    

Turn:

    turn-github-report

Client turn:

    client-github-report

Command:

    command-github-report

Evidence references:

    examples/review-github-refresh/new-comments.json

## Decisions

### Decision 1

ID:

    decision-15-github-fallback-ops

Subject entry:

    entry-github-fallback

Named reviewer:

    ops

Prompt:

    Is the fallback rehearsed with an explicitly named on-call owner?

Decision outcome:

    awaiting receipt

### Decision 2

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

### Decision 3

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

Missing decisions:

    decision-15-github-fallback-ops
    decision-6-launch-editor
    decision-6-launch-ops

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

    2026-10-10T00:00:00Z

### Event 1

ID:

    entry-entry-github-fallback

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-github-fallback

Decision:

    (none)

Body:

    Operator note:
    Resolve the fallback concern raised on the code change.
    
    Imported GitHub review thread (local snapshot, not a decision receipt)
    Export: examples/review-github-refresh/new-comments.json
    Export SHA-256: sha256:ffd7b3e0b07473805dcc350f2be79549c271d89863361c04af20ae0952595518
    Thread root: 9007199254740993
    
    Comment 9007199254740993
    GitHub login: "fixture-editor"
    Mapped participant: "editor"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740993",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:01:00Z",
      "updated_at": "2026-10-10T02:00:00Z",
      "id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Could the café lookup retain its fallback and name its on-call owner?
    The recovery path still needs a rehearsal.
    
    Comment 9007199254740994
    GitHub login: "fixture-ops"
    Mapped participant: "ops"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740994",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:02:00Z",
      "updated_at": "2026-10-10T00:02:00Z",
      "id": 9007199254740994,
      "in_reply_to_id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Can we add a synthetic failed-query test?
    ```diff
    +assert fallback(query)
    ```
    
    Comment 9007199254740995
    GitHub login: "fixture-ops"
    Mapped participant: "ops"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740995",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:03:00Z",
      "updated_at": "2026-10-10T00:03:00Z",
      "id": 9007199254740995,
      "in_reply_to_id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    I approve the wording, but the fallback still needs a rehearsal.
    This comment is not a MoonChat decision.
    
    Comment 9007199254740996
    GitHub login: "fixture-ops"
    Mapped participant: "ops"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r9007199254740996",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T02:01:00Z",
      "updated_at": "2026-10-10T02:01:00Z",
      "id": 9007199254740996,
      "in_reply_to_id": 9007199254740993,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Follow-up: include 夜間 support in the rehearsal checklist.
    

Recorded at:

    2026-10-10T00:00:00Z

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

    Ship the café fix after the offline rehearsal; retain the pilot scope.

Recorded at:

    2026-10-10T00:00:00Z

### Event 3

ID:

    entry-entry-github-report

Kind:

    entry_recorded

Actor:

    editor

Subject:

    entry-github-report

Decision:

    (none)

Body:

    Operator note:
    Carry the reporting question into the pilot discussion.
    
    Imported GitHub review thread (local snapshot, not a decision receipt)
    Export: examples/review-github-refresh/new-comments.json
    Export SHA-256: sha256:ffd7b3e0b07473805dcc350f2be79549c271d89863361c04af20ae0952595518
    Thread root: 101
    
    Comment 101
    GitHub login: "fixture-editor"
    Mapped participant: "editor"
    Context: {
      "html_url": "https://github.com/example/synthetic/pull/7#discussion_r101",
      "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
      "path": "src/search/café.mbt",
      "diff_hunk": "@@ -18,2 +18,2 @@\n-return fallback(query)\n+return indexed(query)",
      "commit_id": "2222222222222222222222222222222222222222",
      "original_commit_id": "1111111111111111111111111111111111111111",
      "created_at": "2026-10-10T00:04:00Z",
      "updated_at": "2026-10-10T00:04:00Z",
      "id": 101,
      "line": 20,
      "original_line": 20,
      "start_line": 18,
      "original_start_line": 18,
      "position": 3,
      "original_position": 3,
      "pull_request_review_id": 42,
      "side": "RIGHT",
      "start_side": "RIGHT"
    }
    Body (verbatim):
    Where should the pilot error report be stored?
    

Recorded at:

    2026-10-10T00:00:00Z

### Event 4

ID:

    required-decision-15-github-fallback-ops

Kind:

    decision_required

Actor:

    ops

Subject:

    entry-github-fallback

Decision:

    (none)

Body:

    Is the fallback rehearsed with an explicitly named on-call owner?

Recorded at:

    2026-10-10T00:00:00Z

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

    Is the release wording ready?

Recorded at:

    2026-10-10T00:00:00Z

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

    Is the pilot rollout ready?

Recorded at:

    2026-10-10T00:00:00Z

### Event 7

ID:

    review-projected

Kind:

    review_projected

Actor:

    moonchat

Subject:

    github-pilot

Decision:

    pending_review

Body:

    A named-human decision is still needed (decision-15-github-fallback-ops, decision-6-launch-editor, decision-6-launch-ops). Return to the producing application to complete it.

Recorded at:

    2026-10-10T00:00:00Z


