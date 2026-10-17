# Curate a local Slack daily export into a pending review

Use this when a review developer has an already-downloaded Slack conversation
export and needs to turn particular recorded messages into explicit questions,
proposals or objections. Catalog the complete daily array, choose one-based
ordinals and the exact source digest, write curator notes, and name the humans
who should decide. The result is an ordinary editable ReviewAgenda consumed by
the existing composer, Markdown/HTML exporters and blank decision forms.

The complete daily file is the reviewed source. A discussion about a release
does not bind the release's separate artifact bytes or approve its execution.
The curator participant is explicitly supplied and is separate from the recorded
Slack user ID. No user directory is read and no identity mapping is inferred.

## Run the synthetic example

Build `cmd/review_slack`, `cmd/review_compose`, `cmd/review_decide`,
`cmd/review_export` and `cmd/review_packet` with the pinned native toolchain.
The accompanying round guide records the private HOME/XDG environment, external
target and exact acceptance runner. Set `$BIN` to that target's
`native/debug/build/cmd` directory. Redirect only to fresh output paths.

```sh
"$BIN/review_slack/review_slack.exe" catalog examples/review-slack/2026-10-13.json
"$BIN/review_slack/review_slack.exe" agenda examples/review-slack/agenda.json examples/review-slack/2026-10-13.json examples/review-slack/selections.json > /tmp/slack-agenda.json
"$BIN/review_compose/review_compose.exe" bundle /tmp/slack-agenda.json examples/review-slack/2026-10-13.json > /tmp/slack-review.json
"$BIN/review_decide/review_decide.exe" prepare /tmp/slack-review.json examples/review-slack/2026-10-13.json ops > /tmp/slack-choices.json
"$BIN/review_export/review_export.exe" /tmp/slack-review.json examples/review-slack/2026-10-13.json > /tmp/slack-review.md
"$BIN/review_packet/review_packet.exe" /tmp/slack-review.json examples/review-slack/2026-10-13.json > /tmp/slack-review.html
```

The catalog contains six records, including edit/deletion history and an
unsupported channel event. The plan selects only the proposal and objection,
retaining a prior agenda question and producing two blank named decisions.
`review_slack bundle`, `preview` and `html` produce those derived outputs
directly. Edit the returned agenda before composing if wording needs refinement.
All outputs use existing bundle contracts; no receipt is created by import.

For your own file, copy its catalog `source_digest` into a
`moonchat.review-slack.v1` plan. Supply each selection's `ordinal`, stable unique
`key`, `kind`, curator `author`, nonblank `note` and explicit `decisions` array.
Set the agenda's source reference/revision to describe that file. Any byte
change, including whitespace or record reordering, needs a new digest and
deliberate reselection. Selection ordinals are not Slack message identities.

The returned agenda carries a machine-checked `source_digest_constraint`.
The ordinary composer checks it against the supplied bytes after reloading the
agenda, so wording edits cannot silently rebind old message evidence to a new
daily file. Keep that field when editing. For a changed export, start from a
fresh preparation agenda and recatalog/reselect, rather than rebinding an old
imported agenda. Legacy hand-authored agendas without the field remain unbound;
the importer adds the constraint. This is an integrity guard against accidental
reuse, not a signature or tamper-proof format: deliberately deleting/replacing
the constraint changes the authoring scope. Reimport any rejected candidate-1
Slack agenda, which predates this constraint, before using it.

## Slack profile and subtype policy

Grounding: Slack's [How to read Slack data exports](https://slack.com/help/articles/220556107-How-to-read-Slack-data-exports),
consulted 2026-10-13, describes per-conversation daily JSON files, message fields,
subtypes, reaction metadata and retained edit/deletion history. This importer
implements the narrower local profile below; it is not a general Slack API,
archive replay or export-completeness implementation.

- Root: one UTF-8 JSON array. Every element must be an object. File order is
  retained; an empty array catalogs successfully but cannot supply selections.
- Selectable: `type: "message"` with no subtype, or exactly `me_message`,
  `bot_message`, or `file_share`. `text` must be a string (empty is allowed).
  `ts` and optional `thread_ts` must be strings with 1–20 decimal second digits,
  a dot and six fractional digits. They are retained exactly, never converted
  through floating point or treated as verified wall-clock timestamps.
