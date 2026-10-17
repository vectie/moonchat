///|
fn json_edit_source() -> Bytes {
  @utf8.encode("{\"launch\":{\"enabled\":true,\"limit\":50,\"owner\":null},\"regions\":[\"west\",\"east\"],\"a/b\":{\"~key\":9007199254740993},\"\":false}")
}

///|
fn json_edit_fixture(outcome? : String = "approve", source? : Bytes = json_edit_source()) -> (String, @review.ReviewJsonEditPlan) raise {
  let previous = authored_bundle(source~)
  previous.decision_receipts.push(fixture_receipt(previous, outcome))
  let text = @review.serialize_review_bundle(previous, previous.source_digest)
  let blank = @review.prepare_review_json_edits(text, source)
  (text, { ..blank, next_source_artifact_ref: "revisions/two/config.json", next_source_revision_id: "rev-two", recorded_at: "2026-10-14T06:00:00Z", edits: [
    { key: "limit", entry_id: "objection", pointer: "/launch/limit", expected_value: 50, replacement: 12.5 },
    { key: "owner", entry_id: "proposal", pointer: "/launch/owner", expected_value: Json::null(), replacement: "Café 雪" },
    { key: "pilot", entry_id: "objection", pointer: "/launch/enabled", expected_value: true, replacement: false },
    { key: "region", entry_id: "proposal", pointer: "/regions/1", expected_value: "east", replacement: Json::null() },
  ] })
}

///|
fn apply_json_fixture(text : String, plan : @review.ReviewJsonEditPlan, source? : Bytes = json_edit_source()) -> @review.ReviewTextEditResult raise {
  @review.apply_review_json_edits(plan, text, source, previous_bundle_ref="history/original-review.json")
}

///|
test "JSON edits produce typed candidate values with retained dissent and fresh decisions" {
  let (text, plan) = json_edit_fixture()
  let previous = @review.decode_review_bundle(@json.parse(text))
  let result = apply_json_fixture(text, plan)
  guard @json.parse(result.source_text) is Object(root) && root["launch"] is Object(launch) else { fail("candidate") }
  assert_eq(launch["enabled"], false)
  assert_eq(launch["limit"], 12.5)
  assert_eq(launch["owner"], "Café 雪")
  assert_eq(root["regions"], ["west", null])
  assert_true(result.source_text.contains("9007199254740993"))
  assert_eq(result.bundle.entries, previous.entries)
  assert_eq(result.bundle.required_decisions, previous.required_decisions)
  assert_eq(result.bundle.participants, previous.participants)
  assert_eq(result.bundle.conversation, previous.conversation)
  assert_eq(result.bundle.decision_receipts, [])
  assert_eq(result.bundle.previous_bundle_digest, plan.base_bundle_digest)
  assert_eq(result.bundle.previous_bundle_ref, "history/original-review.json")
  assert_eq(result.bundle.source_artifact_ref, "revisions/two/config.json")
  assert_eq(@review.review_status(result.bundle), "pending_review")
  assert_eq(@review.claim_class(result.bundle), "research-evidence")
  assert_eq(@review.reimport_review_bundle(@review.serialize_review_bundle(result.bundle, result.bundle.source_digest), @utf8.encode(result.source_text)), result.bundle)
  assert_true(apply_json_fixture(text, plan) == result)
}

///|
test "JSON edits never carry approve reject defer into changed content" {
  for outcome in ["approve", "reject", "defer"] {
    let (text, plan) = json_edit_fixture(outcome~)
    let result = apply_json_fixture(text, plan)
    assert_eq(result.bundle.decision_receipts, [])
    assert_eq(@review.decode_review_bundle(@json.parse(text)).decision_receipts[0].decision, outcome)
    assert_eq(@review.review_status(result.bundle), "pending_review")
  }
}

///|
test "JSON edits support escaped empty and root pointers with arrays and objects" {
  let (text, plan) = json_edit_fixture()
  for (pointer, expected, replacement) in [
    ("/a~1b/~0key", @json.parse("9007199254740993"), @json.parse("9007199254740994")),
    ("/", false.to_json(), Json::array([])),
    ("/regions", (["west", "east"] : Json), ({ "named": true } : Json)),
    ("", @json.parse(@utf8.decode(json_edit_source())), Json::null()),
  ] {
    let selected = { ..plan, edits: [{ ..plan.edits[0], pointer, expected_value: expected, replacement }] }
    let result = apply_json_fixture(text, selected)
    assert_eq(result.bundle.decision_receipts, [])
    assert_true(result.source_text.has_suffix("\n"))
  }
}

