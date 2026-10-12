///|
fn sheet_merge_fixture(
  base : @review.ReviewAgenda,
  left : @review.ReviewAgenda,
  right : @review.ReviewAgenda,
) -> @review.ReviewSheetMerge raise {
  @review.merge_review_sheets(
    base,
    @utf8.encode(@review.export_review_sheet(left, b"source")),
    @utf8.encode(@review.export_review_sheet(right, b"source")),
    b"source",
  )
}

///|
test "sheet merge combines independent fields and named reviewer prompts" {
  let base = agenda_fixture()
  let item = base.items[0]
  let left = {
    ..base,
    items: [
      {
        ..item,
        body: "=Keep café 🌙 rollout small,\nwith a \"rollback\" owner.",
        decisions: [
          { ..item.decisions[0], prompt: "Is the wording precise?", },
          item.decisions[1],
        ],
      },
      ..base.items[1:],
    ],
  }
  let right = {
    ..base,
    items: [
      {
        ..item,
        author: "editor",
        kind: "question",
        evidence_refs: ["notes/rollout.txt", "notes/rollout.txt"],
        decisions: [
          item.decisions[0],
          { ..item.decisions[1], prompt: "Is staging safe?", },
        ],
      },
      ..base.items[1:],
    ],
  }
  let report = sheet_merge_fixture(base, left, right)
  assert_eq(report.conflicts.length(), 0)
  let merged = report.merged_agenda.unwrap()
  assert_eq(merged.items[0].body, left.items[0].body)
  assert_eq(merged.items[0].author, "editor")
  assert_eq(merged.items[0].kind, "question")
  assert_eq(merged.items[0].evidence_refs, right.items[0].evidence_refs)
  assert_eq(merged.items[0].decisions.map(d => d.prompt), [
    "Is the wording precise?", "Is staging safe?",
  ])
  let bundle = @review.compile_review_agenda(merged, b"source")
  let before = @review.compile_review_agenda(base, b"source")
  assert_eq(bundle.entries[0].entry_id, before.entries[0].entry_id)
  assert_eq(
    bundle.required_decisions.map(d => d.decision_id),
    before.required_decisions.map(d => d.decision_id),
  )
  assert_eq(bundle.decision_receipts, [])
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_true(sheet_merge_fixture(base, left, right) == report)
  assert_true(
    sheet_merge_fixture(base, right, left).merged_agenda == report.merged_agenda,
  )
}

///|
test "sheet merge reports all conflicting values without a partial agenda" {
  let base = agenda_fixture()
  let item = base.items[0]
  let left = {
    ..base,
    items: [
      {
        ..item,
        body: "Left body",
        evidence_refs: ["left.md"],
        decisions: [
          { ..item.decisions[0], prompt: "Left prompt", },
          item.decisions[1],
        ],
      },
      ..base.items[1:],
    ],
  }
  let right = {
    ..base,
    items: [
      {
        ..item,
        body: "Right body",
        evidence_refs: ["right.md"],
        decisions: [
          { ..item.decisions[0], prompt: "Right prompt", },
          item.decisions[1],
        ],
      },
      ..base.items[1:],
    ],
  }
  let report = sheet_merge_fixture(base, left, right)
  assert_true(report.merged_agenda is None)
  assert_eq(report.conflicts.map(c => c.field), [
    "body",
    "evidence_refs",
    "decision:" + item.decisions[0].reviewer,
  ])
  assert_eq(report.conflicts[0].item_key, item.key)
  assert_eq(report.conflicts[0].base, item.body.to_json())
  assert_eq(report.conflicts[0].left, "Left body".to_json())
  assert_eq(report.conflicts[0].right, "Right body".to_json())
  assert_eq(report.format, "moonchat.review-sheet-merge.v1")
  // Resolve by editing both sheets to the chosen common value, then retry.
  let resolved = { ..right, items: [{ ..left.items[0], }, ..base.items[1:]], }
  assert_true(
    sheet_merge_fixture(base, left, resolved).merged_agenda == Some(left),
  )
}

///|
test "sheet merge retains uncontested deletion and reports deletion versus edit" {
  let base = agenda_fixture()
  let left = { ..base, items: [base.items[0]], }
  let unchanged = sheet_merge_fixture(base, left, base).merged_agenda.unwrap()
  assert_true(unchanged == left)
  assert_true(sheet_merge_fixture(base, base, left).merged_agenda == Some(left))
  let right = {
    ..base,
    items: [
      base.items[0],
      { ..base.items[1], body: "Keep this edited question", },
    ],
  }
  let conflict = sheet_merge_fixture(base, left, right)
  assert_true(conflict.merged_agenda is None)
  assert_eq(conflict.conflicts.length(), 1)
  assert_eq(conflict.conflicts[0].field, "item")
  assert_eq(conflict.conflicts[0].left, Json::null())
  assert_eq(conflict.conflicts[0].right, right.items[1].to_json())
  assert_true(sheet_merge_fixture(base, left, left).merged_agenda == Some(left))
}

///|
test "sheet merge appends distinct additions and coalesces identical additions" {
  let base = agenda_fixture()
  let fresh = { ..base.items[1], key: "new-question", body: "Which pilot?", }
  let other = { ..fresh, key: "another-question", body: "Which cohort?", }
  let left = { ..base, items: [fresh, ..base.items], }
  let right = { ..base, items: [other, ..base.items, fresh], }
  let merged = sheet_merge_fixture(base, left, right).merged_agenda.unwrap()
  assert_eq(
    merged.items.map(i => i.key),
    [..base.items.map(i => i.key), fresh.key, other.key],
  )
  let incompatible = {
    ..base,
    items: [..base.items, { ..fresh, body: "Different new question", }],
  }
  let conflict = sheet_merge_fixture(base, left, incompatible)
  assert_true(conflict.merged_agenda is None)
  assert_eq(conflict.conflicts[0].item_key, fresh.key)
  assert_eq(conflict.conflicts[0].base, Json::null())
}

