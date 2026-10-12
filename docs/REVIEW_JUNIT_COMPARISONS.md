# Review changed test-report evidence

A later test report can introduce a failure, stop listing an old error, or contain
repeated case names that cannot safely be paired. Compare two retained reports,
then select the relevant differences into the existing editable review agenda.
The resulting questions carry **both full case snapshots and both report digests**.
An absent failure is not silently resolved, and the importer creates no receipts.

This extends the [single-report JUnit intake](REVIEW_JUNIT_IMPORT.md), using its
parser, roster checks and pending-agenda format. It supports MOONCHAT-W01 and
B01–B03 preparation: source binding, explicit named decision requests and preserved
review meanings. It does not execute tests, validate a native bundle, capture human
choices or complete the W05 host review journey.

## Run the complete retained example

From the repository root, use Python 3.10+ with no third-party packages. Pick new
output paths; the CLI refuses to overwrite any existing file.

```sh
python -B tools/review_docx/review_junit.py --output /tmp/report-comparison.json compare examples/review-junit-comparison/before.xml examples/review-junit-comparison/after.xml
python -B tools/review_docx/review_junit.py --output /tmp/changed-tests-agenda.json comparison-draft examples/review-junit-comparison/agenda.json examples/review-junit-comparison/source.md examples/review-junit-comparison/before.xml examples/review-junit-comparison/after.xml examples/review-junit-comparison/selections.json
```

The synthetic example has six cases in each report and six comparison groups:

- The invoice case changes from `failure` to `no-failure-reported`. Its old failure
  and logs remain available. No pass or fix is asserted.
- Backup restore changes from `skipped` to `failure`; both messages are retained.
- The retired check's earlier `error` is absent in the later report. The selected
  objection asks why the case is missing and whether it should be rerun.
- Smoke is unchanged despite changing its report position.
- Two identically named retry cases on each side are one ambiguous group. All four
  snapshots remain, without pairing them by their order or inventing attempt IDs.
- Refund is newly listed with an `error`, distinct from a failure assertion.

Open the generated comparison JSON, choose rows and edit a selection plan. The
checked-in `comparison.json` and `imported-agenda.json` are actual CLI outputs.
The latter preserves the earlier `release-scope` question and appends four selected
items in the curator's order. Each selected item proposes a question for the
existing `ops` human participant. These assignments do not authenticate anybody.

Review and edit the new agenda, then continue through the existing native composer
when a separately installed trusted executable is available:

```sh
review_compose preview /tmp/changed-tests-agenda.json examples/review-junit-comparison/source.md
review_compose bundle /tmp/changed-tests-agenda.json examples/review-junit-comparison/source.md > /tmp/pending-review.json
```

Those native commands were **not run or qualified** for this delivery. Native
validation may still reject a preparation draft, especially a question-only agenda
with no required decision. Use the existing agenda/predecessor workflow for review
revisions; this comparison does not establish bundle lineage or transfer approvals.

## Understand the comparison

The JSON contract is `moonchat.junit-comparison.v1`. Rows group cases by the exact
tuple of the complete suite path, `classname` and `name`. Empty suite/class names
remain literal values. The case name must be nonblank to suggest correspondence.
Matching names are only a heuristic: they cannot prove these are the same tests,
runner configuration, source checkout or invocation. Before and after are caller
labels, not verified execution order. Choose related retained reports yourself.

- `added`: one uniquely named case exists only in the after report.
- `absent`: one uniquely named case exists only in the before report.
- `changed`: unique cases on both sides have different catalog evidence.
- `unchanged`: unique cases have identical catalog evidence except their positional
  indexes. This does not assert identical XML bytes or test execution.
- `ambiguous`: a name is blank or either side contains more than one case for the
  same tuple. All cases remain in `before_cases` and `after_cases`. No automatic
  pairing or outcome-change claim is made, even if repeated content is identical.

`presence` separately says `both`, `before-only` or `after-only`, including for
ambiguous groups. `changed_fields` lists case-evidence differences, including
reported time, file/line metadata, logs, signals and status. Identity changes
appear as absent plus added groups. Formatting and aggregate-count changes may
change report digests without changing case rows. Suite properties, suite-level
logs and vendor extensions are outside the existing parser subset; retain the XML.

