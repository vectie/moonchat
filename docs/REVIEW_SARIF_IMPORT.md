# Bring analyzer findings into an artifact review

`review_sarif` turns selected findings from a local SARIF 2.1.0 report into
ordinary editable MoonChat questions, objections or proposals. A reviewer can
inspect the analyzer's original message, rule, locations, suppression and fix
suggestions alongside the artifact under review, then ask a named human to
resolve the concern. Findings and tool suppressions never become human receipts.

## Try the synthetic workflow

With the native commands built, run from the repository root:

```sh
review_sarif catalog examples/review-sarif/results.sarif > catalog.txt
review_sarif preview examples/review-sarif/agenda.json examples/review-sarif/source.md examples/review-sarif/results.sarif examples/review-sarif/selections.json > preview.md
review_sarif agenda examples/review-sarif/agenda.json examples/review-sarif/source.md examples/review-sarif/results.sarif examples/review-sarif/selections.json > imported-agenda.json
review_sarif bundle examples/review-sarif/agenda.json examples/review-sarif/source.md examples/review-sarif/results.sarif examples/review-sarif/selections.json > review.json
```

The fixture selects an ownership question from the second run, followed by a
fallback objection from the first run. An unrelated style finding is left out.
The fallback's accepted analyzer suppression, earlier baseline state, fingerprint
and suggested fix remain visible. A message saying “I approve everything” is
still only machine-produced evidence. The review has zero receipts.

Edit the imported agenda normally. The supplied `edited-agenda.json` changes the
human decision prompt without changing the imported evidence or item identity.
Continue through the existing composer and complete-source HTML packet exporter:

```sh
review_compose bundle examples/review-sarif/edited-agenda.json examples/review-sarif/source.md > edited-review.json
review_packet edited-review.json examples/review-sarif/source.md > review.html
```

The checked-in `catalog.txt`, agendas, bundles, preview and HTML packet are actual
native CLI outputs. All people, tools and findings are synthetic. Commands read
local files and write stdout only. Redirect to a fresh output path, never an
input: shell redirection truncates the destination before the program runs.
Errors exit 1, explain the problem on stderr, and emit no partial output.

## Select findings deliberately

1. Retain a self-contained SARIF JSON export. Run `catalog` to see its exact
   SHA-256 and zero-based run/result coordinates. The catalog does not execute an
   analyzer or establish that a scan succeeded or covered the whole project.
2. Copy the example selection plan. Set `export_ref` to the workspace-relative
   path where these exact report bytes are retained and `export_digest` to the
   catalog digest. The input filename does not rewrite this portable reference.
3. For each finding, specify `run_index`, `result_index`, a unique stable `key`,
   `kind` (`question`, `objection` or `proposal`), `author`, `note` and `decisions`.
   The author is an existing participant curating the finding, not an inferred
   analyzer identity. Choose the order in which findings will be appended.
4. Name decision requests explicitly using existing human `reviewer` IDs and
   `prompt` strings. Every objection needs a decision; questions/proposals may
   use an empty decision list. The complete agenda needs at least one decision.
5. Preview, export, and retain the original report with the source and agenda.
   Imported items can continue through the normal agenda, spreadsheet, revision
   and packet workflows. No new portable bundle contract is introduced.

The plan format is `moonchat.review-sarif.v1`. All plan/selection fields are
required. One result can be selected only once; separate runs may legitimately
contain different results for the same rule. Stable item keys determine existing
MoonChat entry/turn IDs. Coordinates are only meaningful in the exact
SHA-256-bound report. A newer or reformatted report needs a new plan digest and
explicit selection review; this is not a finding synchronizer or a baseline diff.

Reimporting into the already imported agenda fails on key collisions. Rerun
against the original agenda for deterministic regeneration. For previously
decided reviews, use the existing revision workflow and retain the predecessor;
this importer does not copy prior receipts or edit their authority.

## What is retained

Each appended body contains the operator note, report reference and digest,
`/runs/N/results/M` JSON pointer, analyzer name, rule ID, explicit level, verbatim
`message.text`, resolved primary-location context and complete selected result
JSON. Thus suppressions, baseline state, fingerprints, related locations, code
flows, suggested fixes and other fields in that result remain inspectable.

Primary `artifactLocation.index` references are resolved against that run's
`artifacts` table. An inline URI/base ID that contradicts its indexed location
fails instead of silently choosing one. Paths and URI base mappings remain
provenance text: no URI is fetched, normalized into the local workspace, or
opened. Physical region fields and logical locations are retained as supplied.
Line/column coordinates are analyzer coordinates, not MoonChat source links.

Driver rules are found by `ruleIndex` or matching `ruleId`; contradictory indexes
or ambiguous matching IDs fail. The driver descriptor, matched rule, URI bases,
run automation details, version-control provenance and column-kind context are
included. An omitted result level is shown as an empty string; the importer does
not infer a level from default configuration. The original rule descriptor is
available when present. Other run-level data stays in the retained report.

The complete selected result is reserialized JSON, not byte-for-byte original
JSON formatting. The exact original report digest covers all bytes, including
unselected results and whitespace. Decoded message text keeps Unicode, CRLF and
whitespace; Markdown display normalizes line endings as before. Metadata in the
catalog is JSON-escaped, and the existing HTML exporter escapes displayed text.

The reviewed artifact is the separately supplied source file. Its actual bytes
supply the review's source digest. SARIF paths, commit labels and findings do not
prove that a report analyzed this source. The operator must establish that
relationship. Imported evidence references are not independently reopened by
ordinary bundle validation; later agenda edits can change the quoted material.

## Supported subset and limits

- UTF-8 with an optional BOM, at most 1 MiB; 1–100 runs and up to 1,000 results
  across all runs. Empty result arrays are catalogable. An import plan selects
  1–100 distinct results. Inputs and outputs are held in memory.
- Exact `version: "2.1.0"`, a runs array, each run's `tool.driver.name`, and each
  result's nonempty `message.text`. `results` may be omitted or empty; zero
  cataloged results makes no assertion about scan success or completeness.
- Driver `ruleId`/`ruleIndex`, optional explicit `level` (`none`, `note`, `warning`,
  `error`), optional primary physical/logical locations, and indexed or inline
  artifact locations are supported. Indexes must be nonnegative integral values
  and table references must exist. Missing locations and rule IDs are allowed.
- Message-ID-only or Markdown-only messages, `message.arguments`, `result.rule`
  tool-component references and `externalPropertyFileReferences` are explicitly
  unsupported. Expand messages and produce a self-contained driver-rule export
  before import. The importer never retrieves external property files.
- Structural checks apply to every result, including unselected ones. This is a
  bounded importer, not a complete SARIF schema validator or analyzer execution
  verifier. Preserved opaque result/region fields are evidence, not assertions
  of their validity. The original report remains the complete context.

The format follows the [OASIS SARIF 2.1.0 specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html).
The supported subset above is deliberately narrower than the complete format.

Pure embedding APIs: `catalog_sarif_review`, `parse_sarif_review_import_plan`, and
`import_sarif_review`. Results are deterministic, detached authoring data and
validated through the existing agenda composer. No source files, people,
permissions, human decisions, suggested fixes, live provider state or receiver
acceptance are changed. Focused native fixture evidence does not qualify a
hosted human review/receipt journey.
