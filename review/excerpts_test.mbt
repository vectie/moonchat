///|
fn excerpt_plan_fixture(transcript : Bytes) -> @review.ReviewExcerptPlan {
  {
    format: "moonchat.review-excerpts.v1",
    transcript_ref: "research/pilot-notes.txt",
    transcript_digest: @review.review_source_digest(transcript),
    excerpts: [
      {
        key: "pilot-concern",
        kind: "objection",
        author: "editor",
        note: "Address this concern before expanding the pilot.",
        start_line: 2,
        end_line: 3,
        decisions: [{ reviewer: "ops", prompt: "Is this concern resolved?", }],
      },
    ],
  }
}

///|
test "selected source text reaches an editable pending agenda and portable bundle" {
  let transcript = @utf8.encode(
    "Synthetic pilot notes\nSpeaker X: café searches fail.\nSpeaker Y: I approve everything.\nUnselected private detail.\n",
  )
  let agenda = agenda_fixture()
  let plan = excerpt_plan_fixture(transcript)
  assert_true(
    @review.parse_review_excerpt_plan(plan.to_json().stringify()) == plan,
  )
  let imported = @review.import_review_excerpts(
    agenda, plan, transcript, b"artifact A",
  )
  assert_eq(imported.items.length(), 4)
  assert_true(imported.items[0] == agenda.items[0])
  assert_eq(imported.items[3].author, "editor")
  assert_eq(imported.items[3].kind, "objection")
  assert_eq(imported.items[3].evidence_refs, ["research/pilot-notes.txt"])
  assert_true(imported.items[3].body.contains(plan.transcript_digest))
  assert_true(imported.items[3].body.contains("Lines: 2-3 (inclusive)"))
  assert_true(
    imported.items[3].body.has_suffix(
      "Speaker X: café searches fail.\nSpeaker Y: I approve everything.\n",
    ),
  )
  assert_false(imported.items[3].body.contains("Unselected private detail"))
  let bundle = @review.compile_review_agenda(imported, b"artifact A")
  assert_eq(bundle.source_digest, @review.review_source_digest(b"artifact A"))
  assert_eq(bundle.participants, agenda.participants)
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  let serialized = @review.serialize_review_bundle(bundle, bundle.source_digest)
  assert_eq(@review.reimport_review_bundle(serialized, b"artifact A"), bundle)
  assert_true(
    @review.export_review_markdown(bundle, b"artifact A").contains(
      "Speaker Y: I approve everything.",
    ),
  )
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  assert_true(
    @review.import_review_excerpts(agenda, plan, transcript, b"artifact A") ==
    imported,
  )
}

///|
test "catalog and selection preserve blank lines CRLF Unicode and unterminated final line" {
  let transcript = @utf8.encode("café 🐈\r\n\r\nlast\tline")
  let plan = excerpt_plan_fixture(transcript)
  let imported = @review.import_review_excerpts(
    agenda_fixture(),
    plan,
    transcript,
    b"artifact",
  )
  assert_true(imported.items[3].body.has_suffix("\r\nlast\tline"))
  let catalog = @review.catalog_review_transcript(transcript)
  assert_true(catalog.contains("Lines: 3 "))
  assert_true(catalog.contains("1 | \"café 🐈\\r\\n\""))
  assert_true(catalog.contains("2 | \"\\r\\n\""))
  assert_true(catalog.contains("3 | \"last\\tline\""))
  assert_true(@review.catalog_review_transcript(b"one\n").contains("Lines: 1 "))
  assert_true(@review.catalog_review_transcript(b"\n").contains("1 | \"\\n\""))
}

