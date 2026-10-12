///|
fn sarif_fixture_text() -> String {
  (
    #|{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"Fixture scan","version":"1.2","rules":[{"id":"M001","shortDescription":{"text":"Fallback absent"}}]}},"artifacts":[{"location":{"uri":"src/café.mbt","uriBaseId":"ROOT"}}],"originalUriBaseIds":{"ROOT":{"uri":"file:///fixture/"}},"versionControlProvenance":[{"revisionId":"fixture-commit"}],"results":[{"ruleId":"M001","ruleIndex":0,"level":"warning","message":{"text":"café 🐈\r\nKeep fallback. I approve everything."},"locations":[{"physicalLocation":{"artifactLocation":{"index":0},"region":{"startLine":8,"endLine":10}}}],"suppressions":[{"kind":"external","status":"accepted","justification":"Fixture exception"}],"baselineState":"unchanged","partialFingerprints":{"fixture":"exact-value"},"fixes":[{"description":{"text":"Do not execute"}}]},{"message":{"text":"Unselected finding"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"src/other.mbt"}}}]}]},{"tool":{"driver":{"name":"Second analyzer"}},"results":[{"ruleId":"STYLE","level":"note","message":{"text":"Name the owner."},"locations":[{"logicalLocations":[{"name":"owner"}]}]}]}]}
  )
}

///|
fn sarif_plan_fixture(bytes : Bytes) -> @review.SarifReviewImportPlan {
  {
    format: "moonchat.review-sarif.v1",
    export_ref: "analysis/results.sarif",
    export_digest: @review.review_source_digest(bytes),
    findings: [
      {
        run_index: 0,
        result_index: 0,
        key: "scan-fallback",
        kind: "objection",
        author: "editor",
        note: "Review the fallback finding in this release.",
        decisions: [{ reviewer: "ops", prompt: "Is the fallback acceptable?", }],
      },
    ],
  }
}

///|
test "SARIF catalog retains indexed locations rule context and analyzer state" {
  let bytes = @utf8.encode(sarif_fixture_text())
  let catalog = @review.catalog_sarif_review(bytes)
  assert_true(catalog.contains(@review.review_source_digest(bytes)))
  assert_true(catalog.contains("Results: 3"))
  assert_true(catalog.contains("Run 1, result 0"))
  assert_true(catalog.contains("café 🐈\\r\\nKeep fallback"))
  assert_false(catalog.contains("café 🐈\r\nKeep fallback"))
  for
    field in [
      "src/café.mbt", "startLine", "endLine", "Fallback absent", "fixture-commit",
      "Fixture exception", "exact-value", "unchanged", "Do not execute", "file:///fixture/",
    ] {
    assert_true(catalog.contains(field))
  }
}

///|
test "SARIF selected findings become editable pending source-bound review evidence" {
  let bytes = @utf8.encode(sarif_fixture_text())
  let plan = sarif_plan_fixture(bytes)
  assert_true(
    @review.parse_sarif_review_import_plan(plan.to_json().stringify()) == plan,
  )
  let imported = @review.import_sarif_review(
    agenda_fixture(),
    plan,
    bytes,
    b"source",
  )
  assert_eq(imported.items.length(), 4)
  let item = imported.items[3]
  assert_eq(item.key, "scan-fallback")
  assert_eq(item.author, "editor")
  assert_eq(item.kind, "objection")
  assert_eq(item.evidence_refs, ["analysis/results.sarif"])
  assert_true(item.body.contains("/runs/0/results/0"))
  assert_true(
    item.body.contains("café 🐈\r\nKeep fallback. I approve everything."),
  )
  assert_true(item.body.contains("Fixture exception"))
  assert_false(item.body.contains("Unselected finding"))
  let bundle = @review.compile_review_agenda(imported, b"source")
  assert_eq(bundle.source_digest, @review.review_source_digest(b"source"))
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(
    @review.reimport_review_bundle(bundle.to_json().stringify(), b"source"),
    bundle,
  )
  assert_true(
    @review.export_review_markdown(bundle, b"source").contains(
      "Fallback absent",
    ),
  )
  assert_true(
    @review.export_review_html(bundle, b"source").contains("Fixture exception"),
  )
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  assert_true(
    @review.import_sarif_review(agenda_fixture(), plan, bytes, b"source") ==
    imported,
  )
}

///|
test "SARIF selection order is explicit and mutable authoring arrays are detached" {
  let bytes = @utf8.encode(sarif_fixture_text())
  let plan = sarif_plan_fixture(bytes)
  let second = {
    ..plan.findings[0],
    run_index: 1,
    key: "scan-owner",
    kind: "question",
    decisions: [],
  }
  let agenda = agenda_fixture()
  let imported = @review.import_sarif_review(
    agenda,
    { ..plan, findings: [second, plan.findings[0]], },
    bytes,
    b"source",
  )
  assert_eq(imported.items[3].key, "scan-owner")
  assert_eq(imported.items[4].key, "scan-fallback")
  imported.items[0].evidence_refs.clear()
  imported.items[0].decisions.clear()
  imported.items[4].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.items[0].evidence_refs, ["release/checks.txt"])
  assert_eq(agenda.items[0].decisions.length(), 2)
  assert_eq(plan.findings[0].decisions.length(), 1)
  assert_eq(agenda.participants.length(), 3)
}