///|
test "sheet merge adds and removes reviewer requests by identity" {
  let original = agenda_fixture()
  let item = original.items[0]
  let base = {
    ..original,
    items: [{ ..item, decisions: [item.decisions[0]], }, ..original.items[1:]],
  }
  let left = { ..base, items: [item, ..base.items[1:]], }
  let right = {
    ..base,
    items: [
      {
        ..base.items[0],
        decisions: [
          { ..item.decisions[0], prompt: "Updated original request", },
        ],
      },
      ..base.items[1:],
    ],
  }
  let merged = sheet_merge_fixture(base, left, right).merged_agenda.unwrap()
  assert_eq(
    merged.items[0].decisions.map(d => d.reviewer),
    item.decisions.map(d => d.reviewer),
  )
  assert_eq(merged.items[0].decisions[0].prompt, "Updated original request")
  assert_eq(merged.items[0].decisions[1].prompt, item.decisions[1].prompt)
  let deleted = {
    ..original,
    items: [{ ..item, decisions: [item.decisions[1]], }, ..original.items[1:]],
  }
  let changed = {
    ..original,
    items: [
      {
        ..item,
        decisions: [
          { ..item.decisions[0], prompt: "Changed to conflict", },
          item.decisions[1],
        ],
      },
      ..original.items[1:],
    ],
  }
  assert_true(
    sheet_merge_fixture(original, deleted, original).merged_agenda ==
    Some(deleted),
  )
  let conflict = sheet_merge_fixture(original, deleted, changed)
  assert_true(conflict.merged_agenda is None)
  assert_eq(conflict.conflicts.length(), 1)
  assert_eq(
    conflict.conflicts[0].field,
    "decision:" + item.decisions[0].reviewer,
  )
  assert_eq(conflict.conflicts[0].left, Json::null())
}

///|
test "sheet merge carries one reorder and detects incompatible two-sided reorders" {
  let initial = agenda_fixture()
  let base = {
    ..initial,
    items: [..initial.items, { ..initial.items[1], key: "third", }],
  }
  let left = { ..base, items: [base.items[1], base.items[0], base.items[2]], }
  let edited = {
    ..base,
    items: [
      { ..base.items[0], body: "Edited without reorder", },
      ..base.items[1:],
    ],
  }
  let merged = sheet_merge_fixture(base, left, edited).merged_agenda.unwrap()
  assert_eq(merged.items.map(i => i.key), left.items.map(i => i.key))
  assert_eq(merged.items[1].body, edited.items[0].body)
  assert_true(sheet_merge_fixture(base, left, left).merged_agenda == Some(left))
  let right = { ..base, items: [base.items[0], base.items[2], base.items[1]], }
  let conflict = sheet_merge_fixture(base, left, right)
  assert_true(conflict.merged_agenda is None)
  assert_eq(conflict.conflicts.length(), 1)
  assert_eq(conflict.conflicts[0].field, "item_order")
}

///|
test "sheet merge reorders existing reviewers while preserving independent prompts" {
  let base = agenda_fixture()
  let item = base.items[0]
  let left = {
    ..base,
    items: [
      { ..item, decisions: [item.decisions[1], item.decisions[0]], },
      ..base.items[1:],
    ],
  }
  let right = {
    ..base,
    items: [
      {
        ..item,
        decisions: [
          { ..item.decisions[0], prompt: "Updated prompt", },
          item.decisions[1],
        ],
      },
      ..base.items[1:],
    ],
  }
  let merged = sheet_merge_fixture(base, left, right).merged_agenda.unwrap()
  assert_eq(
    merged.items[0].decisions.map(d => d.reviewer),
    left.items[0].decisions.map(d => d.reviewer),
  )
  assert_eq(merged.items[0].decisions[1].prompt, "Updated prompt")
}

///|
test "sheet merge validates combined decisions and malformed branch input" {
  let original = agenda_fixture()
  let base = { ..original, items: [original.items[0]], }
  let item = base.items[0]
  let left = {
    ..base,
    items: [{ ..item, decisions: [item.decisions[0]], }, ..base.items[1:]],
  }
  let right = {
    ..base,
    items: [{ ..item, decisions: [item.decisions[1]], }, ..base.items[1:]],
  }
  assert_true(
    authoring_fails(() => sheet_merge_fixture(base, left, right) |> ignore),
  )
  let csv = @utf8.encode(@review.export_review_sheet(base, b"source"))
  assert_true(
    authoring_fails(() => {
      @review.merge_review_sheets(base, b"invalid,header", csv, b"source")
      |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => {
      @review.merge_review_sheets(base, csv, [0xff], b"source") |> ignore
    }),
  )
  let invalid = { ..base, items: [], }
  assert_true(
    authoring_fails(() => {
      @review.merge_review_sheets(invalid, csv, csv, b"source") |> ignore
    }),
  )
}

///|
test "sheet merge does not mutate or alias authoring arrays" {
  let base = agenda_fixture()
  let original = base.to_json().stringify()
  let result = sheet_merge_fixture(base, base, base).merged_agenda.unwrap()
  assert_true(result == base)
  result.items[0].evidence_refs.clear()
  result.items[0].decisions.clear()
  result.items.clear()
  result.participants.clear()
  assert_eq(base.to_json().stringify(), original)
}
