///|
test "HTML packet includes bound source discussion and navigable decision context without mutation" {
  let source = @utf8.encode(
    "# Release plan 🌙\r\n\tDeploy after rehearsal.\r\n",
  )
  let bundle = authored_bundle(source~)
  let before = bundle.to_json().stringify()
  let text = @review.export_review_html(bundle, source)
  assert_true(text.has_prefix("<!doctype html>\n"))
  assert_true(text.contains("<span># Release plan 🌙</span>"))
  assert_true(text.contains("<span>\tDeploy after rehearsal.</span>"))
  assert_true(text.contains("id=\"source-line-3\""))
  assert_true(!text.contains("id=\"source-line-4\""))
  assert_true(text.contains("href=\"#decision-1\""))
  assert_true(text.contains("id=\"decision-1\""))
  assert_true(text.contains("id=\"entry-2\" class=\"objection\""))
  assert_true(
    text.contains("Explicit objection about the bound collaboration source."),
  )
  assert_true(text.contains("Fixture accountable reviewer (accountable-human)"))
  assert_true(text.contains("No receipt recorded for this decision."))
  assert_true(text.contains("No decision requested for this entry."))
  assert_true(text.contains("<dd>pending_review</dd>"))
  assert_true(text.contains(bundle.source_digest))
  assert_true(!text.contains("\r"))
  assert_eq(text, @review.export_review_html(bundle, source))
  assert_eq(before, bundle.to_json().stringify())
}

///|
test "HTML packet preserves all outcomes and keeps objections visible after approval" {
  for
    (decision, status) in [
      ("approve", "accepted"),
      ("reject", "rejected"),
      ("defer", "pending_review"),
    ] {
    let draft = authored_bundle()
    let bundle = {
      ..draft,
      decision_receipts: [fixture_receipt(draft, decision)],
    }
    let html = @review.export_review_html(bundle, b"revision one\n")
    assert_true(html.contains("<dd>" + status + "</dd>"))
    assert_true(html.contains("<dd>" + decision + "</dd>"))
    assert_true(html.contains("<dd>fixture-" + decision + "</dd>"))
    assert_true(
      html.contains("Explicit objection about the bound collaboration source."),
    )
    assert_true(
      html.contains(
        "Source test fixture only; no real human authority implied.",
      ),
    )
    assert_true(html.contains("2026-10-06T16:01:00Z"))
    assert_eq(bundle.decision_receipts.length(), 1)
  }
}

///|
test "HTML packet escapes source and every free text context and only emits local anchors" {
  let markup = "<img src=x onerror='go()'> & \" </style><script>go()</script>"
  let escaped = "&lt;img src=x onerror=&#39;go()&#39;&gt; &amp; &quot; &lt;/style&gt;&lt;script&gt;go()&lt;/script&gt;"
  let source = @utf8.encode(markup)
  let base = authored_bundle(source~)
  let participants = base.participants.copy()
  participants[0] = { ..participants[0], display_name: markup, }
  participants[1] = { ..participants[1], display_name: markup, }
  let entries = base.entries.copy()
  entries[0] = {
    ..entries[0],
    body: markup,
    turn: { ..entries[0].turn, command_id: markup, },
    evidence_refs: ["notes/<b>&\"'file"],
  }
  let requirements = base.required_decisions.copy()
  requirements[0] = { ..requirements[0], prompt: markup, }
  let bundle = {
    ..base,
    participants,
    entries,
    required_decisions: requirements,
    source_revision_id: markup,
    conversation: { ..base.conversation, protocol: markup, },
    decision_receipts: [
      {
        ..fixture_receipt(base, "approve"),
        reviewer_name: markup,
        rationale: markup,
        evidence_refs: ["notes/<b>&\"'file"],
      },
    ],
  }
  let html = @review.export_review_html(bundle, source)
  assert_true(html.contains(escaped))
  assert_true(html.contains("notes/&lt;b&gt;&amp;&quot;&#39;file"))
  assert_true(!html.contains("<script>"))
  assert_true(!html.contains("<img"))
  assert_true(!html.contains("<iframe"))
  assert_true(!html.contains(" src=\""))
  assert_true(html.contains("default-src 'none'"))
  assert_true(html.contains("@media print"))
  for part in html.split("href=\"").drop(1) {
    assert_true(part.has_prefix("#"))
    let target = part.split("\"").collect()[0]
      .to_owned()
      .strip_prefix("#")
      .unwrap()
      .to_owned()
    assert_eq(html.split("id=\"" + target + "\"").count(), 2)
  }
}

