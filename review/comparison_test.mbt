///|
test "comparison is deterministic and does not mutate or invent changes" {
  let bundle = authored_bundle()
  let saved = bundle.to_json().stringify()
  let text = @review.export_review_comparison(
    bundle, b"revision one\n", bundle, b"revision one\n",
  )
  assert_true(text.contains("0 added; 0 changed; 0 removed; 3 unchanged."))
  assert_true(!text.contains("### Changed"))
  assert_true(!text.contains("Before order"))
  assert_eq(
    text,
    @review.export_review_comparison(
      bundle, b"revision one\n", bundle, b"revision one\n",
    ),
  )
  assert_eq(saved, bundle.to_json().stringify())
}

///|
test "comparison preserves removed dissent and shows changed evidence and added entries" {
  let before = authored_bundle()
  let after = {
    ..before,
    entries: [
      {
        ..before.entries[0],
        body: "# Updated 🌙\n<script>text</script>",
        evidence_refs: ["new/evidence.md"],
      },
      before.entries[2],
      {
        ..before.entries[2],
        entry_id: "new-proposal",
        turn: {
          turn_id: "new-turn",
          client_turn_id: "new-client",
          command_id: "new-command",
        },
      },
    ],
    required_decisions: [
      {
        ..before.required_decisions[0],
        decision_id: "new-decision",
        subject_entry_id: "new-proposal",
      },
    ],
  }
  let text = @review.export_review_comparison(
    before, b"revision one\n", after, b"revision one\n",
  )
  assert_true(text.contains("1 added; 1 changed; 1 removed; 1 unchanged."))
  assert_true(
    text.contains("Explicit objection about the bound collaboration source."),
  )
  assert_true(text.contains("    # Updated 🌙\n    <script>text</script>"))
  assert_true(!text.contains("\n<script>"))
  assert_true(text.contains("    new/evidence.md"))
  assert_true(text.contains("1 added; 0 changed; 1 removed; 0 unchanged."))
}

///|
test "comparison reports reorder without mislabeling content changes" {
  let before = authored_bundle()
  let after = {
    ..before,
    entries: [before.entries[2], before.entries[0], before.entries[1]],
  }
  let text = @review.export_review_comparison(
    before, b"revision one\n", after, b"revision one\n",
  )
  assert_true(text.contains("0 added; 0 changed; 0 removed; 3 unchanged."))
  assert_true(
    text.contains("After order:\n\n    proposal\n    question\n    objection"),
  )
  assert_true(!text.contains("### Changed"))
}

///|
test "comparison shows changed reviewers prompts and receipt rationale" {
  let draft = authored_bundle()
  let before = {
    ..draft,
    decision_receipts: [fixture_receipt(draft, "defer")],
  }
  let after = {
    ..before,
    participants: [
      before.participants[0],
      { ..before.participants[1], display_name: "Renamed reviewer", },
    ],
    required_decisions: [
      { ..before.required_decisions[0], prompt: "Updated decision prompt", },
    ],
    decision_receipts: [
      {
        ..before.decision_receipts[0],
        reviewer_name: "Renamed reviewer",
        rationale: "Still waiting for evidence",
      },
    ],
  }
  let text = @review.export_review_comparison(
    before, b"revision one\n", after, b"revision one\n",
  )
  assert_true(text.contains("Name: Renamed reviewer"))
  assert_true(text.contains("Updated decision prompt"))
  assert_true(text.contains("Still waiting for evidence"))
  assert_true(
    text.contains("Source test fixture only; no real human authority implied."),
  )
  assert_true(text.contains("Decision: defer"))
}

///|
test "new source comparison retains old approval only as historical evidence" {
  let draft = authored_bundle()
  let before = {
    ..draft,
    decision_receipts: [fixture_receipt(draft, "approve")],
  }
  let after = authored_bundle(source=b"revision two\n", revision="rev-two")
  let text = @review.export_review_comparison(
    before, b"revision one\n", after, b"revision two\n",
  )
  assert_true(text.contains("Before status:\n\n    accepted"))
  assert_true(text.contains("After status:\n\n    pending_review"))
  assert_true(text.contains("prior receipts cover only their original digest"))
  assert_true(text.contains("Decision: approve"))
  assert_true(text.contains("0 added; 0 changed; 1 removed; 0 unchanged."))
  assert_eq(after.decision_receipts, [])
}

///|
test "comparison rejects wrong source bytes on either side and unrelated scopes" {
  let bundle = authored_bundle()
  for
    (old_source, new_source) in [
      (b"wrong", b"revision one\n"),
      (b"revision one\n", b"wrong"),
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.export_review_comparison(
            bundle, old_source, bundle, new_source,
          ),
        )
      }),
    )
  }
  for
    other in [
      { ..bundle, source_artifact_ref: "another/source.md", },
      {
        ..bundle,
        conversation: { ..bundle.conversation, conversation_id: "unrelated", },
      },
      { ..bundle, entries: [bundle.entries[0], bundle.entries[0]], },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.export_review_comparison(
            bundle, b"revision one\n", other, b"revision one\n",
          ),
        )
      }),
    )
  }
}
