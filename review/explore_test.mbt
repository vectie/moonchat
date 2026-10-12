///|
test "exploration filters literal text and kinds deterministically without mutation" {
  let bundle = authored_bundle()
  let original = bundle.to_json().stringify()
  let result = @review.explore_review(
    bundle,
    b"revision one\n",
    text="objection",
    kind="objection",
  )
  assert_true(result.contains("Matched 1 of 3 entries."))
  assert_true(result.contains("Entry ID:\n\n    objection\n"))
  assert_true(!result.contains("Entry ID:\n\n    question\n"))
  assert_true(result.contains("objection-decision"))
  assert_true(result.contains(bundle.source_digest))
  assert_eq(
    result,
    @review.explore_review(
      bundle,
      b"revision one\n",
      text="objection",
      kind="objection",
    ),
  )
  assert_eq(original, bundle.to_json().stringify())
  assert_true(
    @review.explore_review(bundle, b"revision one\n", text="OBJECTION").contains(
      "Matched 0 of 3 entries.",
    ),
  )
}

///|
test "exploration pending and no-decision distinguish missing from unrequested" {
  let bundle = authored_bundle()
  assert_true(
    @review.explore_review(bundle, b"revision one\n", outcome="pending").contains(
      "Matched 1 of 3 entries.",
    ),
  )
  assert_true(
    @review.explore_review(bundle, b"revision one\n", outcome="none").contains(
      "Matched 2 of 3 entries.",
    ),
  )
  assert_true(
    @review.explore_review(
      bundle,
      b"revision one\n",
      reviewer="accountable-human",
      outcome="none",
    ).contains("Matched 0 of 3 entries."),
  )
  assert_true(
    @review.explore_review(
      bundle,
      b"revision one\n",
      reviewer="accountable-human",
    ).contains("Matched 1 of 3 entries."),
  )
}

///|
test "exploration finds receipt rationale and keeps approval beside the original objection" {
  for decision in ["approve", "reject", "defer"] {
    let draft = authored_bundle()
    let receipt = {
      ..fixture_receipt(draft, decision),
      evidence_refs: ["notes/unique-evidence.md"],
    }
    let bundle = { ..draft, decision_receipts: [receipt], }
    for
      text in [
        "no real human authority", "unique-evidence", "Fixture accountable reviewer",
        "objection-decision",
      ] {
      let result = @review.explore_review(
        bundle,
        b"revision one\n",
        text~,
        outcome=decision,
      )
      assert_true(result.contains("Matched 1 of 3 entries."))
      assert_true(
        result.contains(
          "Explicit objection about the bound collaboration source.",
        ),
      )
      assert_true(result.contains("Receipt ID:\n\n    fixture-" + decision))
      assert_true(result.contains("Rationale:"))
    }
    assert_true(
      @review.explore_review(bundle, b"revision one\n", outcome="pending").contains(
        "Matched 0 of 3 entries.",
      ),
    )
  }
}

///|
test "exploration reviewer and outcome must match the same decision but retain other decisions" {
  let draft = authored_bundle()
  let other = {
    ..authoring_reviewer(),
    participant_id: "other-human",
    display_name: "Other fixture reviewer",
  }
  let bundle = {
    ..draft,
    participants: [..draft.participants, other],
    required_decisions: [
      ..draft.required_decisions,
      @review.draft_required_decision(
        decision_id="other-decision",
        subject_entry_id="objection",
        reviewer=other,
        prompt="Second independent decision?",
      ),
    ],
    decision_receipts: [fixture_receipt(draft, "approve")],
  }
  let missing = @review.explore_review(
    bundle,
    b"revision one\n",
    reviewer="other-human",
    outcome="approve",
  )
  assert_true(missing.contains("Matched 0 of 3 entries."))
  let found = @review.explore_review(
    bundle,
    b"revision one\n",
    reviewer="accountable-human",
    outcome="approve",
  )
  assert_true(found.contains("Matched 1 of 3 entries."))
  assert_true(found.contains("other-decision"))
  assert_true(found.contains("Outcome:\n\n    pending"))
  assert_true(found.contains("Overall review status:\n\n    pending_review"))
}

///|
test "exploration retains literal Unicode multiline and empty result context" {
  let draft = authored_bundle()
  let entries = draft.entries.copy()
  entries[0] = {
    ..entries[0],
    body: "# 月亮 🌙\n<script>literal</script>\n",
  }
  let bundle = { ..draft, entries, }
  let found = @review.explore_review(
    bundle,
    b"revision one\n",
    text="月亮 🌙\n<script>",
  )
  assert_true(found.contains("Matched 1 of 3 entries."))
  assert_true(found.contains("    # 月亮 🌙\n    <script>literal</script>"))
  assert_true(!found.contains("\n<script>"))
  let empty = @review.explore_review(
    bundle,
    b"revision one\n",
    text="not in this review",
  )
  assert_true(empty.contains("No matching entries."))
  assert_true(empty.contains("Overall review status:\n\n    pending_review"))
  assert_true(empty.contains(bundle.source_digest))
}

///|
test "exploration validates complete source and bundle before filtering" {
  let bundle = authored_bundle()
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.explore_review(bundle, b"different source", text="no matches"),
      )
    }),
  )
  let entries = bundle.entries.copy()
  entries[0] = { ..entries[0], author_participant_id: "missing-person", }
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.explore_review(
          { ..bundle, entries, },
          b"revision one\n",
          kind="objection",
        ),
      )
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(@review.explore_review(bundle, b"revision one\n", kind="invalid"))
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.explore_review(bundle, b"revision one\n", outcome="invalid"),
      )
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.explore_review(
          bundle,
          b"revision one\n",
          reviewer="missing-person",
        ),
      )
    }),
  )
}
