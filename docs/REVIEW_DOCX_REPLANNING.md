# Carry review questions onto a revised Word document

A curator who has already chosen Word comments and named decision requests should
not have to reconstruct those choices whenever the document changes. The existing
DOCX intake CLI can now draft an explicit transition from the old selection plan,
then export a normal new selection plan after the curator checks every prior item.
Stable item keys, discussion kinds, curator notes, authors and proposed decision
requests survive. Evidence is read anew from the later DOCX when that plan is
used by the existing importer or planning packet.

This is **editorial preparation only**. A request asking someone to decide is not
an actual decision. Re-planning never transfers approvals, decisions or receipts,
creates a bundle, authenticates people, or declares removed comments resolved.
Native MoonChat still validates the final agenda and creates any pending bundle.

## Run the retained example

From the repository root with Python 3.10+, without installed packages:

```sh
python -B tools/review_docx/review_docx.py replan-draft examples/review-docx-replan/agenda.json examples/review-docx-comparison/before.docx examples/review-docx-comparison/after.docx examples/review-docx/selections.json > transition-draft.json
```

Open the [revision comparison](REVIEW_DOCX_COMPARISONS.md) to read both sources and
old dissent before making choices. Edit a copy of `transition-draft.json`. Every
prior selected item starts with `action: "review"`, including unchanged comments
and identical archives. That value deliberately cannot be applied. For each row:

- `keep`: keep the same Word `comment_id`, after checking its current content and
  source scope. A changed passage or comment can be kept only by this explicit
  editorial choice; its earlier request is still merely proposed.
- `remap`: set a different current Word `comment_id` after inspecting it yourself.
  This supports Word IDs that have been renumbered. Matching text or matching IDs
  does not prove continuity; the tool never chooses a replacement automatically.
- `drop`: set `comment_id` to JSON `null`. This excludes the item from the new
  selection plan. It does not resolve the earlier objection or erase either
  original DOCX. Retain the old plan and comparison for the omitted concern.
- For all three actions, enter a nonempty `reason`. This records your editorial
  rationale in the retained transition recipe, not an authenticated human receipt.

The checked-in `examples/review-docx-replan/choices.json` is a completed synthetic
example. It keeps the changed rollback question, explicitly remaps support from
Word ID `2` to `23`, and drops the automated comment from the proposed agenda.
The automated comment remains visible in the later source-reading packet.

```sh
python -B tools/review_docx/review_docx.py replan examples/review-docx-replan/agenda.json examples/review-docx-comparison/before.docx examples/review-docx-comparison/after.docx examples/review-docx/selections.json examples/review-docx-replan/choices.json > new-selections.json
python -B tools/review_docx/review_docx.py plan-packet examples/review-docx-replan/agenda.json examples/review-docx-comparison/after.docx new-selections.json > new-planning.html
```

The retained `draft.json`, `selections.json` and `planning.html` are actual CLI
outputs. Open the new planning page and inspect the named requests beside the
later passages. The same resulting plan works with the existing `agenda`,
`preview` and `bundle` modes when you explicitly supply a trusted native composer:

```sh
python -B tools/review_docx/review_docx.py bundle examples/review-docx-replan/agenda.json examples/review-docx-comparison/after.docx new-selections.json --composer "$COMPOSER" > pending-review.json
```

This last native step was not run for this delivery. Follow the existing
[agenda revision and predecessor workflow](REVIEW_AGENDA.md) when revising a
retained bundle. A successful re-plan is not native review validation and does
not establish the predecessor relationship or complete the host decision journey.

## Prepare the agenda and make additional edits

Supply the **pre-import agenda for the later review scope**, not an agenda already
containing items imported from the old plan. Set its intended source reference,
revision and time yourself before generating the draft. Re-planning does not infer
those values or rewrite existing agenda bodies/references. Existing items remain
your responsibility; check that they still describe the new source. Keep the
participants required by the old plan while transitioning its requests.

The draft binds the exact agenda bytes, original plan bytes and both DOCX archives
with SHA-256. Any changed input, including JSON reformatting, requires a fresh
draft. Hashes identify snapshots; they do not authenticate the editor. Preserve
these inputs and the completed recipe with the generated plan. The output is the
existing `moonchat.docx-review.v1` format; transition reasons and comparison fields
stay in the recipe and are not inserted into source evidence as reviewer claims.

- Edit only `action`, `comment_id` and `reason` in existing selection rows. Preserve
  their keys, old IDs, status and change summary. Those fields are rechecked against
  the actual inputs at apply time. Each old key must occur exactly once.
- Reorder rows if you want a different discussion order. Kept/remapped rows appear
  in that order; additions follow in their supplied order. Dropped rows disappear
  only from the new selection plan.
- Use `additions` for ordinary selection objects documented in
  [DOCX comment intake](REVIEW_DOCX_COMMENTS.md): comment ID, new stable key, kind,
  author, curator note and proposed decisions. You can select any current comment
  not already selected, including a previously unselected old ID.
  `new_comment_ids` is informational; it lists IDs absent from the earlier DOCX.
- Every new key must differ from all previous keys, even dropped ones. A current
  comment can be selected only once. New authors must already be in the agenda;
  requested decision owners must be named humans. No Word author is automatically
  granted review authority.
- To revise retained notes/prompts after the transition, edit `new-selections.json`
  and regenerate its planning packet. The transition recipe describes the exact
  initial carry-forward output, not subsequent manual edits.
- At least one and at most 100 selections must remain, matching the importer.
  Dropping everything does not produce an empty, apparently completed review.
  Retain the disposition recipe and start another agenda if no discussion remains.

## Limits and verification

Both files must satisfy the [existing classic-DOCX subset](REVIEW_DOCX_COMMENTS.md):
1–1,000 comments each, no tracked changes or modern threaded/resolved-comment
metadata, 16 MiB compressed archive, 4 MiB per parsed part, and 1,048,576 logical
source characters. A later document with zero comments is currently unsupported;
its absence of comments must not be treated as resolution. This tool cannot
convert Word documents or refresh an already imported/edited agenda.

Each JSON input and each re-plan output is limited to 4 MiB. Complete selected
passages are used for the import-candidate checks, with the existing 16 MiB
imported-evidence bound. Comparison identifies changes in complete passage hashes,
including edits beyond the displayed quote preview. No file is extracted,
rewritten or fetched. All inputs are read locally; output is written only to stdout
after successful checks. Failure exits 1 with stderr and empty stdout. Redirect to
**new paths only** because the shell truncates its destination before reading inputs.

```sh
PYTHONDONTWRITEBYTECODE=1 python -B -m unittest discover -s tools/review_docx -p 'test_*.py' -v
```

77 focused Python tests pass, including 12 new re-planning checks: actual CLI
creation, explicit changed/removed/unchanged dispositions, remapping, additions,
ordering, snapshot changes, complete long-passage import, native-importer candidate
construction, source packet continuation, deterministic retained examples and input
preservation. The candidate function is real Python intake code; no native composer
is invoked or mocked. Native MoonBit compilation/execution, browser or Word
rendering, accessibility devices, human decisions, host receipt delivery and
receiving-product acceptance remain unqualified. No dependency installation,
network, browser or Moon command was used. R50 remains last fully verified
cumulative; R51–55 remain separate.
