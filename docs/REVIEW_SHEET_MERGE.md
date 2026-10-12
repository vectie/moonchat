# Combine parallel spreadsheet review edits

Two reviewers can now edit separate copies of the same exported agenda, then
combine their changes without choosing one person's entire file over the other.
`cmd/review_sheet` uses the original agenda as a common base and merges the two
CSV imports by stable item key and named reviewer. The result is another editable
agenda, ready for the existing preview, export and bundle composer.

This is local preparation of questions, objections, proposals and required
requests. It never authors a decision receipt. Keep the exact common-base agenda
and source file alongside both CSVs. CSV files do not embed or authenticate their
origin: the caller is responsible for supplying copies from this same base.

## Synthetic example

`examples/review-sheet-merge/` contains a fictional café pilot review:

- The editor rewrites the launch proposal, clarifies their decision prompt,
  moves the support question first and adds a cohort question.
- Operations adds two evidence references, changes its own launch prompt,
  edits the rollback objection and adds a staffing objection.
- The merged agenda retains all of these edits. Item and decision identities
  remain stable when compiled. Its four requested decisions remain pending.

From the delivered workspace, use the pinned environment and external target
from the accompanying `BUILD.md`. After building `cmd/review_sheet` and
`cmd/review_compose`, the binaries accept:

```sh
SHEET=/absolute/external/target/native/debug/build/cmd/review_sheet/review_sheet.exe
COMPOSE=/absolute/external/target/native/debug/build/cmd/review_compose/review_compose.exe
E=examples/review-sheet-merge

"$SHEET" merge "$E/base-agenda.json" "$E/source.md" "$E/editor.csv" "$E/operations.csv" > combined-agenda.json
"$SHEET" merge-preview "$E/base-agenda.json" "$E/source.md" "$E/editor.csv" "$E/operations.csv" > combined-preview.md
"$SHEET" export combined-agenda.json "$E/source.md" > next-round.csv
"$COMPOSE" bundle combined-agenda.json "$E/source.md" > pending-review.json
```

Always redirect to a new output filename. Shell redirection truncates a file
before the command starts; redirecting into an input would destroy that input.
The programs themselves only read files and write stdout/stderr.

The checked-in `merged-agenda.json`, `merged-preview.md`, `merged.csv` and
`pending-review.json` are actual executable outputs. The retained preview shows
all five items, four required decisions and no receipt. No evidence reference is
fetched and no spreadsheet application is required to run this example.

## Find and resolve a disagreement

Use the conflicting operations sheet to inspect an incompatible proposal rewrite
and decision-prompt edit:

```sh
"$SHEET" merge-report "$E/base-agenda.json" "$E/source.md" "$E/editor.csv" "$E/conflicting-operations.csv" > conflicts.json
```

The report has `format: "moonchat.review-sheet-merge.v1"`, a `conflicts` array and
`merged_agenda`. Each conflict contains `item_key`, `field`, `base`, `left` and
`right`. Values are actual JSON values; `null` indicates an absent item or
reviewer request. For an ordering conflict, the values are arrays of identities.
A conflict report sets `merged_agenda` to `null`, never to a partially merged
candidate. All conflicts detected in valid input are reported together.

Edit one or both CSVs to resolve each differing value, then rerun. To choose the
editor's text, either set both branches to that text or restore the operations
cell to the base text so its branch no longer changes that cell. With repeated
rows for an item, update every copy of its core fields. In the example,
`operations.csv` is the corrected branch; retrying with it succeeds.

`merge-report` exits 0 for a successfully computed report, including reports that
contain conflicts. Automation must inspect `conflicts` or `merged_agenda`.
`merge` and `merge-preview` exit 1 with zero stdout when conflicts remain and
point to `merge-report`. Malformed or invalid input exits 1 in every mode.

## Merge rules

- Metadata and participant roster come unchanged from the base agenda. The CSV
  format cannot change source revision, identities or participants.
- Item keys align existing items. `kind`, `author` and `body` merge separately.
  One changed side wins over an unchanged side; identical changes coalesce.
  Different two-sided changes conflict.
- Required requests align by `reviewer` within each item. Separate reviewers'
  prompts can be edited independently. Adding a different reviewer and editing
  an existing prompt combine. Removing a request versus editing its prompt
  conflicts. A review request remains a request, never a human decision.
- Each item's `evidence_refs` array is an atomic ordered value. A one-sided edit
  or equal two-sided edit is retained exactly, including duplicates. Different
  two-sided changes conflict rather than guessing the intended reference order.
- Deleting an item on one side and leaving it unchanged on the other deletes it.
  Deleting versus changing any content conflicts. Different new items combine;
  the same new key must have identical complete content or it conflicts.
- The relative order of surviving common-base items is merged as a separate
  field. One-sided reorders are retained, identical reorders coalesce and
  incompatible two-sided reorders conflict. Deletions are excluded first.
  New items are appended afterward in left then right order, once each, rather
  than guessing an insertion position. Named requests follow the same rule.
  To choose the final insertion positions, reorder the exported merged sheet.

The base and each imported branch must be independently valid under the existing
agenda rules. The combined candidate is validated again. Independently removing
the last two required decisions on different branches can make the combination
invalid even though each branch is valid; this returns a validation error rather
than an agenda. Fix the intended requests in the sheets and retry.

The existing CSV bounds apply independently to each input (1 MiB UTF-8 and
5,000 nonblank records). A combined agenda can be larger than either branch;
subsequent CSV export still enforces its own existing limits. No new size or
performance qualification is claimed. Invalid UTF-8, unknown participants,
non-human required reviewers and malformed repeated rows retain existing errors.

## API and boundaries

`merge_review_sheets(base, left_csv, right_csv, source_bytes)` returns
`ReviewSheetMerge` or raises on invalid data. Its optional `merged_agenda` is
available only when the conflict list is empty and the combined agenda passes
validation. Returned arrays are detached from the base; inputs are not mutated.

The source file binds the newly compiled pending review. A CSV is not a signed
receipt or a provenance guarantee. Use the established linked-revision composer
when retaining earlier bundle history; merging preparation sheets does not alter
an earlier bundle or inherit its approvals. This workflow does not qualify a
live host, spreadsheet UI, named human action, receipt delivery or downstream
MoonBook acceptance.
