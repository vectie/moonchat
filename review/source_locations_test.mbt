///|
fn locations_for(
  bundle : @review.ConversationReviewBundle,
  locations : Array[@review.ReviewSourceLocation],
) -> @review.ReviewSourceLocations {
  {
    format: "moonchat.review-source-locations.v1",
    review_id: bundle.review_id,
    source_digest: bundle.source_digest,
    locations,
  }
}

///|
test "source locations connect overlapping ranges and multiple excerpts without changing review" {
  let source = b"Pilot plan\nTraffic cap: 10%.\nOwner: Jules.\nRollback before expansion.\n"
  let base = authored_bundle(source~)
  let bundle = {
    ..base,
    decision_receipts: [fixture_receipt(base, "approve")],
  }
  let locations = locations_for(bundle, [
    {
      entry_id: "objection",
      start_line: 2,
      end_line: 3,
      quote: "Traffic cap: 10%.\nOwner: Jules.",
    },
    {
      entry_id: "proposal",
      start_line: 3,
      end_line: 4,
      quote: "Owner: Jules.\nRollback before expansion.",
    },
    {
      entry_id: "objection",
      start_line: 4,
      end_line: 4,
      quote: "Rollback before expansion.",
    },
  ])
  let original = bundle.to_json().stringify()
  let original_locations = locations.to_json().stringify()
  let html = @review.export_review_html(bundle, source, locations~)
  assert_true(html.contains("3 ranges across 2 of 3 entries"))
  assert_true(html.contains("Discussion for source line 3"))
  assert_true(
    html.contains(
      "href=\"#location-1\">objection: objection</a> · <a href=\"#location-2\">proposal: proposal</a>",
    ),
  )
  assert_true(html.contains("Read source lines 2–3"))
  assert_true(html.contains("id=\"location-3\""))
  assert_true(html.contains("No source location supplied for this entry."))
  assert_true(html.contains("<dd>accepted</dd>"))
  assert_true(
    html.contains("Explicit objection about the bound collaboration source."),
  )
  assert_true(html.contains("fixture-approve"))
  assert_eq(html, @review.export_review_html(bundle, source, locations~))
  assert_eq(original, bundle.to_json().stringify())
  assert_eq(original_locations, locations.to_json().stringify())
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
test "source locations honor display newlines BOM tabs Unicode blank and final empty lines" {
  let source = @utf8.encode("\u{feff}Café 🌙\r\n\towner\r\n\rfinal\n")
  let bundle = authored_bundle(source~)
  let locations = locations_for(bundle, [
    {
      entry_id: "objection",
      start_line: 1,
      end_line: 4,
      quote: "\u{feff}Café 🌙\n\towner\n\nfinal",
    },
    { entry_id: "question", start_line: 5, end_line: 5, quote: "", },
    { entry_id: "proposal", start_line: 3, end_line: 4, quote: "\nfinal", },
  ])
  let html = @review.export_review_html(bundle, source, locations~)
  assert_true(html.contains("Read source lines 1–4"))
  assert_true(html.contains("Discussion for source line 5"))
  assert_true(html.contains("<code>\nfinal</code>"))
  assert_true(!html.contains("\r"))
  let empty = authored_bundle(source=b"")
  assert_true(
    @review.export_review_html(
      empty,
      b"",
      locations=locations_for(empty, [
        { entry_id: "question", start_line: 1, end_line: 1, quote: "", },
      ]),
    ).contains("Read source lines 1–1"),
  )
}

///|
test "source locations parser round trips portable map and rejects wrong shapes" {
  let bundle = authored_bundle()
  let locations = locations_for(bundle, [
    {
      entry_id: "objection",
      start_line: 1,
      end_line: 1,
      quote: "revision one",
    },
  ])
  assert_true(
    locations ==
    @review.parse_review_source_locations(locations.to_json().stringify()),
  )
  for
    text in [
      "{", "{}", "[]", "{\"format\":\"moonchat.review-source-locations.v99\",\"review_id\":\"x\",\"source_digest\":\"y\",\"locations\":[]}",
    ] {
    assert_true(
      authoring_fails(() => ignore(@review.parse_review_source_locations(text))),
    )
  }
}

///|
test "source locations reject stale scope wrong quote unknown entries and invalid ranges" {
  let source = b"revision one\n"
  let bundle = authored_bundle(source~)
  let location : @review.ReviewSourceLocation = {
    entry_id: "objection",
    start_line: 1,
    end_line: 1,
    quote: "revision one",
  }
  let good = locations_for(bundle, [location])
  for
    bad in [
      { ..good, format: "wrong", },
      { ..good, review_id: "another-review", },
      {
        ..good,
        source_digest: @review.review_source_digest(b"revision one\r\n"),
      },
      { ..good, locations: [{ ..location, entry_id: "missing", }], },
      { ..good, locations: [{ ..location, start_line: 0, }], },
      { ..good, locations: [{ ..location, start_line: 2, end_line: 1, }], },
      { ..good, locations: [{ ..location, end_line: 3, }], },
      { ..good, locations: [{ ..location, end_line: 2147483647, }], },
      { ..good, locations: [{ ..location, quote: "Revision one", }], },
      { ..good, locations: [{ ..location, quote: "revision one\n", }], },
      { ..good, locations: [location, location], },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(@review.export_review_html(bundle, source, locations=bad))
      }),
    )
  }
  assert_true(
    authoring_fails(() => {
      ignore(@review.export_review_html(bundle, b"changed", locations=good))
    }),
  )
}

