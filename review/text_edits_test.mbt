///|
fn text_edit_fixture(
  source? : Bytes = b"# Pilot brief\nRollback owner: TBD\nPublic launch: Friday\nKeep this concern visible.\n",
  outcome? : String = "reject",
) -> (String, @review.ReviewTextEditPlan) raise {
  let previous = authored_bundle(source~)
  previous.decision_receipts.push(fixture_receipt(previous, outcome))
  let text = @review.serialize_review_bundle(previous, previous.source_digest)
  let blank = @review.prepare_review_text_edits(text, source)
  let plan = {
    ..blank,
    next_source_artifact_ref: "revisions/two/brief.md",
    next_source_revision_id: "rev-two",
    recorded_at: "2026-10-13T03:00:00Z",
    edits: [
      {
        key: "name-owner",
        entry_id: "objection",
        start_line: 2,
        end_line: 2,
        quote: "Rollback owner: TBD\n",
        replacement: "Rollback owner: Operations lead\nRehearsal: Wednesday\n",
      },
    ],
  }
  (text, plan)
}

///|
fn apply_text_fixture(
  text : String,
  plan : @review.ReviewTextEditPlan,
  source? : Bytes = b"# Pilot brief\nRollback owner: TBD\nPublic launch: Friday\nKeep this concern visible.\n",
) -> @review.ReviewTextEditResult raise {
  @review.apply_review_text_edits(
    plan,
    text,
    source,
    previous_bundle_ref="history/original-review.json",
  )
}

///|
test "text edits produce real candidate content and retain dissent with fresh decisions" {
  let (text, plan) = text_edit_fixture()
  let previous = @review.decode_review_bundle(@json.parse(text))
  let result = apply_text_fixture(text, plan)
  assert_eq(
    result.source_text,
    "# Pilot brief\nRollback owner: Operations lead\nRehearsal: Wednesday\nPublic launch: Friday\nKeep this concern visible.\n",
  )
  assert_eq(result.bundle.entries, previous.entries)
  assert_eq(result.bundle.required_decisions, previous.required_decisions)
  assert_eq(result.bundle.participants, previous.participants)
  assert_eq(result.bundle.conversation, previous.conversation)
  assert_eq(result.bundle.previous_bundle_digest, plan.base_bundle_digest)
  assert_eq(result.bundle.previous_bundle_ref, "history/original-review.json")
  assert_eq(result.bundle.source_revision_id, "rev-two")
  assert_eq(result.bundle.source_artifact_ref, "revisions/two/brief.md")
  assert_eq(result.bundle.decision_receipts, [])
  assert_eq(@review.review_status(result.bundle), "pending_review")
  assert_eq(@review.claim_class(result.bundle), "research-evidence")
  assert_eq(previous.decision_receipts[0].decision, "reject")
  assert_eq(
    @review.reimport_review_bundle(
      @review.serialize_review_bundle(
        result.bundle,
        result.bundle.source_digest,
      ),
      @utf8.encode(result.source_text),
    ),
    result.bundle,
  )
  assert_true(apply_text_fixture(text, plan) == result)
}

///|
test "text edits never inherit approve reject or defer receipts" {
  for outcome in ["approve", "reject", "defer"] {
    let (text, plan) = text_edit_fixture(outcome~)
    let result = apply_text_fixture(text, plan)
    assert_eq(result.bundle.decision_receipts, [])
    assert_eq(@review.review_status(result.bundle), "pending_review")
    assert_eq(
      @review.decode_review_bundle(@json.parse(text)).decision_receipts[0].decision,
      outcome,
    )
  }
}

///|
test "text edits use original coordinates despite reordered multiple replacements" {
  let (text, plan) = text_edit_fixture()
  let second : @review.ReviewTextEdit = {
    key: "limit-launch",
    entry_id: "proposal",
    start_line: 3,
    end_line: 4,
    quote: "Public launch: Friday\nKeep this concern visible.\n",
    replacement: "Private pilot: Friday\n",
  }
  let two = { ..plan, edits: [second, plan.edits[0]], }
  let result = apply_text_fixture(text, two)
  assert_eq(
    result.source_text,
    "# Pilot brief\nRollback owner: Operations lead\nRehearsal: Wednesday\nPrivate pilot: Friday\n",
  )
  assert_true(
    apply_text_fixture(text, { ..two, edits: [plan.edits[0], second], }) ==
    result,
  )
  assert_true(two.edits[0] == second)
}

