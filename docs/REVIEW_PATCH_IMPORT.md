# Review selected changes from a local unified diff

Use this when a release editor has a saved textual patch and needs named review
of particular changes before deciding what to do with it. A catalog lists every
file and hunk. Explicit selections become editable questions, objections or
proposals with named decision requests. Existing composition, Markdown/HTML
reading and blank decision forms consume the result.

The reviewed source is the exact `.diff` bytes. This does not verify the checkout,
apply the patch, test changed code, authenticate a reviewer, or approve an
unselected hunk. Paths are literal evidence labels, never files to open.

## Runnable local example

Build the native `cmd/review_patch`, `cmd/review_compose`, `cmd/review_decide`
and `cmd/review_export` packages with the repository's pinned MoonBit toolchain.
Use an absolute external target directory and a private HOME/XDG environment.
The batch verification guide accompanying this snapshot gives the exact retained commands.
For a normal checkout, replace `$BIN` below with that target's
`native/debug/build/cmd` directory and run from the repository root.
Every output filename must be a new path, never an input path.

```sh
"$BIN/review_patch/review_patch.exe" catalog examples/review-patch/changes.diff
"$BIN/review_patch/review_patch.exe" preview examples/review-patch/agenda.json examples/review-patch/changes.diff examples/review-patch/selections.json
"$BIN/review_patch/review_patch.exe" agenda examples/review-patch/agenda.json examples/review-patch/changes.diff examples/review-patch/selections.json > /tmp/patch-agenda.json
"$BIN/review_compose/review_compose.exe" bundle /tmp/patch-agenda.json examples/review-patch/changes.diff > /tmp/patch-review.json
"$BIN/review_decide/review_decide.exe" prepare /tmp/patch-review.json examples/review-patch/changes.diff ops > /tmp/patch-choices.json
"$BIN/review_export/review_export.exe" /tmp/patch-review.json examples/review-patch/changes.diff > /tmp/patch-review.md
```

The example catalogs two files and three hunks. It selects the owner assignment
and new checklist. The monitoring hunk remains unselected. The existing
deployment-window question is retained. Two named blank choices are created;
no decision receipt exists. `review_patch bundle` also emits the normal v1
bundle directly when no intermediate agenda editing is needed.

To use your patch, save a complete local UTF-8 unified diff, catalog it, and copy
the catalog's `source_digest` into a new selection plan. Update the agenda's
source reference and revision. File and hunk numbers are one-based. Each
selection supplies a stable unique item key, question/objection/proposal kind,
an existing participant, an operator note, and zero or more named human decision
requests. Edit agenda text or selection notes before composing. Any byte change
to the diff requires a fresh catalog and plan digest; do not reuse a review as
approval of replacement bytes.

## Supported input

- Ordinary `---` / `+++` unified diffs, optionally preceded by Git `diff --git`
  and index/mode/rename/copy metadata. Such metadata is retained as literal
  evidence; it does not establish file permissions or rename validity.
- Multi-file patches and multiple nonoverlapping ordered hunks per file.
- Omitted single-line counts, zero-context additions/deletions, `/dev/null`
  file creation/deletion, section headings and exact no-final-newline markers.
- UTF-8 text, LF or CRLF patch lines, unquoted names with spaces, and optional
  tab-separated timestamps in `---` and `+++` headers. Original headers and
  hunk text, including terminators, are retained inside JSON-escaped evidence.

Binary, combined/merge and metadata-only patches, quoted Git paths, mail
preambles/trailers and arbitrary nonpatch content are rejected. A mixed patch
containing an unsupported file is rejected in full, even if that file was not
selected. Obtain a textual supported patch first; nothing is silently omitted.
Hunk counts, ordering and newline-marker placement are checked, but correctness
against a repository is outside this importer. This is evidence intake, not
`git apply --check`.

## Bounds and failure behavior

Input: at most 1 MiB, 10,000 physical lines, 100 files and 1,000 hunks. Coordinates
are at most 1,000,000,000 and each range count at most 10,000. A plan selects
1–100 distinct hunks, and selected evidence including notes is at most 8 MiB.
All files and selections are validated before any stdout result. Invalid UTF-8,
changed digest, missing file/hunk, duplicate selection/key, unknown participant,
nonhuman reviewer and malformed syntax fail rather than producing a partial
agenda. CLI failures have nonzero status and diagnostics on stderr, with empty
stdout. Inputs are never rewritten. Redirecting stdout is the caller's file
operation, so always choose new output paths.

See [the tested API example](../review/PATCH_IMPORT.mbt.md). The existing v1
bundle and receipt contracts are unchanged. The host still owns authenticated
decisions, persistence, delivery and receiver acceptance. Passing local tests
does not qualify a hosted UI, accessibility or ordinary-user L2 readiness.
