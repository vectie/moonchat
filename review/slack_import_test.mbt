///|
fn slack_fixture() -> Bytes {
  @utf8.encode(
    (
      #|[
      #| { "type":"message", "user":"U_ORIGINAL", "text":"Plan café 🌙 <https://example.invalid|link> and {braces} with \"quotes\".", "ts":"1791882000.000001", "reactions":[{"name":"white_check_mark","count":9,"users":["U_ONE"]}], "attachments":[{"text":"<script>evil()</script>","image_url":"https://example.invalid/private.png"}], "blocks":[{"type":"rich_text","elements":[]}], "extra":{"keep":"all"} },
      #| {"type":"message","user":"U_REPLY","text":"Who owns rollback?","ts":"1791882060.000002","thread_ts":"1791790000.000001"},
      #| {"type":"message","subtype":"message_changed","user":"U_ORIGINAL","text":"Replacement","ts":"1791882080.000003","original_ts":"1791882000.000001","previous":{"text":"Original"}},
      #| {"type":"message","subtype":"message_deleted","ts":"1791882090.000004","previous":{"text":"Deleted","ts":"1791882001.000001"}},
      #| {"type":"message","subtype":"channel_join","text":"joined","ts":"1791882100.000005","user":"U_JOIN"}
      #|]
    ),
  )
}

///|
fn slack_plan(bytes : Bytes) -> @review.SlackReviewImportPlan {
  {
    format: "moonchat.review-slack.v1",
    source_digest: @review.review_source_digest(bytes),
    selections: [
      {
        ordinal: 1,
        key: "slack-plan",
        kind: "proposal",
        author: "editor",
        note: "Evaluate this recorded proposal; reactions are not decisions.",
        decisions: [{ reviewer: "ops", prompt: "Is this proposal ready?", }],
      },
    ],
  }
}

///|
fn slack_rows(bytes : Bytes) -> Array[Json] raise {
  guard @json.parse(@review.catalog_slack_review(bytes))
    is { "messages": Array(rows), .. } else {
    fail("catalog rows")
  }
  rows
}

///|
test "Slack catalog retains exact raw objects metadata ordinals and archival warnings" {
  let bytes = slack_fixture()
  let catalog = @review.catalog_slack_review(bytes)
  assert_eq(catalog, @review.catalog_slack_review(bytes))
  assert_true(catalog.contains(@review.review_source_digest(bytes)))
  let rows = slack_rows(bytes)
  assert_eq(rows.length(), 5)
  assert_true(
    rows[0]
    is {
      "ordinal": Number(1, ..),
      "selectable": True,
      "classification": String("ordinary_snapshot"),
      ..
    },
  )
  assert_true(
    rows[1]
    is { "recorded": { "thread_ts": String("1791790000.000001"), .. }, .. },
  )
  assert_true(
    rows[2]
    is {
      "selectable": False,
      "classification": String("archival_message_changed"),
      ..
    },
  )
  assert_true(
    rows[3]
    is {
      "selectable": False,
      "classification": String("archival_message_deleted"),
      ..
    },
  )
  assert_true(rows[4] is { "ordinal": Number(5, ..), "selectable": False, .. })
  guard rows[0] is { "raw_message": String(raw), .. } else { fail("raw") }
  assert_true(@utf8.decode(bytes).contains(raw))
  assert_true(raw.has_prefix("{ \"type\""))
  assert_true(raw.contains("\\\"quotes\\\""))
  assert_true(raw.contains("\"extra\":{\"keep\":\"all\"}"))
}