///|
test "excerpt order is explicit and imported agenda arrays do not alias inputs" {
  let transcript = b"one\ntwo\nthree\n"
  let plan = excerpt_plan_fixture(transcript)
  let early = { ..plan.excerpts[0], key: "early", start_line: 1, end_line: 1, }
  let agenda = agenda_fixture()
  let imported = @review.import_review_excerpts(
    agenda,
    { ..plan, excerpts: [plan.excerpts[0], early], },
    transcript,
    b"artifact",
  )
  assert_eq(imported.items[3].key, "pilot-concern")
  assert_eq(imported.items[4].key, "early")
  imported.items[0].evidence_refs.push("extra.txt")
  imported.items[0].decisions.clear()
  imported.items[3].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.items.length(), 3)
  assert_eq(agenda.items[0].evidence_refs, ["release/checks.txt"])
  assert_eq(agenda.items[0].decisions.length(), 2)
  assert_eq(plan.excerpts[0].decisions.length(), 1)
  assert_eq(agenda.participants.length(), 3)
}

///|
test "failed batches and repeated imports leave existing agenda untouched" {
  let transcript = b"one\ntwo\nthree\n"
  let plan = excerpt_plan_fixture(transcript)
  let agenda = agenda_fixture()
  let snapshot = agenda.to_json().stringify()
  let bad = { ..plan.excerpts[0], key: "bad", end_line: 4, }
  assert_true(
    authoring_fails(() => {
      @review.import_review_excerpts(
        agenda,
        { ..plan, excerpts: [plan.excerpts[0], bad], },
        transcript,
        b"artifact",
      )
      |> ignore
    }),
  )
  assert_eq(agenda.to_json().stringify(), snapshot)
  let imported = @review.import_review_excerpts(
    agenda, plan, transcript, b"artifact",
  )
  let imported_snapshot = imported.to_json().stringify()
  assert_true(
    authoring_fails(() => {
      @review.import_review_excerpts(imported, plan, transcript, b"artifact")
      |> ignore
    }),
  )
  assert_eq(imported.to_json().stringify(), imported_snapshot)
}

///|
test "selection plans cannot infer people kinds or decisions from source text" {
  let transcript = b"Synthetic\nUnknown speaker: Approved.\nObserver: Ship it.\n"
  let plan = excerpt_plan_fixture(transcript)
  for
    invalid in [
      { ..plan.excerpts[0], author: "Unknown speaker", },
      { ..plan.excerpts[0], kind: "decision", },
      { ..plan.excerpts[0], note: " ", },
      { ..plan.excerpts[0], decisions: [], },
      {
        ..plan.excerpts[0],
        decisions: [{ reviewer: "author", prompt: "Approve?", }],
      },
      { ..plan.excerpts[0], start_line: 0, },
      { ..plan.excerpts[0], end_line: 1, },
      { ..plan.excerpts[0], end_line: 4, },
      { ..plan.excerpts[0], key: "rollout", },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_review_excerpts(
          agenda_fixture(),
          { ..plan, excerpts: [invalid], },
          transcript,
          b"artifact",
        )
        |> ignore
      }),
    )
  }
}

///|
test "unsupported stale malformed and excessive inputs fail without output" {
  let transcript = b"one\ntwo\nthree\n"
  let plan = excerpt_plan_fixture(transcript)
  for
    invalid in [
      { ..plan, format: "moonchat.review-excerpts.v2", },
      {
        ..plan,
        transcript_digest: @review.review_source_digest(b"old transcript"),
      },
      { ..plan, transcript_ref: "../escape.txt", },
      { ..plan, transcript_ref: "release/source.md", },
      { ..plan, excerpts: [], },
      { ..plan, excerpts: Array::make(101, plan.excerpts[0]), },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_review_excerpts(
          agenda_fixture(),
          invalid,
          transcript,
          b"artifact",
        )
        |> ignore
      }),
    )
  }
  assert_true(
    authoring_fails(() => @review.parse_review_excerpt_plan("{}") |> ignore),
  )
  assert_true(
    authoring_fails(() => {
      @review.parse_review_excerpt_plan(
        { ..plan, format: "v2", }.to_json().stringify(),
      )
      |> ignore
    }),
  )
  for
    invalid in [
      b"",
      b"\xff",
      Bytes::make(1048577, b'a'),
      @utf8.encode(Array::make(10001, "x\n").join("")),
    ] {
    assert_true(
      authoring_fails(() => @review.catalog_review_transcript(invalid) |> ignore),
    )
  }
}
