///|
fn revision_fixture() -> (String, @review.ConversationReviewBundle) raise {
  let previous = authored_bundle()
  previous.decision_receipts.push(fixture_receipt(previous, "reject"))
  // Two distinct questions for the same reviewer are valid host data; an
  // agenda compiler's generated key/reviewer IDs cannot represent this shape.
  previous.required_decisions.push({
    decision_id: "another-host-request",
    subject_entry_id: "objection",
    reviewer_participant_id: "accountable-human",
    prompt: "Has the explicit rollback owner been named?",
  })
  (
    "\n" + @review.serialize_review_bundle(previous, previous.source_digest),
    previous,
  )
}

///|
fn compile_revision_fixture(
  draft : @review.ReviewRevisionDraft,
  text : String,
  source? : Bytes = b"revision one\n",
) -> @review.ConversationReviewBundle raise {
  @review.compile_review_revision(
    draft,
    source,
    previous_bundle_text=text,
    previous_source_bytes=b"revision one\n",
    previous_bundle_ref="history/received-review.json",
  )
}

///|
test "reopen arbitrary host identities and duplicate reviewer requests without original agenda" {
  let (text, previous) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  assert_eq(draft.conversation, previous.conversation)
  assert_eq(draft.entries, previous.entries)
  assert_eq(draft.required_decisions, previous.required_decisions)
  assert_eq(draft.participants, previous.participants)
  assert_eq(
    draft.base_bundle_digest,
    @review.review_source_digest(@utf8.encode(text)),
  )
  assert_true(!draft.to_json().stringify().contains("decision_receipts"))
  let parsed = @review.parse_review_revision(
    draft.to_json().stringify(indent=2),
  )
  assert_true(parsed == draft)
  let revised = compile_revision_fixture(parsed, text)
  assert_eq(revised.conversation, previous.conversation)
  assert_eq(revised.entries, previous.entries)
  assert_eq(revised.required_decisions, previous.required_decisions)
  assert_eq(revised.previous_bundle_digest, draft.base_bundle_digest)
  assert_eq(revised.previous_bundle_ref, "history/received-review.json")
  assert_eq(revised.decision_receipts, [])
  assert_eq(@review.review_status(revised), "pending_review")
  assert_eq(@review.claim_class(revised), "research-evidence")
  assert_eq(@review.reimport_review_bundle(text, b"revision one\n"), previous)
  assert_eq(compile_revision_fixture(draft, text), revised)
}

///|
test "revise discussion add remove reorder and reassign decisions while retaining prior dissent" {
  let (text, previous) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  let added = @review.draft_review_entry(
    "question",
    entry_id="host-new-followup",
    author_participant_id="collaborator-agent",
    turn={
      turn_id: "host-followup",
      client_turn_id: "web-321",
      command_id: "edit-42",
    },
    body="Who checks café search after reload? 🌙\nKeep the original evidence.",
    evidence_refs=["new/evidence.txt"],
  )
  let edited = {
    ..draft,
    source_artifact_ref: "revisions/two/source.md",
    source_revision_id: "revision-two",
    recorded_at: "2026-10-09T15:00:00Z",
    entries: [
      {
        ..draft.entries[1],
        body: "Revised objection: retain a named rollback owner.",
      },
      added,
      draft.entries[2],
    ],
    participants: [
      draft.participants[0],
      draft.participants[1],
      {
        participant_id: "ops",
        display_name: "Fixture operations",
        participant_kind: "human",
      },
    ],
    required_decisions: [
      {
        ..draft.required_decisions[0],
        prompt: "Is the revised rollout acceptable?",
      },
      { ..draft.required_decisions[1], reviewer_participant_id: "ops", },
    ],
  }
  let revised = compile_revision_fixture(edited, text, source=b"revision two\n")
  assert_eq(revised.entries.map(e => e.entry_id), [
    "objection", "host-new-followup", "proposal",
  ])
  assert_eq(revised.entries[0].turn, previous.entries[1].turn)
  assert_eq(revised.entries[1], added)
  assert_eq(revised.required_decisions[0].decision_id, "objection-decision")
  assert_eq(revised.required_decisions[1].reviewer_participant_id, "ops")
  assert_eq(
    revised.source_digest,
    @review.review_source_digest(b"revision two\n"),
  )
  assert_eq(revised.source_revision_id, "revision-two")
  assert_eq(previous.entries.length(), 3)
  assert_eq(
    previous.entries[1].body,
    "Explicit objection about the bound collaboration source.",
  )
  assert_eq(previous.decision_receipts[0].decision, "reject")
  assert_eq(@review.reimport_review_bundle(text, b"revision one\n"), previous)
  assert_eq(draft.entries[0].entry_id, "question")
  assert_eq(
    @review.reimport_review_bundle(
      @review.serialize_review_bundle(revised, revised.source_digest),
      b"revision two\n",
    ),
    revised,
  )
}

