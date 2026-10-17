///|
fn checklist_fixture() -> @review.ReviewChecklist {
  {
    format: "moonchat.review-checklist.v1",
    checklist_id: "release-readiness",
    title: "Release readiness",
    roles: ["writer", "operator"],
    variables: ["product", "window"],
    items: [
      {
        key: "launch",
        kind: "proposal",
        author_role: "writer",
        body: "Release ${product} during ${window}.",
        decisions: [
          {
            reviewer_role: "operator",
            prompt: "Is ${product} ready for ${window}?",
          },
        ],
      },
      {
        key: "fallback",
        kind: "objection",
        author_role: "writer",
        body: "Confirm rollback ownership before releasing ${product}.",
        decisions: [
          { reviewer_role: "operator", prompt: "Is rollback covered?", },
        ],
      },
      {
        key: "support",
        kind: "question",
        author_role: "operator",
        body: "Who covers support during ${window}?",
        decisions: [],
      },
    ],
  }
}

///|
fn checklist_input(bytes : Bytes) -> @review.ReviewChecklistInput {
  {
    format: "moonchat.review-checklist-input.v1",
    checklist_id: "release-readiness",
    review_id: "cafe-r1",
    conversation_id: "cafe-review",
    source_artifact_ref: "releases/cafe.md",
    source_revision_id: "r1",
    source_digest: @review.review_source_digest(bytes),
    recorded_at: "2026-10-13T08:00:00Z",
    participants: agenda_fixture().participants,
    role_assignments: [
      { role: "writer", participant_id: "author", },
      { role: "operator", participant_id: "ops", },
    ],
    values: [
      { variable: "product", value: "Café 🌙", },
      { variable: "window", value: "Tuesday", },
    ],
  }
}

///|
test "checklist catalog shows actual role uses and variable locations" {
  let checklist = checklist_fixture()
  assert_true(
    @review.parse_review_checklist(checklist.to_json().stringify()) == checklist,
  )
  let catalog = @review.catalog_review_checklist(checklist)
  assert_eq(catalog, @review.catalog_review_checklist(checklist))
  assert_true(catalog.contains("launch/decision/operator"))
  assert_true(catalog.contains("support/body"))
  assert_true(catalog.contains("preparation_only"))
  guard @json.parse(catalog) is { "roles": Array(roles), .. } else {
    fail("roles")
  }
  assert_true(
    roles[0] is { "requires_human": False, "authors_items": Array(_), .. },
  )
  assert_true(
    roles[1] is { "requires_human": True, "decides_items": Array(_), .. },
  )
}

///|
test "checklist reuse binds two distinct artifacts and human decision forms" {
  let checklist = checklist_fixture()
  let first_bytes = b"Cafe release draft"
  let input = checklist_input(first_bytes)
  assert_true(
    @review.parse_review_checklist_input(input.to_json().stringify()) == input,
  )
  let agenda = @review.instantiate_review_checklist(
    checklist, input, first_bytes,
  )
  let first = @review.compile_review_agenda(agenda, first_bytes)
  let second_bytes = b"Library release draft"
  let second_input = {
    ..input,
    review_id: "library-r7",
    conversation_id: "library-review",
    source_artifact_ref: "releases/library.md",
    source_revision_id: "r7",
    source_digest: @review.review_source_digest(second_bytes),
    role_assignments: [
      { role: "writer", participant_id: "author", },
      { role: "operator", participant_id: "editor", },
    ],
    values: [
      { variable: "product", value: "Library", },
      { variable: "window", value: "Friday", },
    ],
  }
  let second = @review.compile_review_agenda(
    @review.instantiate_review_checklist(checklist, second_input, second_bytes),
    second_bytes,
  )
  assert_eq(first.review_id, "cafe-r1")
  assert_eq(second.review_id, "library-r7")
  assert_eq(second.source_revision_id, "r7")
  assert_eq(second.source_artifact_ref, "releases/library.md")
  assert_true(first.source_digest != second.source_digest)
  assert_eq(second.entries[0].body, "Release Library during Friday.")
  assert_eq(second.entries[0].evidence_refs, ["releases/library.md"])
  assert_eq(second.required_decisions[0].reviewer_participant_id, "editor")
  for bundle in [first, second] {
    assert_eq(@review.review_status(bundle), "pending_review")
    assert_eq(bundle.decision_receipts.length(), 0)
    assert_eq(bundle.previous_bundle_ref, "")
    assert_eq(bundle.previous_bundle_digest, "")
  }
  let saved = @review.serialize_review_bundle(first, first.source_digest)
  assert_eq(@review.reimport_review_bundle(saved, first_bytes), first)
  let form = @review.prepare_review_decisions(saved, first_bytes, "ops")
  assert_eq(form.choices.length(), 2)
  assert_true(
    form.choices.all(choice => choice.outcome == "" && choice.receipt_id == ""),
  )
}

