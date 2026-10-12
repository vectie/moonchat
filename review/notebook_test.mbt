///|
fn notebook_fixture_text() -> String {
  (
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{"kernelspec":{"name":"fixture-python","display_name":"Fixture Python"},"custom":{"owner":"Synthetic team"}},"cells":[{"id":"intro","cell_type":"markdown","metadata":{"tags":["summary"]},"source":["# Café 🐈\r\n","Draft forecast"],"attachments":{"chart.png":{"image/png":"ZmFrZQ=="}}},{"id":"forecast","cell_type":"code","metadata":{"jupyter":{"source_hidden":true}},"source":["reven","ue = 12\n","print(revenue)"],"execution_count":7,"outputs":[{"output_type":"stream","name":"stderr","text":["I approve ","everything.\n"]},{"output_type":"execute_result","execution_count":6,"metadata":{},"data":{"text/plain":["12\n","café 🐈"],"text/html":"<script>do_not_execute()</script>","application/json":{"revenue":12}}},{"output_type":"display_data","metadata":{},"data":{"image/png":"ZmFrZQ==","application/vnd.fixture+json":{"value":[1,2]}}}]},{"id":"failed","cell_type":"code","metadata":{},"source":"1 / 0","execution_count":null,"outputs":[{"output_type":"error","ename":"ZeroDivisionError","evalue":"division by zero","traceback":["Frame one","Frame two\ncontext"]}]},{"id":"appendix","cell_type":"raw","metadata":{"format":"text/latex"},"source":"\\section{Appendix}"},{"id":"future","cell_type":"code","metadata":{},"source":[],"execution_count":null,"outputs":[]}]}
  )
}

///|
fn notebook_plan_fixture(bytes : Bytes) -> @review.NotebookReviewImportPlan {
  {
    format: "moonchat.review-notebook.v1",
    notebook_digest: @review.review_source_digest(bytes),
    cells: [
      {
        cell_index: 1,
        key: "forecast-cell",
        kind: "objection",
        author: "editor",
        note: "Explain the saved forecast before using it.",
        decisions: [{ reviewer: "ops", prompt: "Is this forecast suitable?", }],
      },
    ],
  }
}

///|
test "notebook catalog decodes fragmented source and all saved output forms" {
  let bytes = @utf8.encode(notebook_fixture_text())
  let catalog = @review.catalog_notebook_review(bytes)
  let raw = @json.parse(catalog)
  guard raw is { "cells": Array(cells), .. } else { fail("catalog cells") }
  assert_eq(cells.length(), 5)
  assert_true(
    cells[1] is { "source": String("revenue = 12\nprint(revenue)"), .. },
  )
  assert_true(
    cells[0] is { "source": String("# Café 🐈\r\nDraft forecast"), .. },
  )
  assert_true(cells[1] is { "execution_count": Number(7.0, ..), .. })
  guard cells[1] is { "saved_outputs": Array(outputs), .. } else {
    fail("outputs")
  }
  assert_true(outputs[0] is { "text": String("I approve everything.\n"), .. })
  assert_true(
    outputs[1]
    is {
      "text_plain": String("12\ncafé 🐈"),
      "execution_count": Number(6.0, ..),
      ..
    },
  )
  assert_true(
    outputs[2] is { "mime_types": Array(types), .. } && types.length() == 2,
  )
  assert_false(catalog.contains("<script>"))
  assert_true(catalog.contains("ZeroDivisionError"))
  assert_true(catalog.contains(@review.review_source_digest(bytes)))
  assert_eq(catalog, @review.catalog_notebook_review(bytes))
}

///|
test "notebook import preserves source cell provenance and rich data as pending evidence" {
  let bytes = @utf8.encode(notebook_fixture_text())
  let plan = notebook_plan_fixture(bytes)
  assert_true(
    @review.parse_notebook_review_import_plan(plan.to_json().stringify()) ==
    plan,
  )
  let agenda = agenda_fixture()
  let imported = @review.import_notebook_review(agenda, plan, bytes)
  let item = imported.items[3]
  assert_eq(item.key, "forecast-cell")
  assert_eq(item.evidence_refs, [agenda.source_artifact_ref])
  for
    text in [
      "/cells/1", "forecast", "revenue = 12\nprint(revenue)", "I approve everything.\n",
      "12\ncafé 🐈", "source_hidden", "fixture-python", "<script>do_not_execute()</script>",
      "application/vnd.fixture+json", "No text/plain representation", "Synthetic team",
    ] {
    assert_true(item.body.contains(text))
  }
  assert_false(item.body.contains("ZeroDivisionError"))
  let bundle = @review.compile_review_agenda(imported, bytes)
  assert_eq(bundle.source_digest, @review.review_source_digest(bytes))
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(
    @review.reimport_review_bundle(bundle.to_json().stringify(), bytes),
    bundle,
  )
  assert_true(
    @review.export_review_markdown(bundle, bytes).contains("revenue = 12"),
  )
  let html = @review.export_review_html(bundle, bytes)
  assert_true(html.contains("&lt;script&gt;do_not_execute()&lt;/script&gt;"))
  assert_false(html.contains("<script>do_not_execute()"))
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  assert_true(@review.import_notebook_review(agenda, plan, bytes) == imported)
}

