# Reopen a received host review for editing

Use `review_revise` when you have a portable MoonChat bundle and its exact source,
but do not have the original agenda or host editor. It creates an editable JSON
draft, then compiles your changes into a new pending bundle linked to the
retained original. Existing MoonLib conversation, entry, turn and decision IDs
are copied rather than regenerated as agenda IDs.

This works for valid v1 reviews from any producer, including reviews with more
than one decision request for the same reviewer on an entry. The original
review and all of its receipts remain historical evidence. The new revision
has no receipts, even when the source bytes are unchanged.

## Try the synthetic workflow

From the repository root, with a native build of `cmd/review_revise`:

```sh
review_revise draft examples/review-revision/received-review.json examples/review-revision/old-source.md > draft.json
```

Edit a copy of `draft.json`, or inspect the supplied `edited-draft.json`. That
example revises a rollback objection, adds an operations participant and a
follow-up question, and names the new decision owner. It also binds revision 2
of the source. Preview and compile:

```sh
review_revise preview examples/review-revision/edited-draft.json examples/review-revision/new-source.md examples/review-revision/received-review.json examples/review-revision/old-source.md examples/review-revision/received-review.json > preview.md
review_revise bundle examples/review-revision/edited-draft.json examples/review-revision/new-source.md examples/review-revision/received-review.json examples/review-revision/old-source.md examples/review-revision/received-review.json > revised-review.json
```

The final argument is the portable workspace-relative reference where you retain
the original bundle. The earlier arguments are paths to actual local files.
Keep both versions' bundles and source files. Commands read inputs and write
stdout only; redirect to a new path, never an input, because shell redirection
truncates its destination before the command reads files. An error exits 1 with
stderr diagnostics and no result on stdout.

## What to edit

- Keep `format`, `base_bundle_digest`, `review_id` and the complete `conversation`
  unchanged. They identify the supported preparation format and exact old scope.
  The base digest includes JSON whitespace. Reformatting the retained original
  requires preparing a new draft; silently applying an old draft to a different
  original is rejected.
- Edit `entries` to change wording, type or evidence references, reorder points,
  remove points, or add new ones. Keep existing entry and turn IDs for the same
  point. Assign new stable IDs and all three MoonLib turn identity fields for
  genuinely new points. Entry kinds remain question, objection or proposal.
- Edit `participants` and `required_decisions` to add people, reassign a decision,
  change a prompt or remove an obsolete request. Keep a request's `decision_id`
  when editing it. Each author and reviewer must exist; every objection still
  needs a decision request, and the bundle needs at least one named human
  decision overall. Removing an entry requires removing its requests too.
- Update `source_artifact_ref`, `source_revision_id` and `recorded_at` for the
  revised scope. Changed source bytes require a new revision label. The source
  digest is computed from the actual next-source file. For discussion-only
  edits, use the original source bytes and retain the revision label.

The draft is a complete replacement of editable discussion, not a patch and not
a merge with a concurrently changed review. Removed or rewritten objections and
prior decisions remain in the retained predecessor, not in the new current
projection. The existing review comparison command can inspect changes when
the portable source artifact reference is unchanged. If you retain a new source
under a different reference, as in this example, export the two bundles as
separate full views instead; the comparison command intentionally requires the
same source artifact reference. Export the old bundle for its full dissent and
receipt history.

No draft field carries approval authority. `decision_receipts`, claim/status
fields and other unknown top-level draft fields are rejected by the parser.
Compilation always creates an empty receipt array and uses the existing v1
source-validation and supersession APIs. It does not change a wire schema or
create another authority contract.

## Embedding and limits

The pure APIs are `prepare_review_revision(previous_text, previous_source)`,
`parse_review_revision(text)`, and `compile_review_revision(draft, next_source,
previous_bundle_text~, previous_source_bytes~, previous_bundle_ref~)`.
Outputs are deterministic and detached from mutable editor arrays. The full
old and new bundles are validated, including receipts in the old bundle.

Files are loaded into memory; this is not a streaming editor. Evidence references
are preserved but not fetched. Storage, verification that retained files remain
available, human authentication, new decision capture, delivery to a live host
and downstream acceptance remain consumer responsibilities. These synthetic
local examples do not qualify a hosted decision journey.

After compiling a revision, [relocate retained source links](REVIEW_SOURCE_RELOCATION.md)
to moved exact passages, inspect unresolved associations, and export a complete
next-revision packet. The original review, source, map and receipts stay retained.
