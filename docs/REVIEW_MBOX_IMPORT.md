# Review selected messages from a local mailbox

Turn explicit messages from a local Unix mbox export into ordinary pending
MoonChat review items. This is useful for retaining a proposal, a quoted objection
and a follow-up question without copying an entire mailbox into each item.
For explicit HTML-only or alternative-body selection, see
[static HTML text intake](MAIL_HTML_TEXT.md); the v1 workflow below remains plain-only.
The original mailbox is the reviewed artifact; the full byte digest and stable
message ordinal identify every selected message within that exact snapshot.

Use Python 3.9+ and an existing trusted native `review_compose` executable. No
package, mailbox account, server or provider is required. From this repository:

```sh
python3 -B scripts/review_mbox.py catalog examples/review-mbox/thread.mbox
python3 -B scripts/review_mbox.py preview examples/review-mbox/agenda.json examples/review-mbox/thread.mbox examples/review-mbox/selections.json --composer /absolute/path/to/review_compose
python3 -B scripts/review_mbox.py agenda examples/review-mbox/agenda.json examples/review-mbox/thread.mbox examples/review-mbox/selections.json --composer /absolute/path/to/review_compose > imported-agenda.json
python3 -B scripts/review_mbox.py bundle examples/review-mbox/agenda.json examples/review-mbox/thread.mbox examples/review-mbox/selections.json --composer /absolute/path/to/review_compose > pending-review.json
```

Check exit status and redirect only to new files. Shell redirection can truncate
an input before the command reads it. Catalog reads locally and writes JSON to
stdout. Agenda, preview and bundle all validate the complete candidate through
the existing native composer before emitting stdout. Failure emits no partial
review. The importer never rewrites any input; native consumption uses private
temporary copies of the exact snapshots already read.

## Choose messages and name the questions

1. Inspect the catalog's mailbox digest, message ordinals, envelope, selected
   headers and decoded inline text. Message-ID and threading headers are supplied
   metadata only. Duplicated or missing Message-IDs are allowed and never used as
   identity or to infer conversation order. The exporter order is retained.
2. Copy the example selection format `moonchat.mbox-review.v1`. Set
   `mailbox_digest` to the exact catalog digest. Select 1–100 distinct one-based
   ordinals in your desired review-item order.
3. Each selection supplies `ordinal`, stable unique `key`, `kind`, existing
   participant `author`, your own nonempty `note`, and explicit `decisions`.
   Kinds are question, objection or proposal. Each objection requires at least
   one request naming an existing human participant and a nonempty prompt.
4. Set the original agenda's portable `source_artifact_ref` to the place where
   this complete mailbox will be retained, and give it an explicit revision
   label. The local filename does not rewrite the portable reference.
5. Preview, then emit the ordinary agenda or bundle. Existing agenda entries and
   participants remain intact. Selections append in plan order. Continue using
   the ordinary [agenda composer](REVIEW_AGENDA.md), including its later linked
   revision workflow when needed. A repeated import into an already-imported
   agenda fails on duplicate item keys rather than duplicating discussion.

The sample selects a recorded objection before its earlier proposal. Two sample
messages deliberately share one Message-ID, and a third has none. The first
contains “I approve everything” as a quoted claim. Its imported review remains
pending: no sender, envelope, display name, timestamp or message content proves
reviewer identity, approval, authority or downstream acceptance. The user names
the curator and human decision owners; they are never inferred from email.

## Exact evidence and supported subset

Each selected body is JSON-labeled quoted evidence following the curator note.
It retains the mailbox reference/hash, message ordinal, original byte start/end,
message-byte digest, Unix envelope, headers and readable MIME parts. End offsets
are exclusive and the message segment includes its From envelope and any stored
separator blanks. Message hashes cover exactly those stored bytes, not decoded
or reconstructed messages. The whole mailbox hash also includes unselected
messages, line endings and whitespace.

