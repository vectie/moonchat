# Literal local mailbox discovery

Run `python3 -B scripts/review_mbox.py search examples/review-mbox/thread.mbox rollback --field body --limit 1`.
Subject search is the default; `--field header --header X-Project` searches a named top-level header, including repeated and custom headers. `--field body` searches decoded inline plain-text MIME parts. Queries are case-sensitive literal Unicode text, never regex. Attachments and nested email text remain opaque in these searches. `--field body --body-mode html-text` separately opts into bounded static HTML text as described in [MAIL_HTML_TEXT.md](MAIL_HTML_TEXT.md). MIME decoding and mailbox refusal rules match catalog intake.

Each matching header or part produces one result for its first match. Results carry exact mailbox and envelope-inclusive message SHA-256 digests, ordinal, original half-open message byte span and MIME locator. Header index counts all retained top-level headers; header locators are `1`. Character positions and excerpts refer to decoded Unicode text, not raw byte offsets. Repeated Message-ID values never merge messages.

Pages default to 20 and allow 1–100 hits, with excerpts capped at 336 characters. Continue with `--offset NEXT --mailbox-digest DIGEST` using the previous page's digest; a changed snapshot fails closed. The same query, field and header must be retained. No total hit count is an approval or import. Select discovered ordinals explicitly in the existing digest-bound `moonchat.mbox-review.v1` selection file and use agenda/preview/bundle with a trusted composer.

Input remains at most 4 MiB / 500 messages with existing MIME depth, part and decoded-text limits. Search validates the complete mailbox before emitting anything, including malformed later messages. It is a local discovery utility, not an index, sender verification, threading inference, hosted review UI or provider integration.

## Discover attachment passages, then explicitly select them

```sh
python3 -B scripts/review_mbox.py search original.mbox 'rollback owner' --field attachment --limit 20
```

`--field attachment` is the explicit opt-in to the existing
[plain-text attachment profile](MAIL_ATTACHMENT_TEXT.md). It decodes accessible
`text/plain` leaves with `Content-Disposition: attachment`; it never searches
inline bodies, PDFs, HTML attachments, nested messages or descendants of attached
containers. Filenames, including duplicate filenames, are metadata and never
paths or identifiers. Supported charsets and transfer encodings and all existing
catalog bounds remain unchanged. A malformed supported attachment anywhere in
the snapshot fails the search with no partial stdout, even beyond the requested
page. This mode cannot be combined with HTML body mode or a header name.

The `moonchat.mbox-search.v3` result retains exact mailbox and message digests,
message ordinal, envelope-inclusive byte span, MIME locator, decoded-content
digest and size, filename, charset, transfer encoding, and attachment
interpretation. Its `attachment` object supplies the existing selection locator:
`{"part":"1.2","mode":"plain-text-attachment"}`. One hit is returned per
matching attachment, for its first literal match. Excerpt and match positions
are decoded Unicode character positions; neither is a raw attachment byte
offset. Discovery returns bounded excerpts, while a selected review item quotes
the entire chosen decoded attachment with its exact source context.

Continue with the same query and `--field attachment --offset NEXT
--mailbox-digest DIGEST`; use the previous page's digest to reject source drift.
Search writes only discovery JSON to stdout. It creates no selection, agenda,
review item, decision or approval, and never executes text or follows links.

To review chosen matches, explicitly create a `moonchat.mbox-review.v4` plan
using the result's `mailbox_digest`. For each chosen hit, copy its `ordinal` and
`attachment` object, then supply a distinct key, review kind, curator, note and
named decisions as shown in [MAIL_ATTACHMENT_TEXT.md](MAIL_ATTACHMENT_TEXT.md).
Select only the hits you intend to review. Two attachments with the same
filename are distinguished by their message ordinal and MIME part, never by
filename. Multiple selected parts from one message become independent items in
plan order. V4 does not accept the search result itself as a plan.

```sh
python3 -B scripts/review_mbox.py agenda agenda.json original.mbox selection.json --composer /absolute/path/to/review_compose.exe
python3 -B scripts/review_mbox.py preview agenda.json original.mbox selection.json --composer /absolute/path/to/review_compose.exe
python3 -B scripts/review_mbox.py bundle agenda.json original.mbox selection.json --composer /absolute/path/to/review_compose.exe
```

Every composition uses the native composer, preserves the original digest
constraint and keeps named decisions pending. Quoted approval words confer no
authority. Changed source bytes require new discovery and deliberate selection;
neither search nor export establishes receiving-product acceptance.