///|
test "source locations keep full validation and unlocated dissent and allow an empty map" {
  let source = b"revision one\n"
  let bundle = authored_bundle(source~)
  let empty = locations_for(bundle, [])
  let html = @review.export_review_html(bundle, source, locations=empty)
  assert_true(html.contains("0 ranges across 0 of 3 entries"))
  assert_eq(
    html.split("No source location supplied for this entry.").count(),
    4,
  )
  assert_true(html.contains("Explicit objection"))
  assert_true(html.contains("<dd>pending_review</dd>"))
  let invalid = {
    ..bundle,
    decision_receipts: [
      { ..fixture_receipt(bundle, "approve"), source_digest: "bad", },
    ],
  }
  assert_true(
    authoring_fails(() => {
      ignore(@review.export_review_html(invalid, source, locations=empty))
    }),
  )
  assert_true(
    !@review.export_review_html(bundle, source).contains(
      "Source-linked reading:",
    ),
  )
}

///|
test "source locations render markup as literal quotes and retain rejected and deferred receipts" {
  let quote = "<img src=x onerror='go()'> & \" </pre><script>go()</script>"
  let source = @utf8.encode(quote)
  let base = authored_bundle(source~)
  for outcome in ["reject", "defer"] {
    let bundle = {
      ..base,
      decision_receipts: [fixture_receipt(base, outcome)],
    }
    let locations = locations_for(bundle, [
      { entry_id: "objection", start_line: 1, end_line: 1, quote, },
    ])
    let html = @review.export_review_html(bundle, source, locations~)
    assert_true(
      html.contains(
        "&lt;img src=x onerror=&#39;go()&#39;&gt; &amp; &quot; &lt;/pre&gt;&lt;script&gt;go()&lt;/script&gt;",
      ),
    )
    assert_true(!html.contains("<script>"))
    assert_true(!html.contains("<img"))
    assert_true(html.contains("fixture-" + outcome))
    assert_true(html.contains("Explicit objection"))
  }
}

///|
test "source locations range count and selected line limits are exact" {
  let source = @utf8.encode("line\n".repeat(1000))
  let bundle = authored_bundle(source~)
  let ranges = Array::makei(1000, i => @review.ReviewSourceLocation::{
    entry_id: "objection",
    start_line: i + 1,
    end_line: i + 1,
    quote: "line",
  })
  assert_true(
    @review.export_review_html(
      bundle,
      source,
      locations=locations_for(bundle, ranges),
    ).contains("1000 ranges across 1 of 3 entries"),
  )
  let excess = ranges.copy()
  excess.push({
    entry_id: "question",
    start_line: 1,
    end_line: 1,
    quote: "line",
  })
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.export_review_html(
          bundle,
          source,
          locations=locations_for(bundle, excess),
        ),
      )
    }),
  )
  let ten_thousand = @utf8.encode("\n".repeat(9999))
  let large = authored_bundle(source=ten_thousand)
  let full : @review.ReviewSourceLocation = {
    entry_id: "objection",
    start_line: 1,
    end_line: 10000,
    quote: "\n".repeat(9999),
  }
  assert_true(
    @review.export_review_html(
      large,
      ten_thousand,
      locations=locations_for(large, [full]),
    ).contains("Discussion for source line 10000"),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.export_review_html(
          large,
          ten_thousand,
          locations=locations_for(large, [
            full,
            { entry_id: "question", start_line: 1, end_line: 1, quote: "", },
          ]),
        ),
      )
    }),
  )
}

///|
test "source locations quote size limit counts repeated excerpts" {
  let quote = "x".repeat(524288)
  let source = @utf8.encode(quote + "\ny")
  let bundle = authored_bundle(source~)
  let ranges : Array[@review.ReviewSourceLocation] = [
    { entry_id: "objection", start_line: 1, end_line: 1, quote, },
    { entry_id: "proposal", start_line: 1, end_line: 1, quote, },
  ]
  assert_true(
    @review.export_review_html(
      bundle,
      source,
      locations=locations_for(bundle, ranges),
    ).contains("2 ranges across 2 of 3 entries"),
  )
  ranges.push({ entry_id: "question", start_line: 2, end_line: 2, quote: "y", })
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.export_review_html(
          bundle,
          source,
          locations=locations_for(bundle, ranges),
        ),
      )
    }),
  )
}
