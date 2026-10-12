# Edit review items in a spreadsheet

`cmd/review_sheet` moves an editable review agenda into a seven-column CSV and
back. Use it to collect structured comments, rewrite a proposal, assign several
named reviewers, add evidence, or reorder the discussion without editing nested
JSON. It operates on local files and prints its result to stdout.

## Try the synthetic example

All names, comments and evidence references in `examples/review-sheet/` are
synthetic. From the MoonChat module root:

```sh
moon run cmd/review_sheet --target native -- export examples/review-sheet/agenda.json examples/review-sheet/source.md > initial.csv
moon run cmd/review_sheet --target native -- import examples/review-sheet/agenda.json examples/review-sheet/source.md examples/review-sheet/edited.csv > imported-agenda.json
moon run cmd/review_sheet --target native -- preview examples/review-sheet/agenda.json examples/review-sheet/source.md examples/review-sheet/edited.csv > preview.md
moon run cmd/review_compose --target native -- bundle imported-agenda.json examples/review-sheet/source.md > review.json
moon run cmd/review_sheet --target native -- export imported-agenda.json examples/review-sheet/source.md > reexported.csv
```

Use a new output filename, never an input path. Shell redirection truncates its
destination before the command reads inputs. Import errors exit nonzero, write a
diagnostic to stderr and emit no partial agenda. The checked-in `initial.csv`,
`imported-agenda.json`, `preview.md`, `review.json` and `reexported.csv` are actual
CLI outputs. Re-export the imported agenda to start another spreadsheet edit.

Open the CSV through your spreadsheet's text import, select UTF-8 and a comma
separator, and treat **all seven columns as text**. Edit and save as CSV, then
preview before compiling. No spreadsheet application or graphical UI is required
by the CLI; this release tests CSV bytes, not any specific spreadsheet product.

## Columns and repeated rows

Keep this exact header and column order:

```text
key,kind,author,body,evidence_ref,reviewer,prompt
```

- `key`: stable item identifier. Keep it when rewriting or moving a point. A
  new key creates a new item. Remove every row with a key to remove that item.
- `kind`: `question`, `objection` or `proposal`.
- `author`: a participant ID from the template agenda.
- `body`: the complete comment. Commas, quotation marks, Unicode and multiline
  cells are supported. Leading/trailing whitespace is retained.
- `evidence_ref`: optional workspace-relative reference, one per row.
- `reviewer` and `prompt`: both blank, or a human participant ID and the question
  that person must decide. This is a request for a decision, never an approval.

Repeat the first four columns **identically** on additional rows to attach more
references or request more decisions for that item. Each nonempty evidence cell
adds a reference; duplicates are retained. Each reviewer may occur only once per
item. References and reviewers need not have the same number of rows: leave unused
cells blank. Repeated rows may be nonadjacent; the first occurrence of each key
sets item order, and references/decisions retain their row order. To edit a
repeated item's body or kind, update every row for that key.

Import **replaces all template items** with the sheet's rows. It retains the
template's review ID, conversation ID, source reference, revision label, timestamp
and participant roster. Add people or change that metadata in the template JSON
first. An empty `items` array can serve as a template for a new sheet. Existing
bundle rules still apply, including a named decision for every objection and at
least one required decision overall.

In the example, a support question moves first, the launch proposal gains a
multiline pilot limit and two evidence references, the rollback objection is
rewritten, and a capacity objection is added. Launch keeps its original key and
two decision owners. Compiling the imported agenda preserves its generated item
and turn identities while producing a pending source-bound bundle.

## Format and limits

The bounded CSV dialect accepts quoted or unquoted fields, doubled quotation
marks inside quoted fields, CRLF/LF/CR record separators, a UTF-8 BOM, blank physical
lines and a missing final newline. Newlines inside quoted fields are preserved.
Quotes in unquoted fields, text after a closing quote, wrong column counts and
conflicting repeated keys receive errors. Files are limited to 1 MiB UTF-8 and
5,000 nonblank data records. Export uses CRLF and quotes every data cell.

Export prefixes formula-like cells (first non-space/tab/newline character is
`=`, `+`, `-` or `@`) with an apostrophe. An existing initial apostrophe is doubled.
Import removes this one reversible marker. When authoring CSV directly, double a
literal initial apostrophe if it precedes a formula-like value or another
apostrophe. Import all columns as text anyway: spreadsheet evaluation and save
behavior varies and is outside MoonChat's control. Avoid automatic numeric/date
conversion of identifiers. Formulas, formatting and spreadsheet metadata are not
part of the format.

The library APIs are `export_review_sheet(agenda, source_bytes)` and
`import_review_sheet(template, csv_bytes, source_bytes)`. Both validate the agenda
through the existing composer. Import returns fresh arrays, leaves inputs
untouched and never creates receipts. Source/evidence references are not fetched;
human authentication and host decisions remain host-owned. To retain earlier
review history, compile with the [agenda guide's linked revision
arguments](REVIEW_AGENDA.md#revise-a-retained-review).

## Parallel edits

When two people edited copies of the same agenda, use the
[three-way merge workflow](REVIEW_SHEET_MERGE.md) to combine independent changes
and inspect conflicts before exporting the next spreadsheet round.