///|
test "Slack import composes pending quoted evidence through existing APIs" {
  let bytes = slack_fixture()
  let plan = slack_plan(bytes)
  assert_true(
    @review.parse_slack_review_import_plan(plan.to_json().stringify()) == plan,
  )
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  let imported = @review.import_slack_review(agenda, plan, bytes)
  assert_eq(agenda.to_json().stringify(), before)
  assert_eq(imported.items.length(), 4)
  let item = imported.items[3]
  assert_eq(item.author, "editor")
  assert_eq(item.evidence_refs, [agenda.source_artifact_ref])
  for
    text in [
      "U_ORIGINAL", "white_check_mark", "attachments", "raw_message", "blocks", "not a decision receipt",
      "not a verified mapping",
    ] {
    assert_true(item.body.contains(text), msg=text)
  }
  assert_false(item.body.contains("Who owns rollback?"))
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  let bundle = @review.compile_review_agenda(imported, bytes)
  assert_eq(bundle.source_digest, plan.source_digest)
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(@review.claim_class(bundle), "research-evidence")
  let serialized = @review.serialize_review_bundle(bundle, bundle.source_digest)
  assert_eq(@review.reimport_review_bundle(serialized, bytes), bundle)
  let form = @review.prepare_review_decisions(serialized, bytes, "ops")
  assert_true(
    form.choices.all(choice => choice.outcome == "" && choice.receipt_id == ""),
  )
  let markdown = @review.export_review_markdown(bundle, bytes)
  assert_true(markdown.contains("Is this proposal ready?"))
  let html = @review.export_review_html(bundle, bytes)
  assert_true(html.contains("&lt;script&gt;evil()&lt;/script&gt;"))
  assert_false(html.contains("<script>evil()</script>"))
  assert_false(html.contains("src=\"https://example.invalid/private.png\""))
  assert_false(html.contains("href=\"https://example.invalid\""))
}

///|
test "Slack supported snapshots include bot action file and edited records with literal context" {
  for
    raw in [
      "{\"type\":\"message\",\"subtype\":\"bot_message\",\"bot_id\":\"B1\",\"text\":\"Build passed\",\"ts\":\"1.000001\"}",
      "{\"type\":\"message\",\"subtype\":\"me_message\",\"user\":\"U1\",\"text\":\"waves\",\"ts\":\"1.000001\"}",
      "{\"type\":\"message\",\"subtype\":\"file_share\",\"user\":\"U1\",\"text\":\"\",\"ts\":\"1.000001\",\"files\":[{\"url_private\":\"https://example.invalid\"}]}",
      "{\"type\":\"message\",\"user\":\"U1\",\"text\":\"edited snapshot\",\"ts\":\"1.000001\",\"edited\":{\"user\":\"U2\",\"ts\":\"2.000001\"},\"hidden\":false}",
    ] {
    let bytes = @utf8.encode("[" + raw + "]")
    let rows = slack_rows(bytes)
    assert_true(rows[0] is { "selectable": True, .. })
    guard rows[0] is { "raw_message": String(recorded), .. } else {
      fail("raw")
    }
    assert_eq(recorded, raw)
    let imported = @review.import_slack_review(
      agenda_fixture(),
      slack_plan(bytes),
      bytes,
    )
    assert_true(imported.items[3].body.contains(raw.to_json().stringify()))
    if raw.contains("edited snapshot") {
      assert_true(imported.items[3].body.contains("ordinary_edited_snapshot"))
    }
  }
}

///|
test "Slack missing thread roots and duplicate timestamps remain ordinal snapshots" {
  let raw = "{\"type\":\"message\",\"user\":\"U1\",\"text\":\"reply\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\"}"
  let bytes = @utf8.encode("[" + raw + "," + raw + "]")
  let plan = slack_plan(bytes)
  let first = plan.selections[0]
  let second = { ..first, ordinal: 2, key: "second", kind: "objection", }
  let a = @review.compile_review_agenda(
    @review.import_slack_review(
      agenda_fixture(),
      { ..plan, selections: [first, second], },
      bytes,
    ),
    bytes,
  )
  let b = @review.compile_review_agenda(
    @review.import_slack_review(
      agenda_fixture(),
      { ..plan, selections: [second, first], },
      bytes,
    ),
    bytes,
  )
  assert_eq(a.entries[3], b.entries[4])
  assert_eq(a.entries[4], b.entries[3])
}

