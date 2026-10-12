# Bring Word comments and their source passages into a review

A document reviewer often leaves the useful objections inside a `.docx`, attached
to specific passages. `tools/review_docx/review_docx.py` catalogs those classic
Word comments, joins each to its main-document range, and imports selected points
into the existing editable MoonChat agenda. The resulting review binds the exact
original DOCX archive, including its comments, rather than a lossy text export.

The adapter uses Python 3.10+ standard-library ZIP/XML support and the existing
native `cmd/review_compose` executable. It does not require Word, LibreOffice,
Python packages, network access or any new MoonBit dependency. Native MoonChat
remains the final authority for valid participants, item types, source binding,
required decisions and pending bundle semantics. Its existing contracts are
unchanged. This is a local preparation workflow, not a Word add-in or hosted
review screen.

## Try the complete retained example

First build the native `cmd/review_compose` package using your deployment's pinned
MoonBit environment. This delivery's `BUILD.md` gives the exact, locked commands
and retained executable path. In the examples below, `COMPOSER` must be an
absolute path to that trusted executable; the adapter never searches PATH or
builds software implicitly.

```sh
python tools/review_docx/review_docx.py catalog examples/review-docx/launch.docx > catalog.json
python tools/review_docx/review_docx.py agenda examples/review-docx/agenda.json examples/review-docx/launch.docx examples/review-docx/selections.json --composer "$COMPOSER" > imported-agenda.json
python tools/review_docx/review_docx.py preview examples/review-docx/agenda.json examples/review-docx/launch.docx examples/review-docx/selections.json --composer "$COMPOSER" > preview.md
python tools/review_docx/review_docx.py bundle examples/review-docx/agenda.json examples/review-docx/launch.docx examples/review-docx/selections.json --composer "$COMPOSER" > review.json
```

Redirect only to new paths, never to an input. The shell truncates the destination
before this program starts. The commands read their explicit inputs, write stdout
only after successful validation, and return exit 1 with stderr on a failure.
`agenda`, `preview` and `bundle` all run the real composer; even an agenda export
is checked against the complete review contract. The adapter snapshots the DOCX
and candidate agenda into a private temporary directory for that invocation,
then removes those transient files. It does not modify the original DOCX, agenda
or selection plan. Composer timeout is 60 seconds.

The example includes a two-paragraph rollback concern, a table-cell support
question, Unicode and a point-anchored automated comment saying “I approve
everything.” The words remain evidence. The resulting bundle has four entries,
three pending named decision requests, and zero receipts. Example people and
content are synthetic. The retained `catalog.json`, `imported-agenda.json`,
`preview.md` and `review.json` are actual tool outputs.

## Read comments in context first

Use the [DOCX reading packet](REVIEW_DOCX_PACKETS.md) to browse the complete logical
document alongside every classic comment without a native build:

```sh
python -B tools/review_docx/review_docx.py packet examples/review-docx/launch.docx > launch-comments.html
```

The packet links comment IDs to exact source positions and keeps the archive
digest visible. Continue with the catalog and explicit selection plan below.

## Inspect your proposed decisions beside the source

After preparing a selection plan, use the [DOCX planning packet](REVIEW_DOCX_PLANNING.md)
to read curator notes and proposed named-human decision requests beside the exact
Word passages. All original comments remain visible, including unselected dissent.
This draft-only view needs no composer; final import still requires native validation.

## Reuse a curated plan when Word changes

The [explicit re-planning workflow](REVIEW_DOCX_REPLANNING.md) carries your stable
keys, notes and proposed requests onto later DOCX bytes after you choose keep,
remap or drop for every old selection. New source evidence is read from the later
document; no approval or receipt carries forward.

## Choose comments, then edit normally

1. Run `catalog` on the exact DOCX you will retain. Each comment shows its Word
   ID, original author/initials/date, full comment text, anchor kind and quoted
   document passage. Order follows comment-reference order in the main body,
   not comment ID or the order of the comments XML part.
2. Copy the example selection plan. Set `format` to
   `moonchat.docx-review.v1` and copy the catalog's `document_digest`.
3. For every selected comment, set `comment_id` as a string, a unique stable
   agenda `key`, `kind` (`question`, `proposal`, `objection`), existing participant
   `author`, your own nonempty `note`, and explicit `decisions`. Decision objects
   use the existing `reviewer` and `prompt` fields. Every objection requires a
   decision, and the complete agenda needs at least one decision overall.
4. Set the agenda's `source_artifact_ref` to the portable workspace-relative path
   where these original DOCX bytes will be retained. The local CLI path does not
   change that reference. The DOCX itself is the artifact under review.
