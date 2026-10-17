# Complete named review decisions in a host

MoonChat's agenda composer can prepare a review, but a host previously had to
construct raw receipts manually. The decision-form API now connects the existing
bundle to explicit approve, reject, and defer choices, then to the existing
projection, serialization and journal APIs. It is a pure review capability,
not a chat application, login service or delivery runtime.

## Local preparation

The native `cmd/review_decide` command supports:

```
review_decide prepare bundle.json source.md reviewer-id > new-form.json
review_decide preview new-form.json bundle.json source.md
```

Use new output paths, never redirect onto an input. A prepared form includes the
exact source identity, every discussion entry (including objections), named
reviewer, decision subjects and prompts. All outcomes start blank. Edit a choice
with an explicit `approve`, `reject`, or `defer`, a rationale, unique receipt ID,
canonical UTC decision time and optional workspace-relative evidence references.
Blank untouched choices remain undecided. A partly filled choice is rejected.

The CLI identifies all input as an **unverified decision submission**. It cannot
apply a decision or produce a qualifying receipt. It makes no authentication or
human-review claim from someone typing a participant name.

## Offline named-choice editor

The local Python producer now consumes an **exact blank native prepare form**
and opens an interactive choice-entry page. This is separate from the existing
DOCX agenda authoring workflow: it fills outstanding review decisions rather
than creating agenda items or copying earlier receipts.

From the repository root, using a trusted already-built native executable:

```sh
DECIDER=/absolute/path/to/review_decide.exe
"$DECIDER" prepare examples/review-agenda/review.json \
  examples/review-agenda/source.md ops > /new/path/prepared.json
python3 -B tools/review_decisions/review_decision_editor.py \
  /new/path/prepared.json examples/review-agenda/review.json \
  examples/review-agenda/source.md --decider "$DECIDER" \
  --output /new/path/decision-editor.html
```

Open the generated HTML in your browser. The producer reruns the actual native
`prepare` on immutable local input snapshots and refuses a form whose identity,
complete discussion, choices, prompts or blank initial values differ. It never
compiles, installs dependencies, invokes a provider, or applies a decision.
Existing output files are refused. Use fresh paths for shell redirection too.

1. Inspect the complete source, source digest/revision, all discussion and
   objections, all named requests, participants and historical receipts.
2. Enter `approve`, `reject` or `defer` explicitly for an outstanding request.
   Supply a rationale, a unique **proposed** receipt ID, declared UTC timestamp,
   and optional workspace-relative evidence paths, one per line. These fields
   are unverified input. No name, time or ID is generated as reviewer evidence.
3. Leave every field blank to keep a request undecided. “Clear this choice”
   resets only that request. Partly entered choices can be saved as drafts,
   but cannot pass preview or export. No approval is defaulted.
4. “Preview unverified choices” displays the exact native form JSON after local
   checks. Every edit invalidates this preview. “Export native form.json”
   downloads the unchanged native schema, including protected discussion and
   identity fields, with only the editable choice values filled in.
5. “Save unverified draft” downloads an explicitly labeled draft envelope,
   including unfinished text. “Reopen saved draft” stages its choices for
   inspection and requires a separate replacement click. Cancel, a newer file
   selection, or a local edit prevents an earlier asynchronous read from
   replacing current work. Wrong review/revision/reviewer, hidden discussion,
   changed prompts/ownership, missing/reordered choices and unknown fields are
   rejected without altering the current draft. Reopening always requires a
   fresh preview before export.
6. To combine two partial drafts, reopen the first draft, then use “Merge
   another partial draft for this reviewer” for the second. The import is
   staged against the exact same blank native form, including the named
   reviewer, source revision/digests, all discussion, prompts and choice order.
   Disjoint choices are combined; a wholly blank incoming choice never erases
   current work. Identical choices need no resolution. Every differing pair
   of nonblank choices is a conflict, even if their outcomes agree.
7. Inspect both **whole choice objects** for each conflict and explicitly keep
   the current or imported choice. Outcome, rationale, proposed receipt ID,
   timestamp and evidence travel together; fields from different choices are
   never spliced. No side is selected by default. Only “Merge resolved draft”
   changes current choices, atomically, after every conflict is resolved. A
   proposed receipt ID repeated across merged choices or historical receipts
   blocks the merge; choose differently or cancel and edit before retrying.
   Cancel preserves the current work and its preview. Edits, clear-choice,
   replacement/merge selections and cancel invalidate stale reads and staged
   resolutions. Merging clears the previous preview and marks the result
   unsaved. Save the merged draft before closing, then preview and export.
   Unfinished choice text is preserved as one object and can be saved; it
   cannot pass preview/export until completed or cleared. This is a two-draft
   merge relative to a blank form, not a deletion or receipt-supersession
   protocol and not a merge across reviewers or review revisions.
8. Consume the exported form with the existing native command:

```sh
"$DECIDER" preview /downloaded/form.json \
  examples/review-agenda/review.json examples/review-agenda/source.md
```

