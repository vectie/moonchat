# Bring selected source notes into a review agenda

Use `cmd/review_extract` when research notes, a rehearsal transcript or pasted
reviewer comments contain points worth discussing. Inspect numbered source
lines, choose exact ranges, and append them to an existing editable agenda.
The tool retains the selected text, its source SHA-256 and line range, so you do
not need to copy quotes or reconstruct citations by hand.

This is a local, read-only authoring workflow. You choose the item kind, curator,
note and decision requests. A speaker saying “approved” remains quoted evidence;
it does not supply a participant identity or a human decision receipt.

## Try the synthetic example

Run these commands from the repository root. Redirect to new output paths,
never an input file: shell redirection truncates a file before the tool runs.

```sh
moon run cmd/review_extract --target native -- catalog examples/review-excerpts/transcript.txt > catalog.txt
moon run cmd/review_extract --target native -- agenda examples/review-excerpts/agenda.json examples/review-excerpts/source.md examples/review-excerpts/transcript.txt examples/review-excerpts/selections.json > imported-agenda.json
moon run cmd/review_extract --target native -- preview examples/review-excerpts/agenda.json examples/review-excerpts/source.md examples/review-excerpts/transcript.txt examples/review-excerpts/selections.json > preview.md
moon run cmd/review_compose --target native -- bundle imported-agenda.json examples/review-excerpts/source.md > review.json
```

The example adds a concrete search/rollback objection for the named operations
reviewer and a support-routing question. The original proposal remains first.
The resulting bundle is pending with no receipts. The checked-in catalog,
imported agenda, bundle and preview are actual outputs from these commands.

## Select your own excerpts

1. Keep the original UTF-8 text in your workspace and run `catalog` on it.
   The catalog prints the whole-file digest and one-based line numbers. Each
   line is a JSON string literal so tabs, newlines and control characters are
   visible. The original source text is never rewritten.
2. Copy `examples/review-excerpts/selections.json`. Copy the catalog digest into
   `transcript_digest` and set `transcript_ref` to where you will retain that
   exact transcript. This portable reference is independent of the local file
   path passed to the command.
3. For each excerpt, choose an inclusive `start_line` and `end_line`, a unique
   stable `key`, `question`, `objection` or `proposal` as `kind`, an existing
   participant ID as `author`, and a nonempty operator `note`. The author is the
   curator of the agenda item. It is not an inferred transcript speaker.
4. Set `decisions` explicitly, using existing human participant IDs and prompts.
   Every objection needs at least one decision request. Questions and proposals
   may use `[]`; the complete agenda still needs a decision overall.
5. Preview and export. Edit the resulting agenda with the normal
   [agenda workflow](REVIEW_AGENDA.md), then compile it. Retain the transcript,
   selection plan, artifact source and outputs together.

All selection fields are required. The `format` is
`moonchat.review-excerpts.v1`. Selections are appended in the order you specify,
even if that differs from source order. Overlapping ranges are allowed when
one passage deserves separate questions. Existing agenda items keep their keys,
content and order. New keys must not collide with an existing item or another
selection. Running the same plan twice against the already-imported agenda
therefore reports a duplicate key instead of silently duplicating its items.

To revise the selected ranges, edit the plan and rerun it against the original
agenda. To revise wording, edit the imported agenda. Keep prior agendas/bundles
if you need history; use the composer's predecessor arguments for linked review
revisions. The importer neither changes earlier files nor carries over receipts.

## Exactness and limits

- UTF-8 transcript input is limited to 1 MiB and 10,000 physical lines; a plan
  contains 1–100 excerpts. Malformed UTF-8 and empty input are rejected.
- LF separates lines. CRLF is retained exactly within imported bodies. A final
  LF terminates the last physical line rather than creating an extra selectable
  empty line. Blank lines count, and a last line without LF is selectable.
- Whole-file SHA-256 must match before any range is imported. A changed line
  ending or unselected line also requires a new catalog digest.
- The selected text is copied verbatim after a labeled operator note and source
  citation. JSON string escaping is serialization, not a text rewrite. The
  existing Markdown exporter normalizes line endings for readable display;
  retain the agenda JSON and original transcript for exact text.
- Import validates the complete agenda against the separately supplied artifact
  source. A failure produces no agenda on stdout. Input files and in-memory
  arrays are left untouched. CLI files are read into memory before validation;
  this is not a streaming importer.

The artifact under review and the transcript may be different files. The v1
bundle still binds the reviewed artifact's bytes. The transcript digest/range
are retained in each excerpt body, and its file reference is in `evidence_refs`.
This is not a new independently verified evidence-manifest contract. Later
agenda editing can change a citation or quote, and ordinary bundle import does
not re-open evidence files. Hosts retain and verify those files when required.

No live transcript connector, speaker recognition, model summary, automatic
classification, decision capture, host screen or external publishing is added.
The library API exposes `catalog_review_transcript`,
`parse_review_excerpt_plan` and `import_review_excerpts` for embedding.
