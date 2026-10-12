# Bring GitHub review threads into an editable agenda

`review_github` imports selected pull-request review-comment threads from a
local GitHub REST JSON export. It keeps replies together, carries the original
file/diff/commit locations and comment links, and appends ordinary editable
MoonChat questions, objections or proposals. This avoids retyping code-review
feedback or selecting individual lines from a flattened transcript.

## Try the synthetic workflow

With a native `cmd/review_github` executable on PATH, run from the module root:

```sh
review_github catalog examples/review-github/comments.json > catalog.txt
review_github preview examples/review-github/agenda.json examples/review-github/source.md examples/review-github/comments.json examples/review-github/import-plan.json > preview.md
review_github agenda examples/review-github/agenda.json examples/review-github/source.md examples/review-github/comments.json examples/review-github/import-plan.json > imported-agenda.json
review_github bundle examples/review-github/agenda.json examples/review-github/source.md examples/review-github/comments.json examples/review-github/import-plan.json > review.json
```

The supplied fixture deliberately places a reply before its parent, includes
Unicode and multiline comments, and contains one unselected thread. The output
adds a fallback objection with its two replies and a reporting question. The
original proposal remains first. The imported bundle is pending with no receipts,
even though a quoted comment says “I approve”. Checked-in catalog, agenda,
preview and bundle files are actual command outputs from this fixture.

All commands read local files and write stdout only. Redirect to a new path,
never an input: the shell truncates its destination before MoonChat reads it.
Errors exit 1 with diagnostics on stderr and no result on stdout. Imported agenda
JSON can be edited with the existing [agenda](REVIEW_AGENDA.md) or
[spreadsheet](REVIEW_SHEETS.md) workflow. For later revisions, compile the edited
agenda using the composer's existing predecessor arguments.

## Prepare an import plan

1. Retain a flat JSON array returned by GitHub's [list pull-request review
   comments REST endpoint](https://docs.github.com/en/rest/pulls/comments#list-review-comments-on-a-pull-request).
   Use the raw/default representation containing `body`. Gather all desired
   pages into one flat array, preserving JSON numeric IDs exactly. Do not use a
   floating-point conversion that rounds large IDs. An ordinary PR's issue
   comments, review summaries and GraphQL review threads are different formats.
2. Run `catalog` to see the snapshot SHA-256, root IDs, thread sizes, logins and
   bodies. It does not contact GitHub or prove that every remote comment was
   exported. A missing parent, duplicate ID or reply cycle is an error.
3. Copy `import-plan.json`. Set `export_ref` to the workspace-relative location
   where the exact export is retained and `export_digest` to the catalog digest.
   The file path passed to the CLI is the file read now; it does not rewrite the
   portable reference. Reformatting the JSON changes the digest.
4. Map each selected comment's exact `user.login` to an existing MoonChat
   `participant_id` in `authors`. This includes every reply's author. Mappings
   are explicit attribution, not identity authentication, participant creation
   or an import of GitHub permissions. Unselected authors need no mapping.
5. Choose root IDs as decimal strings in `threads`, in the order you want agenda
   items appended. Give each a unique stable `key`, a `kind` of `question`,
   `objection` or `proposal`, an operator `note`, and explicit `decisions`.
   Every objection needs a named human decision request. Questions and proposals
   can use `[]`; the complete agenda still needs a decision overall.
6. Preview, then export an editable agenda or portable bundle. Keep the original
   GitHub export and reviewed source alongside it.

The root comment's mapped participant becomes the agenda item author. Each
comment retains its own mapped attribution inside the thread body. The root is
first; replies follow by `created_at`, with exact numeric ID order breaking
same-timestamp ties. Input array order does not affect reply order. Nested parent
references resolve to their root; this ordering is chronological rather than a
nested tree display. Every comment in a selected thread is imported, including
outdated or disagreeing comments. This export does not declare resolution state.

A thread body includes the operator note, snapshot reference/digest, root ID,
per-comment metadata and original comment text. Metadata is JSON-escaped;
comment bodies retain exact decoded Unicode, whitespace and line endings.
Generated MoonChat entry/turn identities use the chosen stable item key. GitHub
IDs are retained as external provenance, not substituted for MoonLib identities.
Repeat an import against the original agenda to regenerate it. Importing into
an already-imported agenda fails on key collisions; this is not a synchronizer
or an automatic merge of edited GitHub comments. For subsequent local snapshots,
use the explicit [refresh workflow](REVIEW_GITHUB_REFRESH.md) to preserve
independent agenda edits and inspect conflicting changes.

## Supported input and limits

- UTF-8, optional BOM, at most 1 MiB and 1–1000 comment objects from one
  `pull_request_url`. All comments are parsed, including unselected threads.
  Export completeness is unknown: a snapshot can omit a root and all its replies
  without a detectable dangling reference.
- Required: numeric positive integral `id`; `user.login`; nonempty `body`,
  `path`, `commit_id`, `original_commit_id`, `html_url`, `pull_request_url`,
  `created_at`, `updated_at`; and string `diff_hunk`, which may be empty for a
  file comment. Times use `YYYY-MM-DDTHH:MM:SSZ` with decimal digits. This is
  format checking, not independent validation of the timestamp's truth.
- Optional/null `in_reply_to_id` supplies the parent. Optional/null `line`,
  `original_line`, `start_line`, `original_start_line`, `position`,
  `original_position` and `pull_request_review_id` are preserved as positive
  integral numbers. Optional/null `side`, `start_side` and `subject_type` are
  preserved as strings. Outdated comments with null positions are supported.
- IDs and numeric location fields support up to 20 decimal digits. Large IDs
  are retained from exact JSON number tokens without conversion to floating
  point. Small integral JSON number forms may normalize to decimal integers.
- Other API fields are ignored, including user profile metadata, permissions,
  association and links not listed above. A deleted/null user cannot be mapped
  and is unsupported. No comment, source path, URL, commit or diff is fetched,
  executed or checked against the local repository.
- Plans select 1–100 unique exported roots. Missing mappings, duplicate mappings,
  missing parents, cycles, changed export digests, invalid agenda keys/types or
  decision requests produce no partial import. The result has detached mutable
  arrays; inputs are not modified. Inputs and outputs are held in memory.

The artifact under review is the separately supplied source file. Its actual
bytes determine the existing bundle digest; GitHub commit identifiers and line
locations are provenance text, not proof that this local source is that commit.
The import uses the existing agenda composer and v1 bundle contract. It creates
no decisions or receipts, sends nothing to GitHub, and does not qualify a hosted
review/receipt journey or a receiver's independent acceptance.

Pure embedding APIs: `catalog_github_review_comments`,
`parse_github_review_import_plan`, and `import_github_review_comments`.
