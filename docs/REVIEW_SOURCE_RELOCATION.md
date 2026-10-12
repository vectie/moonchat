# Keep discussion linked when source passages move

After revising an artifact, reuse unchanged source quotations without hunting for
all their new line numbers. `review_relocate` compares a retained location map
with the exact old and next review snapshots. It produces a readable report, a
JSON report and a suggested map for the existing offline HTML packet exporter.

This completes the local sequence: reopen a review, edit the source, compile a
new pending revision, relocate unchanged passages, inspect unresolved locations,
and export the whole next review with navigable source excerpts. It never edits
discussion or transfers an old receipt to new bytes.

## Try the synthetic pilot

Build the native `cmd/review_relocate`, `cmd/review_revise` and
`cmd/review_packet` packages with your configured pinned toolchain and external
build target. Use their resulting executables from the repository directory:

```sh
E=examples/review-relocation
review_revise draft "$E/before.json" "$E/before-source.md" > draft.json
# Edit a copy of the draft. The retained edited-draft.json selects pilot-2.
review_revise bundle "$E/edited-draft.json" "$E/next-source.md" "$E/before.json" "$E/before-source.md" examples/review-relocation/before.json > next-review.json
review_relocate preview "$E/before.json" "$E/before-source.md" "$E/before-locations.json" next-review.json "$E/next-source.md" > relocation.md
review_relocate report "$E/before.json" "$E/before-source.md" "$E/before-locations.json" next-review.json "$E/next-source.md" > relocation.json
review_relocate locations "$E/before.json" "$E/before-source.md" "$E/before-locations.json" next-review.json "$E/next-source.md" > suggested-locations.json
review_packet --locations suggested-locations.json next-review.json "$E/next-source.md" > next-review.html
```

Always redirect to a new path, never an input file: the shell truncates its
output before the command reads inputs. All commands read local files and write
stdout only. Invalid input exits 1 with a stderr diagnostic and no partial stdout.
An unresolved location is a successful report, not a validation error: inspect
`unresolved_count` and every result. All three modes intentionally exit 0 for a
valid input with unresolved ranges. `locations` emits a **partial map**, which can
be empty. Read the report before using it.

The included real outputs show one mapped range and two unresolved ranges:

- The complete traffic passage moves from lines 3–5 to 6–8 and is relinked.
- The rollback passage has a changed owner, so the old quote has no exact match.
- The coverage sentence occurs twice, at lines 15 and 18. Neither is chosen.

`partial-review.html` keeps the full question, objection and proposal visible.
The unlocated entries explicitly say no source location was supplied. The old
synthetic approval and deferral remain in `before.json`; the compiled next
review contains no receipts and remains pending.

## Finish the unresolved locations

Read the next source in context and edit a copy of the suggested map using the
[location-file format](REVIEW_SOURCE_LOCATIONS.md). For a changed passage, select
its current inclusive lines and copy their exact display text into `quote`.
For an ambiguous passage, choose the intended occurrence explicitly. Do not
assume a repeated sentence identifies the same semantic passage.

The synthetic `resolved-locations.json` adds the newly worded rollback passage
at lines 10–12 and deliberately selects **current** coverage at line 15 rather
than future coverage at line 18. Export it with the existing validator:

```sh
review_packet --locations "$E/resolved-locations.json" next-review.json "$E/next-source.md" > resolved-review.html
```

The retained `resolved-review.html` is the actual output. Validation checks exact
quotes and identities; it cannot establish the reader's semantic choice. The
complete original review/source/map and report remain useful evidence, including
when an entry was removed from the next snapshot. Removed discussion is not
silently reintroduced into a new review.

## Matching and result meanings

Both complete bundles are validated against their own bytes before matching, as
is the entire old map. The snapshots must share their full conversation binding
and source artifact reference. Review IDs and revision labels may differ. This
is snapshot comparison, not proof of journal lineage or an authorization to
create a new revision. Use the existing revision workflow for that step.

Each old range gets one result in its original order:

- `relocated`: its complete entry record is unchanged, the quote occurs exactly
  once, and no other old range for this entry collapses onto that destination.
  The coordinates may remain the same. The range appears in the suggested map.
- `entry-removed`: the next review has no entry with this stable ID.
- `entry-changed`: the ID exists but some part of the entry changed, including
  body, kind, author, any turn identifier or evidence reference/order. The reader
  needs to reconsider the association, even if its quote has an exact match.
- `quote-not-found`: an unchanged entry's complete quote no longer occurs.
- `ambiguous`: an unchanged entry's quote occurs more than once. The old line
  number is not used as a tie-breaker.
- `range-collision`: two old ranges for the same entry would map to one new
  range. Both stay unresolved rather than silently collapsing separate history.

Entry removed/changed takes precedence over quote status, but exact candidates
are still shown to help a reader. Different entries can share one source range;
that is supported by the packet exporter and is not a collision. New entries
have no old associations, so remain unlocated until a reader supplies them.

Only complete display-line sequences match. There is no substring search, fuzzy
similarity, whitespace trimming, case folding or Unicode normalization. Display
rules match the HTML exporter: CRLF and CR become LF; BOM, tabs, spaces and
Unicode are significant; a terminal newline supplies a final empty display line;
empty source has one empty display line. Source digests always use original
bytes, including original line endings. An unchanged quote can still acquire a
different meaning from surrounding changes, so inspect context. Existing entry
text, including any prose line-number references, is never rewritten.

## Embedding and limits

The pure API is `relocate_review_source_locations(previous, previous_source,
locations, next, next_source)`. It returns `ReviewSourceRelocation` with exact
old/next bindings, result counts, per-range `original`, `status`,
`candidate_count`, `candidates`, and `suggested_locations`.
`result.to_markdown()` formats the reading view. Serialize the result as JSON or
pass `result.suggested_locations` to `export_review_html` directly. Outputs are
deterministic; input bundles and maps remain unchanged.

The same packet limits apply to each source: valid UTF-8, at most 1 MiB and
10000 display lines, with no unsupported text controls. The old map has at most
1000 ranges, 10000 total selected lines and 1048576 UTF-16 quote units. These
limits are validated again for the suggested map. A whole-line KMP scan handles
repeated prefixes in linear line-comparison time per range. All exact matches,
including overlaps, are counted; reports retain only the first 20 candidate
ranges per old location. A count above 20 always remains ambiguous. No truncation
can turn it into a unique match. Inputs and outputs are in memory, not streamed.
The existing review bundle and JSON decoder have no new file-size limit.

These are reader navigation outputs. They do not create receipts, alter review
claims, change an old location map, authenticate humans, verify a receiving host
or accept knowledge. Evidence references are preserved without fetching them.
Local API and executable checks do not qualify a browser, accessibility, a live
host or an end-to-end human decision journey.
