# Refresh imported GitHub discussion after follow-up replies

Use `review_github refresh-*` when you have edited an imported agenda and a
later local GitHub review-comment export contains follow-up replies or changed
comments. It reconstructs the original imported items from the retained import
plan and snapshot, then merges their newer versions with the current agenda.
Independent local edits survive; overlapping changes are shown for inspection.
No network, GitHub account or model provider is used.

## Try the synthetic journey

Build `cmd/review_github` for native, then from the module root:

```sh
E=examples/review-github-refresh
review_github refresh-report "$E/current-agenda.json" "$E/source.md" "$E/old-comments.json" "$E/old-plan.json" "$E/new-comments.json" "$E/new-plan.json" > refresh-report.json
review_github refresh-preview "$E/current-agenda.json" "$E/source.md" "$E/old-comments.json" "$E/old-plan.json" "$E/new-comments.json" "$E/new-plan.json" > refresh-preview.md
review_github refresh-agenda "$E/current-agenda.json" "$E/source.md" "$E/old-comments.json" "$E/old-plan.json" "$E/new-comments.json" "$E/new-plan.json" > refreshed-agenda.json
review_github refresh-bundle "$E/current-agenda.json" "$E/source.md" "$E/old-comments.json" "$E/old-plan.json" "$E/new-comments.json" "$E/new-plan.json" > refreshed-review.json
```

The example carries a new reply and amended fallback concern into the existing
objection, retaining an independently edited decision prompt, proposal and item
order. Every existing reply stays visible, including an apparent approval in
ordinary comment text. The exported bundle remains pending with zero receipts.
`review_packet refreshed-review.json "$E/source.md" > packet.html` produces the
existing complete offline reading packet. Checked-in outputs are actual CLI
results; all people, comments and review content are synthetic.

Commands read explicit local files and write stdout only. Always redirect to a
fresh path, never an input file: the shell truncates output before reading begins.
`refresh-report` returns 0 for a valid comparison even when conflicts exist;
inspect `conflicts` and nullable `merged_agenda`. Other refresh modes refuse a
conflict with exit 1, stderr diagnostics and no stdout. Invalid inputs also exit
1 with no result. References in imported content are inert, never fetched.

## Retain and update the recipe

1. Keep the exact original comment export and the import plan used to create the
   agenda. The plan must be the actual original recipe; MoonChat cannot infer
   one from a manually rewritten body or authenticate its historical use.
2. Save the later flat REST comment array separately. Use the existing `catalog`
   command to get its exact digest. Its `pull_request_url` must match the old
   snapshot. Every previously selected comment must still be present in its
   original root thread. Missing comments are rejected because an incomplete
   export cannot establish deletion or resolution of dissent.
3. Copy the old import plan. Update only `export_ref` and `export_digest`, and
   add explicit login-to-participant mappings for new reply authors if needed.
   Keep old mappings and the complete `threads` selections unchanged. Edit
   kind, operator wording and decision requests in the current agenda instead.
   A changed snapshot needs a distinct retained reference. Add new participants
   to the current agenda before mapping them. They must pass ordinary validation.
4. Supply the current edited agenda and the actual source bytes under review.
   This is a pending authoring workflow, so the digest is calculated from those
   bytes, as for the composer. It does not infer a source revision from GitHub
   commits or validate a historic local source that was not supplied. For a
   changed reviewed artifact, use the existing explicit revision/supersession
   workflow and retain both sources and reviews.
5. Inspect the report, export the merged agenda, and keep it alongside the
   refreshed bundle, old/new plans, old/new snapshots and exact source. For a
   later refresh, the last new plan/snapshot become the old pair. Repeating the
   same refresh against its result coalesces changes without duplicate replies.

This workflow refreshes the selected threads only. New unselected roots do not
become agenda items automatically. Their comments need no participant mapping.
Import additional roots explicitly with the existing importer and a separate
plan. Export completeness against live GitHub remains unknown. A comment's
`updated_at` is retained data, not proof that one file was captured later.

## Merge and conflict behavior

Stable item keys link imported discussion to local edits. The base is regenerated
from the old plan/snapshot, the left branch is the current agenda, and the right
branch is regenerated from the new plan/snapshot. Other local items and current
scope/participant metadata pass through unchanged.

- Kind, author and body merge independently. Decision prompts merge per named
  reviewer. A local prompt change can therefore coexist with new remote replies.
- Body text and evidence-reference arrays are atomic. No textual or semantic
  merging is attempted. Snapshot reference/digest text is part of an imported
  body, so a provenance-only change can still conflict with a local body edit.
- A local item deletion survives an unchanged imported item; deletion versus
  an updated imported item conflicts. Removing earlier selected comments from
  the new export is an input error, never an automatic agenda deletion.
- Local item order is retained. Original thread selections cannot be reordered
  or rekeyed in the new plan. Local new items remain intact.
- Every conflicting field reports its item key and full `base`, `left`, `right`
  values. No partial agenda is returned. `added_comment_ids` and
  `changed_comment_ids` refer only to selected threads, in deterministic thread
  order. Changes cover parsed body, author and retained context metadata;
  ignored GitHub API fields are not reported as comment changes.

For a conflict, inspect all three values. In a copy of the current agenda, choose
exactly the base or right value for conflicting fields and retry to accept the
refreshed version; make any additional combined wording edit to the resulting
agenda afterwards. Alternatively keep your local agenda unchanged and do not
refresh it. `conflicting-agenda.json` and `conflict-report.json` demonstrate a
local body edit that cannot be silently overwritten.

The common three-way item merge is shared with spreadsheet reconciliation.
There is no new receipt, journal, decision, approval, receiver-acceptance or wire
bundle contract. A quoted approval is discussion only. For an already received
or decided review, retain its bundle/receipts and use revision compilation for
the next pending version rather than treating `refresh-bundle` as supersession.

## API and scope

`refresh_github_review_comments(current, previous_plan, previous_export,
next_plan, next_export, source_bytes)` returns `GitHubReviewRefresh` with source
and snapshot bindings, comment changes, conflicts and an optional merged agenda.
Inputs are fully validated and not mutated; returned mutable arrays are detached.
The report uses `ReviewSheetConflict`'s existing field shape. The importer's
1 MiB/1000-comment and 100-selected-thread limits still apply to each snapshot.
Files and outputs are held in memory. Native focused tests and CLI examples do
not qualify a browser, named human host, receipt return or live integration.