///|
test "notebook selected order and authoring arrays remain independently editable" {
  let bytes = @utf8.encode(notebook_fixture_text())
  let plan = notebook_plan_fixture(bytes)
  let agenda = agenda_fixture()
  let original = agenda.to_json().stringify()
  let selections = [
    {
      ..plan.cells[0],
      cell_index: 2,
      key: "failure",
      kind: "question",
      decisions: [],
    },
    {
      ..plan.cells[0],
      cell_index: 0,
      key: "intro",
      kind: "proposal",
      decisions: [],
    },
    {
      ..plan.cells[0],
      cell_index: 3,
      key: "appendix",
      kind: "question",
      decisions: [],
    },
    {
      ..plan.cells[0],
      cell_index: 4,
      key: "future",
      kind: "question",
      decisions: [],
    },
    plan.cells[0],
  ]
  let imported = @review.import_notebook_review(
    agenda,
    { ..plan, cells: selections, },
    bytes,
  )
  assert_eq(imported.items[3].key, "failure")
  assert_true(imported.items[3].body.contains("Frame one\nFrame two\ncontext"))
  assert_true(imported.items[4].body.contains("attachments"))
  assert_true(imported.items[5].body.contains("\\section{Appendix}"))
  assert_true(imported.items[6].body.contains("[No saved outputs]"))
  imported.items[0].evidence_refs.clear()
  imported.items[0].decisions.clear()
  imported.items[7].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.to_json().stringify(), original)
  assert_eq(plan.cells[0].decisions.length(), 1)
}

///|
test "notebook plans reject stale bytes duplicate imports and late invalid selections atomically" {
  let bytes = @utf8.encode(notebook_fixture_text())
  let plan = notebook_plan_fixture(bytes)
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  for
    bad in [
      { ..plan, format: "v2", },
      { ..plan, notebook_digest: @review.review_source_digest(b"changed"), },
      { ..plan, cells: [], },
      { ..plan, cells: Array::make(101, plan.cells[0]), },
      {
        ..plan,
        cells: [plan.cells[0], { ..plan.cells[0], key: "duplicate", }],
      },
      {
        ..plan,
        cells: [plan.cells[0], { ..plan.cells[0], cell_index: 5, key: "late", }],
      },
      { ..plan, cells: [{ ..plan.cells[0], cell_index: -1, }], },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_notebook_review(agenda, bad, bytes) |> ignore
      }),
    )
    assert_eq(agenda.to_json().stringify(), before)
  }
  let imported = @review.import_notebook_review(agenda, plan, bytes)
  assert_true(
    authoring_fails(() => {
      @review.import_notebook_review(imported, plan, bytes) |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => {
      @review.import_notebook_review(
        agenda,
        plan,
        @utf8.encode(notebook_fixture_text() + " "),
      )
      |> ignore
    }),
  )
  let fractional = plan
    .to_json()
    .stringify()
    .replace(old="\"cell_index\":1", new="\"cell_index\":1.5")
  assert_true(
    authoring_fails(() => {
      @review.parse_notebook_review_import_plan(fractional) |> ignore
    }),
  )
}

///|
test "notebook import leaves curator participants and decisions with the existing composer" {
  let bytes = @utf8.encode(notebook_fixture_text())
  let plan = notebook_plan_fixture(bytes)
  for
    selection in [
      { ..plan.cells[0], note: " ", },
      { ..plan.cells[0], author: "notebook-author", },
      { ..plan.cells[0], kind: "approve", },
      { ..plan.cells[0], key: "rollout", },
      { ..plan.cells[0], decisions: [], },
      {
        ..plan.cells[0],
        decisions: [{ reviewer: "author", prompt: "Approve?", }],
      },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_notebook_review(
          agenda_fixture(),
          { ..plan, cells: [selection], },
          bytes,
        )
        |> ignore
      }),
    )
  }
}