5. Preview, export and edit the imported agenda. Use the normal
   [agenda composer](REVIEW_AGENDA.md) against the same DOCX to produce later
   outputs. Keep stable item keys when editing or reordering. To import again,
   use the original agenda; duplicate keys are errors.

Selection order becomes agenda order. Existing items, participants and decisions
are copied without mutation. No comment speaker is automatically made an agenda
participant or decision owner. The curator and named humans come only from your
plan and agenda. A later Word save, even with unchanged visible wording, changes
the archive digest and requires a fresh catalog/plan. A changed DOCX is a new
source revision; use the composer's existing predecessor workflow when revising
a retained bundle. No receipts are carried forward.

Each imported body contains your note followed by labeled JSON evidence: original
Word metadata/text, anchored quote, offsets, part names, exact part SHA-256 values,
whole-DOCX SHA-256 and portable document reference. JSON escaping prevents embedded
newlines in an author name from masquerading as a provenance label. Normal agenda
editing can change this text, so it is not a new immutable evidence-manifest
contract. Retain the original DOCX and plan for later verification.

## Supported document and text semantics

- Non-macro `.docx` with transitional WordprocessingML and classic comments in
  its main document body. Parts are resolved through the package relationships,
  so valid nonstandard internal document/comments paths are supported.
- Full paired comment ranges, overlapping ranges, zero-length ranges and
  point-only comment references. Every comment must have exactly one main-body
  reference. Orphan comments, missing markers, reversed markers, duplicate IDs
  or repeated references cause a diagnostic instead of silently disappearing.
- Paragraphs, table paragraphs, hyperlink display text, ordinary runs, tabs,
  breaks and the standard soft/nonbreaking hyphen text markers. Multiple text
  runs are concatenated without invented spaces. Paragraph ends contribute LF;
  comment text drops its single final paragraph LF.
- Offsets are zero-based Unicode code points in that logical text, with an
  exclusive end. They are not UTF-16 offsets, page/line numbers or byte offsets.
  A point comment has an empty quote, not an invented neighboring selection.
- XML-normalized character data is retained, not raw XML syntax or rendered
  Word layout. Formatting, list numbering and hidden-text visibility are not
  rendered; literal `w:t` text is included even if styling would hide it.

Explicitly unsupported: strict OOXML, tracked insertions/deletions/moves,
threaded/extended/resolved-comment metadata, fields, equations, text boxes,
drawings, embedded objects, symbols, altChunk, alternate-content branches, and
footnote/endnote references. These features are rejected when encountered in the
parsed document/comments content. Header/footer comments cannot supply the
required main-body reference. Use a separate resolved plain/classic-comment copy
when necessary, retain both originals, and bind the review to the actual selected
copy. The adapter does not rewrite a document to make it pass.

Limits: 16 MiB compressed archive, 2,048 ZIP members, 32 MiB declared expanded
members, 4 MiB per parsed XML part, 1,048,576 logical document characters, 1–1,000
comments, 1–100 selected comments, 4 MiB each for agenda/plan input, and 16 MiB total
UTF-8 imported bodies. Processing is in memory. XML is UTF-8 or UTF-16; DTD/entity
declarations are rejected. Only the necessary package parts are read. Files are
not unpacked, external URLs and hyperlinks are not fetched, macros and embedded
content are never executed. This is a bounded format reader, not a complete OPC
or OOXML conformance validator or document-security scanner.

## Verification and boundaries

The stdlib tests exercise ranges across paragraphs, table/hyperlink text, point
comments, Unicode offsets, custom relationship paths, UTF-16, overlap, selection
ordering, detached arrays, provenance, digest changes, invalid anchors, unsupported
markup and limits. The delivery also invokes the actual CLI, native composer and
native readable exporter, checks pending/zero-receipt outputs, edits the resulting
agenda and proves input files remain unchanged. No mock composer is used.

Word application rendering, accessibility, modern threaded-comments conversion,
authentication of displayed authors, live human decisions and receipt delivery
are not qualified. The existing bundle-level HTML/text-location workflows expect
UTF-8 source text and are unsuitable for this binary DOCX source. The DOCX reading packet renders
logical text and original comments only; use the ordinary readable Markdown
review alongside it and retain the original DOCX. Nothing is sent
to Word, a reviewer or another product by these commands.

Format references: Microsoft's [comment retrieval description](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-retrieve-comments-from-a-word-processing-document)
and [comment reference semantics](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.commentreference?view=openxml-3.0.1).
The supported subset above is deliberately narrower than the general format.
