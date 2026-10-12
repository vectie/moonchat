# Offline source-inclusive review packets

Use `review_packet` to read a source-bound review in an ordinary browser or
print it for an offline meeting. The single HTML file includes the actual UTF-8
source text next to its discussion, the named reviewers, every current-bundle
objection and all recorded receipts. It needs no server, JavaScript, fonts,
images or network access. Browser Find, in-document links and Print work with
the locally saved file.

## Create a packet

Build `cmd/review_packet` with the native target, then run:

```sh
review_packet examples/review-packet/mixed-review.json examples/review-packet/source.md > packet.html
review_packet --help
```

The supplied example is synthetic: one proposal has an approval, one objection
has a deferral and a second decision still awaits a receipt. The overall review
therefore remains `pending_review`. Open `packet.html` in a browser. Use the
decision index to jump to the exact request, its subject discussion and the
recorded rationale. Source lines have stable local links for this display.
At narrow widths and in print, source and discussion become consecutive sections.
The discussion index exposes questions, objections and proposals without a
filter that could conceal disagreement.

The command reads only the two explicit local input paths and writes stdout.
Redirect to a new file, never either input: the shell truncates a destination
before MoonChat can read it. Missing/unreadable inputs, malformed bundles,
invalid receipts, source mismatch and unsupported source text exit 1 with a
stderr diagnostic and no HTML on stdout. Embedded source/evidence/predecessor
references are displayed as inert text, never opened or fetched.

## Link discussion to exact source passages

Pass `--locations locations.json` before the two inputs to add bidirectional
source/discussion links and literal excerpts. The [source-location guide](REVIEW_SOURCE_LOCATIONS.md)
explains the separate digest-bound map, exact-quote checks and runnable example.
Unlocated entries and every decision stay visible. The original invocation and
output are unchanged.

## Scope and authority

`@review.export_review_html(bundle, observed_source_bytes)` is a deterministic,
nonmutating pure API. It validates the complete bundle with the existing review
projection before rendering. The displayed digest covers the exact supplied
source bytes, including line endings and a UTF-8 BOM if present. All dynamic
text is HTML-escaped. All active links are generated fragment-only links.

This is a derived reading output, not an import format or decision editor.
Retain the original JSON and source separately. Existing receipts are displayed,
not authenticated or created. An accepted MoonChat review does not deliver a
receipt, execute a proposal, or make a receiving product accept its claims.
Prior revisions are identified by reference/digest only; retain and export them
separately to inspect prior dissent. The packet does not claim to be a stored
journal or an actual qualified host journey.

This complements Markdown export and literal text exploration. Its additional
workflow is source-inclusive, linked, offline browser reading and printing.
It does not reopen received bundles, edit agendas or replace a consuming host.

## Display limits

- Source must be valid UTF-8, at most 1 MiB and 10000 display lines.
- LF, CRLF and CR are normalized to LF in the display only. A final newline adds
  an empty final display line; an empty source has one empty display line.
- Tab is retained with a four-column display width. C0 controls other than tab,
  CR and LF, plus DEL, are rejected rather than silently omitted. Unicode text
  and its normal browser shaping are retained; this is not a hex viewer.
- Source markup is literal text, never rendered as HTML or Markdown. A binary
  artifact can still use the existing source-bound Markdown review exporter,
  which does not embed its bytes.
- The existing contract has no new total bundle-size limit. Inputs and the
  complete generated HTML are in memory; this is not a streaming renderer.
- Source line numbers are display references, not parsed evidence locations or
  a claim that an entry's prose line citation has been verified. Optional explicit
  location maps verify exact quoted ranges rather than interpreting prose citations.

## Focused checks

Native and JS review tests cover exact source validation, deterministic output,
all receipt outcomes, preserved objections, mixed and multiple requests, safe
escaping, local-only links, source limits, Unicode, normalized newlines, invalid
control bytes and predecessor visibility. The actual CLI sample is retained at
`examples/review-packet/mixed-review.html`.

The HTML uses semantic headings, navigation, visible focus styles and print
CSS. Static output checks do not establish assistive-technology, cross-browser
or real-host qualification; those remain consumer testing responsibilities.
