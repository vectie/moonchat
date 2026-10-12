# Prepare and edit a review agenda

Use `cmd/review_compose` to turn an editable JSON agenda and a local source file
into a portable pending review. You write the substance and name the people;
the composer fills in contract identifiers, source hashes, turn identifiers,
entry identifiers, and required-decision links. No service or model is needed.

Start with `examples/review-agenda/agenda.json` and `source.md`. The people are
synthetic. Edit the participants, questions, objections, proposals and prompts
in any text editor. Preview the exact agenda against the source:

```sh
moon run cmd/review_compose --target native -- preview examples/review-agenda/agenda.json examples/review-agenda/source.md > preview.md
moon run cmd/review_compose --target native -- bundle examples/review-agenda/agenda.json examples/review-agenda/source.md > review.json
```

Both commands read inputs and write stdout only. Redirect to a separate file,
never an input path. `preview` displays entries, named decision owners, source
identity and pending status using the existing readable export. The generated
JSON can be reimported by existing MoonChat hosts and `cmd/review_export`.
Keep the exact source bytes alongside it. It is still a pending research record.

## Agenda fields

- `review_id` and `conversation_id`: stable identifiers for this review.
- `source_artifact_ref`: the workspace-relative location at which the source
  will be retained. The source-file command argument is the file read now;
  it does not rewrite this portable reference.
- `source_revision_id`: your revision label; change it when source bytes change.
- `recorded_at`: explicit UTC time, such as `2026-10-08T12:00:00Z`.
- `participants`: IDs, display names and `human` or `agent` kinds.
- `items`: ordered discussion points with `key`, `kind`, `author`, `body`,
  `evidence_refs`, and `decisions`. All fields are required; use empty arrays
  for no evidence or no decision requests. `kind` is `question`, `proposal`,
  or `objection`; `author` refers to a participant ID.
- Each decision request contains a `reviewer` participant ID and a `prompt`.
  Several humans may decide on the same item. Every objection needs a decision,
  and the existing bundle contract requires at least one decision overall.

Item keys must be unique safe identifiers (letters, digits, `-`, `_`, `.`).
Keep a key when editing or moving an item so its generated identity is stable;
use a new key for a new point. The compiler preserves item and decision order.
It copies authoring values, does not mutate the agenda, and produces identical
output for identical input. Decision owners must be named humans; an agenda
never contains or creates a human approval receipt.

## Revise a retained review

Edit a copy of the agenda. You can change wording, reorder items, add questions,
and update decision requests. To link the new version to a retained previous
bundle, supply three additional arguments: previous bundle file, previous source
file, and the workspace-relative reference where the previous bundle is retained.

```sh
moon run cmd/review_compose --target native -- bundle edited-agenda.json new-source.md review.json old-source.md retained/review.json > revised-review.json
moon run cmd/review_compose --target native -- preview edited-agenda.json new-source.md review.json old-source.md retained/review.json > revised-preview.md
```

Review and conversation IDs must stay unchanged. Changed source bytes require
a new source revision label. The prior bundle and its source remain untouched;
retain them at their recorded references. The new version has no receipts,
including when the prior version already had decisions. This is the existing
supersession API exposed for local editing, not a receipt editor or journal.

The library entry points are `parse_review_agenda(text)` and
`compile_review_agenda(agenda, source_bytes)`. The agenda is a preparation format;
the exported bundle continues using the existing v1 contract. Referenced evidence
files are not fetched or verified by the composer. Human identity verification,
real decision capture, storage, and downstream acceptance remain host-owned.

Import local analyzer findings with the [SARIF workflow](REVIEW_SARIF_IMPORT.md),
then continue editing this same agenda format. Findings stay evidence with
explicitly assigned human decision requests.

For annotated Word artifacts, use the [DOCX comment workflow](REVIEW_DOCX_COMMENTS.md) to retain anchored passages and compile a review bound to the original DOCX.

For analysis notebooks, use the [notebook cell workflow](REVIEW_NOTEBOOK_IMPORT.md)
to select saved code/text/output context and bind the review to the original
`.ipynb` without running it.