///|
test "checklist interpolation is single pass literal Unicode multiline and escaped dollar" {
  let checklist = checklist_fixture()
  let first = {
    ..checklist.items[0],
    body: "${product}\n$$5 $7 $${window} ${window} ${product}",
  }
  let input = {
    ..checklist_input(b"x"),
    values: [
      { variable: "product", value: "café 🌙 ${window}\nline two", },
      { variable: "window", value: "<script>literal()</script>", },
    ],
  }
  let agenda = @review.instantiate_review_checklist(
    { ..checklist, items: [first], },
    input,
    b"x",
  )
  assert_eq(
    agenda.items[0].body,
    "café 🌙 ${window}\nline two\n$5 $7 ${window} <script>literal()</script> café 🌙 ${window}\nline two",
  )
  let html = @review.export_review_html(
    @review.compile_review_agenda(agenda, b"x"),
    b"x",
  )
  assert_true(html.contains("&lt;script&gt;literal()&lt;/script&gt;"))
  assert_false(html.contains("<script>literal()</script>"))
}

///|
test "checklist variables require an exact unique nonempty input set" {
  let checklist = checklist_fixture()
  let input = checklist_input(b"x")
  for
    values in [
      [],
      [input.values[0]],
      [input.values[0], input.values[0], input.values[1]],
      [..input.values, { variable: "unknown", value: "x", }],
      [{ variable: "product", value: " ", }, input.values[1]],
    ] {
    assert_true(
      (try? @review.instantiate_review_checklist(
        checklist,
        { ..input, values, },
        b"x",
      ))
      is Err(_),
    )
  }
}

///|
test "checklist roles require exact assignments and named human deciders" {
  let checklist = checklist_fixture()
  let input = checklist_input(b"x")
  for
    role_assignments in [
      [],
      [input.role_assignments[0]],
      [
        input.role_assignments[0],
        input.role_assignments[0],
        input.role_assignments[1],
      ],
      [..input.role_assignments, { role: "unknown", participant_id: "ops", }],
      [
        input.role_assignments[0],
        { role: "operator", participant_id: "missing", },
      ],
      [
        input.role_assignments[0],
        { role: "operator", participant_id: "author", },
      ],
    ] {
    assert_true(
      (try? @review.instantiate_review_checklist(
        checklist,
        { ..input, role_assignments, },
        b"x",
      ))
      is Err(_),
    )
  }
  // Distinct role slots cannot silently collapse two requests into one receipt.
  let two = {
    ..checklist.items[0],
    decisions: [
      ..checklist.items[0].decisions,
      { reviewer_role: "writer", prompt: "Second choice?", },
    ],
  }
  let same_person = {
    ..input,
    role_assignments: [
      { role: "writer", participant_id: "ops", },
      { role: "operator", participant_id: "ops", },
    ],
  }
  assert_true(
    (try? @review.instantiate_review_checklist(
      { ..checklist, items: [two], },
      same_person,
      b"x",
    ))
    is Err(_),
  )
}

///|
test "checklist declarations and text reject unknown missing duplicate and malformed names" {
  let checklist = checklist_fixture()
  for
    invalid in [
      { ..checklist, format: "moonchat.review-checklist.v2", },
      { ..checklist, checklist_id: "", },
      { ..checklist, title: " ", },
      { ..checklist, roles: ["writer", "writer", "operator"], },
      { ..checklist, roles: ["writer"], },
      { ..checklist, variables: ["product"], },
      { ..checklist, variables: ["product", "window", "unused"], },
      { ..checklist, variables: ["product", "window", "window"], },
      { ..checklist, items: [], },
      { ..checklist, items: [checklist.items[0], checklist.items[0]], },
    ] {
    assert_true((try? @review.catalog_review_checklist(invalid)) is Err(_))
    assert_true(
      (try? @review.parse_review_checklist(invalid.to_json().stringify()))
      is Err(_),
    )
  }
  for body in ["${}", "${product", "${bad name}", "${unknown}"] {
    let invalid = { ..checklist, items: [{ ..checklist.items[0], body, }], }
    assert_true((try? @review.catalog_review_checklist(invalid)) is Err(_))
  }
}