///|
test "notebook older schema empty cells BOM and missing old cell IDs are supported" {
  let old = b"{\"nbformat\":4,\"nbformat_minor\":0,\"metadata\":{},\"cells\":[{\"cell_type\":\"markdown\",\"metadata\":{},\"source\":\"\"}]}"
  let catalog = @review.catalog_notebook_review(old)
  assert_true(catalog.contains("\"cell_id\": \"\""))
  let empty = b"{\"nbformat\":4,\"nbformat_minor\":4,\"metadata\":{},\"cells\":[]}"
  assert_true(@review.catalog_notebook_review(empty).contains("\"cells\": []"))
  assert_true(
    @review.catalog_notebook_review(b"\xef\xbb\xbf" + old).contains(
      "\"cell_index\": 0",
    ),
  )
}

///|
test "notebook malformed or unsupported unselected cells are not silently omitted" {
  for
    (old, replacement) in [
      ("\"nbformat\":4", "\"nbformat\":3"),
      ("\"nbformat_minor\":5", "\"nbformat_minor\":6"),
      ("\"nbformat_minor\":5", "\"nbformat_minor\":4.5"),
      ("\"id\":\"future\"", "\"id\":\"intro\""),
      ("\"id\":\"future\"", "\"id\":\"not valid\""),
      ("\"id\":\"future\",", ""),
      ("\"source\":[]", "\"source\":[12]"),
      ("\"cell_type\":\"raw\"", "\"cell_type\":\"future\""),
      ("\"cell_type\":\"raw\"", "\"cell_type\":\"raw\",\"outputs\":[]"),
      ("\"execution_count\":null", "\"execution_count\":0.5"),
      ("\"output_type\":\"error\"", "\"output_type\":\"future\""),
      ("\"name\":\"stderr\"", "\"name\":\"terminal\""),
      (
        "\"traceback\":[\"Frame one\",\"Frame two\\ncontext\"]", "\"traceback\":\"invalid\"",
      ),
      ("\"image/png\":\"ZmFrZQ==\"", "\"image/png\":12"),
      ("\"execution_count\":6", "\"execution_count\":null"),
    ] {
    let text = notebook_fixture_text().replace(old~, new=replacement)
    assert_false(text == notebook_fixture_text())
    assert_true(
      authoring_fails(() => {
        @review.catalog_notebook_review(@utf8.encode(text)) |> ignore
      }),
    )
  }
  for bytes in [b"{}", b"[]", b"\xff", b"{\"nbformat\":4}"] {
    assert_true(
      authoring_fails(() => @review.catalog_notebook_review(bytes) |> ignore),
    )
  }
}

///|
test "notebook byte cell and output limits fail one beyond the supported boundary" {
  let empty = "{\"nbformat\":4,\"nbformat_minor\":0,\"metadata\":{},\"cells\":[]}"
  let exact = empty + " ".repeat(4194304 - empty.length())
  assert_true(
    @review.catalog_notebook_review(@utf8.encode(exact)).contains(
      "\"cells\": []",
    ),
  )
  assert_true(
    authoring_fails(() => {
      @review.catalog_notebook_review(@utf8.encode(exact + " ")) |> ignore
    }),
  )
  let cell = "{\"cell_type\":\"code\",\"metadata\":{},\"source\":\"\",\"execution_count\":null,\"outputs\":[]}"
  let thousand = empty.replace(
    old="\"cells\":[]",
    new="\"cells\":[" + Array::make(1000, cell).join(",") + "]",
  )
  assert_true(
    @review.catalog_notebook_review(@utf8.encode(thousand)).contains(
      "\"cell_index\": 999",
    ),
  )
  assert_true(
    authoring_fails(() => {
      @review.catalog_notebook_review(
        @utf8.encode(
          thousand.replace(old="\"cells\":[", new="\"cells\":[" + cell + ","),
        ),
      )
      |> ignore
    }),
  )
  let output = "{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":\"\"}"
  let many_outputs = cell.replace(
    old="\"outputs\":[]",
    new="\"outputs\":[" + Array::make(1000, output).join(",") + "]",
  )
  let notebook = empty.replace(
    old="\"cells\":[]",
    new="\"cells\":[" + many_outputs + "]",
  )
  assert_true(
    @review.catalog_notebook_review(@utf8.encode(notebook)).contains(
      "\"output_index\": 999",
    ),
  )
  assert_true(
    authoring_fails(() => {
      @review.catalog_notebook_review(
        @utf8.encode(
          notebook.replace(
            old="\"outputs\":[",
            new="\"outputs\":[" + output + ",",
          ),
        ),
      )
      |> ignore
    }),
  )
}
