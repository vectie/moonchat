# Select static HTML mail text as review evidence

A saved HTML-only email can now enter the existing pending-review workflow.
Inspect it with `--html-text`, then explicitly select one MIME locator and
representation in a version 2 plan. The same decoder serves standalone EML and
Unix MBOX. This is static extracted text, never a rendering of the sender's
intended appearance. No URL, image, stylesheet or embedded document is loaded.

## Inspect, choose, compose

From this repository, using Python 3.9+ and an existing trusted native composer:

```sh
python3 -B scripts/review_eml.py catalog original.eml --html-text
python3 -B scripts/review_mbox.py catalog original.mbox --html-text
python3 -B scripts/review_mbox.py search original.mbox rollback --field body --body-mode html-text
```

Inspect each part's locator, decoded text, charset, transfer encoding,
interpretation, omissions and limitations. The catalog has version 2 only when
HTML interpretation is explicitly requested. MIME parts remain distinct.
Plaintext and HTML alternatives are never merged by a v2 selection.

Use the existing agenda shape with your original source's portable reference,
revision label, curator participant and named human reviewer. For EML:

```json
{
  "format": "moonchat.eml-review.v2",
  "source_digest": "sha256:COPY_EXACT_CATALOG_DIGEST",
  "selection": {
    "key": "email-question",
    "kind": "objection",
    "author": "curator",
    "note": "Please assess the recorded rollback concern independently.",
    "decisions": [{"reviewer": "ops", "prompt": "Is rollback ownership clear?"}],
    "body": {"part": "1.2", "mode": "html-text"}
  }
}
```

For MBOX use `moonchat.mbox-review.v2`, `mailbox_digest`, and a `messages` array
instead of `selection`. Add the exact message `ordinal` to each selection.
Every v2 selection must name exactly one `body.part` and `body.mode`; use
`plain-text` for an inline text/plain leaf or `html-text` for an inline text/html
leaf. Missing choices, wrong content types, attachments, nested messages,
unsupported media, nonexistent locators and stale digests fail.

```sh
python3 -B scripts/review_eml.py preview agenda.json original.eml selection.json --composer /absolute/path/to/review_compose.exe
python3 -B scripts/review_mbox.py bundle agenda.json original.mbox selection.json --composer /absolute/path/to/review_compose.exe
```

Both tools also support `agenda`, `bundle` and `preview`. Each route invokes the
actual native composer before emitting output, including agenda mode. Redirect
stdout only to a fresh output path; shell redirection can otherwise truncate an
input before the companion reads it. A failed operation emits no partial stdout.

All v2 plans inspect supported inline HTML while parsing the snapshot. A malformed
HTML part anywhere in that snapshot fails the operation even if another part was
selected. Use the unchanged v1 plain-only workflow when HTML interpretation is
not desired. Default catalogs/search/thread exploration retain their prior
plain-text behavior. Explicit HTML body search searches only static HTML text,
not plaintext alternatives, and remains discovery rather than review selection.

## Exact originals, interpretations and omissions

The native composer receives untouched original EML/MBOX bytes. The selected
evidence retains the exact file digest, original message byte span/digest, MIME
locator, charset and transfer encoding. HTML additionally records a digest and
length of transfer-decoded content bytes. MIME locators are tree locations, not
raw byte ranges; they must be interpreted against the exact retained original.
Header `raw_value` is parser-retained spelling, not exact header-token bytes.

The selected part carries `moonchat.static-html-text.v1` plus static text,
aggregated omission records and limitations. Unselected alternatives retain
metadata but lose their decoded text in the imported item and have an explicit
"not selected" omission. Catalogs may expose all inspectable alternatives.
Keep the exact original file with the bundle; extracted text is not a replacement.

Both new EML and MBOX agendas carry the existing native `source_digest_constraint`.
Preserve that field when editing or composing directly: changed source bytes are
rejected. Deliberately removing the constraint is a new authoring scope, not a
protected signature. No sender, email approval claim or HTML markup supplies
authority. Existing participants/items survive; user-selected questions and
human decision requests remain pending until the separate decision workflow.

## Deliberately narrow HTML profile

The Python standard-library HTMLParser tokenizes locally; there is no browser,
JavaScript, CSS engine, resource resolution, networking or rendering. Tags must
be explicitly closed and well nested. Optional end-tag recovery, unknown visible
elements, duplicate attributes, non-void self-closing elements, processing
instructions, unknown character references and unsupported declarations reject.
Only an inert `<!DOCTYPE html>` is accepted. This is not general HTML5 mail
compatibility; malformed browser-tolerated mail may need a new supported export.

- Blocks get line breaks; list items get `- `; table cells get ` | ` separators.
  This flattens structure and does not reconstruct numbering or table layout.
- Normal text collapses ASCII space/tab/newline runs; preformatted blocks retain
  their internal whitespace. Named/numeric entities and Unicode are decoded.
- Anchor targets are quoted strings labeled `link target`, including non-HTTP
  schemes. They are never followed or made executable. Attribute references use
  HTMLParser's attribute decoding; the original bytes remain authoritative.
- Scripts, styles, head content, templates, frames, objects, SVG/MathML, canvas,
  audio/video, forms and fallback content are excluded with omission records.
  Images and other void resources are omitted; neither URLs nor event handlers
  are evaluated. Comments and doctype are disclosed as excluded/ignored.
- All other attributes, CSS and hidden/aria-hidden visibility are ignored.
  Hidden text can be included; intended display, reading order, styling,
  accessibility, image alternatives and layout fidelity are not claimed.

Existing mail bounds still apply: 4 MiB source, 500 MBOX messages, 2000 MIME nodes,
depth 16, and 8 MiB decoded content/imported evidence. Each HTML leaf additionally
has at most 1,048,576 decoded characters, 20,000 parser events, nesting depth 64,
1,048,576 accumulated UTF-8 output bytes and 2048 characters per link target.
No truncation silently turns over-limit input into evidence. Attachments are not
decoded; nested message bodies and application/xhtml+xml are not selectable.

## Focused checks

Run `python3 -B scripts/test_review_mail_html.py`. Its required real-consumer tests
fail rather than skip if their environment or pins are missing. Set:

- `MOONCHAT_REVIEW_COMPOSER`: absolute trusted retained executable path
- `MOONCHAT_COMPOSER_INPUTS`: the retained source-input SHA-256 receipt
- `MOONCHAT_HTML_EVIDENCE`: a fresh output directory for small real CLI journeys

The tests verify executable SHA-256
`60a1da93f31b568d43f18fb7eac831af4486f72b37c061ba46ecec1184c4520a`,
every unchanged native-source receipt entry, both real agenda/bundle/preview
journeys, exact originals, pending named decisions and native stale-source
refusal. Boundary inputs stay in memory. Also rerun existing EML, MBOX, search
and thread suites with the verified composer configured.

This bounded companion contribution concerns MOONCHAT-B01/B03/B06. Native
sources/interfaces are unchanged. It does not establish a graphical client,
hosted/authenticated human review, receiver acceptance, provider execution,
installed lifecycle or full-product release; existing required gates remain.
