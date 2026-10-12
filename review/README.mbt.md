# Source-bound review authoring

The `vectie/moonchat/review` package offers pure authoring and portability APIs
for existing hosts. There is no separate Chat app or decision UI. All serialized
objects retain the existing `moonchat.conversation-review-bundle.v1` shape and
operation/schema versions.

## Draft, serialize, import and supersede

This executable example creates a pending review. Its named reviewer is fixture
data; no real human authority or decision is implied.

```mbt check
///|
test "host authors and supersedes a source-bound pending review" {
  let human : @review.ReviewParticipant = {
    participant_id: "named-reviewer",
    display_name: "Fixture reviewer",
    participant_kind: "human",
  }
  let question = @review.draft_review_entry(
    "question",
    entry_id="scope-question",
    author_participant_id="named-reviewer",
    turn={
      turn_id: "turn-scope",
      client_turn_id: "client-scope",
      command_id: "command-scope",
    },
    body="Is this frozen source ready for review?",
  )
  let requirement = @review.draft_required_decision(
    decision_id="scope-decision",
    subject_entry_id="scope-question",
    reviewer=human,
    prompt="Review the exact source and decide in the authorized host.",
  )
  let draft = @review.draft_review_bundle(
    review_id="source-review",
    source_artifact_ref="revisions/one/source-packet.json",
    source_bytes=b"{\"revision\":1}\n",
    source_revision_id="one",
    conversation={
      contract_id: @review.conversation_contract_id(),
      protocol: "moontown.collaboration-review.v1",
      product_id: "moontown",
      conversation_id: "source-review-room",
    },
    participants=[human],
    entries=[question],
    required_decisions=[requirement],
    recorded_at="2026-10-06T16:00:00Z",
  )
  let serialized = @review.serialize_review_bundle(draft, draft.source_digest)
  let imported = @review.reimport_review_bundle(
    serialized, b"{\"revision\":1}\n",
  )
  assert_eq(imported, draft)
  assert_eq(imported.decision_receipts, [])
  // A new comment on the same exact source can create a new review version.
  // New source bytes instead require a fresh draft with a new revision ID.
  let next = @review.supersede_review_bundle(
    serialized,
    previous_bundle_ref="revisions/one/review-bundle.json",
    previous_source_bytes=b"{\"revision\":1}\n",
    next_bundle=draft,
    next_source_bytes=b"{\"revision\":1}\n",
  )
  assert_eq(next.decision_receipts, [])
  assert_eq(@review.review_status(next), "pending_review")
  assert_eq(
    next.previous_bundle_digest,
    @review.review_source_digest(@utf8.encode(serialized)),
  )
  assert_eq(draft.previous_bundle_ref, "")
}
```

`draft_review_entry` accepts exactly `question`, `objection` or `proposal`.
`draft_required_decision` requires an explicit named human. The owner need not
be the objection author; an agent's objection can require a different human's
decision. Final bundle validation rejects unknown participants, uncovered
objections, missing decisions and inconsistent turn identities.

Authoring returns detached arrays and never creates a receipt. Existing receipt
serialization/import preserves history. Supersession requires a fresh pending
draft, validates both observed sources, and binds the exact original serialized
predecessor bytes. It does not reserialize or alter the predecessor. Review and
conversation identity stay stable. Different source bytes require a different
source revision identity, even if the source filename is reused.

## Host responsibilities

- Hash actual observed source bytes, not a supplied digest or filename
- Freeze the source packet and every referenced snapshot before exposing review
- When a packet contains constituent files, verify their digests at import,
  preview and export; MoonChat validates the main source only
- Retain exact prior bundle, source and snapshots at their original relative
  references; moving a bundle under `history/` does not rebase its references
- Store immutable versions and perform deterministic create-new retries
- Show source scope, unanswered questions, objections and named decision owners
- Obtain and verify real human authority in the existing authorized host before
  creating any later decision receipt; structural validation is not identity
  authentication
- Keep producer execution authority and MoonBook's acceptance independent

Town's collaboration composer consumes this library as a paired local workspace
member. Its export stays `pending_review`, with `decision_receipts: []`. Hosted
approve/reject/defer controls remain with existing decision owners such as
MoonFind; the composer does not duplicate them.

## Build the delivered pairing

Use sibling delivered source checkouts `moontown/` and `moonchat/`. Town declares
`vectie/moonchat@0.1.0` and its committed
`moon.work` contains `members = [".", "../moonchat"]`. Run builds and
tests from Town's module or its documented UI workspace. The workspace resolves
this delivered MoonChat source rather than an unpublished registry release.
Standalone Town development and CI must check out both source trees in this
layout; the registry's `0.1.0` alone does not contain the new authoring helpers.
The existing wire versions remain unchanged. Standalone library verification
can be run from this module with `moon test review --target js` and
`moon test --target native --strip -j 1`.

Declared direct library dependencies: `moonbitlang/async@0.20.2`,
`moonbitlang/x@0.4.50`, `vectie/moonlib@0.1.19`. `x` was upgraded from `0.4.46`
because that older source uses lexer syntax rejected by the verified
2026-09-20 toolchain. Generated `moon tree --json` and package graph evidence
record the actual resolved graph.

These are source-level guarantees. They do not qualify a live UI, accessibility,
real human decision, provider, publication or downstream company acceptance.
