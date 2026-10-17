# Explicit plain-text attachment review

Saved EML/MBOX attachments can now become pending review evidence through an
explicit v3 selection. Default catalogs, v1/v2 plans, body search and thread
exploration retain their existing behavior: attachments remain opaque.

## Inspect and deliberately choose

From the source directory, with Python 3.9+:

```sh
python3 -B scripts/review_eml.py catalog original.eml --attachment-text
python3 -B scripts/review_mbox.py catalog original.mbox --attachment-text
```

This opt-in decodes all accessible `Content-Disposition: attachment` leaves
whose media type is exactly `text/plain`. Inspect their MIME locators, filename
metadata, text, charset, transfer encoding, decoded-content digest and byte
length. A filename is untrusted metadata: it is never used as a filesystem path.
HTML attachment payloads, PDFs, nested messages and attachment containers remain
opaque. Their descendants are never selected. Inline parts, including inline
parts with filenames, are not attachments under this deliberately narrow profile.

For a saved mailbox, `python3 -B scripts/review_mbox.py search original.mbox
'rollback owner' --field attachment` explicitly searches this same decoded
attachment profile. [MAILBOX_SEARCH.md](MAILBOX_SEARCH.md) explains bounded
excerpts, exact message/MIME locators, digest-pinned continuation, and copying
chosen matches into the independent v4 review items below. Search alone never
selects evidence or changes decisions.

Copy the exact catalog source digest into a selection file:

```json
{
  "format": "moonchat.eml-review.v3",
  "source_digest": "sha256:COPY_EXACT_CATALOG_DIGEST",
  "selection": {
    "key": "attachment-question",
    "kind": "objection",
    "author": "curator",
    "note": "Please review the attached rollback concern independently.",
    "decisions": [{"reviewer": "ops", "prompt": "Is rollback ownership clear?"}],
    "attachment": {"part": "1.2", "mode": "plain-text-attachment"}
  }
}
```

Use your existing agenda with a source reference, revision, curator and named
human reviewer. `examples/review-eml/agenda.json` shows its shape; replace the
fixture identities and original-source reference appropriately. For MBOX use
`moonchat.mbox-review.v3`, `mailbox_digest`, and `messages` instead of `selection`,
adding the exact message `ordinal` to each selection. V3 requires exactly one
attachment per selected message; it never accepts a `body` field. Use the
unchanged v2 workflow for an inline body.

## Review several attachments together

Use a v4 plan to review multiple attachments from the same message in one
composition. Each selection becomes its own ordinary review item, in plan order,
with its own key, kind, curator note and named decisions. No text is merged.
For EML, replace the v3 `selection` object with a `selections` array:

```json
{
  "format": "moonchat.eml-review.v4",
  "source_digest": "sha256:COPY_EXACT_CATALOG_DIGEST",
  "selections": [
    {
      "key": "rollback", "kind": "objection", "author": "curator",
      "note": "Review rollback ownership.",
      "decisions": [{"reviewer": "ops", "prompt": "Is rollback ownership clear?"}],
      "attachment": {"part": "1.2", "mode": "plain-text-attachment"}
    },
    {
      "key": "schedule", "kind": "question", "author": "curator",
      "note": "Review the proposed schedule separately.",
      "decisions": [{"reviewer": "ops", "prompt": "Is the schedule workable?"}],
      "attachment": {"part": "1.3", "mode": "plain-text-attachment"}
    }
  ]
}
```

Use locators actually present in your catalog. For MBOX use
`moonchat.mbox-review.v4`, `mailbox_digest`, and `messages` instead of
`selections`; add `ordinal` to every selection. Repeating an ordinal is allowed
only when selecting different attachment MIME locators. V1–v3 retain their
original distinct-message behavior. V4 accepts 1–100 selections, distinct item
keys (also distinct from existing agenda items), and distinct message/attachment
pairs. Each item's evidence omits all other attachment and body text. The
aggregate imported-evidence limit applies across the whole selection list.
Use the same `agenda`, `preview`, and `bundle` commands below for either version.

```sh
python3 -B scripts/review_eml.py preview agenda.json original.eml selection.json --composer /absolute/path/to/review_compose.exe
python3 -B scripts/review_mbox.py bundle agenda.json original.mbox selection.json --composer /absolute/path/to/review_compose.exe
```

Both companions support `agenda`, `bundle`, and `preview`; every route validates
through the actual native composer before emitting stdout. Only redirect output
to fresh paths: shell redirection may otherwise truncate an input. Catalog
`--html-text` and `--attachment-text` are mutually exclusive.

## Meaning and limits

Selected text carries `moonchat.plain-text-attachment.v1` and an explicit
`attachment_choice`; `body_available` remains false for attachment evidence.
Unselected body and attachment text is removed from imported evidence, with
omissions retained. Original source digest, message byte span/digest, MIME tree
locator and supplied headers remain visible. Keep the exact original beside the
bundle: decoded text and filename are not substitutes for original bytes.

The native agenda keeps `source_digest_constraint`; both the companion and
native composer reject changed source bytes. A sender's approval words, script
text or filename supplies no authority. Text is quoted without executing it,
extracting files, following URLs or loading resources. Required human decisions
remain pending until the separate decision workflow.

Existing bounds apply: 4 MiB input, 500 MBOX messages, 2000 MIME nodes, depth 16,
8 MiB aggregate decoded text and 8 MiB imported evidence. Supported charsets are
ASCII, UTF-8, ISO-8859-1 and Windows-1252; transfer encodings are 7bit, 8bit,
strict base64 and quoted-printable. Malformed supported attachments fail the
entire opt-in catalog, even when another attachment would be selected. There is
no silent truncation or fallback interpretation. This remains a bounded saved
mail reader, not exhaustive RFC compliance or a graphical mail client.

## Regression verification

Run `python3 -B scripts/test_review_mail_attachment.py` with:

- `MOONCHAT_REVIEW_COMPOSER`: trusted retained native composer executable
- `MOONCHAT_COMPOSER_INPUTS`: retained native-input SHA-256 receipt
- `MOONCHAT_ATTACHMENT_EVIDENCE`: fresh evidence directory (must not exist)

Tests require the real pinned composer, verify every native source pin and fail
instead of silently skipping missing configuration. They cover both real CLI
journeys, pending named decisions, deterministic output, stale-source refusal,
attachment/body separation, legacy behavior, decoding and malformed selections.
Native source/interfaces are unchanged; host qualification, receiver acceptance,
installed lifecycle and full-product release gates remain separate.
