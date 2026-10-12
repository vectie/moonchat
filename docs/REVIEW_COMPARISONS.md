# Compare review revisions

Before asking a reviewer to revisit an artifact, produce a focused change report:

```sh
review_compare before.json before-source.md after.json after-source.md > changes.md
```

The native CLI validates each bundle against its own exact source bytes before
writing stdout. The two snapshots must name the same source artifact reference
and the same full conversation binding. Review IDs and revision IDs may differ.
A bad digest, invalid bundle, or unrelated scope fails without a partial report.

The report includes both revision/digest bindings and independently projected
statuses, followed by added, changed, removed and unchanged counts for:

- Participants, including display names and human/agent kinds
- Typed questions, objections and proposals, including body, author, turn IDs and
  evidence references
- Required decisions, including subject, named reviewer and prompt
- Decision receipts, including rationale, evidence and original source digest

Objects match by their explicit stable IDs. Changed objects show both complete
versions; removed objects show the old content so discarded objections remain
visible. Added objects show their new content. Array order changes are reported
separately and do not count as content edits. Keep agenda item keys stable during
spreadsheet edits to get useful comparisons. An ID rename is removal plus addition.
Unchanged content is omitted to keep the comparison focused.

The public library API is `export_review_comparison(before, before_source,
after, after_source)`. It returns Markdown without mutating either bundle.

## Inspect what changed in the source text

When the artifact itself changed, include its exact line edits in the same report:

```sh
review_compare --source-text before.json before-source.md after.json after-source.md > source-changes.md
review_compare --source-text --context 1 before.json before-source.md after.json after-source.md > compact-changes.md
```

The source section appears after both review identities/statuses and before the
existing discussion and decision comparison. It includes every added or removed
line, with three unchanged context lines on each side by default. `--context`
accepts integers from 0 through 20 and requires `--source-text`; both options go
before the four paths. Nearby edits share a hunk, distant edits get separate
hunks, and the report counts omitted unchanged lines. Zero context still shows
every changed line. Repeated lines align deterministically, preferring removal
when two shortest edit sequences are possible. Moves appear as removal/addition.

Each row shows the change (`=` unchanged context, `-` removed, `+` added), the
one-based before and after line numbers, and a JSON string containing the exact
physical line. A dash in a number column means the line is absent on that side.
String quotes and escapes make whitespace, tabs and line endings visible:
`"owner: ops\r\n"` differs from `"owner: ops\n"`, and a missing final newline
is visible. CRLF, CR and LF each end a physical line. An empty source has zero
lines; a terminal newline does not invent another line. A UTF-8 BOM is retained
and displayed as `\uFEFF`. Unicode text stays readable; source markup remains
literal text in an indented block. This is a textual diff, not an interpretation
of document semantics or a verified mapping from an objection to a source line.

Try the retained synthetic example from the module root:

```sh
review_compare --source-text --context 1 examples/review-source-comparison/before.json examples/review-source-comparison/before-source.md examples/review-source-comparison/after.json examples/review-source-comparison/after-source.md > regenerated.md
```

Its output is retained as `examples/review-source-comparison/changes.md`. The
pilot changes its traffic limit and rollback owner; the existing objection
also changes and another objection is added. Source edits and their discussion
are visible together, while the new review remains pending. All people and
review records in the example are fictional.

For embedding, pass `source_context=3` (or another integer from 0 through 20) to
`export_review_comparison`. Leaving this optional argument out produces the
unchanged existing report and continues to support arbitrary binary sources.
Text mode accepts valid UTF-8, at most 1 MiB and 2000 physical lines per source.
It uses a bounded longest-common-subsequence table of at most 2001 × 2001
integer cells. Its source section has at most 4000 data rows, with JSON escaping
possibly expanding each line. The existing review/discussion output has no new
size limit; all inputs and the complete output remain in memory.

Invalid UTF-8, either exceeded source limit, invalid context, unrelated scopes
or any failed full-bundle validation exit with a diagnostic and no stdout.
There is no fallback that silently replaces undecodable source bytes. Use the
ordinary comparison without `--source-text` for binary or larger sources.
Commands read only the four explicit local files. Redirect to a new path, never
an input file, because the shell truncates the destination before reading starts.

## Boundaries

This is a comparison of verified snapshots, not proof of journal ancestry or a
semantic source-document diff. Optional source text comparison is literal line
comparison. It shows existing predecessor fields but does not
verify their lineage. A receipt disappearing or changing in the second snapshot
is visible; this tool does not authorize deleting or rewriting journal evidence.
An old approval is not copied to the new source. Retain both JSON bundles and
both source versions. Reference paths are printed, never fetched. No host UI,
reviewer authentication, live decision capture, or receiving-host acceptance is
implemented or qualified by this output.
