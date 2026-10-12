# MoonChat

> **Portable review-contract pack · not a chat application or agent runtime.**
> Read the [product contract](docs/PRODUCT_CONTRACT.md) for the authority and
> ownership boundary.

MoonChat records reviewable conversations as portable, append-only evidence.
It consumes MoonLib's shared `moonsuite-conversation.v2` identity contract and
adds only the review-specific layer: questions, objections, proposals,
required decisions and named-human receipts.

The canonical capability is:

```text
moonchat/conversation.review.record@0.1.0
```

It can emit a pending or rejected research record. It emits
`accepted-knowledge` only when every required decision has a valid approval
receipt from its named human reviewer.

## Scope And Boundary

MoonChat owns:

- product identity for `moonchat`
- shared MoonSuite state, service, cache, temp, and accepted-output paths
- the versioned conversation-review bundle and record contracts
- append-only review events and content-addressed version lineage
- agent-suggestion versus human-decision authority checks
- the pack-local MoonFlow v2 execute, reconcile and short-lived health adapter

MoonChat does not own agent execution, model routing, desktop UI, durable
book truth, or town scheduling. MoonClaw owns execution, Moondesk owns the
desktop projection, MoonBook owns durable accepted material, and Moontown owns
coordination.

## Implementation Map

- `moonchat.mbt`: product identity.
- `moonsuite_layout.mbt`: thin adapters over `@moonsuite` for MoonChat product
  paths.
- `review/`: portable review contracts, pure source-bound authoring, validation
  and deterministic projection. See the executable
  [authoring guide](review/README.mbt.md) for host integration.
- `flow_adapter/` and `cmd/moonflow_adapter/`: durable MoonFlow v2 adapter.
- `pack.json`, `schemas/`, `policies/`, `workflows/`, `providers/`: capability
  truth and operating boundary.
- `cmd/main/`: minimal CLI entrypoint.
- `moonchat_test.mbt`, `review/*_test.mbt` and
  `flow_adapter/*_wbtest.mbt`: focused contract and restart tests.
- `scripts/fresh-suite-product-home-smoke.sh`: shell smoke for fresh-suite
  product-home behavior.

## Editable review agendas

Already have a host-authored bundle but no original agenda? The
[received-review revision workflow](docs/REVIEW_REVISIONS.md) reopens its
discussion for editing, preserves host identities, and produces a new pending
bundle linked to the exact retained original. Prior receipts stay historical.

Prepare questions, proposals and objections in a small JSON agenda, assign named
decision owners, then preview or compile it against a local source file:

```sh
moon run cmd/review_compose --target native -- preview examples/review-agenda/agenda.json examples/review-agenda/source.md
moon run cmd/review_compose --target native -- bundle examples/review-agenda/agenda.json examples/review-agenda/source.md > review.json
```

The [agenda guide](docs/REVIEW_AGENDA.md) covers editing, stable item keys, multiple
reviewers and linked revisions. Generated bundles are pending and never invent
human receipts. A realistic synthetic agenda and readable result are included.

## Edit review items in a spreadsheet

Export an agenda to CSV, edit comments and decision prompts in a spreadsheet,
then import or preview the revised items against the retained source. Multiple
references and reviewers are supported without JSON inside spreadsheet cells.
The [spreadsheet guide](docs/REVIEW_SHEETS.md) includes the column format and an
end-to-end synthetic example with actual outputs.

```sh
moon run cmd/review_sheet --target native -- export examples/review-sheet/agenda.json examples/review-sheet/source.md > initial.csv
moon run cmd/review_sheet --target native -- preview examples/review-sheet/agenda.json examples/review-sheet/source.md examples/review-sheet/edited.csv
```

## Combine parallel spreadsheet edits

Two people can edit copies of the same review sheet, then merge their independent
changes by item key and named reviewer. Preview the combined pending agenda or
inspect conflicting base/left/right values, edit the sheets and retry. The
[parallel-edit guide](docs/REVIEW_SHEET_MERGE.md) includes runnable synthetic
inputs and explains additions, deletions and ordering.

## Import GitHub review threads

Bring selected threads from a local GitHub REST pull-request comment export into
an existing agenda. The importer groups replies, retains file/diff/commit context,
and maps authors to existing participants before preview or bundle compilation.
See the [GitHub import guide](docs/REVIEW_GITHUB_IMPORT.md) and synthetic examples.
The workflow is offline and creates no decision receipts.

## Import selected source notes