`outcome_change` describes only unique matched summary statuses. It can mark a
new failure/error report, a failure/error no longer reported, a status change or
the same reported status. Always read the full `signals` arrays: all failure,
error and skipped signals remain in source order. The existing summary precedence
is error, failure, skipped, then no-failure-reported. Failure-to-error remains a
reported-status change. Neither a missing case nor a skipped/unmarked case proves
a pass, resolution, release eligibility or review completion.

Rows are ordered by first appearance in the before report, followed by identities
new in the after report. Their zero-based `index` belongs only to this exact pair
of report snapshots. Each case retains its own original report index. Summary
counts count identity groups, not cases; `before_case_count` and `after_case_count`
separately record catalog sizes without trusting XML suite count attributes.

## Select evidence for named review questions

Copy `examples/review-junit-comparison/selections.json` and set these exact fields:

- `contract_id`: `moonchat.junit-comparison-selection.v1`
- `source_digest`: `sha256:` plus the reviewed artifact's exact byte hash
- `before_report_digest` and `after_report_digest`: copy from the comparison
- `before_report_ref` and `after_report_ref`: distinct workspace-relative paths to
  retained reports. References are recorded as evidence, never opened or fetched.
- `rows`: 1–100 distinct comparison indexes in desired discussion order

Each selection has `index`, a new stable `key`, `kind` (question, objection or
proposal), existing participant `author`, nonblank curator `note`, and `decisions`.
Each requested decision has an existing human `reviewer` and a nonblank `prompt`.
An objection must request a decision. Duplicate keys, duplicate selected indexes,
unknown people and agent decision owners are refused. An ambiguous or absent row
may be deliberately selected to ask for clarification; the complete ambiguity or
old evidence follows it into the agenda. Unselected rows remain in the comparison
and original XML, rather than being declared resolved.

The draft retains agenda metadata, existing items and participants. For each
selected row it appends the note plus a labeled JSON evidence block containing the
source reference/revision/digest, both report references/digests, matching limits
and the full selected comparison row. Both report references are also ordinary
`evidence_refs`. Keep these through editing so the reader can trace each claim to
its side and source. Re-import into that resulting agenda is refused on key reuse.
The source can be a release proposal; no relationship between the reports and the
source checkout is inferred. Source/report byte changes require explicit selection
updates, not receipt carry-forward. Hashes identify bytes, not their signer.

## Limits and verification

Reports use the existing UTF-8, unnamespaced JUnit-style `testsuite`/`testsuites`
subset: 2 MiB each, 5,000 cases and suite nesting depth 32. DTD/entity declarations
are refused. Empty reports are allowed and cannot produce a completion claim.
Agenda/selection inputs are at most 2 MiB each and the reviewed source 8 MiB.
Comparison JSON is limited to 16 MiB; draft JSON to 8 MiB. Serialization bounds
are checked incrementally before the destination is created. Reduce the retained
report scope deliberately if necessary, keeping the original reports separately.

Only explicitly supplied local files are read. Evidence strings stay plain JSON
and are never executed. Output creation is exclusive and begins only after all
validation/serialization checks pass. A write failure may leave a partial newly
created file; preserve the original inputs and choose a fresh path when retrying.
No files are shared. Selected logs may be sensitive, so review before sharing.

```sh
PYTHONDONTWRITEBYTECODE=1 python -B -m unittest discover -s tools/review_docx -p 'test_*.py' -v
```

98 focused Python tests pass, including 12 new comparison tests covering actual
CLI comparison → row selection → agenda creation → reopening, earlier discussion
preservation, ambiguity, absent evidence, status distinctions, source/report
bindings, no-overwrite, invalid late selection and deterministic retained outputs.
The real existing Python planning-shape check is exercised, with no fake native
composer. Native MoonBit, browser/host UI, runner execution, human authentication,
receipt delivery and receiving-product acceptance remain unqualified. No install,
network, browser or Moon command was used. R50 remains the last fully verified
cumulative result; R51–55 remain separate.
