///|
fn slack_ordinal_plan_text(token : String) -> String {
  "{\"format\":\"moonchat.review-slack.v1\",\"source_digest\":\"unused\",\"selections\":[{\"ordinal\":" +
  token +
  ",\"key\":\"one\",\"kind\":\"question\",\"author\":\"editor\",\"note\":\"literal \\\"ordinal\\\":1.9 inside a note\",\"decisions\":[]}]}"
}

///|
test "Slack ordinal parsing rejects exact fractions including binary64 rounded integers" {
  for
    token in [
      "1.9", "1.0000000000000000000000000000000000000001", "0.99999999999999999999999999999999999",
      "999.99999999999999999999999", "10.00000000000000000001e-1", "1e-1000000",
      "1e1000000", "1e9999999999999999999999999999", "0", "-1", "-0", "1001", "2147483648",
      "true", "null", "\"1\"",
    ] {
    assert_true(
      (try? @review.parse_slack_review_import_plan(
        slack_ordinal_plan_text(token),
      ))
      is Err(_),
      msg=token,
    )
  }
  let escaped = slack_ordinal_plan_text("1.9").replace(
    old="\"ordinal\":",
    new="\"ord\\u0069nal\":",
  )
  assert_true((try? @review.parse_slack_review_import_plan(escaped)) is Err(_))
}

///|
test "Slack ordinal parsing preserves mathematically exact integral decimal and exponent forms" {
  for
    token in [
      "1", "1.0", "1e0", "1e+0", "10e-1", "0.01e2", "100000000000000000000000000000000e-32",
      "1.0000000000000000000000000", "1e000000000000000000000",
    ] {
    let plan = @review.parse_slack_review_import_plan(
      slack_ordinal_plan_text(token),
    )
    assert_eq(plan.selections[0].ordinal, 1, msg=token)
  }
  assert_eq(
    @review.parse_slack_review_import_plan(slack_ordinal_plan_text("1.5e1")).selections[0].ordinal,
    15,
  )
  assert_eq(
    @review.parse_slack_review_import_plan(slack_ordinal_plan_text("10.00e2")).selections[0].ordinal,
    1000,
  )
}

///|
test "Slack source constraint survives serialized agenda wording edits and blocks stale composition" {
  let bytes = slack_fixture()
  let imported = @review.import_slack_review(
    agenda_fixture(),
    slack_plan(bytes),
    bytes,
  )
  assert_eq(
    imported.source_digest_constraint,
    @review.review_source_digest(bytes),
  )
  let parsed = @review.parse_review_agenda(imported.to_json().stringify())
  let edited_items = parsed.items.copy()
  edited_items[3] = {
    ..edited_items[3],
    body: "Curator wording edited independently of the evidence snapshot.",
  }
  let edited = { ..parsed, items: edited_items, }
  let bundle = @review.compile_review_agenda(edited, bytes)
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(bundle.entries[3].body, edited_items[3].body)
  let changed = @utf8.encode(
    @utf8.decode(bytes).replace(
      old="Plan café",
      new="Do not release. The rollback check failed. café",
    ),
  )
  assert_true((try? @review.compile_review_agenda(parsed, changed)) is Err(_))
  assert_true((try? @review.compile_review_agenda(edited, changed)) is Err(_))
  assert_true(
    (try? @review.import_slack_review(parsed, slack_plan(changed), changed))
    is Err(_),
  )
  assert_true((try? @review.export_review_html(bundle, changed)) is Err(_))
  assert_true(
    (try? @review.compile_review_agenda(
      { ..parsed, source_digest_constraint: "malformed", },
      bytes,
    ))
    is Err(_),
  )
}

///|
test "Legacy agenda JSON remains unbound while explicit constraints and duplicate keys validate" {
  let agenda = agenda_fixture()
  let value = agenda.to_json()
  guard value is Object(fields) else { fail("object") }
  fields.remove("source_digest_constraint")
  let legacy = @review.parse_review_agenda(value.stringify())
  assert_eq(legacy.source_digest_constraint, "")
  @review.compile_review_agenda(legacy, b"first") |> ignore
  @review.compile_review_agenda(legacy, b"second") |> ignore
  fields["source_digest_constraint"] = (1 : Int).to_json()
  assert_true((try? @review.parse_review_agenda(value.stringify())) is Err(_))
  assert_true(
    (try? @review.parse_review_agenda(
      "{\"source_digest_constraint\":\"a\",\"source_digest_constraint\":\"\"}",
    ))
    is Err(_),
  )
}