///|
test "revision never inherits approved rejected or deferred receipts" {
  for outcome in ["approve", "reject", "defer"] {
    let previous = authored_bundle()
    previous.decision_receipts.push(fixture_receipt(previous, outcome))
    let text = @review.serialize_review_bundle(previous, previous.source_digest)
    let revised = compile_revision_fixture(
      @review.prepare_review_revision(text, b"revision one\n"),
      text,
    )
    assert_eq(revised.decision_receipts, [])
    assert_eq(@review.review_status(revised), "pending_review")
    assert_eq(previous.decision_receipts[0].decision, outcome)
  }
}

///|
test "revision draft binds exact predecessor serialization and both source scopes" {
  let (text, _) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  for wrong_text in [text + "\n", text.replace(old="rollback", new="backout")] {
    assert_true(
      authoring_fails(() => ignore(compile_revision_fixture(draft, wrong_text))),
    )
  }
  assert_true(
    authoring_fails(() => {
      ignore(@review.prepare_review_revision(text, b"different source"))
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(compile_revision_fixture(draft, text, source=b"revision two\n"))
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.compile_review_revision(
          draft,
          b"revision one\n",
          previous_bundle_text=text,
          previous_source_bytes=b"different source",
          previous_bundle_ref="history/received-review.json",
        ),
      )
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.compile_review_revision(
          draft,
          b"revision one\n",
          previous_bundle_text=text,
          previous_source_bytes=b"revision one\n",
          previous_bundle_ref=draft.source_artifact_ref,
        ),
      )
    }),
  )
}

///|
test "revision rejects changed host scope and incomplete edited discussion" {
  let (text, _) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  for
    invalid in [
      { ..draft, review_id: "unrelated-review", },
      {
        ..draft,
        conversation: { ..draft.conversation, product_id: "other-host", },
      },
      { ..draft, format: "moonchat.review-revision.v99", },
      { ..draft, participants: [draft.participants[0]], },
      { ..draft, entries: [draft.entries[0]], },
      { ..draft, required_decisions: [], },
      {
        ..draft,
        required_decisions: [
          {
            ..draft.required_decisions[0],
            reviewer_participant_id: "collaborator-agent",
          },
        ],
      },
      { ..draft, entries: [{ ..draft.entries[1], body: " ", }], },
    ] {
    assert_true(
      authoring_fails(() => ignore(compile_revision_fixture(invalid, text))),
    )
  }
}

///|
test "revision parsing rejects invalid format missing fields and receipt fields" {
  let (text, _) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  let encoded = draft.to_json().stringify()
  for
    invalid in [
      "{",
      "[]",
      "{}",
      encoded.replace(old="moonchat.review-revision.v1", new="v99"),
      encoded.replace(
        old="\"format\":",
        new="\"decision_receipts\":[],\"format\":",
      ),
    ] {
    assert_true(
      authoring_fails(() => ignore(@review.parse_review_revision(invalid))),
    )
  }
}

///|
test "revision snapshots detach mutable editing arrays" {
  let (text, previous) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  let revised = compile_revision_fixture(draft, text)
  draft.entries[0].evidence_refs.push("later/editor-change.md")
  draft.entries.clear()
  draft.required_decisions.clear()
  draft.participants.clear()
  assert_eq(revised.entries, previous.entries)
  assert_eq(revised.required_decisions, previous.required_decisions)
  assert_eq(revised.participants, previous.participants)
  assert_eq(@review.reimport_review_bundle(text, b"revision one\n"), previous)
}

///|
test "revision validates predecessor receipt evidence even with a matching draft digest" {
  let (text, previous) = revision_fixture()
  let draft = @review.prepare_review_revision(text, b"revision one\n")
  let invalid_receipt = {
    ..previous.decision_receipts[0],
    reviewer_participant_id: "collaborator-agent",
  }
  for
    invalid in [
      { ..previous, decision_receipts: [invalid_receipt], },
      { ..previous, contract_id: "moonchat.conversation-review-bundle.v99", },
    ] {
    let invalid_text = invalid.to_json().stringify()
    assert_true(
      authoring_fails(() => {
        ignore(@review.prepare_review_revision(invalid_text, b"revision one\n"))
      }),
    )
    let rebound = {
      ..draft,
      base_bundle_digest: @review.review_source_digest(
        @utf8.encode(invalid_text),
      ),
    }
    assert_true(
      authoring_fails(() => {
        ignore(compile_revision_fixture(rebound, invalid_text))
      }),
    )
  }
}