///|
test "text edits preserve Unicode CRLF and absent final newline byte for byte" {
  let source = @utf8.encode("café 🌙\r\nold\r\nlast line")
  let (text, plan) = text_edit_fixture(source~)
  let edit = { ..plan.edits[0], quote: "old\r\n", replacement: "更新\r\n", }
  let result = apply_text_fixture(text, { ..plan, edits: [edit], }, source~)
  assert_eq(
    @utf8.encode(result.source_text),
    @utf8.encode("café 🌙\r\n更新\r\nlast line"),
  )
  assert_eq(
    result.bundle.source_digest,
    @review.review_source_digest(@utf8.encode(result.source_text)),
  )
  let remove = { ..edit, replacement: "", }
  assert_eq(
    apply_text_fixture(text, { ..plan, edits: [remove], }, source~).source_text,
    "café 🌙\r\nlast line",
  )
}

///|
test "text edit single final line replacement does not add a newline" {
  let source = b"one\ntwo"
  let (text, plan) = text_edit_fixture(source~)
  let edit = { ..plan.edits[0], quote: "two", replacement: "three", }
  assert_eq(
    apply_text_fixture(text, { ..plan, edits: [edit], }, source~).source_text,
    "one\nthree",
  )
}

///|
test "text edit plan preparation is empty and binds exact input" {
  let (text, _) = text_edit_fixture()
  let source = b"# Pilot brief\nRollback owner: TBD\nPublic launch: Friday\nKeep this concern visible.\n"
  let blank = @review.prepare_review_text_edits(text, source)
  assert_true(blank.edits.is_empty())
  assert_eq(blank.next_source_artifact_ref, "")
  assert_eq(blank.next_source_revision_id, "")
  assert_eq(blank.recorded_at, "")
  assert_eq(
    blank.base_bundle_digest,
    @review.review_source_digest(@utf8.encode(text)),
  )
  assert_true(
    @review.parse_review_text_edits(blank.to_json().stringify()) == blank,
  )
  assert_true(authoring_fails(() => ignore(apply_text_fixture(text, blank))))
}

///|
test "text edits reject replaced source changed bundle and stale identities" {
  let (text, plan) = text_edit_fixture()
  assert_true(
    authoring_fails(() => ignore(apply_text_fixture(text + "\n", plan))),
  )
  assert_true(
    authoring_fails(() => {
      ignore(apply_text_fixture(text, plan, source=b"replaced"))
    }),
  )
  for
    invalid in [
      { ..plan, source_digest: "wrong", },
      { ..plan, base_bundle_digest: "wrong", },
      { ..plan, format: "moonchat.review-text-edits.v2", },
      { ..plan, next_source_revision_id: "rev-one", },
      { ..plan, next_source_revision_id: "", },
      { ..plan, next_source_artifact_ref: "collaboration/source-packet.json", },
      { ..plan, next_source_artifact_ref: "../escape.md", },
      { ..plan, next_source_artifact_ref: "history/original-review.json", },
      { ..plan, recorded_at: "", },
    ] {
    assert_true(
      authoring_fails(() => ignore(apply_text_fixture(text, invalid))),
    )
  }
}

///|
test "text edits reject mismatched quotes ranges missing entries and no-ops" {
  let (text, plan) = text_edit_fixture()
  let edit = plan.edits[0]
  for
    invalid in [
      { ..edit, start_line: 0, },
      { ..edit, end_line: 1, },
      { ..edit, end_line: 5, },
      { ..edit, quote: "Rollback owner: TBD", },
      { ..edit, entry_id: "missing", },
      { ..edit, key: "", },
      { ..edit, replacement: edit.quote, },
      { ..edit, replacement: "bare\rreturn", },
      { ..edit, replacement: "NUL\u{0}", },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(apply_text_fixture(text, { ..plan, edits: [invalid], }))
      }),
    )
  }
}

