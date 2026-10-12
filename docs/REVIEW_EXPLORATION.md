# Find a review point with its decision context

Use `review_explore` to locate a particular objection, a named reviewer's pending
items, or the evidence behind a receipt without reading a whole exported bundle.
The command reads local files and writes a Markdown reading view to stdout.
It verifies the complete original bundle against exact source bytes first.

From the module root, try the retained synthetic examples:

```sh
moon run cmd/review_explore --target native -- examples/review-explore/pending.json examples/review-explore/source.md --kind objection --reviewer ops --outcome pending > objections.md
moon run cmd/review_explore --target native -- examples/review-explore/pending.json examples/review-explore/source.md --text café > search.md
moon run cmd/review_explore --target native -- examples/review-explore/pending.json examples/review-explore/source.md --outcome none > questions.md
moon run cmd/review_explore --target native -- examples/review-explore/approved.json examples/review-explore/approved-source.md --text "no real review authority" --outcome approve > receipt.md
```

Redirect only to a new path, never an input: shell redirection truncates its
output before MoonChat can read it. No files, receipts or review status are
changed. Evidence references are displayed, never fetched. These examples use
fictional people and receipts; the checked-in reports are actual CLI outputs.
Portable source references still name their original fixture locations.

## Filters

All filters are optional and may appear in any order, once each. Omit them to
browse every entry with its associated decisions.

- `--text`: case-sensitive literal substring, including Unicode and multiline
  text. Searches each entry's ID, kind, author ID/name, body, turn identifiers
  and evidence references, plus its decision IDs/prompts/reviewer IDs/names and
  receipt IDs/names/rationales/evidence references. It does not search source
  bytes, unrelated participants, timestamps or digests. No regex, tokenization,
  fuzzy matching, Unicode normalization or automatic case folding.
- `--kind`: exactly `question`, `objection` or `proposal`.
- `--reviewer`: exact participant ID, not display name; finds required decisions
  assigned to that participant. An unknown ID is an error. A participant with no
  assigned decisions produces an explicit empty result.
- `--outcome`: `pending` (no receipt), `approve`, `reject`, `defer`, or `none`
  (no decision was requested on this entry). Deferral is distinct from pending.

Filters combine with AND at entry level. When reviewer and outcome are both
supplied, the same required decision must satisfy both. The text can match any
field associated with that entry. `--outcome none` together with a reviewer has
no matches. An empty, unknown, repeated or missing CLI option value is an error.
The library uses empty strings to mean an omitted filter.

## Reading the result

The header always reports the original review's status and claim class, exact
source identity, selected filters, and matched versus total entry count. Entries
remain in bundle order. Each match shows its original body, author, turn IDs,
evidence, and **all** its decision requests and receipts. This means another
reviewer's rejection or deferral stays visible even when it did not match the
filter. Approval does not remove the objection that prompted it.

A no-match report still carries source identity and full-review status. It does
not mean there is no dissent or that the review is complete. This partial view
is not an importable bundle or a replacement for the complete review handoff.
Use `review_export` for the complete report and retain original JSON and source
bytes for exact evidence. Dynamic values use literal blocks; line endings are
normalized for display, as in the existing Markdown exporter.

The pure API is `explore_review(bundle, source_bytes, text?, kind?, reviewer?,
outcome?)`. It validates the full input before applying filters, returns a
deterministic String, and leaves input objects untouched. An invalid hidden
entry or wrong source still fails. No result is printed on CLI validation error;
the command exits 1 with stderr diagnostics. There is no pagination, live
search index, host screen, provider integration or new decision authority.