///|
test "HTML packet retains multiple decisions on one subject with unique complete navigation" {
  let base = authored_bundle()
  let bundle = {
    ..base,
    required_decisions: [
      base.required_decisions[0],
      {
        ..base.required_decisions[0],
        decision_id: "second-request",
        prompt: "Separate rollback question",
      },
    ],
    decision_receipts: [fixture_receipt(base, "approve")],
  }
  let html = @review.export_review_html(bundle, b"revision one\n")
  assert_true(html.contains("<dd>pending_review</dd>"))
  assert_true(html.contains("id=\"decision-2\""))
  assert_true(html.contains("href=\"#decision-2\""))
  assert_eq(html.split("id=\"decision-1\"").count(), 2)
  assert_eq(html.split("id=\"decision-2\"").count(), 2)
  assert_true(html.contains("Separate rollback question"))
  assert_true(html.contains("2 required decisions; 1 recorded receipts."))
}

///|
test "HTML packet validates entire review source receipts and schema before output" {
  let base = authored_bundle()
  for
    invalid in [
      { ..base, contract_id: "moonchat.conversation-review-bundle.v99", },
      {
        ..base,
        decision_receipts: [
          { ..fixture_receipt(base, "approve"), source_digest: "wrong", },
        ],
      },
      {
        ..base,
        decision_receipts: [
          {
            ..fixture_receipt(base, "approve"),
            reviewer_participant_id: "collaborator-agent",
          },
        ],
      },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(@review.export_review_html(invalid, b"revision one\n"))
      }),
    )
  }
  assert_true(
    authoring_fails(() => {
      ignore(@review.export_review_html(base, b"revision one"))
    }),
  )
}

///|
test "HTML packet rejects nontext sources and supports bounded empty Unicode and newline displays" {
  for source in [b"\xff", b"a\x00b", b"\x1b[1m", b"\x7f"] {
    let bundle = authored_bundle(source~)
    assert_true(
      authoring_fails(() => ignore(@review.export_review_html(bundle, source))),
    )
  }
  for source in [b"", @utf8.encode("\u{feff}你好 🌙\na\rb\r\nc")] {
    let bundle = authored_bundle(source~)
    let html = @review.export_review_html(bundle, source)
    assert_true(html.contains(bundle.source_digest))
    assert_true(html.contains("id=\"source-line-1\""))
  }
}

///|
test "HTML packet source display boundaries are explicit and nontruncating" {
  let limit = @utf8.encode("a".repeat(1048576))
  assert_true(
    @review.export_review_html(authored_bundle(source=limit), limit).contains(
      "1048576 original bytes",
    ),
  )
  let excess = @utf8.encode("a".repeat(1048577))
  assert_true(
    authoring_fails(() => {
      ignore(@review.export_review_html(authored_bundle(source=excess), excess))
    }),
  )
  let lines = @utf8.encode("\n".repeat(9999))
  assert_true(
    @review.export_review_html(authored_bundle(source=lines), lines).contains(
      "id=\"source-line-10000\"",
    ),
  )
  let too_many = @utf8.encode("\n".repeat(10000))
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.export_review_html(authored_bundle(source=too_many), too_many),
      )
    }),
  )
}

///|
test "HTML packet retains lineage without fetching predecessor or inheriting old dissent" {
  let previous = authored_bundle()
  let next = @review.supersede_review_bundle(
    @review.serialize_review_bundle(previous, previous.source_digest),
    previous_bundle_ref="reviews/previous.json",
    previous_source_bytes=b"revision one\n",
    next_bundle=authored_bundle(source=b"revision two\n", revision="rev-two"),
    next_source_bytes=b"revision two\n",
  )
  let html = @review.export_review_html(next, b"revision two\n")
  assert_true(html.contains("<dd>reviews/previous.json</dd>"))
  assert_true(html.contains(next.previous_bundle_digest))
  assert_true(html.contains("separately retained bundles"))
  assert_true(!html.contains("href=\"reviews/previous.json\""))
}