///|
test "Slack rejects archival or unsupported selected records without dropping catalog rows" {
  let bytes = slack_fixture()
  let plan = slack_plan(bytes)
  for ordinal in [3, 4, 5] {
    assert_true(
      (try? @review.import_slack_review(
        agenda_fixture(),
        { ..plan, selections: [{ ..plan.selections[0], ordinal, }], },
        bytes,
      ))
      is Err(_),
    )
  }
  for
    extra in [
      "\"subtype\":\"thread_broadcast\",", "\"subtype\":\"channel_topic\",", "\"subtype\":\"future_kind\",",
      "\"subtype\":null,", "\"subtype\":\"ordinary\",", "\"previous\":{},", "\"previous_message\":{},",
      "\"original_ts\":\"1.000001\",", "\"deleted_ts\":\"1.000001\",", "\"message\":{},",
      "\"hidden\":true,", "\"hidden\":null,", "\"edited\":null,", "\"edited\":{\"user\":\"U1\",\"ts\":3},",
      "\"thread_ts\":null,",
    ] {
    let bytes = @utf8.encode(
      "[{" +
      extra +
      "\"type\":\"message\",\"user\":\"U1\",\"text\":\"evidence\",\"ts\":\"1.000001\"}]",
    )
    assert_true(slack_rows(bytes)[0] is { "selectable": False, .. }, msg=extra)
    assert_true(
      (try? @review.import_slack_review(
        agenda_fixture(),
        slack_plan(bytes),
        bytes,
      ))
      is Err(_),
    )
  }
}

///|
test "Slack field profile validates strings without converting timestamps or guessing users" {
  for
    raw in [
      "{}", "{\"type\":\"event\"}", "{\"type\":\"message\",\"text\":\"x\",\"ts\":\"1.000001\"}",
      "{\"type\":\"message\",\"user\":\"\",\"text\":\"x\",\"ts\":\"1.000001\"}",
      "{\"type\":\"message\",\"user\":\"U1\",\"text\":null,\"ts\":\"1.000001\"}",
      "{\"type\":\"message\",\"user\":\"U1\",\"text\":\"x\",\"ts\":1.000001}", "{\"type\":\"message\",\"user\":\"U1\",\"text\":\"x\",\"ts\":\"1.1\"}",
      "{\"type\":\"message\",\"subtype\":\"bot_message\",\"user\":null,\"bot_id\":\"B1\",\"text\":\"x\",\"ts\":\"1.000001\"}",
    ] {
    assert_true(
      slack_rows(@utf8.encode("[" + raw + "]"))[0]
      is { "selectable": False, .. },
    )
  }
}

///|
test "Slack malformed containers duplicate decoded keys depth bytes and record limits reject wholly" {
  for
    bytes in [
      b"",
      b"{}",
      b"[null]",
      b"[[]]",
      b"[{}",
      b"[{},]",
      b"[1]",
      Bytes::from_array([0xff]),
      b"[{\"type\":\"message\",\"type\":\"other\"}]",
      b"[{\"text\":\"first\",\"te\\u0078t\":\"second\"}]",
      b"[{\"attachments\":[{\"x\":1,\"x\":2}]}]",
      @utf8.encode("[" + "{} ,".repeat(1000) + "{}]"),
      @utf8.encode("[{}]" + " ".repeat(1048576)),
      @utf8.encode(
        "[{\"nested\":" + "[".repeat(65) + "0" + "]".repeat(65) + "}]",
      ),
    ] {
    assert_true((try? @review.catalog_slack_review(bytes)) is Err(_))
  }
  assert_eq(slack_rows(b"[]").length(), 0)
  assert_eq(
    slack_rows(@utf8.encode("[" + "{},".repeat(999) + "{}]")).length(),
    1000,
  )
}

