///|
fn relocation_map(
  bundle : @review.ConversationReviewBundle,
  ranges : Array[@review.ReviewSourceLocation],
) -> @review.ReviewSourceLocations {
  {
    format: "moonchat.review-source-locations.v1",
    review_id: bundle.review_id,
    source_digest: bundle.source_digest,
    locations: ranges,
  }
}

///|
fn relocation_range(
  id : String,
  start : Int,
  end : Int,
  quote : String,
) -> @review.ReviewSourceLocation {
  { entry_id: id, start_line: start, end_line: end, quote, }
}

///|
test "relocation moves whole exact passages into complete next packet without mutating evidence" {
  let old_source = b"Plan\nTraffic cap: 10%.\nOwner: Jules.\nRollback before expansion.\n"
  let new_source = b"Revision 2\nSummary\nPlan\nTraffic cap: 10%.\nOwner: Jules.\nRollback before expansion.\nMore detail.\n"
  let old_base = authored_bundle(source=old_source)
  let old = {
    ..old_base,
    decision_receipts: [fixture_receipt(old_base, "defer")],
  }
  let draft = @review.prepare_review_revision(
    old.to_json().stringify(),
    old_source,
  )
  let next = @review.compile_review_revision(
    { ..draft, source_revision_id: "rev-two", },
    new_source,
    previous_bundle_text=old.to_json().stringify(),
    previous_source_bytes=old_source,
    previous_bundle_ref="reviews/previous.json",
  )
  let map = relocation_map(old, [
    relocation_range("objection", 2, 3, "Traffic cap: 10%.\nOwner: Jules."),
    relocation_range("proposal", 4, 4, "Rollback before expansion."),
  ])
  let original = old.to_json().stringify()
  let next_original = next.to_json().stringify()
  let map_original = map.to_json().stringify()
  let result = @review.relocate_review_source_locations(
    old, old_source, map, next, new_source,
  )
  assert_eq(result.mapped_count, 2)
  assert_eq(result.unresolved_count, 0)
  assert_eq(result.results.map(r => r.status), ["relocated", "relocated"])
  assert_eq(result.suggested_locations.locations[0].start_line, 4)
  assert_eq(result.suggested_locations.locations[0].end_line, 5)
  assert_eq(result.suggested_locations.source_digest, next.source_digest)
  let html = @review.export_review_html(
    next,
    new_source,
    locations=result.suggested_locations,
  )
  assert_true(html.contains("Read source lines 4–5"))
  assert_true(html.contains("No source location supplied for this entry."))
  assert_true(
    html.contains("Explicit question about the bound collaboration source."),
  )
  assert_eq(next.decision_receipts, [])
  assert_eq(@review.review_status(next), "pending_review")
  assert_true(old.decision_receipts[0].decision == "defer")
  assert_true(result.to_markdown().contains("2 ranges mapped; 0 unresolved."))
  assert_eq(
    result.to_json().stringify(),
    @review.relocate_review_source_locations(
      old, old_source, map, next, new_source,
    )
    .to_json()
    .stringify(),
  )
  assert_eq(old.to_json().stringify(), original)
  assert_eq(next.to_json().stringify(), next_original)
  assert_eq(map.to_json().stringify(), map_original)
}

///|
test "relocation reports repeated quotes including overlapping matches without picking the old line" {
  let old_source = b"a\na\n"
  let new_source = b"a\na\na\nb\na\na\n"
  let old = authored_bundle(source=old_source)
  let next = authored_bundle(source=new_source, revision="two")
  let result = @review.relocate_review_source_locations(
    old,
    old_source,
    relocation_map(old, [relocation_range("objection", 1, 2, "a\na")]),
    next,
    new_source,
  )
  assert_eq(result.results[0].status, "ambiguous")
  assert_eq(result.results[0].candidate_count, 3)
  assert_eq(result.results[0].candidates.map(c => c.start_line), [1, 2, 5])
  assert_eq(result.suggested_locations.locations.length(), 0)
  assert_eq(result.unresolved_count, 1)
}

///|
test "relocation leaves changed and removed entries or rewritten quotes unresolved" {
  let old_source = b"unchanged source\nold wording\n"
  let new_source = b"unchanged source\nnew wording\n"
  let old = authored_bundle(source=old_source)
  let base = authored_bundle(source=new_source, revision="two")
  let next = {
    ..base,
    entries: base.entries
    .filter(e => e.entry_id != "question")
    .map(e => {
      if e.entry_id == "proposal" {
        { ..e, body: "A different proposal", }
      } else {
        e
      }
    }),
  }
  let map = relocation_map(old, [
    relocation_range("proposal", 1, 1, "unchanged source"),
    relocation_range("question", 1, 1, "unchanged source"),
    relocation_range("objection", 2, 2, "old wording"),
  ])
  let result = @review.relocate_review_source_locations(
    old, old_source, map, next, new_source,
  )
  assert_eq(result.results.map(r => r.status), [
    "entry-changed", "entry-removed", "quote-not-found",
  ])
  assert_eq(result.results.map(r => r.candidate_count), [1, 1, 0])
  assert_eq(result.mapped_count, 0)
  assert_eq(result.unresolved_count, 3)
  assert_eq(result.suggested_locations.locations.length(), 0)
  let html = @review.export_review_html(
    next,
    new_source,
    locations=result.suggested_locations,
  )
  assert_true(html.contains("A different proposal"))
  assert_true(
    html.contains("Explicit objection about the bound collaboration source."),
  )
}

