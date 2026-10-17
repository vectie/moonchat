///|
fn decision_form_fixture() -> (String, @review.ReviewDecisionForm) raise {
  let bundle = @review.compile_review_agenda(agenda_fixture(), b"release one")
  let text = @review.serialize_review_bundle(bundle, bundle.source_digest)
  (text, @review.prepare_review_decisions(text, b"release one", "ops"))
}

///|
fn choose(
  form : @review.ReviewDecisionForm,
  outcome : String,
) -> @review.ReviewDecisionForm {
  {
    ..form,
    choices: form.choices.map(c => {
      ..c,
      outcome,
      rationale: "Explicit fixture choice; retain the objection.",
      receipt_id: "receipt-" + c.decision_id,
      decided_at: "2026-10-12T12:00:00Z",
      evidence_refs: ["release/checks.txt"],
    }),
  }
}

///|
test "decision form has no default decision and preserves full discussion" {
  let (text, form) = decision_form_fixture()
  assert_eq(form.choices.length(), 2)
  assert_eq(form.entries.length(), 3)
  assert_true(form.choices.all(c => c.outcome == ""))
  assert_true(
    @review.parse_review_decisions(form.to_json().stringify()) == form,
  )
  assert_true(
    authoring_fails(() => {
      @review.preview_review_decisions(form, text, b"release one") |> ignore
    }),
  )
  assert_eq(
    @review.reimport_review_bundle(text, b"release one").decision_receipts.length(),
    0,
  )
}

///|
test "verified fixture host completes approve reject defer and replay with dissent" {
  for outcome in ["approve", "reject", "defer"] {
    let (text, blank) = decision_form_fixture()
    let form = choose(blank, outcome)
    let preview = @review.preview_review_decisions(form, text, b"release one")
    assert_true(preview.contains("UNVERIFIED DECISION SUBMISSION"))
    assert_true(preview.contains("The rollback owner is missing."))
    let partial = @review.apply_verified_review_decisions(
      form,
      text,
      b"release one",
      verified_reviewer_participant_id="ops",
    )
    assert_eq(@review.review_status(partial), "pending_review")
    assert_eq(partial.entries, blank.entries)
    assert_eq(partial.decision_receipts.length(), 2)
    assert_eq(
      @review.apply_verified_review_decisions(
        form,
        text,
        b"release one",
        verified_reviewer_participant_id="ops",
      ),
      partial,
    )
    let partial_text = @review.serialize_review_bundle(
      partial,
      partial.source_digest,
    )
    let editor = choose(
      @review.prepare_review_decisions(partial_text, b"release one", "editor"),
      "approve",
    )
    let complete = @review.apply_verified_review_decisions(
      editor,
      partial_text,
      b"release one",
      verified_reviewer_participant_id="editor",
    )
    assert_eq(complete.decision_receipts[0], partial.decision_receipts[0])
    assert_eq(complete.entries, partial.entries)
    let expected = match outcome {
      "approve" => "accepted"
      "reject" => "rejected"
      _ => "pending_review"
    }
    let reloaded = @review.reimport_review_bundle(
      @review.serialize_review_bundle(complete, complete.source_digest),
      b"release one",
    )
    assert_eq(
      @review.project_review_record(reloaded, complete.source_digest, []).review_status,
      expected,
    )
    assert_eq(
      @review.review_events(reloaded, complete.source_digest)
      .filter(e => e.event_kind == "human_decision_recorded")
      .length(),
      3,
    )
    assert_true(
      authoring_fails(() => {
        @review.prepare_review_decisions(partial_text, b"release one", "ops")
        |> ignore
      }),
    )
    assert_true(
      authoring_fails(() => {
        @review.apply_verified_review_decisions(
          form,
          partial_text,
          b"release one",
          verified_reviewer_participant_id="ops",
        )
        |> ignore
      }),
    )
  }
}

///|
test "decision scope refuses stale source bundle reviewer and edited discussion" {
  let (text, blank) = decision_form_fixture()
  let form = choose(blank, "approve")
  assert_true(
    authoring_fails(() => {
      @review.apply_verified_review_decisions(
        form,
        text,
        b"changed",
        verified_reviewer_participant_id="ops",
      )
      |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => {
      @review.apply_verified_review_decisions(
        form,
        text + " ",
        b"release one",
        verified_reviewer_participant_id="ops",
      )
      |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => {
      @review.apply_verified_review_decisions(
        form,
        text,
        b"release one",
        verified_reviewer_participant_id="editor",
      )
      |> ignore
    }),
  )
  for
    bad in [
      { ..form, entries: [form.entries[0]], },
      { ..form, reviewer_name: "Someone else", },
      { ..form, source_revision_id: "r2", },
      {
        ..form,
        choices: [{ ..form.choices[0], prompt: "Different question", }],
      },
      { ..form, choices: [{ ..form.choices[0], subject_entry_id: "other", }], },
      { ..form, choices: [{ ..form.choices[0], decision_id: "foreign", }], },
      { ..form, choices: [form.choices[0], form.choices[0]], },
      { ..form, choices: [{ ..form.choices[0], outcome: "yes", }], },
      { ..form, choices: [{ ..form.choices[0], rationale: "", }], },
      {
        ..form,
        choices: [{ ..form.choices[0], evidence_refs: ["../secret"], }],
      },
      { ..form, choices: [{ ..form.choices[0], outcome: "", }], },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.apply_verified_review_decisions(
          bad,
          text,
          b"release one",
          verified_reviewer_participant_id="ops",
        )
        |> ignore
      }),
    )
  }
  assert_true(
    authoring_fails(() => {
      @review.prepare_review_decisions(text, b"release one", "author") |> ignore
    }),
  )
}

///|
test "partial submission keeps blank requirements pending and detaches form storage" {
  let (text, blank) = decision_form_fixture()
  let choices = choose(blank, "defer")
  let form = { ..choices, choices: [choices.choices[0], blank.choices[1]], }
  let bundle = @review.apply_verified_review_decisions(
    form,
    text,
    b"release one",
    verified_reviewer_participant_id="ops",
  )
  assert_eq(bundle.decision_receipts.length(), 1)
  form.choices[0].evidence_refs.push("more.txt")
  assert_eq(bundle.decision_receipts[0].evidence_refs.length(), 1)
  form.entries.clear()
  assert_eq(bundle.entries.length(), 3)
  assert_eq(
    @review.reimport_review_bundle(text, b"release one").decision_receipts.length(),
    0,
  )
  assert_eq(@review.review_status(bundle), "pending_review")
}

///|
test "decision parser refuses unknown top level and choice fields" {
  let (_, form) = decision_form_fixture()
  let raw = form.to_json().stringify()
  assert_true(
    authoring_fails(() => {
      @review.parse_review_decisions(
        raw.replace(old="\"outcome\":", new="\"approve_automatically\":"),
      )
      |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => {
      @review.parse_review_decisions(
        raw.replace(old="\"format\":", new="\"unsupported\":"),
      )
      |> ignore
    }),
  )
}
