# Turn review discussion into candidate source edits

Use `review_edit` when an objection or proposal needs an actual wording change
in a retained UTF-8 artifact. Select exact source lines, write their replacement,
and export both the candidate artifact and its next pending review. This fills
the gap between discussing a change and preparing changed content for review.

The existing review revision workflow edits **discussion**. This workflow edits
the **source artifact** while preserving every discussion entry and named request.
An editor's replacement is not proof that an objection is resolved. Every prior
approve/reject/defer receipt stays in the retained predecessor; the candidate
review has no receipts. A human must review the new scope explicitly.

## Try the synthetic release-brief workflow

Use a trusted native build of `cmd/review_edit`. From the repository root:

```sh
EDIT=/absolute/path/to/review_edit.exe
"$EDIT" catalog examples/review-agenda/source.md
"$EDIT" draft examples/review-agenda/review.json examples/review-agenda/source.md > /new/path/blank-plan.json
```

The catalog displays exact LF-delimited physical lines as JSON strings, including
CRLF/LF terminators. Copy the intended line text into `quote`, including its
terminator. Fill the blank plan with:

- A new workspace-relative `next_source_artifact_ref`, a new revision ID and an
  explicit `recorded_at` value accepted by the existing review validator.
- One edit per selected replacement. Each has a stable unique `key`, an existing
  `entry_id` explaining the change, one-based inclusive `start_line`/`end_line`,
  an exact `quote`, and the proposed `replacement`.

The supplied `examples/review-text-edits/selected-edits.json` names the rollback
owner and adds a support collection path. Its unchanged predecessor is the
existing synthetic café release agenda. Review and export it:

```sh
"$EDIT" preview examples/review-text-edits/selected-edits.json examples/review-agenda/review.json examples/review-agenda/source.md examples/review-agenda/review.json > /new/path/preview.md
"$EDIT" source examples/review-text-edits/selected-edits.json examples/review-agenda/review.json examples/review-agenda/source.md examples/review-agenda/review.json > /new/path/candidate-source.md
"$EDIT" bundle examples/review-text-edits/selected-edits.json examples/review-agenda/review.json examples/review-agenda/source.md examples/review-agenda/review.json > /new/path/candidate-review.json
```

The last argument is the portable reference where you retain the original bundle,
not another file to read. Actual fixture outputs are alongside the selected plan.
The source and bundle modes perform the same whole-plan validation before any
stdout output. The source mode emits exact candidate bytes without adding a
newline. Preserve these bytes and the bundle together; its source digest binds
them. Keep the plan to explain which original discussion and passages motivated
the changes.

Commands never write an input, install dependencies, contact a provider or apply
a review decision. Shell redirection occurs before a command starts: always use
new output paths, never an input path. If an export fails, a newly redirected
file may be empty; do not treat it as a result. This is a read-only generator,
not a transactional multi-file storage manager. The declared candidate reference
is portable metadata; the command does not create folders or save at that path.
Place candidate bytes there when organizing a retained workspace.

## Edit semantics and recovery

- Coordinates always refer to the original source, even if earlier replacements
  add or remove lines. Input edit order does not change the candidate result.
- Ranges must not overlap. Choose a single combined replacement when two
  suggestions touch the same lines; no side is selected automatically.
- `quote` must include every exact selected byte represented as UTF-8, including
  line terminators. No trimming, newline normalization or fuzzy matching occurs.
- An empty replacement deletes the selected lines. Include existing text plus
  additional lines to insert nearby. A replacement without a final newline can
  intentionally join with the following original line; inspect the full preview.
- Keep both binding digests unchanged. Changed bundle serialization, changed
  source bytes, stale quotes, missing discussion entries and invalid references
  fail with no candidate output. Prepare a fresh plan against the intended retained
  review and source instead of replacing a digest to force an old plan through.
- The whole discussion, participant set, host conversation identities and named
  decision requests are unchanged. Multiple selected edits may cite the same
  entry. Entry references express editor intent, not authenticated authorship or
  an automatic judgment that the concern has been answered.
- The source reference and revision must both change. Original bundles and
  sources remain historical; the new bundle links the exact predecessor bytes.
  The host still owns retention, identity, storage, receipt delivery and acceptance.

Supported scope: nonempty UTF-8 source up to 1 MiB and 10,000 physical lines,
LF or CRLF (including mixed LF/CRLF), tabs and Unicode; 1–100 selected edits.
Unsupported controls, bare CR, empty candidate content, unchanged replacements,
duplicate keys, overlapping ranges and oversized source/replacements are refused.
Inputs are in-memory; this is not a streaming or binary/document-format editor.
Use the existing DOCX tools for annotated Word material. Original byte-coordinate
edit plans are separate from the HTML packet's normalized display-line locations.

## Continue reviewing the output

Open the resulting bundle and source with the existing `review_packet`,
`review_export` or `review_decide prepare` commands. Each named reviewer must
decide again. The predecessor retains historical objections and receipts; the
candidate retains every current discussion entry as well. You may use the
existing source-location relocation workflow separately to inspect moved exact
quotes; rewritten passages require new explicit locations.

The pure APIs are `prepare_review_text_edits`, `parse_review_text_edits`,
`apply_review_text_edits` and `preview_review_text_edits`. Application returns
candidate source text and an existing v1 `ConversationReviewBundle`. It connects
the existing exact-source import, revision, supersession and Markdown projection
primitives without changing the bundle/record contract or adding a runtime.

## Verification scope

`review/text_edits_test.mbt` tests the production package. The CLI verifier at
`scripts/verify-text-edits.mbtx` invokes actual native binaries and passes generated
content into the existing native decision-form and Markdown consumers. It checks
that errors have empty stdout, input bytes are unchanged, and candidate source
bytes/digests/lineage/dissent survive consumption. Synthetic fixture identities
are not authenticated humans. Browser accessibility, a live producing host,
durable receipt return, downstream acceptance and ordinary-user L2 readiness
remain unqualified.

Run the verifier with `moon run scripts/verify-text-edits.mbtx --target wasm
--target-dir /absolute/external/target -- /absolute/review_edit.exe
/absolute/review_decide.exe /absolute/review_export.exe /absolute/source-root`
in a prepared environment. Its Wasm automation invokes actual native executables;
it does not replace production behavior with a scripted model.
