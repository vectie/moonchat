# Read an objection beside its exact source passage

An offline review packet can now link each existing question, objection or
proposal to one or more exact passages. Click a source line's “Linked discussion”
link to read the associated entry and its receipts. Click “Read source lines” in
an entry to return to the passage. Quoted excerpts also make a printed packet
useful without jumping between pages. All entries, decisions and receipts stay
visible, including discussion with no supplied source location.

This is reader-authored navigation for the existing review packet, not another
review bundle or a decision editor. It does not infer line numbers from prose.

## Try the included example

Build `cmd/review_packet` for native using your configured toolchain and an
external target directory. From this repository, run the resulting executable:

```sh
review_packet --locations examples/review-locations/locations.json examples/review-packet/mixed-review.json examples/review-packet/source.md > linked-review.html
```

Use a new output path, never an input: shell redirection truncates the destination
before the command reads it. `examples/review-locations/linked-review.html` is the
actual generated example. Open it locally in a browser. It links the matching
proposal to lines 5–7 and the rollback objection to both the open issue at lines
14–16 and the rollout step at lines 11–12. The unrelated coverage question is
still shown. The approved query examples, deferred rollback owner, and missing
rehearsal decision retain their original meanings and overall pending status.

The original two-input invocation still emits the identical unannotated packet.
No JavaScript, network requests, active evidence links or provider is added.

## Prepare a location file

1. Open an ordinary packet or inspect the exact source with the display-line
   rules below. Copy the review ID and source SHA-256 from its header.
2. Choose an entry ID from the discussion, its one-based inclusive line range,
   and the complete literal text of those lines. Add a second range when an
   objection needs more than one passage. Ranges may overlap across or within
   entries; an identical entry/range pair may appear only once.
3. Store the following separate JSON file and pass it with `--locations` before
   the bundle and source paths. The example IDs/digest are from the retained
   fixture; substitute your own values.

```json
{
  "format": "moonchat.review-source-locations.v1",
  "review_id": "cafe-release-review",
  "source_digest": "sha256:6fa3b32405be3fa1960d89b2196e8bee6ccb6567ea3f0846ed540de5eaae7b9b",
  "locations": [
    {
      "entry_id": "rollback-objection",
      "start_line": 14,
      "end_line": 16,
      "quote": "## Open issue\nThe named rollback owner and rehearsal date are not yet recorded.\nApproval of the query examples does not resolve that objection."
    }
  ]
}
```

Every quote must match the complete selected display lines exactly. CRLF and CR
become LF for display, and lines are joined with LF without an extra terminating
newline. A final source newline creates a final empty display line, which may
be selected with an empty quote. Empty source has one empty display line. A
UTF-8 BOM, Unicode, indentation, tabs and spaces remain significant. Unlike the
transcript importer, these are the HTML packet's display lines, not retained
physical-line terminators. Original bytes, including newline style and BOM,
still determine the source digest.

Location order controls the excerpt order for each entry and the backlink order
when ranges overlap. Source and discussion retain their existing order.
An empty `locations` array is allowed and explicitly reports zero located entries.

The command checks the complete review and source first, then every location.
Wrong source/review identity, an unknown entry, out-of-range/reversed lines,
duplicate pairs, quote mismatch, unsupported format or invalid JSON produces
stderr and exit 1, with no partial HTML on stdout. It never repairs a location
by searching for similar text or silently moving it onto another revision.

## Embedding API

```mbt nocheck
let locations = @review.parse_review_source_locations(location_json)
let html = @review.export_review_html(bundle, source_bytes, locations~)
```

The public `ReviewSourceLocations` and `ReviewSourceLocation` types also support
direct construction. Both paths receive the same semantic validation when
exporting. Parsing checks the JSON shape and format; it cannot validate source
binding until the bundle and bytes are available. The pure export is deterministic
and does not mutate either input.

## Limits and meaning

The existing packet source limit remains 1 MiB and 10000 display lines. A map may
contain at most 1000 ranges, totaling at most 10000 selected lines (overlapping
lines count once for each range) and 1048576 UTF-16 code units of quoted text
(including repeated quotes). All data and output are in memory. The existing
review contract has no new total bundle limit; the location-file JSON decoder
still reads the complete local file before validating the map.

The exporter verifies location quotes, source identity and entry existence.
The reader chooses which entry belongs to which passage. That association is
not proof of semantic relevance, resolved dissent or human approval. Locations
are deliberately separate from review evidence and do not alter contract IDs,
event IDs, receipts, review status or knowledge acceptance. Retain the original
bundle, exact source and location file alongside the derived HTML. A reused
review ID/entry ID on unchanged source can use the same map; if the entry's
meaning changes, inspect its association again. Changed source bytes require a
new map and review binding.

Generated anchors and links are local to this HTML. All quotes and labels are
escaped as literal text. Navigation uses ordinary keyboard-focusable links and
explicit labels. Static/API/CLI tests do not qualify a real host, assistive
technology, a particular browser or receipt delivery.

For a revised artifact, the [source-link relocation workflow](REVIEW_SOURCE_RELOCATION.md)
can prepare a separately bound next map from unchanged entries and unique exact
quotes. It reports ambiguous and changed passages for explicit reader editing;
it never silently repairs the old map or overwrites the original review.