///|
test "checklist preserves review meanings and requires decisions for objections" {
  let checklist = checklist_fixture()
  for
    item in [
      { ..checklist.items[0], kind: "approve", },
      { ..checklist.items[0], author_role: "missing", },
      {
        ..checklist.items[0],
        decisions: [{ reviewer_role: "missing", prompt: "Choose?", }],
      },
      {
        ..checklist.items[0],
        decisions: [{ reviewer_role: "operator", prompt: " ", }],
      },
      {
        ..checklist.items[0],
        decisions: [
          checklist.items[0].decisions[0],
          checklist.items[0].decisions[0],
        ],
      },
      { ..checklist.items[0], decisions: [], },
      { ..checklist.items[0], kind: "objection", decisions: [], },
    ] {
    assert_true(
      (try? @review.catalog_review_checklist({ ..checklist, items: [item], }))
      is Err(_),
    )
  }
}

///|
test "checklist source and identity fields stay explicit and are validated" {
  let checklist = checklist_fixture()
  let input = checklist_input(b"x")
  assert_true(
    (try? @review.instantiate_review_checklist(checklist, input, b"changed"))
    is Err(_),
  )
  for
    invalid in [
      { ..input, format: "moonchat.review-checklist-input.v2", },
      { ..input, checklist_id: "different", },
      { ..input, review_id: "", },
      { ..input, source_artifact_ref: "../source", },
      { ..input, source_revision_id: "", },
      { ..input, conversation_id: "", },
      { ..input, recorded_at: "yesterday", },
      { ..input, participants: [..input.participants, input.participants[0]], },
    ] {
    assert_true(
      (try? @review.instantiate_review_checklist(checklist, invalid, b"x"))
      is Err(_),
    )
  }
  assert_true((try? @review.parse_review_checklist_input("{")) is Err(_))
  assert_true(
    (try? @review.parse_review_checklist_input(
      { ..input, format: "v2", }.to_json().stringify(),
    ))
    is Err(_),
  )
}

///|
test "checklist outputs can be edited without changing the reusable original or other reviews" {
  let checklist = checklist_fixture()
  let input = checklist_input(b"x")
  let before_template = checklist.to_json().stringify()
  let before_input = input.to_json().stringify()
  let agenda = @review.instantiate_review_checklist(checklist, input, b"x")
  let again = @review.instantiate_review_checklist(checklist, input, b"x")
  assert_true(agenda == again)
  agenda.items[0].evidence_refs.push("new/evidence.txt")
  agenda.items[0].decisions.clear()
  agenda.participants.clear()
  assert_eq(checklist.to_json().stringify(), before_template)
  assert_eq(input.to_json().stringify(), before_input)
  assert_eq(again.items[0].decisions.length(), 1)
  assert_eq(again.items[0].evidence_refs, ["releases/cafe.md"])
  assert_eq(again.participants.length(), 3)
  let edited = {
    ..again,
    items: [
      again.items[2],
      { ..again.items[0], body: "Revised local proposal", },
      again.items[1],
    ],
  }
  let bundle = @review.compile_review_agenda(edited, b"x")
  assert_eq(bundle.entries[1].body, "Revised local proposal")
  assert_eq(bundle.entries[1].entry_id, "entry-launch")
  assert_eq(bundle.required_decisions.length(), 2)
  assert_eq(bundle.decision_receipts.length(), 0)
}

///|
test "checklists without text variables and shared author roles remain useful" {
  let checklist = {
    ..checklist_fixture(),
    variables: [],
    roles: ["operator"],
    items: [
      {
        key: "owner",
        kind: "question",
        author_role: "operator",
        body: "Who owns rollback?",
        decisions: [
          { reviewer_role: "operator", prompt: "Is ownership documented?", },
        ],
      },
    ],
  }
  let input = {
    ..checklist_input(b"x"),
    values: [],
    role_assignments: [{ role: "operator", participant_id: "ops", }],
  }
  let agenda = @review.instantiate_review_checklist(checklist, input, b"x")
  assert_eq(agenda.items[0].body, "Who owns rollback?")
  assert_eq(agenda.items[0].author, "ops")
  assert_eq(
    @review.review_status(@review.compile_review_agenda(agenda, b"x")),
    "pending_review",
  )
}
