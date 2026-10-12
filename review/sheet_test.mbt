///|
test "spreadsheet export and import preserve agenda content, order and identities" {
  let agenda = agenda_fixture()
  let csv = @review.export_review_sheet(agenda, b"source")
  assert_true(
    csv.has_prefix("key,kind,author,body,evidence_ref,reviewer,prompt\r\n"),
  )
  let imported = @review.import_review_sheet(
    agenda,
    @utf8.encode(csv),
    b"source",
  )
  assert_true(imported == agenda)
  assert_eq(
    @review.compile_review_agenda(imported, b"source"),
    @review.compile_review_agenda(agenda, b"source"),
  )
  imported.items[0].evidence_refs.push("new-note.txt")
  imported.items[0].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.items[0].evidence_refs.length(), 1)
  assert_eq(agenda.items[0].decisions.length(), 2)
  assert_eq(agenda.participants.length(), 3)
}

///|
test "spreadsheet edits replace add remove reorder and group noncontiguous item rows" {
  let agenda = agenda_fixture()
  let csv =
    #|key,kind,author,body,evidence_ref,reviewer,prompt
    #|timing,question,editor,"Which day, exactly?",release/calendar.txt,,
    #|rollout,proposal,author,"Stage the café rollout.
    #|Keep the ""rollback"" owner available.",release/checks.txt,ops,Can we stage safely?
    #|new-point,objection,editor,Capacity is tight.,,editor,Is capacity sufficient?
    #|rollout,proposal,author,"Stage the café rollout.
    #|Keep the ""rollback"" owner available.",release/owners.txt,editor,Is the wording ready?
    #|
  let imported = @review.import_review_sheet(
    agenda,
    @utf8.encode(csv),
    b"source",
  )
  assert_eq(imported.items.map(item => item.key), [
    "timing", "rollout", "new-point",
  ])
  assert_eq(imported.items[1].evidence_refs, [
    "release/checks.txt", "release/owners.txt",
  ])
  assert_eq(imported.items[1].decisions.map(item => item.reviewer), [
    "ops", "editor",
  ])
  assert_eq(
    imported.items[1].body,
    "Stage the café rollout.\nKeep the \"rollback\" owner available.",
  )
  assert_eq(imported.source_revision_id, agenda.source_revision_id)
  assert_eq(imported.source_artifact_ref, agenda.source_artifact_ref)
  let before = @review.compile_review_agenda(agenda, b"source")
  let after = @review.compile_review_agenda(imported, b"source")
  assert_eq(after.entries[1].entry_id, before.entries[0].entry_id)
  assert_eq(after.entries[1].turn, before.entries[0].turn)
  assert_eq(after.decision_receipts.length(), 0)
  assert_eq(@review.review_status(after), "pending_review")
  assert_true(
    @review.export_review_markdown(after, b"source").contains(
      "Capacity is tight.",
    ),
  )
  assert_eq(agenda.items[0].body, "Stage the café rollout.")
  let reexported = @review.export_review_sheet(imported, b"source")
  assert_true(
    @review.import_review_sheet(agenda, @utf8.encode(reexported), b"source") ==
    imported,
  )
}

///|
test "spreadsheet reexport doubles every quote in multiline bodies prompts and references" {
  let base = agenda_fixture()
  let body = "Check café staffing,\nincluding the \"Friday\" shift."
  let agenda = {
    ..base,
    items: [
      {
        ..base.items[0],
        body,
        evidence_refs: ["pilot/\"Friday\".md"],
        decisions: [
          { reviewer: "editor", prompt: "Is \"Friday\" or \"Monday\" ready?", },
        ],
      },
    ],
  }
  let csv = @review.export_review_sheet(agenda, b"source")
  assert_true(csv.contains("including the \"\"Friday\"\" shift."))
  assert_true(csv.contains("Is \"\"Friday\"\" or \"\"Monday\"\" ready?"))
  assert_true(
    @review.import_review_sheet(base, @utf8.encode(csv), b"source") == agenda,
  )
}

