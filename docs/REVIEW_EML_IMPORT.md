# Curate a standalone email into pending review

For explicit HTML-only or alternative-body selection, see
[static HTML text intake](MAIL_HTML_TEXT.md); the v1 workflow below remains plain-only.

This local workflow accepts one standalone RFC822 EML file, without Unix mailbox framing. It reuses the conservative MIME decoder from mailbox intake, but never invents an envelope, unescapes body lines or normalizes original bytes. `From ` inside the body is ordinary content. An EML archive, directory, live mailbox or concatenated-message transport is outside this profile.

From the repository root:

```
python3 -B scripts/review_eml.py catalog examples/review-eml/objection.eml
python3 -B scripts/review_eml.py preview examples/review-eml/agenda.json examples/review-eml/objection.eml examples/review-eml/selection.json --composer /absolute/path/to/review_compose.exe
```

Use `agenda` or `bundle` in place of `preview` for editable input or portable pending review. All three invoke the real trusted native composer before printing output. Output is stdout only; redirect to a fresh path rather than overwriting inputs.

1. Inspect the catalog's original source digest, single message and MIME parts.
2. Copy its exact source digest into a `moonchat.eml-review.v1` selection with the example's exact fields.
3. Explicitly assign an existing curator, item key/kind, note and named human decision requests. No sender or quoted approval becomes participant authority.
4. Compose against the original file. Preserve the returned agenda's source_digest_constraint when editing; ordinary native composition rejects changed bytes. Removing that constraint deliberately is a new authoring scope, not a protected signature.

The catalog's single message has ordinal 1, message digest equal to the original file digest and half-open byte span [0, byte_count). There is no envelope field. MIME locators identify decoded leaves, not exact raw part byte ranges. All top-level headers, including repeated custom headers, are retained in order. Their raw_value preserves parser spelling, not exact header byte tokens; original file bytes remain the provenance authority. No date parsing, thread inference or sender authentication is performed.

Bounds: 1 byte–4 MiB source, 2000 MIME nodes, depth 16, 8 MiB decoded plain text/imported evidence. LF and CRLF work; bare CR, NUL, BOM, Unix envelope, malformed MIME, Content-Length and unsupported plain-text encodings/charsets fail closed. Inline text/plain supports ASCII, UTF-8, ISO-8859-1 and Windows-1252, 7bit/8bit, strict base64 and quoted-printable. Multipart mixed/alternative/related are supported; all available plain-text leaves are retained without choosing a preferred alternative. HTML, images, attachments and nested email content remain opaque and cannot alone satisfy selection. This is a bounded review reader, not exhaustive RFC conformance validation.

Synthetic fixtures and CLI/native tests establish local development behavior only. They do not establish a hosted review screen, authenticated human, receipt delivery, receiver acceptance, provider access or ordinary-user readiness.
