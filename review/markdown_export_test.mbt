///|
test "markdown review handoff preserves conversation decisions and projected events" {
  let bundle = authored_bundle()
  let before = bundle.to_json().stringify()
  let text = @review.export_review_markdown(bundle, b"revision one\n")
  assert_true(text.contains("# MoonChat review handoff\n"))
  assert_true(text.contains("Status:\n\n    pending_review\n"))
  assert_true(
    text.contains(
      "    Explicit objection about the bound collaboration source.\n",
    ),
  )
  assert_true(text.contains("    awaiting receipt\n"))
  assert_true(text.contains("    objection-decision\n"))
  assert_true(text.contains("### Event 5\n"))
  assert_true(text.contains("    review_projected\n"))
  assert_true(text.contains("    client-proposal\n"))
  assert_true(text.contains(bundle.source_digest))
  assert_eq(text, @review.export_review_markdown(bundle, b"revision one\n"))
  assert_eq(before, bundle.to_json().stringify())
}

///|
test "markdown shows existing approve reject and defer receipts without creating authority" {
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
    let text = @review.export_review_markdown(bundle, b"revision one\n")
    assert_true(text.contains("Status:\n\n    " + status + "\n"))
    assert_true(text.contains("Decision outcome:\n\n    " + decision + "\n"))
    assert_true(text.contains("    fixture-" + decision + "\n"))
    assert_true(
      text.contains(
        "    Source test fixture only; no real human authority implied.\n",
      ),
    )
    assert_true(text.contains("    human_decision_recorded\n"))
    assert_eq(bundle.decision_receipts.length(), 1)
  }
}

///|
test "markdown literal blocks retain Unicode multiline and Markdown-looking content" {
  let draft = authored_bundle()
  let body = "# 标题 🌙\n```\n<script>example</script>\n[reference](file.md)\n\nlast line"
  let entries = draft.entries.copy()
  entries[0] = { ..entries[0], body, }
  let bundle = { ..draft, entries, }
  let text = @review.export_review_markdown(bundle, b"revision one\n")
  assert_true(
    text.contains(
      "    # 标题 🌙\n    ```\n    <script>example</script>\n    [reference](file.md)\n    \n    last line\n",
    ),
  )
  assert_true(!text.contains("\n<script>"))
  assert_true(!text.contains("\n```"))
}

///|
test "markdown retains source lineage and requires the observed exact source" {
  let previous = authored_bundle()
  let next = @review.supersede_review_bundle(
    @review.serialize_review_bundle(previous, previous.source_digest),
    previous_bundle_ref="reviews/previous.json",
    previous_source_bytes=b"revision one\n",
    next_bundle=authored_bundle(source=b"revision two\n", revision="rev-two"),
    next_source_bytes=b"revision two\n",
  )
  let text = @review.export_review_markdown(next, b"revision two\n")
  assert_true(text.contains("    reviews/previous.json\n"))
  assert_true(text.contains(next.previous_bundle_digest))
  assert_true(text.contains("    rev-two\n"))
  assert_true(
    authoring_fails(() => {
      ignore(@review.export_review_markdown(next, b"revision one\n"))
    }),
  )
}
