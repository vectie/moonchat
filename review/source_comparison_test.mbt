///|
fn text_comparison(
  before : Bytes,
  after : Bytes,
  context? : Int = 3,
) -> String raise {
  @review.export_review_comparison(
    authored_bundle(source=before),
    before,
    authored_bundle(source=after, revision="rev-two"),
    after,
    source_context=context,
  )
}

///|
test "source comparison exposes replacements insertions deletions and unchanged context" {
  let text = text_comparison(
    b"intro\nold\nkeep\nlast\n", b"intro\nnew\nkeep\nextra\nlast\n",
  )
  assert_true(
    text.contains("4 before lines; 5 after lines; 2 added; 1 removed."),
  )
  assert_true(text.contains("    = | 1 | 1 | \"intro\\n\""))
  assert_true(text.contains("    - | 2 | - | \"old\\n\""))
  assert_true(text.contains("    + | - | 2 | \"new\\n\""))
  assert_true(text.contains("    = | 3 | 3 | \"keep\\n\""))
  assert_true(text.contains("    + | - | 4 | \"extra\\n\""))
  assert_true(text.contains("    = | 4 | 5 | \"last\\n\""))
  assert_true(text.contains("## Required decisions"))
  assert_true(text.contains("## Decision receipts"))
}

///|
test "source comparison is deterministic detached and retains exact review scopes" {
  let draft = authored_bundle(source=b"old\n")
  let before = {
    ..draft,
    decision_receipts: [fixture_receipt(draft, "approve")],
  }
  let after = authored_bundle(source=b"new\n", revision="rev-two")
  let old_saved = before.to_json().stringify()
  let new_saved = after.to_json().stringify()
  let output = @review.export_review_comparison(
    before,
    b"old\n",
    after,
    b"new\n",
    source_context=0,
  )
  assert_eq(
    output,
    @review.export_review_comparison(
      before,
      b"old\n",
      after,
      b"new\n",
      source_context=0,
    ),
  )
  assert_true(output.contains(before.source_digest))
  assert_true(output.contains(after.source_digest))
  assert_true(output.contains("Before status:\n\n    accepted"))
  assert_true(output.contains("After status:\n\n    pending_review"))
  assert_true(output.contains("Decision: approve"))
  assert_true(
    output.contains("prior receipts cover only their original digest"),
  )
  assert_eq(before.to_json().stringify(), old_saved)
  assert_eq(after.to_json().stringify(), new_saved)
}

///|
test "source comparison preserves newline-only edits BOM Unicode and escaped controls" {
  let before = @utf8.encode("\u{feff}café 🌙\r\nsecond\rthird\n")
  let after = @utf8.encode("café 🌙\nsecond\nthird")
  let text = text_comparison(before, after, context=0)
  assert_true(text.contains("3 added; 3 removed."))
  assert_true(text.contains("\\uFEFFcafé 🌙\\r\\n"))
  assert_true(text.contains("\"second\\r\""))
  assert_true(text.contains("\"third\""))
  let escaped = text_comparison(
    b"old",
    @utf8.encode("<script>\t\u{0}\n```\n# heading\n"),
  )
  assert_true(escaped.contains("\"<script>\\t\\u0000\\n\""))
  assert_true(!escaped.contains("\n<script>"))
  assert_true(!escaped.contains("\n```"))
  assert_true(!escaped.contains("\n# heading"))
}

///|
test "source comparison handles empty identical blank and unterminated sources" {
  assert_true(
    text_comparison(b"", b"").contains(
      "0 before lines; 0 after lines; 0 added; 0 removed.",
    ),
  )
  assert_true(text_comparison(b"", b"").contains("No source text changes."))
  assert_true(text_comparison(b"", b"\n").contains("+ | - | 1 | \"\\n\""))
  assert_true(text_comparison(b"\n", b"").contains("- | 1 | - | \"\\n\""))
  assert_true(text_comparison(b"a\n", b"a").contains("1 added; 1 removed."))
  assert_true(
    text_comparison(b"a\r\nb\rc", b"a\r\nb\rc").contains(
      "3 before lines; 3 after lines; 0 added; 0 removed.",
    ),
  )
  assert_true(
    text_comparison(b"\n\n", b"\n\n").contains(
      "2 before lines; 2 after lines; 0 added; 0 removed.",
    ),
  )
}

