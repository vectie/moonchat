# Local mailbox review selection workbench

Start from an existing editable agenda, a local Unix MBOX snapshot, and an
explicit absolute path to a trusted existing `review_compose` executable:

```
python3 -B scripts/review_mbox_workbench.py agenda.json snapshot.mbox \
  --composer /absolute/path/to/review_compose.exe \
  --native-lock /absolute/path/to/shared/native-build.lock
```

Open the printed `http://127.0.0.1:PORT/SESSION/` URL in your local browser.
The server binds only IPv4 loopback; optional `--port` chooses a port instead
of the default ephemeral port. Keep the session URL private. Stop with Ctrl-C.
There are no dependencies beyond Python's standard library and the existing
native composer (plus POSIX `fcntl` for shared locking). No live account,
provider, credential, remote write or HTML mail interpretation is involved.

## Curate without writing selection JSON

1. Read the snapshot digest, existing participants and preserved agenda items.
   Expand catalog MIME parts to inspect plain text and supplied headers.
2. Click **Add message body** for the exact message ordinal and MIME part.
   To inspect existing text/plain attachments first click **Inspect supported
   text/plain attachments**, then use **Add attachment** on an exact part.
   Attachment inspection does not select any evidence. Other attachment
   formats, attached containers and HTML remain opaque.
3. Enter a unique item key, review kind, existing curator author and explicit
   curator note. Add decision requests, choosing a named existing human and
   writing the pending decision prompt. Remove any unwanted request or item.
   Up/Down changes the selected items' export order; original agenda items
   remain first and unchanged.
4. Click **Preview pending review**. Existing mailbox import validation builds
   the candidate; the native composer validates and produces both the readable
   preview and the pending bundle under the shared native lock.
5. Download the exact successful native bundle using the displayed link.
   Errors hide the link and revoke the prior server-side result. Editing an
   item hides the link until preview succeeds again. Late responses from a
   preview begun before an edit cannot re-enable the download link.

## Save and reopen unfinished work

Click **Save unfinished draft**, then **Download unfinished draft file**.
The second click is what saves the file through your browser. No automatic
disk storage or autosave is performed. You can save empty selections and
incomplete keys, curator names, notes, reviewer choices and pending prompts;
draft saving does not run the native composer or turn incomplete work into a
valid review. Item order, questions/objections/proposals and named requests are
preserved exactly, including whitespace and Unicode. Keep the downloaded JSON
private: it contains your curator edits and participant identifiers.

Restart the workbench with the same agenda and mailbox snapshots. Choose the
file under **Saved draft file**, then click **Open saved draft**. Its cards
replace the current selected cards only after the entire draft validates.
Existing agenda items and participants remain untouched. Failed imports keep
your current edits and show the error; you can choose a compatible file and
retry. Editing while an open request is in flight keeps those newer edits.
Opening or preparing a draft revokes the prior server-side preview/bundle and
draft download; the browser clears its old links even on a failed reopen.
Changes made to cards also hide their prior download links until preparation
or preview succeeds again. A late response cannot restore an obsolete link.

The file uses the distinct `moonchat.mailbox-review-draft.v1` format. It carries
only the agenda digest, mailbox digest and ordered selection edits/locators.
It is not a portable review bundle, approval, journal or decision receipt.
It contains no decoded mailbox evidence, preview links, server tokens, or
attachment-inspection consent. In a fresh session, saved attachment cards
remain editable but their text stays opaque until you explicitly click
**Inspect supported text/plain attachments** again. Preview refuses those
attachment selections until inspection succeeds; it still requires complete
valid review fields and produces pending decisions without receipts.

The mailbox digest binds its exact bytes. The agenda digest binds every field
using UTF-8 JSON with sorted object keys, compact separators and preserved
array order. JSON whitespace or object key order alone can differ, but changed
participants, items, source identifiers or any other agenda value cannot reuse
a saved draft. Both digests must match before any cards are replaced. Unsupported
versions, extra fields, duplicate JSON keys, unknown participants, non-human
reviewers, invalid MIME locators and embedded decision/approval fields are
refused. Empty names are retained as unfinished choices. These digests bind
snapshots; they do not authenticate the curator or make a draft trusted.

All mail and preview content is displayed as text, including HTML-looking
strings. Supplied sender names and quoted approval words never identify a
reviewer or record approval. Exported decisions remain pending with no decision
receipts. A receiving product must independently decide what to import and
accept; this workbench does not implement or qualify that receiving integration.

## Snapshot and compatibility boundaries

The agenda and MBOX bytes are read once at launch, copied into session memory,
and never overwritten. Later changes to the files do not change this session:
restart to review new snapshots. Selection requests carry the launch mailbox
digest; any differing digest is refused. Existing source digest constraints
remain enforced by import and native composition. Downloaded drafts can be
reopened between launches; the original agenda/participants are never edited.

The implementation reuses `review_mbox.parse_mailbox`, `import_messages` and
`compile_candidate`. Body items use explicit plain-text v2 selections;
attachment items use explicit v4 selections, combined in curator order. An
exact message/part cannot be selected twice. Multiple distinct MIME bodies or
attachments can be separate items, each with its own key, meaning and requests.

Existing limits remain: 4 MiB input, 500 messages, 2,000 MIME nodes, depth 16,
8 MiB decoded/imported evidence. This workbench also bounds a preview request
to 1 MiB, total candidate JSON to 8 MiB, and selections to 1–100. Invalid,
unsupported, oversized or native-rejected candidates yield no downloadable
result. Draft requests and serialized draft downloads are bounded to 1 MiB,
0–100 selected items and at most 100 pending requests per item. Size-boundary
tests use memory, not large persisted fixtures. The native executable is trusted code supplied by the operator; the
workbench does not install, build or authenticate arbitrary executables.

## Validation

Set `MOONCHAT_REVIEW_COMPOSER` to an independently verified native executable
and `MOONCHAT_NATIVE_LOCK` to the shared absolute lock path, then run:

```
cd scripts
python3 -B -m unittest -v test_review_mbox_workbench
```

These tests use real loopback HTTP and native composition. The production JS
controller is exercised using a minimal DOM test double and real HTTP, not a
browser engine. Tests download a draft to a small file, start a fresh server,
reopen incomplete mixed evidence, finish edits and verify the exact native
pending bundle. Separate controller instances exercise the file-picker flow,
failed/racing reopens and renewed attachment inspection. Node is required only
for that test. Browser visual layout, actual browser/OS file dialogs,
real-browser accessibility, installed lifecycle, cross-product acceptance and
full release gates remain unrun. No MoonBit source/interface changes are made.