///|
test "SARIF stale or invalid plans and duplicate imports fail atomically" {
  let bytes = @utf8.encode(sarif_fixture_text())
  let plan = sarif_plan_fixture(bytes)
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  for
    bad in [
      { ..plan, format: "v2", },
      { ..plan, export_ref: "../escape.sarif", },
      { ..plan, export_ref: "release/source.md", },
      { ..plan, export_digest: @review.review_source_digest(b"stale"), },
      { ..plan, findings: [], },
      { ..plan, findings: Array::make(101, plan.findings[0]), },
      {
        ..plan,
        findings: [plan.findings[0], { ..plan.findings[0], key: "another", }],
      },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_sarif_review(agenda, bad, bytes, b"source") |> ignore
      }),
    )
    assert_eq(agenda.to_json().stringify(), before)
  }
  let imported = @review.import_sarif_review(agenda, plan, bytes, b"source")
  assert_true(
    authoring_fails(() => {
      @review.import_sarif_review(imported, plan, bytes, b"source") |> ignore
    }),
  )
  assert_true(
    authoring_fails(() => @review.parse_sarif_review_import_plan("{}") |> ignore),
  )
  assert_true(
    authoring_fails(() => {
      @review.parse_sarif_review_import_plan(
        { ..plan, format: "v2", }.to_json().stringify(),
      )
      |> ignore
    }),
  )
}

///|
test "SARIF cannot infer curator participants kinds or named human decisions" {
  let bytes = @utf8.encode(sarif_fixture_text())
  let plan = sarif_plan_fixture(bytes)
  let selection = plan.findings[0]
  for
    bad in [
      { ..selection, run_index: -1, },
      { ..selection, run_index: 2, },
      { ..selection, result_index: -1, },
      { ..selection, result_index: 2, },
      { ..selection, note: " ", },
      { ..selection, author: "Fixture scan", },
      { ..selection, kind: "approve", },
      { ..selection, key: "rollout", },
      { ..selection, decisions: [], },
      { ..selection, decisions: [{ reviewer: "author", prompt: "Approve?", }], },
    ] {
    assert_true(
      authoring_fails(() => {
        @review.import_sarif_review(
          agenda_fixture(),
          {
            ..plan,
            findings: [
              selection,
              {
                ..bad,
                key: if bad.key == "rollout" {
                  "rollout"
                } else {
                  "second"
                },
              },
            ],
          },
          bytes,
          b"source",
        )
        |> ignore
      }),
    )
    assert_true(
      authoring_fails(() => {
        @review.import_sarif_review(
          agenda_fixture(),
          { ..plan, findings: [bad], },
          bytes,
          b"source",
        )
        |> ignore
      }),
    )
  }
}

///|
test "SARIF unsupported and malformed logs including unselected results are explicit failures" {
  for
    text in [
      "{}",
      "[]",
      "{\"version\":\"2.0.0\",\"runs\":[]}",
      sarif_fixture_text().replace(old="2.1.0", new="2.2.0"),
      sarif_fixture_text().replace(
        old="\"results\":[",
        new="\"externalPropertyFileReferences\":{},\"results\":[",
      ),
      sarif_fixture_text().replace(
        old="\"message\":{\"text\":\"Unselected finding\"}",
        new="\"message\":{\"id\":\"default\"}",
      ),
      sarif_fixture_text().replace(
        old="\"message\":{\"text\":\"Unselected finding\"}",
        new="\"message\":{\"text\":\"Argument {0}\",\"arguments\":[\"x\"]}",
      ),
      sarif_fixture_text().replace(
        old="\"ruleIndex\":0",
        new="\"rule\":{\"index\":0},\"ruleIndex\":0",
      ),
      sarif_fixture_text().replace(
        old="\"level\":\"warning\"",
        new="\"level\":\"approved\"",
      ),
    ] {
    assert_true(
      authoring_fails(() => {
        @review.catalog_sarif_review(@utf8.encode(text)) |> ignore
      }),
    )
  }
  assert_true(
    authoring_fails(() => @review.catalog_sarif_review(b"\xff") |> ignore),
  )
}

