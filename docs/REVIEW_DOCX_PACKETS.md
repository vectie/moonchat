# Read Word comments beside their source

The existing DOCX import workflow starts with a JSON comment catalog. The new
`packet` command makes the same supported document readable before choosing
which comments to import: open one local HTML file, read the entire logical
document, and follow a numbered anchor to its comment or a comment back to the
source. No Word installation, native MoonChat executable or Python package is
needed for this reading step.

## Open the retained example

From this repository, using Python 3.10 or later:

```sh
python -B tools/review_docx/review_docx.py packet examples/review-docx/launch.docx > launch-comments.html
```

Open `launch-comments.html` in a browser on your own machine. It is self-contained:
no server, JavaScript, fonts, images, network requests or external links are
required. Browser Find can search document and comment text; ordinary links move
between source and comments; the print stylesheet lays out source before comments.
The command writes a complete packet to stdout only after parsing and rendering
succeed. On failure it writes a diagnostic to stderr, exits 1 and emits no packet.

Redirect to a **new output path**, never the DOCX or another input. The shell opens
and truncates a redirection target before this program can inspect it. The tool
does not overwrite or modify its inputs itself.

## What to read

- The header binds the exact original archive and its parsed document/comments
  XML parts with SHA-256 values. Keep the DOCX beside the packet. Saving the Word
  document again changes the archive digest and requires regenerating the packet.
- The complete logical main-document text appears once in the source pane,
  including text outside comment ranges. Blue numbered links mark comment starts;
  gold identifies covered text and darker gold shows overlapping ranges.
- Each comment keeps its original ID, author, initials, date, full comment text,
  anchor type and Unicode-code-point offsets. Navigation and cards follow the
  same main-document comment-reference order as `catalog`, which may differ from
  numeric ID or range-start order. Missing metadata is labeled as missing.
- Point comments and empty ranges select no text. Their exact positions are
  linked without turning surrounding words into an invented quote.
- Cards repeat the first 2,000 Unicode characters of an anchored passage. Any
  truncation states the exact remaining character count and links to the full
  source range. Full document text and full comment text are never silently
  truncated. Offsets are zero-based, end-exclusive logical-text offsets; they are
  not Word page coordinates or UTF-16 offsets.

All document/comment text and metadata are HTML-escaped. Untrusted content cannot
create links or executable markup. The packet also declares a restrictive Content
Security Policy. Printed packets retain comment IDs, offset ranges and excerpts,
but printed pages do not offer interactive navigation.

## Continue into the existing import workflow

Use the packet to identify useful objections and their exact comment IDs, then
run the existing catalog against the same DOCX:

```sh
python -B tools/review_docx/review_docx.py catalog examples/review-docx/launch.docx > launch-catalog.json
```

Follow [the DOCX comment import guide](REVIEW_DOCX_COMMENTS.md) to create an explicit
selection plan, map comments to agenda participants and named decision owners,
and compile using the native composer when that executable is available. The
packet does not create an agenda, infer reviewers, create receipts, validate a
bundle or change review status. Displayed author names and dates are unverified
document metadata; “I approve everything” remains comment text.

This packet fills the binary-DOCX source-reading gap in the existing text-only
[review packet workflow](REVIEW_HTML_PACKETS.md). It is a reading aid for the
existing importer, not a standalone chat application or replacement for an
authoritative portable review bundle.

## Boundaries and tests

All [existing DOCX subset restrictions](REVIEW_DOCX_COMMENTS.md#supported-document-and-text-semantics)
still apply: classic transitional Word comments in the main body, supported plain
text constructs and complete consistent anchors. Tracked edits, threaded/resolved
comments and unsupported semantic markup fail rather than disappear. Word layout,
formatting, list numbering and hidden-text visibility are not reproduced. Styled
hidden text may appear, so inspect the packet before deciding to share it.

Input bounds are unchanged: 16 MiB archive, 2,048 ZIP members, 32 MiB declared
expanded content, 4 MiB per parsed XML part, 1,048,576 logical document characters
and at most 1,000 comments. HTML output is limited to 32 MiB, checked while
building it in memory. Repeated long ranges only allocate bounded card excerpts;
the full logical source is retained once. A rejected packet has no partial stdout.

Run the existing importer tests and packet functional/actual-CLI checks together:

```sh
PYTHONDONTWRITEBYTECODE=1 python -B -m unittest discover -s tools/review_docx -p 'test_*.py' -v
```

These checks cover exact source/comment preservation, forward/back fragment links,
crossing/nested/empty/point ranges, Unicode, leading newlines, custom part paths,
UTF-16, hostile metadata/text, bounded excerpts, output limits, deterministic
reruns, malformed-input failures and source immutability. They do not qualify the
native composer, real Word rendering, assistive technology, human decision
capture, receiver acceptance or receipt delivery.

For a returned revision, use [Word revision comparison](REVIEW_DOCX_COMPARISONS.md)
to inspect both snapshots and keep removed comments visible before making a new
selection plan. No earlier decisions are carried into the revised source.

## Read the proposed review with its source

The [planning packet](REVIEW_DOCX_PLANNING.md) combines the original agenda and an
explicit comment-selection recipe with this same source/comment view. It adds
curator notes and a named-reviewer request index without collecting decisions or
claiming native validation. Use it before the normal import step.
