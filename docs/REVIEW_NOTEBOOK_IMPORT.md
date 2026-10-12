# Review selected cells from a saved notebook

`review_notebook` opens a local Jupyter `.ipynb` snapshot as a static cell catalog.
Select a calculation, failed cell or explanation, add your review point, and
export an ordinary editable MoonChat agenda or readable review. The whole
original notebook supplies the source digest, including metadata and saved
outputs. You do not have to copy code and results into a separate text artifact.

This workflow never starts a kernel, reruns code, renders Markdown/HTML, opens
attachments, loads widgets or follows URLs. Saved outputs may be stale or edited;
an execution count does not establish when, how or whether code was executed.
Cell metadata, author names and notebook text do not identify a human reviewer.

## Try the retained example

Build `cmd/review_notebook` in your pinned native environment; the delivery's
`BUILD.md` gives repeatable commands and exact executable locations. From the
repository root, with that executable available as `review_notebook`:

```sh
review_notebook catalog examples/review-notebook/forecast.ipynb > catalog.json
review_notebook preview examples/review-notebook/agenda.json examples/review-notebook/forecast.ipynb examples/review-notebook/selections.json > preview.md
review_notebook agenda examples/review-notebook/agenda.json examples/review-notebook/forecast.ipynb examples/review-notebook/selections.json > imported-agenda.json
review_notebook bundle examples/review-notebook/agenda.json examples/review-notebook/forecast.ipynb examples/review-notebook/selections.json > review.json
```

All commands read local inputs and write stdout only after successful validation.
Errors exit 1 with stderr diagnostics and no partial output. Redirect to a new
path, never an input: shell redirection truncates its target before the program
can inspect it. No input files are changed. A later bad selection rejects the
whole import. Unknown CLI modes and malformed inputs do not produce an agenda.

The fixture is synthetic. It selects a division-error cell first, then a forecast
cell with different saved cell/result counts. The result includes decoded code,
stream output, a plain-text result, an error traceback, and retained rich-data
JSON. An image-only display is explicitly identified as having no text/plain
representation. A stream saying “I approve everything” stays quoted evidence.
The resulting bundle has three review entries, three pending decision requests
and zero receipts. The catalog, imported agenda, Markdown and bundle checked into
`examples/review-notebook/` are real native CLI outputs.

## Choose cells and continue editing

1. Run `catalog`. It returns the exact `notebook_digest`, notebook metadata and
   zero-based `cell_index` values, with cell IDs where available. It includes
   decoded source, execution counts and static output summaries. Rich payloads
   and cell attachments remain in the original notebook; MIME names are listed.
2. Copy the selection plan. Set `format` to `moonchat.review-notebook.v1` and
   `notebook_digest` to the catalog digest. Every entry in `cells` requires
   `cell_index`, unique stable `key`, `kind`, `author`, `note` and `decisions`.
3. Use an existing participant as curator `author`. `kind` is `question`,
   `objection` or `proposal`; `note` is your own nonempty explanation. Decision
   requests use existing `reviewer` and `prompt` fields. Ordinary agenda rules
   apply, including a decision request for every objection.
4. Set the agenda's `source_artifact_ref` to the workspace-relative path where
   this exact notebook will be retained. The local CLI filename does not change
   the portable reference. The notebook itself is the reviewed artifact.
5. Preview and export. Selection order determines appended item order; existing
   items are preserved. Edit the imported agenda through the ordinary
   [agenda workflow](REVIEW_AGENDA.md) or [spreadsheet workflow](REVIEW_SHEETS.md).

The existing native composer validates the entire result, including `agenda`
mode. Run imports against the original agenda to regenerate deterministically;
importing again into the already imported agenda fails on item-key collisions.
Keep item keys when changing wording so the usual generated identities remain
stable. The supplied `edited-agenda.json` demonstrates changing a decision prompt
while preserving imported evidence and item identity.

```sh
review_compose bundle examples/review-notebook/edited-agenda.json examples/review-notebook/forecast.ipynb > edited-review.json
review_export review.json examples/review-notebook/forecast.ipynb > exported-review.md
review_packet review.json examples/review-notebook/forecast.ipynb > review.html
```

