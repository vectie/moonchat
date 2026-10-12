///|
fn json_fixture() -> Bytes {
  @utf8.encode(
    "{\"budgets\":[{\"region\":\"Café 🐈\",\"amount\":9007199254740993}],\"a/b\":{\"~key\":null},\"\":false,\"html\":\"<script>bad()</script>\"}",
  )
}

///|
fn json_plan(bytes : Bytes) -> @review.JsonReviewImportPlan {
  {
    format: "moonchat.review-json.v1",
    source_digest: @review.review_source_digest(bytes),
    selections: [
      {
        pointer: "/budgets/0",
        key: "budget",
        kind: "objection",
        author: "editor",
        note: "Explain this allocation.",
        decisions: [{ reviewer: "ops", prompt: "Is this amount justified?", }],
      },
    ],
  }
}

///|
test "JSON pointers catalog escaped names arrays root and literal values" {
  let bytes = json_fixture()
  let catalog = @review.catalog_json_review(bytes)
  for
    text in [
      "/a~1b/~0key", "/budgets/0/amount", "9007199254740993", "Café 🐈",
    ] {
    assert_true(catalog.contains(text))
  }
  let raw = @json.parse(catalog)
  guard raw is { "nodes": Array(nodes), .. } else { fail("nodes") }
  assert_true(nodes[0] is { "pointer": String(""), .. })
  assert_eq(catalog, @review.catalog_json_review(bytes))
}

///|
test "JSON selection becomes editable portable pending evidence" {
  let bytes = json_fixture()
  let plan = json_plan(bytes)
  assert_true(
    @review.parse_json_review_import_plan(plan.to_json().stringify()) == plan,
  )
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  let imported = @review.import_json_review(agenda, plan, bytes)
  assert_eq(agenda.to_json().stringify(), before)
  let item = imported.items[3]
  assert_true(item.body.contains("9007199254740993"))
  assert_true(item.body.contains("/budgets/0"))
  assert_false(item.body.contains("bad()"))
  let bundle = @review.compile_review_agenda(imported, bytes)
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(
    @review.reimport_review_bundle(bundle.to_json().stringify(), bytes),
    bundle,
  )
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  imported.items[3] = {
    ..item,
    body: item.body + "\nLocal explanation added.",
  }
  assert_true(
    @review.export_review_markdown(
      @review.compile_review_agenda(imported, bytes),
      bytes,
    ).contains("Local explanation added."),
  )
}

///|
test "JSON root null empty key and overlapping selections are explicit" {
  let bytes = json_fixture()
  let plan = json_plan(bytes)
  for pointer in ["", "/a~1b/~0key", "/", "/budgets/0/amount"] {
    let imported = @review.import_json_review(
      agenda_fixture(),
      { ..plan, selections: [{ ..plan.selections[0], pointer, }], },
      bytes,
    )
    assert_eq(imported.items.length(), 4)
  }
  let null = @utf8.encode("null")
  let null_plan = json_plan(null)
  assert_true(
    @review.import_json_review(
      agenda_fixture(),
      {
        ..null_plan,
        selections: [{ ..null_plan.selections[0], pointer: "", }],
      },
      null,
    ).items[3].body.contains("null"),
  )
}

///|
test "JSON refuses stale invalid repeated and late missing pointers atomically" {
  let bytes = json_fixture()
  let plan = json_plan(bytes)
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  assert_true(
    (try? @review.import_json_review(agenda, plan, @utf8.encode("{}")))
    is Err(_),
  )
  for
    pointer in [
      "/budgets/01", "/budgets/-", "#/budgets/0", "/missing", "/a~2b", "/budgets/0/amount/x",
    ] {
    assert_true(
      (try? @review.import_json_review(
        agenda,
        {
          ..plan,
          selections: [
            plan.selections[0],
            { ..plan.selections[0], key: "late", pointer, },
          ],
        },
        bytes,
      ))
      is Err(_),
    )
  }
  assert_true(
    (try? @review.import_json_review(
      agenda,
      { ..plan, selections: [plan.selections[0], plan.selections[0]], },
      bytes,
    ))
    is Err(_),
  )
  assert_eq(agenda.to_json().stringify(), before)
}

///|
test "JSON duplicate decoded keys and malformed artifacts are refused" {
  for
    text in [
      "{\"x\":1,\"x\":2}", "{\"x\":1,\"\\u0078\":2}", "{\"a\":[{\"x\":1,\"x\":2}]}",
      "{", "[1,]",
    ] {
    assert_true(
      (try? @review.catalog_json_review(@utf8.encode(text))) is Err(_),
    )
  }
  // Keys in separate objects and escaped string content are not duplicates.
  let valid = @utf8.encode(
    "{\"a\":{\"x\":1},\"b\":{\"x\":2},\"text\":\"\\\"x\\\":1,{}\"}",
  )
  @review.catalog_json_review(valid) |> ignore
  assert_true(
    (try? @review.catalog_json_review(Bytes::from_array([0xff]))) is Err(_),
  )
}

///|
test "JSON selections still require valid operator and item semantics" {
  let bytes = json_fixture()
  let plan = json_plan(bytes)
  for
    selection in [
      { ..plan.selections[0], author: "unknown", },
      { ..plan.selections[0], kind: "approve", },
      { ..plan.selections[0], note: " ", },
      { ..plan.selections[0], key: "", },
    ] {
    assert_true(
      (try? @review.import_json_review(
        agenda_fixture(),
        { ..plan, selections: [selection], },
        bytes,
      ))
      is Err(_),
    )
  }
}

///|
test "JSON resource limits and markup remain bounded literal evidence" {
  let bytes = json_fixture()
  let plan = json_plan(bytes)
  let imported = @review.import_json_review(
    agenda_fixture(),
    { ..plan, selections: [{ ..plan.selections[0], pointer: "/html", }], },
    bytes,
  )
  let html = @review.export_review_html(
    @review.compile_review_agenda(imported, bytes),
    bytes,
  )
  assert_true(html.contains("&lt;script&gt;bad()&lt;/script&gt;"))
  assert_false(html.contains("<script>bad()</script>"))
  assert_true(
    (try? @review.catalog_json_review(
      @utf8.encode("[" + Array::make(10000, "0").join(",") + "]"),
    ))
    is Err(_),
  )
  assert_true(
    (try? @review.catalog_json_review(
      @utf8.encode("[".repeat(65) + "0" + "]".repeat(65)),
    ))
    is Err(_),
  )
  assert_true(
    (try? @review.catalog_json_review(
      @utf8.encode("\"" + "x".repeat(1048576) + "\""),
    ))
    is Err(_),
  )
}