Inspect numbered transcript lines, choose exact ranges with explicit authors and
review meanings, then append cited excerpts to an agenda without retyping them.
The [excerpt import guide](docs/REVIEW_EXCERPTS.md) includes a synthetic pilot
review, runnable commands and actual pending review outputs.

```sh
moon run cmd/review_extract --target native -- catalog examples/review-excerpts/transcript.txt
```

## Readable review export

Export a portable review bundle and its retained source as a readable Markdown
handoff, including entries, decisions, receipts, lineage and projected events:

```sh
moon run cmd/review_export --target native -- examples/review-export/pending.json examples/review-export/source.md > review.md
```

See [the export guide](docs/REVIEW_MARKDOWN_EXPORT.md). This local read-only view
does not create receipts or replace the original bundle JSON and source bytes.

## Plan decisions on annotated Word documents

Read proposed agenda items and each named reviewer's questions alongside the exact
DOCX passages that prompted them. The [DOCX planning packet](docs/REVIEW_DOCX_PLANNING.md)
uses the existing comment importer and preserves every original comment. It is
draft preparation; native validation and human decision capture remain separate.

## Testing Guidance

Run focused checks before changing the review contracts:

```sh
moon check
moon test review
moon test flow_adapter --target native
moon info
moon fmt
```

For layout changes, also run:

```sh
scripts/fresh-suite-product-home-smoke.sh
```

Review `pkg.generated.mbti` after `moon info`; any new public type or function
should be deliberate because other MoonSuite products may consume it.

## Worth Noticing

- Product paths must go through MoonLib `@moonsuite`, not local string
  concatenation.
- Selected `books/<book-id>` roots should resolve product state through the
  owning suite root, while accepted outputs remain book-scoped.
- MoonLib owns the base conversation DTO contract; MoonChat does not fork it.
- Agent-authored proposals and objections never count as decision receipts.
- Keep the package independent from UI frameworks and model-provider code.

## Intended consumers

- MoonTown's collaboration composer authors pending source-bound review bundles
  through the delivered paired local workspace. It verifies snapshot constituents
  and retains previous source versions; authoring never creates decision receipts.
- MoonFind exports a stakeholder-review bundle and consumes the resulting
  pending/accepted record in a compiled MoonFlow graph.
- MoonBook may import an accepted record as evidence for Bookkeeper closure,
  but performs its own closure and acceptance checks.

These product integrations are consumers of this contract, not new MoonChat
runtimes or applications.

## Explore a retained review

Find an objection, a named reviewer's pending items, or receipt evidence with
`cmd/review_explore`. The [local exploration guide](docs/REVIEW_EXPLORATION.md)
shows literal text, kind, reviewer and outcome filters. Each matched entry keeps
all its decisions and receipts; the report clearly distinguishes filtered results
from the original review's full status.

## Read objections at their source passages

[Source-linked offline packets](docs/REVIEW_SOURCE_LOCATIONS.md) connect existing
review entries to exact quoted line ranges. Jump from a source passage to its
objections and receipts, or read the excerpts inline when printing. A separate
location file keeps the original review intact; every unlocated entry stays
visible.

## Carry source links into a revised artifact

When unchanged passages move, [relocate their exact quoted ranges](docs/REVIEW_SOURCE_RELOCATION.md)
into the next review packet. The offline report lists every ambiguous, rewritten
or removed passage and changed entry; only unique matches for unchanged entries
enter the suggested map. Inspect the report, complete unresolved locations in
context, then export the whole next review with the existing packet command.

## Structured JSON review

Catalog and select nested artifact values with JSON Pointers, then edit and export
a source-bound review: [JSON import guide](docs/REVIEW_JSON_IMPORT.md).

## Read Word comments in their document context

Before selecting classic DOCX comments for import, export a self-contained
[Word comment reading packet](docs/REVIEW_DOCX_PACKETS.md). Read the complete
logical document, jump between comment cards and exact source ranges, and retain
the original archive digest. This local Python-only reading step needs no native
composer and creates no review decisions.

```sh
python -B tools/review_docx/review_docx.py packet examples/review-docx/launch.docx > launch-comments.html
```

## Review changed test-report evidence

Compare two retained JUnit reports before asking named reviewers about new failures,
missing cases or ambiguous repeated test names. Select complete before/after rows
into the existing editable agenda while preserving both report digests and earlier
concerns. See [test-report comparison](docs/REVIEW_JUNIT_COMPARISONS.md). Report
changes create questions, never test passes, resolved objections or review receipts.
