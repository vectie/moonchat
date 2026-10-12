# Readable review handoffs

MoonChat can export its portable review bundle as a standalone Markdown handoff.
Use it to read a conversation and its outstanding decisions outside a MoonSuite
host, attach a readable review to a work item, or retain a review alongside its
source. It is a local projection, with no provider or service connection.

## Command line

From the MoonChat module:

```sh
moon run cmd/review_export --target native -- examples/review-export/pending.json examples/review-export/source.md > review.md
```

Or build `cmd/review_export` and invoke the resulting binary:

```sh
review_export bundle.json source-file > review.md
review_export --help
```

Both input paths are explicit local files. Source paths embedded in the bundle
are displayed, not opened. The command writes only to stdout; shell redirection
chooses the output file. Keep the destination distinct from both inputs, since
a shell opens/truncates the redirect destination before the command starts.
Missing arguments, unreadable files, invalid JSON/bundles, and source mismatches
exit unsuccessfully without a Markdown report.

## Pure API

`@review.export_review_markdown(bundle, observed_source_bytes)` returns a String
or raises the existing review validation error. Supply the actual bytes of the
retained source, just as with `reimport_review_bundle`; no new authority rule or
receipt requirement is introduced. The API does not change the bundle or write
files. Its result is deterministic for the same bundle and source bytes.

## What the report contains

- Review status, claim class and the existing operator outcome guidance
- Source artifact, SHA-256, revision and previous-bundle lineage
- Conversation identity and named participants
- Questions, objections and proposals, including turn IDs and evidence refs
- Each required decision's subject, prompt, named reviewer and existing receipt
- Approval, rejection and deferral outcomes, rationale, timestamps and evidence
- Missing/rejected decision IDs and the existing projected event sequence

Dynamic text is rendered in indented literal blocks. Unicode and multiline text
remain readable; Markdown-looking entry text, HTML and evidence references are
displayed literally rather than interpreted as report structure or active links.
CRLF and bare CR are normalized to LF for readable output. An empty field is
shown as `(none)`. These display choices mean Markdown is not a lossless wire
format: retain the original JSON and source bytes for reimport or exact history.
The CLI adds its normal terminal newline after the API's report.

The event section uses `review_events`' deterministic projection order. It is
not a chronological sort or proof that a durable execution journal was written.
Export does not author decisions, accept material on a reviewer’s behalf, or
change downstream MoonBook/MoonFlow behavior. Accepted status means only what
the existing MoonChat contract says for that exact source-bound bundle.

## Examples and tests

`examples/review-export/` contains one source with pending, approved, rejected
and deferred fixture bundles, each accompanied by actual CLI Markdown output.
All people and receipts in these examples are synthetic fixtures. Run:

```sh
moon test review --target native
moon check --target native
```

Focused tests cover deterministic/nonmutating output, all receipt outcomes,
Unicode and literal Markdown text, lineage and exact-source binding. CLI evidence
also exercises fixture exports, unchanged inputs, usage and invalid inputs.