///|
test "relocation never collapses two old passages for the same entry into one destination" {
  let old_source = b"same\nseparator\nsame"
  let new_source = b"same"
  let old = authored_bundle(source=old_source)
  let next = authored_bundle(source=new_source, revision="two")
  let result = @review.relocate_review_source_locations(
    old,
    old_source,
    relocation_map(old, [
      relocation_range("objection", 1, 1, "same"),
      relocation_range("objection", 3, 3, "same"),
      relocation_range("proposal", 1, 1, "same"),
    ]),
    next,
    new_source,
  )
  assert_eq(result.results.map(r => r.status), [
    "range-collision", "range-collision", "relocated",
  ])
  assert_eq(result.mapped_count, 1)
  assert_eq(result.unresolved_count, 2)
  assert_eq(result.suggested_locations.locations[0].entry_id, "proposal")
}

///|
test "relocation honors display newlines Unicode BOM whitespace and final empty line" {
  let old_source = @utf8.encode("\u{feff}Café 🌙\r\n\tOwner\r\n")
  let new_source = @utf8.encode("Header\r\u{feff}Café 🌙\n\tOwner\n")
  let old = authored_bundle(source=old_source)
  let next = authored_bundle(source=new_source, revision="two")
  let result = @review.relocate_review_source_locations(
    old,
    old_source,
    relocation_map(old, [
      relocation_range("objection", 1, 2, "\u{feff}Café 🌙\n\tOwner"),
      relocation_range("question", 3, 3, ""),
    ]),
    next,
    new_source,
  )
  assert_eq(result.results.map(r => r.status), ["relocated", "relocated"])
  assert_eq(result.suggested_locations.locations.map(l => l.start_line), [2, 4])
  let whitespace = @utf8.encode("Header\n\u{feff}Café 🌙\n Owner\n")
  let changed = authored_bundle(source=whitespace, revision="three")
  let retry = @review.relocate_review_source_locations(
    old,
    old_source,
    relocation_map(old, [
      relocation_range("objection", 1, 2, "\u{feff}Café 🌙\n\tOwner"),
    ]),
    changed,
    whitespace,
  )
  assert_eq(retry.results[0].status, "quote-not-found")
}

///|
test "relocation counts every candidate despite bounded display and handles empty source maps" {
  let old = authored_bundle(source=b"x")
  let new_source = @utf8.encode(Array::make(30, "x").join("\n"))
  let next = authored_bundle(source=new_source, revision="two")
  let result = @review.relocate_review_source_locations(
    old,
    b"x",
    relocation_map(old, [relocation_range("objection", 1, 1, "x")]),
    next,
    new_source,
  )
  assert_eq(result.results[0].candidate_count, 30)
  assert_eq(result.results[0].candidates.length(), 20)
  assert_eq(result.results[0].status, "ambiguous")
  assert_true(
    result
    .to_markdown()
    .contains("30 exact matches in next source; first 20 shown"),
  )
  let empty = authored_bundle(source=b"")
  let empty_result = @review.relocate_review_source_locations(
    empty,
    b"",
    relocation_map(empty, [relocation_range("objection", 1, 1, "")]),
    empty,
    b"",
  )
  assert_eq(empty_result.mapped_count, 1)
  let no_map = @review.relocate_review_source_locations(
    old,
    b"x",
    relocation_map(old, []),
    next,
    new_source,
  )
  assert_eq(no_map.results.length(), 0)
  assert_eq(no_map.unresolved_count, 0)
  assert_true(no_map.to_markdown().contains("0 ranges mapped; 0 unresolved."))
}

///|
test "relocation validates both complete bundles scope old quotes and source bytes" {
  let old = authored_bundle()
  let map = relocation_map(old, [
    relocation_range("objection", 1, 1, "revision one"),
  ])
  let source = b"revision one\n"
  let bad_nexts = [
    { ..old, source_artifact_ref: "other/source.md", },
    {
      ..old,
      conversation: { ..old.conversation, conversation_id: "other-room", },
    },
    {
      ..old,
      entries: old.entries.map(e => {
        if e.entry_id == "question" {
          { ..e, author_participant_id: "unknown", }
        } else {
          e
        }
      }),
    },
    {
      ..old,
      decision_receipts: [
        { ..fixture_receipt(old, "approve"), source_digest: "wrong", },
      ],
    },
  ]
  for next in bad_nexts {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.relocate_review_source_locations(
            old, source, map, next, source,
          ),
        )
      }),
    )
  }
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.relocate_review_source_locations(
          old, b"changed", map, old, source,
        ),
      )
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.relocate_review_source_locations(
          old, source, map, old, b"changed",
        ),
      )
    }),
  )
  for
    bad_map in [
      { ..map, source_digest: "wrong", },
      { ..map, review_id: "wrong", },
      { ..map, locations: [relocation_range("objection", 1, 1, "not exact")], },
      { ..map, locations: [relocation_range("unknown", 1, 1, "revision one")], },
      { ..map, locations: [map.locations[0], map.locations[0]], },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.relocate_review_source_locations(
            old, source, bad_map, old, source,
          ),
        )
      }),
    )
  }
}

///|
test "relocation applies packet text limits before producing a map" {
  let old = authored_bundle(source=b"x")
  let map = relocation_map(old, [relocation_range("objection", 1, 1, "x")])
  for
    bytes in [
      ([0xff] : Bytes),
      b"x\u0000",
      @utf8.encode(Array::make(10001, "x").join("\n")),
      @utf8.encode(Array::make(1048577, "x").join("")),
    ] {
    let next = authored_bundle(source=bytes, revision="two")
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.relocate_review_source_locations(old, b"x", map, next, bytes),
        )
      }),
    )
  }
}