This bounded reader accepts an mboxo-style Unix From-envelope layout:

- The first byte starts an ASCII `From sender recorded-envelope-text` line.
  Every later unescaped line beginning `From ` starts another message. Envelope
  date text is recorded, not parsed, authenticated or used for sorting.
- LF and CRLF are supported; bare CR, BOM, preambles and NUL are refused.
  Every message must have at least one mail header and a header/body separator.
- Stored `>From` and `>>From` lines remain exactly as decoded body text. This
  deliberately does not try to recover ambiguous mboxo quoting or unescape an
  mboxrd transport. Export properly escaped mailboxes; an unescaped body line
  beginning `From ` is interpreted as a boundary, never silently repaired.
- Content-Length-based mbox variants are rejected. This is not an mboxcl,
  mboxcl2, Maildir, PST, EML archive, compressed archive or live mailbox client.
  For one standalone RFC822 EML file, use the separate [EML intake](REVIEW_EML_IMPORT.md);
  mailbox framing rules do not apply to that workflow.
- From, To, Cc, Subject, Date, Message-ID, In-Reply-To and References values are
  recorded in header order, including duplicates. `raw_value` is the Python mail
  parser's retained header spelling; `decoded_value` is its readable decoding,
  not a claim of exact header-token bytes. The original mailbox remains exact.
- Inline text/plain supports 7bit, 8bit, strict base64 and strict quoted-printable
  decoding. Supported charsets are ASCII, UTF-8, ISO-8859-1 and Windows-1252 with
  the small documented aliases in the source. Missing charset defaults to ASCII.
  Bad encoded bytes or unsupported charsets/transfer encodings fail.
- Multipart mixed, alternative and related are supported. All inline plain-text
  leaves are kept with part locators; no preferred alternative is guessed.
  HTML, images, nested RFC822 content and attachments are listed as unavailable
  bodies and never rendered, fetched or executed. Attachment payloads are not
  decoded. A selected message must contain supported inline plain text.
- Malformed MIME structure and duplicate MIME control headers fail, including
  in later unselected messages. Opaque nested trees still count against limits.
  This is a conservative static reader, not a full mail/MIME validator.

Bounds: 4 MiB per selected input, at most 500 messages, 2000 MIME parts over the
whole mailbox, depth 16, at most 4000 delimiter-like lines beginning `--`, and
8 MiB decoded plain text overall. Selected imported evidence is additionally
limited to 8 MiB. Inputs and outputs are in memory; parsing is not streaming.
These limits can reject unusual but valid mail. No unsupported content is
silently converted into a claimed readable body.

Changed mailbox bytes require a new catalog digest and deliberate selection
plan. There is no automatic thread reconstruction, deduplication, source repair,
identity verification, reply, sharing, receipt creation or knowledge acceptance.
The catalog and bundle can contain private messages and metadata. Keep the
original mailbox and handle the catalog with the same care; generating either
does not authorize sending it to anyone.

## Focused checks

`python3 -B scripts/test_review_mbox.py` runs local parser/CLI tests. Four native
consumer tests require `MOONCHAT_REVIEW_COMPOSER` after verifying the executable
and its exact source/dependency inputs; the delivery's `run-focused.sh` performs
that verification and runs all tests. Native tests consume real mailbox-authored
agendas, prove exact source digest and zero decision receipts, retain existing
items, and reject wrong source binding, invalid references and missing decisions.

This is a bounded contribution to MOONCHAT-B01/B02/B03. It does not qualify a
hosted human-decision journey, receipt return, sender authentication, graphical
mail client, provider, receiving product, release or full-product readiness.
# Reply context discovery

Use [explicit reply-thread exploration](MAILBOX_THREADS.md) to inspect supplied
Message-ID, In-Reply-To and References relationships before choosing ordinals.
Ambiguity, missing parents and cycles stay visible; exploration never adds a
review selection or decision.