///|
test "Slack exact raw slices preserve CRLF Unicode whitespace escape spelling and nested delimiters" {
  let raw = "{\r\n \"type\":\"message\", \"user\":\"U1\", \"text\":\"café 🌙 \\\" } ] \\\\ \\u0061\", \"ts\":\"1.000001\", \"nested\":[{},[{}]]\r\n}"
  let bytes = @utf8.encode("[ \r\n" + raw + " , " + raw + "\r\n]")
  let rows = slack_rows(bytes)
  assert_eq(rows.length(), 2)
  for row in rows {
    guard row is { "raw_message": String(value), .. } else { fail("raw") }
    assert_eq(value, raw)
    assert_eq(@utf8.encode(value), @utf8.encode(raw))
  }
}

///|
test "Slack stale and invalid selections reject atomically with ordinary authoring rules" {
  let bytes = slack_fixture()
  let plan = slack_plan(bytes)
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  assert_true(
    (try? @review.import_slack_review(
      agenda,
      plan,
      @utf8.encode(@utf8.decode(bytes) + "\n"),
    ))
    is Err(_),
  )
  for
    selection in [
      { ..plan.selections[0], ordinal: 0, },
      { ..plan.selections[0], ordinal: -1, },
      { ..plan.selections[0], ordinal: 6, },
      { ..plan.selections[0], key: "", },
      { ..plan.selections[0], key: "rollout", },
      { ..plan.selections[0], author: "U_ORIGINAL", },
      { ..plan.selections[0], kind: "approve", },
      { ..plan.selections[0], note: " ", },
      {
        ..plan.selections[0],
        decisions: [{ reviewer: "author", prompt: "Approve?", }],
      },
      {
        ..plan.selections[0],
        decisions: [{ reviewer: "missing", prompt: "Approve?", }],
      },
    ] {
    assert_true(
      (try? @review.import_slack_review(
        agenda,
        { ..plan, selections: [selection], },
        bytes,
      ))
      is Err(_),
    )
  }
  for
    selections in [
      [],
      [plan.selections[0], plan.selections[0]],
      [plan.selections[0], { ..plan.selections[0], ordinal: 5, key: "late", }],
      Array::make(101, plan.selections[0]),
    ] {
    assert_true(
      (try? @review.import_slack_review(agenda, { ..plan, selections, }, bytes))
      is Err(_),
    )
  }
  assert_eq(agenda.to_json().stringify(), before)
}

///|
test "Slack plan schema duplicate keys size and selected evidence bounds are explicit" {
  let bytes = slack_fixture()
  let plan = slack_plan(bytes)
  let wrong = { ..plan, format: "moonchat.review-slack.v2", }
  assert_true(
    (try? @review.parse_slack_review_import_plan(wrong.to_json().stringify()))
    is Err(_),
  )
  assert_true(
    (try? @review.import_slack_review(agenda_fixture(), wrong, bytes)) is Err(_),
  )
  assert_true(
    (try? @review.parse_slack_review_import_plan("{\"format\":1,\"format\":2}"))
    is Err(_),
  )
  assert_true(
    (try? @review.parse_slack_review_import_plan(
      plan.to_json().stringify() + " ".repeat(1048576),
    ))
    is Err(_),
  )
  assert_true(
    (try? @review.import_slack_review(
      agenda_fixture(),
      {
        ..plan,
        selections: [{ ..plan.selections[0], note: "x".repeat(8388608), }],
      },
      bytes,
    ))
    is Err(_),
  )
}

///|
test "Slack output mutation cannot change agenda or plan arrays" {
  let bytes = slack_fixture()
  let agenda = agenda_fixture()
  let plan = slack_plan(bytes)
  let before = agenda.to_json().stringify()
  let plan_before = plan.to_json().stringify()
  let imported = @review.import_slack_review(agenda, plan, bytes)
  imported.items[0].evidence_refs.push("other/evidence")
  imported.items[0].decisions.clear()
  imported.items[3].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.to_json().stringify(), before)
  assert_eq(plan.to_json().stringify(), plan_before)
}
