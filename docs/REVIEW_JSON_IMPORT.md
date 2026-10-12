# Review selected JSON values

Use `review_json` to inspect a local JSON artifact and bring selected nested
records or values into an editable review agenda. This supports configuration,
forecast and structured export review without copying a whole minified file
into every discussion item. It extends the portable artifact-review preparation
workflow; it does not supply human decisions or hosted review qualification.

## Workflow

1. Run `review_json catalog artifact.json`. The JSON catalog gives the exact
   byte digest and canonical JSON Pointer for every node. Containers have child
   counts; scalar values are shown. The catalog includes all scalar content, so
   retain it with the same care as the input.
2. Copy the digest and pointers into a `moonchat.review-json.v1` selection plan.
   See `examples/review-json/selections.json`. Each selection provides a stable
   item key, question/objection/proposal kind, existing curator participant,
   operator note and optional pending decision requests.
3. Run `review_json preview agenda.json artifact.json selections.json` to read
   the prepared review. Use `agenda` to export editable agenda JSON or `bundle`
   for a portable, source-bound pending review bundle.
4. Edit the exported agenda while retaining its item keys. Use the existing
   `review_compose bundle edited-agenda.json artifact.json` and `review_export
   bundle.json artifact.json` commands for the ordinary compose/export path.

All commands write stdout only. Redirect to a new path, never an input path.
Keep the original source bytes. Changed whitespace, values or key order require
a fresh digest and deliberate selection plan. Re-importing the same selected
keys into the already imported agenda fails instead of duplicating discussion.

## Pointer rules

The empty string selects the root. `/budgets/0` selects array element zero.
Object names escape `~` as `~0` and `/` as `~1`: key `a/b`, containing `~key`,
is `/a~1b/~0key`. `/` selects an empty object key. Array indexes have no leading
zeros, and `-` is not an element. URI fragment pointers (`#/...`), wildcard
queries and automatic missing-path creation are unsupported. Copy canonical
pointers from the catalog rather than guessing. Parent and child selections
are allowed, but repeating the exact same pointer in a plan is refused.

## Evidence and limits

The selected value is pretty-printed decoded JSON, not a verbatim text excerpt.
Its original source reference, full-source SHA-256 and pointer stay in the body.
Numeric source representations are retained by the pinned JSON parser, including
large integers; the importer does not perform arithmetic on them. Whitespace
and escape spelling can change in the displayed value; the digest always covers
original bytes. Imported strings, markup and apparent instructions remain data.
The existing HTML exporter escapes their markup. No code, URLs or providers run.

Supported input is strict UTF-8 JSON, at most 1 MiB, with parser nesting limit
64 and at most 10,000 total nodes. Duplicate decoded object keys are rejected
throughout the artifact, including unselected branches, because they make
selection ambiguous. Plans select 1–100 unique pointers, and combined imported
bodies are limited to 8 MiB. Null, false, empty containers and scalar roots are
valid. Missing pointers, stale digests, invalid authors/keys/decision requests,
or any invalid late selection reject the complete import before output.

The agenda is detached authoring data. The source, original agenda and existing
receipts are never modified. New bundles have no receipts; asking a reviewer a
question does not imply their answer. Receiving-product acceptance, a real host
screen and approval delivery remain separate, unqualified workflows.