///|
test "source context forms separate or merged hunks without hiding edits" {
  let before = b"zero\nold-one\na\nb\nc\nd\ne\nold-two\nend\n"
  let after = b"zero\nnew-one\na\nb\nc\nd\ne\nnew-two\nend\n"
  let narrow = text_comparison(before, after, context=0)
  assert_true(narrow.contains("### Source hunk 2"))
  assert_true(!narrow.contains("    = |"))
  assert_true(narrow.contains("5 unchanged lines omitted."))
  assert_true(narrow.contains("1 unchanged lines omitted."))
  let context = text_comparison(before, after, context=1)
  assert_true(context.contains("### Source hunk 2"))
  assert_true(context.contains("3 unchanged lines omitted."))
  assert_true(context.contains("    = | 3 | 3 | \"a\\n\""))
  let merged = text_comparison(before, after, context=3)
  assert_true(!merged.contains("### Source hunk 2"))
  assert_true(!merged.contains("lines omitted"))
  assert_true(merged.contains("2 added; 2 removed."))
}

///|
test "repeated source lines align deterministically with deletion first on ties" {
  let text = text_comparison(b"a\nb\na\n", b"b\na\nb\n", context=0)
  assert_true(text.contains("1 added; 1 removed."))
  assert_true(text.contains("    - | 1 | - | \"a\\n\""))
  assert_true(text.contains("    + | - | 3 | \"b\\n\""))
  assert_true(text.contains("2 unchanged lines omitted."))
}

///|
test "source text limits reject unsupported inputs while legacy binary comparison remains available" {
  let binary : Bytes = [0xff, 0x00, 0xfe]
  let bundle = authored_bundle(source=binary)
  let legacy = @review.export_review_comparison(bundle, binary, bundle, binary)
  assert_true(!legacy.contains("## Source text changes"))
  for (old, next) in [(binary, b"valid"), (b"valid", binary)] {
    assert_true(authoring_fails(() => ignore(text_comparison(old, next))))
  }
  for context in [-1, 21] {
    assert_true(
      authoring_fails(() => ignore(text_comparison(b"a", b"b", context~))),
    )
  }
  let too_many = @utf8.encode(Array::make(2001, "x\n").join(""))
  let too_big = @utf8.encode(String::make(1048577, 'x'))
  for source in [too_many, too_big] {
    assert_true(authoring_fails(() => ignore(text_comparison(source, b"a"))))
    assert_true(authoring_fails(() => ignore(text_comparison(b"a", source))))
  }
}

///|
test "source text exact limits are accepted" {
  let lines = @utf8.encode(Array::make(2000, "x\n").join(""))
  assert_true(
    text_comparison(lines, lines, context=20).contains(
      "2000 before lines; 2000 after lines; 0 added; 0 removed.",
    ),
  )
  let bytes = @utf8.encode(String::make(1048576, 'x'))
  assert_true(
    text_comparison(bytes, bytes).contains(
      "1 before lines; 1 after lines; 0 added; 0 removed.",
    ),
  )
}

///|
test "text mode validates full bundles sources and related scope before displaying changes" {
  let before = authored_bundle(source=b"old")
  let after = authored_bundle(source=b"new", revision="rev-two")
  for (old, next) in [(b"wrong", b"new"), (b"old", b"wrong")] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.export_review_comparison(
            before,
            old,
            after,
            next,
            source_context=0,
          ),
        )
      }),
    )
  }
  for
    invalid in [
      { ..after, source_artifact_ref: "another/file", },
      {
        ..after,
        conversation: { ..after.conversation, conversation_id: "other", },
      },
      { ..after, entries: [after.entries[0], after.entries[0]], },
      { ..after, decision_receipts: [fixture_receipt(before, "approve")], },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.export_review_comparison(
            before,
            b"old",
            invalid,
            b"new",
            source_context=0,
          ),
        )
      }),
    )
  }
}
