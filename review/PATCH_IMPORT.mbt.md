# Review selected patch hunks

The source is the exact diff artifact. Hunk paths and coordinates describe that
artifact, not verified checkout content. Nothing is applied or executed.

```mbt check
///|
test "catalog a patch and compose explicit pending review" {
  let patch = b"--- a/release.txt\n+++ b/release.txt\n@@ -1 +1 @@\n-Owner: none\n+Owner: operations\n"
  let catalog = @review.catalog_patch_review(patch)
  assert_true(catalog.contains("Owner: operations"))
  let agenda : @review.ReviewAgenda = {
    source_digest_constraint: "",
    review_id: "patch-example",
    conversation_id: "release-room",
    source_artifact_ref: "changes/release.diff",
    source_revision_id: "r1",
    recorded_at: "2026-10-13T05:30:00Z",
    participants: [
      {
        participant_id: "owner",
        display_name: "Release owner",
        participant_kind: "human",
      },
    ],
    items: [],
  }
  let plan : @review.PatchReviewImportPlan = {
    format: "moonchat.review-patch.v1",
    source_digest: @review.review_source_digest(patch),
    selections: [
      {
        file: 1,
        hunk: 1,
        key: "owner-change",
        kind: "proposal",
        author: "owner",
        note: "Check who owns this release.",
        decisions: [
          { reviewer: "owner", prompt: "Is this assignment correct?", },
        ],
      },
    ],
  }
  let selected = @review.import_patch_review(agenda, plan, patch)
  let bundle = @review.compile_review_agenda(selected, patch)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(bundle.decision_receipts.length(), 0)
  let saved = @review.serialize_review_bundle(bundle, bundle.source_digest)
  let form = @review.prepare_review_decisions(saved, patch, "owner")
  assert_eq(form.choices[0].outcome, "")
}
```

Use the [CLI guide](../docs/REVIEW_PATCH_IMPORT.md) for a multi-file example,
supported diff syntax, error cases and existing consumer commands.