Native preview remains the semantic authority and may reject a stale input or
an unsupported choice. It prints **UNVERIFIED DECISION SUBMISSION — not a review
receipt**. The HTML page and exported form cannot authenticate, apply, journal,
deliver or establish knowledge acceptance. A host must still perform the
separate authenticated workflow below. Existing receipts are displayed only as
historical bundle data; their IDs cannot be reused for newly entered choices.

### Bounds, safety and recovery

- Each producer input and reopened/merged/saved draft is limited to 2 MiB. The page
  supports up to 200 outstanding choices and 2,000 discussion entries. Source
  display supports complete UTF-8 text without NUL/other unsupported controls;
  binary artifact display is refused rather than replaced by a partial view.
- The editor accepts real calendar UTC timestamps in
  `YYYY-MM-DDTHH:mm:ssZ` form, and slash-separated relative evidence paths
  without empty/dot segments, drive/URL colons, backslashes or controls. This
  intentionally narrows the native validator's permissive formatting checks.
  Evidence references are neither opened nor checked for existence.
- All imported text is escaped/read-only. The page uses a hash-bound inline
  script/style CSP, no remote resources, no fetch, no local storage and no
  automatic saving. It contains the complete source and review; keep the HTML
  and downloaded drafts private. Do not treat HTML as a security boundary
  against someone deliberately editing its script or developer-console state;
  the unchanged native consumer independently validates the form.
- Download requests cannot prove a file was saved. Verify it exists and reopen
  it before closing if recovery matters. A best-effort unsaved-change warning
  may be suppressed by the browser. No reload or Back/Forward recovery is
  promised without a saved draft.
- Producer/controller and actual native-consumer tests cover interruptions,
  repeated clicks, failed downloads/reads, stale imports, partial choices,
  whole-choice merge conflicts, duplicate merged receipt IDs, disjoint native
  preview, cancel/late-read races across both import paths,
  malformed/duplicate JSON, invalid UTF-8 file bytes (fatal decoding, no silent
  replacement), hostile text and all three outcomes. The small
  DOM controller harness does not qualify browser layout, file-download/CSP
  enforcement, keyboard/screen-reader use or a real authenticated human journey.

Focused source tests require `MOONCHAT_REVIEW_DECIDER` pointing to a trusted
native executable and Python 3 plus Node.js. Run the Python test module in
`tools/review_decisions/`; the emitted-controller test accepts an actual generated
HTML path, the native executable, bundle path, source path and an existing
output directory. The bounded batch runner verifies the retained runtime and
source/dependency closure before and after those tests without rebuilding.

## Host integration and authority

1. Use `prepare_review_decisions` with exact retained bundle and source bytes.
2. Show that source revision and all discussion in the producing host. Obtain
   explicit choices and confirmation from the named human.
3. Parse a received form with `parse_review_decisions`; optionally call
   `preview_review_decisions` for a non-authoritative confirmation summary.
4. Authenticate the reviewer in the host. Call
   `apply_verified_review_decisions` with `verified_reviewer_participant_id`
   derived from trusted host session state, **never copied from the form**.
5. Retain the old bundle and newly serialized result. Feed the result into the
   existing journal and `project_review_record` only under that host's authority.
   Return and verify delivery using the host's own producing-record attachment.

The verified-identity argument is a trust boundary, not authentication supplied
by this library. An integrator bypassing host authentication could fabricate
receipts with this API just as with the existing public bundle constructors.
Do not expose this call directly as an unauthenticated endpoint.

Exact bundle bytes guard concurrent edits (including reserialization), while
observed source bytes guard replaced artifacts. Discussion, prompts, decision
ownership and reviewer names cannot be altered through the form. Application
validates the whole result atomically; failed input returns no changed bundle.
Other reviewers' receipts are preserved. Reapplying against the same input gives
the same result; applying an old form against an updated bundle fails, requiring
reopening. Storage idempotency, journal persistence and delivery retries remain
host-owned.

An existing receipt is never overwritten, including reject/defer receipts. To
change a recorded position, use the existing linked review-revision workflow and
review the new scope explicitly. Earlier bundles remain historical evidence.
This feature does not implement a receipt supersession protocol.

## Evidence and limits

Run `scripts/verify-decision-form.sh` from any directory. It uses the pinned
process environment, frozen local dependencies, external target directory and
shared native build lock. Set `MOON_ENVIRONMENT`, `WORKER_ROOT`, and
`DECISION_TARGET_DIR` for another prepared workspace. Exact required dependencies
are async 0.20.2, x 0.4.50 and moonlib 0.1.19; the script never installs them.

Black-box MoonBit tests exercise agenda → form → host application → portable
readback → existing record/journal projection for all three outcomes, partial
review, retained dissent, stale input, ownership, invalid choices and non-aliasing.
The CLI fixture invokes the actual native executable. Fixture identities are not
live authenticated humans. The offline editor above adds a bounded consuming choice-entry surface. Real
browser/keyboard accessibility, authenticated host application, actual receipt
delivery, MoonBook intake and ordinary-user L2 readiness remain unqualified.