///|
test "text edits reject overlap duplicate keys and empty result atomically" {
  let (text, plan) = text_edit_fixture()
  let edit = plan.edits[0]
  for
    edits in [
      [],
      [edit, edit],
      [edit, { ..edit, key: "other", }],
      [
        edit,
        {
          ..edit,
          start_line: 3,
          end_line: 3,
          quote: "Public launch: Friday\n",
        },
      ],
      [
        {
          ..edit,
          start_line: 1,
          end_line: 4,
          quote: "# Pilot brief\nRollback owner: TBD\nPublic launch: Friday\nKeep this concern visible.\n",
          replacement: "",
        },
      ],
    ] {
    assert_true(
      authoring_fails(() => ignore(apply_text_fixture(text, { ..plan, edits, }))),
    )
  }
  assert_true(plan.edits == [edit])
  assert_eq(
    @review.decode_review_bundle(@json.parse(text)).decision_receipts.length(),
    1,
  )
}

///|
test "text edit preview keeps all discussion and explicit before after source" {
  let (text, plan) = text_edit_fixture()
  let preview = @review.preview_review_text_edits(
    plan,
    text,
    b"# Pilot brief\nRollback owner: TBD\nPublic launch: Friday\nKeep this concern visible.\n",
    previous_bundle_ref="history/original-review.json",
  )
  for
    value in [
      "Rollback owner: TBD", "Rollback owner: Operations lead", "Complete candidate source",
      "Explicit objection", "accountable-human", "pending_review", "fresh review",
      "history/original-review.json",
    ] {
    assert_true(preview.contains(value))
  }
}

///|
test "text edit parser refuses malformed unsupported and authority-bearing plans" {
  let (text, plan) = text_edit_fixture()
  let encoded = plan.to_json().stringify()
  for
    invalid in [
      "{",
      "[]",
      "{}",
      encoded.replace(old="moonchat.review-text-edits.v1", new="v99"),
      encoded.replace(
        old="\"format\":",
        new="\"decision_receipts\":[],\"format\":",
      ),
    ] {
    assert_true(
      authoring_fails(() => ignore(@review.parse_review_text_edits(invalid))),
    )
  }
  let result = apply_text_fixture(
    text,
    @review.parse_review_text_edits(encoded),
  )
  plan.edits.clear()
  assert_eq(result.bundle.entries.length(), 3)
  assert_eq(result.bundle.required_decisions.length(), 1)
}

///|
test "text edits enforce source and selected edit bounds" {
  for source in [b"", b"bad\xff", b"bare\rreturn", b"control\x00"] {
    let previous = authored_bundle(source~)
    let text = @review.serialize_review_bundle(previous, previous.source_digest)
    assert_true(
      authoring_fails(() => {
        ignore(@review.prepare_review_text_edits(text, source))
      }),
    )
  }
  let (text, plan) = text_edit_fixture()
  assert_true(
    authoring_fails(() => {
      ignore(
        apply_text_fixture(text, {
          ..plan,
          edits: Array::make(101, plan.edits[0]),
        }),
      )
    }),
  )
  let huge = String::make(1048577, 'x')
  assert_true(
    authoring_fails(() => {
      ignore(
        apply_text_fixture(text, {
          ..plan,
          edits: [{ ..plan.edits[0], replacement: huge, }],
        }),
      )
    }),
  )
}

///|
test "text edits apply final size limit after a later deletion offsets expansion" {
  let first = String::make(524287, 'a') + "\n"
  let second = String::make(524287, 'b') + "\n"
  let source = @utf8.encode(first + second)
  assert_eq(source.length(), 1048576)
  let (text, plan) = text_edit_fixture(source~)
  let grow = {
    ..plan.edits[0],
    key: "expand-first",
    start_line: 1,
    end_line: 1,
    quote: first,
    replacement: String::make(524288, 'a') + "\n",
  }
  let shrink = {
    ..plan.edits[0],
    key: "shrink-second",
    quote: second,
    replacement: "b\n",
  }
  let result = apply_text_fixture(
    text,
    { ..plan, edits: [grow, shrink], },
    source~,
  )
  assert_eq(@utf8.encode(result.source_text).length(), 524291)
  assert_eq(result.source_text, grow.replacement + shrink.replacement)
  assert_eq(
    result.bundle.source_digest,
    @review.review_source_digest(@utf8.encode(result.source_text)),
  )
  assert_true(
    apply_text_fixture(text, { ..plan, edits: [shrink, grow], }, source~) ==
    result,
  )
  assert_true(
    authoring_fails(() => {
      ignore(apply_text_fixture(text, { ..plan, edits: [grow], }, source~))
    }),
  )
}