- A nonblank string `user` is required except `bot_message` may instead carry
  a nonblank string `bot_id`. If `user` exists it must be a nonblank string.
  These are recorded IDs, not resolved or authenticated names.
- Optional `edited` must be an object with string `user` and a supported `ts`.
  Such rows are explicitly labeled `*_edited_snapshot`, retained as observed
  edited snapshots, and never reconstructed as original or current messages.
- `message_changed` and `message_deleted` are cataloged with explicit archival
  classifications and cannot be selected. Their complete raw objects remain
  available in the catalog and original source. Edits are never applied and
  deletions never silently ignored as if the remaining text were current.
- Every other subtype is unsupported, including thread broadcasts, channel/group
  lifecycle events, file replies/mentions, pin events and unknown future values.
  Empty, null and synthetic `ordinary` subtype values are unsupported too.
- Supported-looking records with `previous`, `previous_message`, `original_ts`,
  `deleted_ts` or nested `message` fields are labeled ambiguous archival data
  and cannot be selected. `hidden` must be absent or false. Invalid field types
  produce unselectable rows with reasons, without renumbering later records.

Reactions, attachments, files, text, recorded IDs and all other fields remain
quoted evidence. `raw_message` is a JSON string containing the exact original
object slice, including key order, spacing, escape spelling and line endings;
decode that string to recover it. Selected recorded metadata is also shown as
decoded JSON for reading. The digest binds the whole file including its array
delimiters and surrounding whitespace. No rich-text blocks, links or images are
rendered or fetched. Reaction counts/users are not approval or a voter roster.
Threads are not stitched or sorted: a reply can refer to a root absent from that
daily file. Duplicate timestamps remain distinct explicitly selected ordinals.

## Bounds, failure and authority

Source limits: 1 MiB, 1,000 records and JSON nesting depth 64. Duplicate decoded
object keys at any level, malformed JSON, non-object entries and invalid UTF-8
reject the entire file. ZIP, TXT, message API envelopes and directories are not
accepted. Unsupported object rows remain visible and cannot be selected.
Plan parsing is capped at 1 MiB and depth 64 and rejects duplicate decoded keys.
A plan selects 1–100 distinct ordinals. Selected rendered evidence, including
notes, is capped at 8 MiB. Each ordinal must be mathematically an exact integer
in 1–1000. Original numeric tokens are checked before Int decoding, so fractional
numbers reject even when binary64 rounds them to integers. Exact integral forms
such as `1.0`, `10e-1` and `0.01e2` are accepted as 1. Use the dedicated plan
parser with the original JSON text; do not pre-convert numeric tokens through
floating point. Any extra JSON field named `ordinal` follows the same rule.
Programmatic plans have the same selection/evidence
bounds. Existing agenda authoring checks enforce participant IDs, item keys,
named-human decision ownership and an explicit decision for every objection.
At least one named decision across the resulting agenda is required.

All selections are validated before any stdout result. Stale digest, invalid
ordinal, unsupported selected record, late invalid selection, missing file or
malformed plan yields nonzero exit and stderr with empty stdout. Inputs are
never rewritten. Do not redirect onto an input: redirection is the caller's
operation and this CLI does not provide transactional storage. Native CLIs read
local files into memory before enforcing parser bounds, so this is bounded
in-memory preparation, not a streaming untrusted-file service.
The retained `review_export` command writes a failure diagnostic on stdout for
stale input; it emits no Markdown handoff. Always check every command's exit
status. The new `review_slack` modes report failures on stderr only.

HTML includes the whole source file, including unselected and archival records,
as literal source evidence. Selected-only agenda entries do not redact the
source. Share packets only with recipients allowed to see the complete export.
The existing HTML exporter also limits source display to 10,000 lines, which
can reject a highly whitespace-expanded file accepted by the JSON catalog.
The host owns retention, authenticated decisions, delivery and independent
receiver acceptance. No Slack access, remote mutation, automatic review of
other artifacts, hosted UI or ordinary-user/L2 qualification is claimed.

See [the tested public API example](../review/SLACK_IMPORT.mbt.md).