///|
test "spreadsheet cells round trip unicode whitespace punctuation and text markers" {
  let base = agenda_fixture()
  for
    body in [
      "Comma, quote \" café 🌙 中文\r\nsecond line\nlast", "\"\"\"", "=SUM(1,2)",
      "+proposed change", "-do not launch", "@operator please review", "\t  =formula-looking text",
      "'=literal apostrophe", "'ordinary quoted prose", "''two apostrophes", "  Keep leading and trailing whitespace.  ",
    ] {
    let agenda = { ..base, items: [{ ..base.items[0], body, }], }
    let csv = @review.export_review_sheet(agenda, b"source")
    let imported = @review.import_review_sheet(
      agenda,
      @utf8.encode(csv),
      b"source",
    )
    assert_true(imported == agenda)
    if body.has_prefix("=") {
      assert_true(csv.contains("\"'=SUM(1,2)\""))
    }
  }
}

///|
test "spreadsheet accepts UTF8 BOM CRLF blank lines and no terminal newline" {
  let base = agenda_fixture()
  let text = "\uFEFFkey,kind,author,body,evidence_ref,reviewer,prompt\r\n\r\nrollout,proposal,author,Hello,,editor,Ready?"
  let imported = @review.import_review_sheet(
    base,
    @utf8.encode(text),
    b"source",
  )
  assert_eq(imported.items.length(), 1)
  assert_eq(imported.items[0].body, "Hello")
  let exported = @review.export_review_sheet(imported, b"source")
  assert_true(exported.has_suffix("\r\n"))
}

///|
test "spreadsheet import reports malformed rows without altering the template" {
  let base = agenda_fixture()
  let header = "key,kind,author,body,evidence_ref,reviewer,prompt\n"
  let original = base.to_json().stringify()
  for
    row in [
      "x,proposal,author,Body,,editor", "x,proposal,author,Body,,editor,Ready?,extra",
      "x,proposal,author,\"Body,,editor,Ready?", "x,proposal,author,Bo\"dy,,editor,Ready?",
      "x,proposal,author,\"Body\"unexpected,,editor,Ready?", "x,proposal,author,Body,,editor,",
      "x,proposal,author,Body,,,Ready?", "x,proposal,unknown,Body,,editor,Ready?",
      "x,proposal,author,Body,,author,Ready?", "x,approval,author,Body,,editor,Ready?",
      "x,proposal,author,Body,,editor,Ready?\nx,proposal,author,Different,,ops,Ready?",
      "x,proposal,author,Body,,editor,Ready?\nx,proposal,author,Body,,editor,Ready?",
      "x,proposal,author,Body,../outside,editor,Ready?", "x,objection,author,Body,,,",
      "",
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_review_sheet(base, @utf8.encode(header + row), b"source")
        |> ignore
      }),
    )
    assert_eq(base.to_json().stringify(), original)
  }
  assert_true(
    authoring_fails(() => {
      @review.import_review_sheet(base, b"wrong,header", b"source") |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => {
      @review.import_review_sheet(base, [0xff], b"source") |> ignore
    }),
  )
}

///|
test "spreadsheet supports more evidence rows than reviewers without dropping references" {
  let base = agenda_fixture()
  let item = {
    ..base.items[0],
    evidence_refs: ["a.txt", "b.txt", "c.txt", "c.txt"],
  }
  let agenda = { ..base, items: [item], }
  let imported = @review.import_review_sheet(
    agenda,
    @utf8.encode(@review.export_review_sheet(agenda, b"source")),
    b"source",
  )
  assert_true(imported == agenda)
}

///|
test "spreadsheet template can have no items until imported rows provide them" {
  let base = agenda_fixture()
  let empty = { ..base, items: [], }
  let csv = @review.export_review_sheet(base, b"source")
  assert_true(
    @review.import_review_sheet(empty, @utf8.encode(csv), b"source") == base,
  )
}

///|
test "spreadsheet bounds reject oversized bytes and too many records" {
  let base = agenda_fixture()
  assert_true(
    authoring_fails(() => {
      @review.import_review_sheet(
        base,
        @utf8.encode("a".repeat(1048577)),
        b"source",
      )
      |> ignore
    }),
  )
  let header = "key,kind,author,body,evidence_ref,reviewer,prompt\n"
  assert_true(
    authoring_fails(() => {
      @review.import_review_sheet(
        base,
        @utf8.encode(header + "x,proposal,author,Body,,,\n".repeat(5001)),
        b"source",
      )
      |> ignore
    }),
  )
}