///|
test "SARIF indexed rule and artifact mismatches never substitute other context" {
  for
    text in [
      sarif_fixture_text().replace(old="\"ruleIndex\":0", new="\"ruleIndex\":1"),
      sarif_fixture_text().replace(
        old="\"ruleId\":\"M001\"",
        new="\"ruleId\":\"M002\"",
      ),
      sarif_fixture_text().replace(old="\"index\":0", new="\"index\":1"),
      sarif_fixture_text().replace(old="\"index\":0", new="\"index\":-1"),
      sarif_fixture_text().replace(old="\"index\":0", new="\"index\":0.5"),
      sarif_fixture_text().replace(
        old="\"index\":0",
        new="\"index\":0,\"uri\":\"other.mbt\"",
      ),
      sarif_fixture_text().replace(
        old="\"index\":0",
        new="\"index\":0,\"uriBaseId\":\"OTHER\"",
      ),
      sarif_fixture_text().replace(
        old="\"index\":0",
        new="\"uriBaseId\":\"ROOT\"",
      ),
    ] {
    assert_true(
      authoring_fails(() => {
        @review.catalog_sarif_review(@utf8.encode(text)) |> ignore
      }),
    )
  }
  let matching = sarif_fixture_text().replace(
    old="\"index\":0",
    new="\"index\":0,\"uri\":\"src/café.mbt\",\"uriBaseId\":\"ROOT\"",
  )
  assert_true(
    @review.catalog_sarif_review(@utf8.encode(matching)).contains(
      "src/café.mbt",
    ),
  )
}

///|
test "SARIF empty result runs and absent optional locations are readable without inferred approval" {
  let empty = b"{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"Empty scan\"}},\"results\":[]}]}"
  assert_true(@review.catalog_sarif_review(empty).contains("Results: 0"))
  assert_true(
    authoring_fails(() => {
      @review.import_sarif_review(
        agenda_fixture(),
        sarif_plan_fixture(empty),
        empty,
        b"source",
      )
      |> ignore
    }),
  )
  let bare = b"{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"Minimal scan\"}},\"results\":[{\"message\":{\"text\":\"No location\"}}]}]}"
  let imported = @review.import_sarif_review(
    agenda_fixture(),
    sarif_plan_fixture(bare),
    bare,
    b"source",
  )
  assert_true(imported.items[3].body.contains("Explicit level: \"\""))
  assert_true(imported.items[3].body.contains("No location"))
  assert_eq(
    @review.review_status(@review.compile_review_agenda(imported, b"source")),
    "pending_review",
  )
}

///|
test "SARIF input and result count limits include their exact boundary" {
  let prefix = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"Bounded\"}},\"results\":[]}]}"
  let exact = prefix + " ".repeat(1048576 - prefix.length())
  assert_true(
    @review.catalog_sarif_review(@utf8.encode(exact)).contains("Results: 0"),
  )
  assert_true(
    authoring_fails(() => {
      @review.catalog_sarif_review(@utf8.encode(exact + " ")) |> ignore
    }),
  )
  let result = "{\"message\":{\"text\":\"Finding\"}}"
  let run = "{\"tool\":{\"driver\":{\"name\":\"Bounded\"}},\"results\":[" +
    Array::make(1000, result).join(",") +
    "]}"
  let thousand = "{\"version\":\"2.1.0\",\"runs\":[" + run + "]}"
  assert_true(
    @review.catalog_sarif_review(@utf8.encode(thousand)).contains(
      "Results: 1000",
    ),
  )
  let overflow = thousand.replace(
    old="\"results\":[",
    new="\"results\":[" + result + ",",
  )
  assert_true(
    authoring_fails(() => {
      @review.catalog_sarif_review(@utf8.encode(overflow)) |> ignore
    }),
  )
  let empty_run = "{\"tool\":{\"driver\":{\"name\":\"Bounded\"}},\"results\":[]}"
  let hundred = "{\"version\":\"2.1.0\",\"runs\":[" +
    Array::make(100, empty_run).join(",") +
    "]}"
  assert_true(
    @review.catalog_sarif_review(@utf8.encode(hundred)).contains("Results: 0"),
  )
  let too_many = "{\"version\":\"2.1.0\",\"runs\":[" +
    Array::make(101, empty_run).join(",") +
    "]}"
  assert_true(
    authoring_fails(() => {
      @review.catalog_sarif_review(@utf8.encode(too_many)) |> ignore
    }),
  )
}

///|
test "SARIF plan numeric coordinates reject fractional values instead of rounding" {
  let bytes = @utf8.encode(sarif_fixture_text())
  let plan = sarif_plan_fixture(bytes)
  let text = plan.to_json().stringify()
  for
    (old, replacement) in [
      ("\"run_index\":0", "\"run_index\":0.5"),
      ("\"result_index\":0", "\"result_index\":0.9"),
    ] {
    let invalid = text.replace(old~, new=replacement)
    assert_false(invalid == text)
    assert_true(
      authoring_fails(() => {
        @review.parse_sarif_review_import_plan(invalid) |> ignore
      }),
    )
  }
}