///|
test "JSON edits preserve plans and have order independent disjoint replacements" {
  let (text, plan) = json_edit_fixture()
  let before = plan.to_json().stringify()
  let reversed = plan.edits.rev()
  assert_true(apply_json_fixture(text, plan) == apply_json_fixture(text, { ..plan, edits: reversed }))
  assert_eq(plan.to_json().stringify(), before)
  assert_true(@review.parse_review_json_edits(before) == plan)
  let preview = @review.preview_review_json_edits(plan, text, json_edit_source(), previous_bundle_ref="history/original-review.json")
  assert_true(preview.contains("/launch/limit"))
  assert_true(preview.contains("pending_review"))
}

///|
test "JSON edits reject stale source bundle values and identities" {
  let (text, plan) = json_edit_fixture()
  assert_true(authoring_fails(() => ignore(apply_json_fixture(text + "\n", plan))))
  assert_true(authoring_fails(() => ignore(apply_json_fixture(text, plan, source=b"{}"))))
  let previous = @review.decode_review_bundle(@json.parse(text))
  for bad in [
    { ..plan, base_bundle_digest: "wrong" }, { ..plan, source_digest: "wrong" },
    { ..plan, next_source_artifact_ref: previous.source_artifact_ref },
    { ..plan, next_source_revision_id: previous.source_revision_id },
    { ..plan, edits: [] },
    { ..plan, edits: [{ ..plan.edits[0], expected_value: "50" }] },
    { ..plan, edits: [{ ..plan.edits[0], replacement: 50 }] },
    { ..plan, edits: [{ ..plan.edits[0], entry_id: "unknown" }] },
  ] { assert_true(authoring_fails(() => ignore(apply_json_fixture(text, bad)))) }
}

///|
test "JSON edits reject overlapping canonical locations and late invalid pointers" {
  let (text, plan) = json_edit_fixture()
  for pointer in ["/regions/01", "/regions/-", "#/regions/0", "/missing", "/a~2b", "/launch/limit/x"] {
    let bad = { ..plan, edits: [plan.edits[0], { ..plan.edits[1], pointer }] }
    assert_true(authoring_fails(() => ignore(apply_json_fixture(text, bad))))
  }
  for pointer in ["", "/launch", "/launch/limit"] {
    let bad = { ..plan, edits: [plan.edits[0], { ..plan.edits[1], pointer }] }
    assert_true(authoring_fails(() => ignore(apply_json_fixture(text, bad))))
  }
  assert_true(authoring_fails(() => ignore(apply_json_fixture(text, { ..plan, edits: [plan.edits[0], plan.edits[0]] }))))
}

///|
test "JSON edit plan refuses duplicate and unknown fields and source keys" {
  let (text, plan) = json_edit_fixture()
  for source in [b"{\"x\":1,\"x\":2}", b"{\"x\":1,\"\\u0078\":2}", b"[1,]"] {
    assert_true(authoring_fails(() => ignore(json_edit_fixture(source~))))
  }
  guard plan.to_json() is Object(fields) else { fail("plan") }
  fields["approved"] = true
  assert_true(authoring_fails(() => ignore(@review.parse_review_json_edits(Json::object(fields).stringify()))))
  let duplicate = plan.to_json().stringify().replace(old="\"format\":", new="\"format\":\"wrong\",\"format\":")
  assert_true(authoring_fails(() => ignore(@review.parse_review_json_edits(duplicate))))
  let blank = @review.prepare_review_json_edits(text, json_edit_source())
  assert_true(blank.edits.is_empty())
  assert_true(authoring_fails(() => ignore(apply_json_fixture(text, blank))))
}

///|
test "JSON edits retain unchanged precise fractions and reject rounded expected values" {
  let source = b"{\"launch\":{\"limit\":1.00000000000000001},\"other\":1.00000000000000002}"
  let (text, plan) = json_edit_fixture(source~)
  let raw = plan.to_json().stringify()
  let exact = @review.parse_review_json_edits(raw.replace(old="\"expected_value\":50", new="\"expected_value\":1.00000000000000001"))
  let one = { ..exact, edits: [exact.edits[0]] }
  let result = apply_json_fixture(text, one, source~)
  assert_true(result.source_text.contains("1.00000000000000002"))
  assert_true(@review.catalog_json_review(source).contains("1.00000000000000001"))
  assert_true(authoring_fails(() => ignore(apply_json_fixture(text, { ..one, edits: [{ ..one.edits[0], expected_value: 1 }] }, source~))))
}
