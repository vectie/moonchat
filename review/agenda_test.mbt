///|
fn agenda_fixture() -> @review.ReviewAgenda {
  {
    review_id: "launch",
    conversation_id: "launch-room",
    source_artifact_ref: "release/source.md",
    source_revision_id: "r1",
    recorded_at: "2026-10-08T12:00:00Z",
    participants: [
      {
        participant_id: "author",
        display_name: "Fixture assistant",
        participant_kind: "agent",
      },
      {
        participant_id: "editor",
        display_name: "Fixture editor",
        participant_kind: "human",
      },
      {
        participant_id: "ops",
        display_name: "Fixture operator",
        participant_kind: "human",
      },
    ],
    items: [
      {
        key: "rollout",
        kind: "proposal",
        author: "author",
        body: "Stage the café rollout.",
        evidence_refs: ["release/checks.txt"],
        decisions: [
          { reviewer: "editor", prompt: "Is the wording ready?", },
          { reviewer: "ops", prompt: "Is the rollout ready?", },
        ],
      },
      {
        key: "fallback",
        kind: "objection",
        author: "author",
        body: "The rollback owner is missing.",
        evidence_refs: [],
        decisions: [
          { reviewer: "ops", prompt: "Is rollback ownership covered?", },
        ],
      },
      {
        key: "timing",
        kind: "question",
        author: "editor",
        body: "Which day?",
        evidence_refs: [],
        decisions: [],
      },
    ],
  }
}

///|
test "agenda editing compiles stable linked pending reviews and readable outputs" {
  let agenda = agenda_fixture()
  let parsed = @review.parse_review_agenda(agenda.to_json().stringify())
  assert_true(parsed == agenda)
  let first = @review.compile_review_agenda(parsed, b"release one")
  assert_eq(first.entries.length(), 3)
  assert_eq(first.required_decisions.length(), 3)
  assert_eq(first.decision_receipts.length(), 0)
  assert_eq(@review.review_status(first), "pending_review")
  let serialized = @review.serialize_review_bundle(first, first.source_digest)
  assert_eq(@review.reimport_review_bundle(serialized, b"release one"), first)
  let edited = {
    ..agenda.items[0],
    body: "Stage the café rollout on Monday.",
  }
  let next_agenda = {
    ..agenda,
    source_revision_id: "r2",
    items: [agenda.items[2], edited, agenda.items[1]],
  }
  let next = @review.compile_review_agenda(next_agenda, b"release two")
  assert_eq(next.entries[1].entry_id, first.entries[0].entry_id)
  assert_eq(next.entries[1].turn, first.entries[0].turn)
  assert_eq(next.required_decisions[0], first.required_decisions[0])
  let linked = @review.supersede_review_bundle(
    serialized,
    previous_bundle_ref="release/first.json",
    previous_source_bytes=b"release one",
    next_bundle=next,
    next_source_bytes=b"release two",
  )
  assert_eq(
    linked.previous_bundle_digest,
    @review.review_source_digest(@utf8.encode(serialized)),
  )
  assert_eq(linked.decision_receipts.length(), 0)
  assert_true(
    @review.export_review_markdown(linked, b"release two").contains("Monday"),
  )
  assert_eq(first.entries[0].body, "Stage the café rollout.")
}

///|
test "agenda rejects ambiguous keys and nonhuman owners through normal authoring rules" {
  let agenda = agenda_fixture()
  assert_true(
    authoring_fails(() => {
      @review.compile_review_agenda(
        { ..agenda, items: [agenda.items[0], agenda.items[0]], },
        b"source",
      )
      |> ignore
    }),
  )
  let item = {
    ..agenda.items[0],
    decisions: [{ reviewer: "author", prompt: "Approve?", }],
  }
  assert_true(
    authoring_fails(() => {
      @review.compile_review_agenda({ ..agenda, items: [item], }, b"source")
      |> ignore
    }),
  )
}
