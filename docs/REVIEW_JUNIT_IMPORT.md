# Bring test-report evidence into an artifact review

When a release proposal needs a human decision about a failing or skipped test,
import that case's report evidence into the existing MoonChat editable agenda.
Select cases explicitly, retain their original messages, and ask existing named
humans a question. The tool runs no tests and creates no decisions or receipts.
This supports MOONCHAT-W01 and B01–B02 preparation: scoped source identity,
participants and explicit decision requests. It does not complete a host review
journey, validate a bundle natively, or establish that a test runner succeeded.

## Prepare, inspect, edit

From the repository root with Python 3.10+ and no third-party packages:

```
python3 -B tools/review_docx/review_junit.py --output /tmp/test-catalog.json catalog examples/review-junit/results.xml
python3 -B tools/review_docx/review_junit.py --output /tmp/test-agenda.json draft examples/review-junit/agenda.json examples/review-junit/source.md examples/review-junit/results.xml examples/review-junit/selections.json
```

The supplied example is synthetic. It selects an invoice failure and a skipped
backup check, leaving a nested-suite error and an unmarked case unselected.
The retained imported-agenda.json is actual CLI output. Reopen it, edit the
curator note or decision prompt, and continue via the existing native composer:

```
review_compose preview /tmp/test-agenda.json examples/review-junit/source.md
review_compose bundle /tmp/test-agenda.json examples/review-junit/source.md > /tmp/review-bundle.json
```

Those final commands require your separately installed trusted native composer;
they were not run or qualified for this change. Native validation may still
refuse a draft. Redirect to a fresh path; shell redirection can truncate inputs.
The Python tool never invokes the composer or writes a bundle itself.

1. Retain exact report and reviewed artifact bytes. Catalog the report. Its
   zero-based indexes distinguish repeated case names across nested suites.
2. Start with the selection example. Copy the catalog's report_digest, set
   report_ref to the workspace-relative retained XML path, and set source_digest
   to `sha256:` followed by the SHA-256 of the complete reviewed artifact bytes.
   The source need not be the test report: it may be the release proposal.
3. Select 1–100 distinct indexes in your desired append order. Every selection
   specifies key, kind, existing author, nonblank curator note and decisions.
   Each decision names an existing human reviewer and prompt. An objection must
   request a decision. Human names in XML are never inferred as participants.
4. Generate the draft to a NEW output path. Existing agenda items, source
   metadata and roster remain intact. Item keys must be unique, including prior
   items. Re-import into the already imported draft is refused on duplicate keys.
5. Review the output before continuing to native composition. Source/report
   hashes, source revision, retained report reference, zero-based index, suite
   path and full selected case evidence remain in the item's ordinary body.
   The report_ref is also an ordinary evidence_ref. Keep these through editing.

## What the report means

Failure, error and skipped signals remain distinct, with all messages/types/text
retained in source order. If multiple signal kinds coexist, the summary order is
error, failure, skipped; every original signal stays present. An unmarked case is
called `no-failure-reported`, never a proven pass. The tool does not trust suite
aggregate counts, measure durations or infer coverage. The original time/file/line
attributes and per-case stdout/stderr are retained as unverified text. Nested
suite paths preserve empty names and repeated case names. Suite-level logs,
properties and other extensions are not imported; retain original XML for them.
No matching of case file attributes to the reviewed source is inferred.

Supported input is UTF-8 unnamespaced JUnit-style testsuite/testsuites XML,
up to 2 MiB, 5,000 cases and nesting depth 32. DTD/entity declarations are refused;
predefined XML escapes are decoded normally. Namespaced and vendor-specific
schemas are unsupported. Source bytes are bounded to 8 MiB, agenda/plan to 2 MiB,
and generated draft to 8 MiB. File references are not opened. Evidence markup,
logs and apparent instructions remain plain agenda strings, not commands.

Changed source or report bytes require a fresh explicit selection digest. Digests
bind bytes, not signer identity or test execution. This tool checks the existing
planning shape, known participants and decision requests; it does not duplicate
native agenda/bundle validation. It can prepare requestless question-only drafts
that native composition may reject. No approval or accepted-knowledge claim is
made. Sharing the output would expose selected logs and source metadata; the
CLI does not share anything. An interrupted write may leave a partial output.

## Focused verification

```
python3 -B tools/review_docx/test_review_junit.py
```

Nine dependency-free tests cover nested/repeated names, all four outcome labels,
retained logs/signals, exact digest binding, prior items, decision-prompt editing,
selection order, actual CLI file reopening and refusal before an invalid late
selection writes. Checks use the existing planning-shape validator, not a fake
native composer. Native bundle composition, browser/host review, runner execution
and receipt return remain unqualified. No Moon commands or installs were run.

## After another report arrives

Use [test-report comparison](REVIEW_JUNIT_COMPARISONS.md) to retain both snapshots,
inspect changed or absent evidence, and append selected comparison rows to an
agenda. Duplicate test identities stay ambiguous, and an unmarked later case never
becomes a proven pass or a resolved review objection.
