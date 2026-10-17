# Reuse a checklist for a new artifact

A role assignment names a participant for preparation. It does not verify that
person or authorize a decision. Values are inserted literally, once.

```mbt check
///|
test "instantiate a reusable checklist and inspect a blank decision" {
  let checklist : @review.ReviewChecklist = {
    format: "moonchat.review-checklist.v1",
    checklist_id: "ownership",
    title: "Check ownership",
    roles: ["owner"],
    variables: ["product"],
    items: [
      {
        key: "rollback",
        kind: "question",
        author_role: "owner",
        body: "Who owns rollback for ${product}?",
        decisions: [
          { reviewer_role: "owner", prompt: "Is ownership documented?", },
        ],
      },
    ],
  }
  let source = b"Rollback owner: unassigned."
  let input : @review.ReviewChecklistInput = {
    format: "moonchat.review-checklist-input.v1",
    checklist_id: "ownership",
    review_id: "release-r1",
    conversation_id: "release-room",
    source_artifact_ref: "release/plan.md",
    source_revision_id: "r1",
    source_digest: @review.review_source_digest(source),
    recorded_at: "2026-10-13T08:00:00Z",
    participants: [
      {
        participant_id: "mei",
        display_name: "Synthetic Mei",
        participant_kind: "human",
      },
    ],
    role_assignments: [{ role: "owner", participant_id: "mei", }],
    values: [{ variable: "product", value: "Café 🌙", }],
  }
  let agenda = @review.instantiate_review_checklist(checklist, input, source)
  assert_eq(agenda.items[0].body, "Who owns rollback for Café 🌙?")
  let bundle = @review.compile_review_agenda(agenda, source)
  assert_eq(@review.review_status(bundle), "pending_review")
  let saved = @review.serialize_review_bundle(bundle, bundle.source_digest)
  let form = @review.prepare_review_decisions(saved, source, "mei")
  assert_eq(form.choices[0].outcome, "")
  assert_eq(form.choices[0].receipt_id, "")
}
```

See [the checklist guide](../docs/REVIEW_CHECKLISTS.md) for two complete reuse
examples, catalog discovery, literal syntax and editing the generated agenda.
