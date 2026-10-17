# Select a local Slack snapshot for review

The reviewed source is the exact daily JSON file. Catalog ordinals include
unsupported archival records. A named curator selects evidence; Slack users,
reactions and quoted approval words never become authenticated participants or
decision receipts. Keep the original file alongside the editable agenda.

```mbt check
///|
test "catalog and select a Slack message for a pending review" {
  let bytes = b"[{\"type\":\"message\",\"user\":\"U1\",\"text\":\"Who owns rollback?\",\"ts\":\"1791882000.000001\"}]"
  let agenda : @review.ReviewAgenda = {
    source_digest_constraint: "",
    review_id: "release",
    conversation_id: "release-review",
    source_artifact_ref: "exports/release/2026-10-13.json",
    source_revision_id: "saved-1",
    recorded_at: "2026-10-13T12:00:00Z",
    participants: [
      {
        participant_id: "editor",
        display_name: "Named curator",
        participant_kind: "human",
      },
    ],
    items: [],
  }
  let plan : @review.SlackReviewImportPlan = {
    format: "moonchat.review-slack.v1",
    source_digest: @review.review_source_digest(bytes),
    selections: [
      {
        ordinal: 1,
        key: "rollback",
        kind: "question",
        author: "editor",
        note: "Request an explicit ownership check.",
        decisions: [
          { reviewer: "editor", prompt: "Is rollback ownership documented?", },
        ],
      },
    ],
  }
  assert_true(@review.catalog_slack_review(bytes).contains("ordinary_snapshot"))
  let selected = @review.import_slack_review(agenda, plan, bytes)
  let bundle = @review.compile_review_agenda(selected, bytes)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_true(@review.export_review_markdown(bundle, bytes).contains("U1"))
}
```

See [the supported input profile and native workflow](../docs/REVIEW_SLACK_IMPORT.md).