The HTML packet shows notebook JSON as escaped source text and review bodies as
literal text; it is not a notebook renderer. The ordinary packet's stricter
1 MiB source/10,000-line limit still applies. Larger supported notebooks can use
the ordinary Markdown review. No browser-rendering qualification is claimed.

Any changed notebook bytes, including a save that only reformats JSON, require a
new catalog digest and explicit selections. Indexes identify cells only within
that exact snapshot; cell IDs are provenance, not an automatic rebase or refresh
mechanism. For a retained prior review, use the existing composer predecessor
workflow and a new source revision label. Old receipts do not transfer.

## What travels with each selected cell

The body contains the curator note, decoded literal source and readable saved
text outputs, followed by JSON provenance: source reference, notebook digest,
cell JSON pointer, format version, notebook metadata, decoded output summary and
the complete original selected cell object. This retains cell metadata,
attachments, rich MIME data and unknown extension fields as JSON evidence.
Notebook-level extension fields outside metadata stay in the retained original
file. Unselected cells are not copied into selected review bodies.

String-array fields are concatenated without inserting line breaks. Traceback
frames are separated by LF in the reading section; their original boundaries and
strings remain in the evidence JSON. No ANSI processing, widget interpretation,
Markdown evaluation, image decoding or code execution is performed. Original
cell JSON is reserialized, not byte-for-byte source formatting. The source digest
covers the original whole file, including whitespace and any UTF-8 BOM.

Normal agenda editing can change the copied text. It is not an immutable evidence
manifest: keep the notebook and selection plan to check or regenerate the import.
The importer does not verify model assumptions, output correctness, execution
order, kernel availability, reviewer identity or receiving-product acceptance.

## Supported notebook subset

- UTF-8, optional BOM, `nbformat` 4 with minor versions 0–5; required notebook
  metadata object and cells array. Empty notebooks can be cataloged.
- Markdown, raw and code cells with metadata objects and `source` as a string or
  array of strings, including empty strings/arrays. Hidden-source metadata does
  not hide text from the catalog or review.
- Cell IDs are required for 4.5, optional for older versions. Supplied IDs must
  be unique and contain 1–64 ASCII letters, digits, `-` or `_`.
- Code cells require `execution_count` (null or nonnegative 32-bit integer) and
  an outputs array. Non-code cells with execution fields and code attachments
  are rejected by this bounded reader.
- `stream` outputs with stdout/stderr and string/string-array text; `error`
  outputs with string name/value and a string-array traceback; `display_data`
  and `execute_result` with metadata and MIME-data objects. Execute-result
  counts must be nonnegative 32-bit integers. They need not equal the cell count;
  both values remain visible without claiming either is current.
- `text/plain` is the only rich display representation decoded for reading.
  Other MIME types are listed and retained in complete selected-cell JSON.
  `application/json` and `+json` values may be arbitrary JSON; other MIME values
  must be strings or string arrays. Markdown/raw attachments use the same MIME
  rules and remain uninterpreted evidence.
- Unknown notebook major/minor versions, cell types or output types fail clearly,
  including in unselected cells. Required structure is checked across the entire
  notebook; opaque metadata and extension fields are preserved, not validated.

Limits: notebook at most 4 MiB, up to 1,000 cells and 1,000 saved outputs total,
1–100 distinct selected cells, and at most 16 MiB of UTF-8 imported bodies. Inputs
are read into memory; this is not a streaming reader or full nbformat validator.
Existing agenda limits and source exporters' separate limits still apply.

The format interpretation follows the official
[Jupyter notebook format description](https://nbformat.readthedocs.io/en/stable/format_description.html).
The supported subset above is deliberately narrower. No nbformat package,
notebook runtime, provider or new dependency is installed.

Public pure APIs: `catalog_notebook_review`,
`parse_notebook_review_import_plan`, and `import_notebook_review`. The existing
portable bundle contract is unchanged. Local focused tests do not qualify a
hosted decision/receipt journey, notebook rendering, or cumulative readiness.
