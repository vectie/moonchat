# Reuse a review checklist

Review developers can save recurring questions, objections and decision prompts
once, then prepare fresh reviews for different artifacts and named people. A
checklist separates reusable wording from each review's source, participants and
literal text values. It creates an ordinary editable agenda for the existing
MoonChat composer, decision forms and export tools.

## Try the two-artifact example

The complete synthetic example is in `examples/review-checklist/`. One release
checklist prepares a Café review for Mei and a separate Library review for Sam.
The first plan lacks a rollback owner; the second names one. Both still require
human review. No answer is inferred from the artifact's prose.

Build `cmd/review_checklist` with the repository's pinned MoonBit toolchain. In
the retained R664 workspace, `../run-focused.mbtx` builds it and its consumers,
runs both examples and saves all actual outputs in `../evidence/`. See the batch
guide for the private environment and external target setup.

With `BIN` set to the absolute native command directory and the shell in the
source root, these commands are the complete user journey:

```sh
"$BIN/review_checklist/review_checklist.exe" catalog examples/review-checklist/release-checklist.json
"$BIN/review_checklist/review_checklist.exe" agenda examples/review-checklist/release-checklist.json examples/review-checklist/cafe-input.json examples/review-checklist/cafe.md > /tmp/cafe-agenda.json
"$BIN/review_compose/review_compose.exe" preview /tmp/cafe-agenda.json examples/review-checklist/cafe.md
"$BIN/review_compose/review_compose.exe" bundle /tmp/cafe-agenda.json examples/review-checklist/cafe.md > /tmp/cafe-review.json
"$BIN/review_decide/review_decide.exe" prepare /tmp/cafe-review.json examples/review-checklist/cafe.md mei
"$BIN/review_checklist/review_checklist.exe" preview examples/review-checklist/release-checklist.json examples/review-checklist/library-input.json examples/review-checklist/library.md
```

Use fresh output paths; shell redirection can overwrite files before a command
runs. The CLI itself only reads local inputs and writes stdout. It never sends,
authenticates, applies decisions, or writes back to the source artifact.

## Author and explore a checklist

`moonchat.review-checklist.v1` has:

- A stable `checklist_id` and a readable `title`
- `roles`, such as `writer` and `operator`; these are slots, not people
- `variables`, the exact set of textual values needed for reuse
- `items`: stable key, question/objection/proposal kind, author role, body and
  decision prompts with reviewer roles

`catalog` explains which items each role authors or decides, which roles need
humans, and each variable's body/prompt locations. It includes all reusable
wording so the author can inspect the checklist before supplying values.

Bodies and prompts support `${name}` substitutions. A value is inserted once,
as literal text: a value containing `${window}` remains exactly that text.
`$$` emits one dollar sign; `$${window}` emits literal `${window}`. Other dollar
signs, such as `$5`, remain literal. Unicode and multiline text are supported.
There are no expressions, nested templates, includes, conditionals, commands or
automatic summaries. Only body and prompt text are interpolated, never IDs,
roles, source references or participants.

Declare every used variable exactly once. Missing, extra, duplicate, empty or
whitespace-only input values are errors. Unknown placeholders, malformed `${...}`
syntax, unused variable declarations, duplicate keys, unknown roles and
unsupported versions are errors. Objections need at least one decision; every
checklist needs at least one named-human decision request.

## Instantiate against a new source

Copy a sample `moonchat.review-checklist-input.v1` input and explicitly choose:

1. New review and conversation IDs, the source artifact reference and revision,
   and recorded-at time
2. The actual source digest; `review_checklist digest <source>` computes it
3. Participant IDs, names and human/agent kinds
4. Exactly one assignment for every declared role
5. Exactly one literal value for every declared variable

The input's checklist ID must match. Changed source bytes fail until the author
deliberately updates the binding. Assignment to a participant missing from the
input fails. A role that decides must resolve to a human. Two distinct decision
roles on one item cannot collapse onto one participant and silently lose a
request. One person can otherwise fill multiple roles.

`agenda`, `bundle` and `preview` accept the same three inputs. The agenda retains
item keys and makes fresh source evidence references. Edit or reorder it using
the existing agenda workflow; edits to that result do not affect the reusable
checklist or other instances. Question, objection and proposal meanings survive
composition. Bundle output has zero receipts, no inherited previous bundle and
the existing `pending_review` state.

## Scope and limits

This is a preparation workflow, not a verified identity or authority mechanism.
Role assignment does not authenticate a reviewer. Checklist text is the author's
wording, not a claim that the source contains a fact. Materialization cannot
import prior approvals: the format has no receipts or old source binding.
Generated evidence references point only at the newly chosen source.

The checklist ID labels reusable content; it is not a signed or digest-bound
template version. Save template/input files alongside the result if exact
preparation provenance matters. No automatic migration of existing bundles or
extraction of former decisions is provided. User-controlled JSON is an in-memory
preparation format, not a bounded untrusted-data ingestion service.

Native synthetic CLI tests establish catalog-to-agenda-to-consumer behavior.
They do not establish hosted browser/keyboard accessibility, identity provider
integration, durable receipt delivery, receiving-product acceptance, production
readiness or L2 qualification. All failed, skipped or unrun required gates stay
blocking. No PRD acceptance requirement is newly marked complete.

The [executable API example](../review/CHECKLIST.mbt.md) is tested with the review
suite. `scripts/verify-checklists.mbtx` runs the actual native CLI examples.
