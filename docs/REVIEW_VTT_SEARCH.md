# Find a speaker's WebVTT evidence and review it

MoonChat is a portable artifact-review contract. Locate relevant cues in long
caption transcripts before writing an explicit review item. This extends the
existing WebVTT importer and PRD W01 bundle-authoring journey. A declared voice
label is quoted evidence, never a verified person or an approval.

From the repository root:

```
python3 -B scripts/review_vtt.py search meeting.vtt --voice Alex --text rollback --start-ms 1000 --end-ms 30000 --context 1 > search.json
```

Filters are ANDed. Text is literal, case-insensitive Unicode after caption markup
removal and entity decoding. Voice labels come from `<v Alex>` or `<v.class Alex>`
annotations and match exactly, including case. A cue with several voice spans
matches any declared label; text matches the whole cue, not only that voice's
span. Time windows use overlap, start inclusive and end exclusive. Context adds
up to five neighboring cues without selecting them. Original text stays visible.

Copy desired numbers from `matched_cues` into an item's `cues` array in
`examples/review-vtt/selection.json`, retaining explicit author, review kind,
body and named decision requests. Inspect and compile the selected review:

```
python3 -B scripts/review_vtt.py agenda meeting.vtt selection.json > agenda.json
python3 -B scripts/review_vtt.py bundle meeting.vtt selection.json --composer /path/to/review_compose > bundle.json
```

Search includes the exact source SHA-256. Keep that transcript while selecting;
if it changes, search again. Indices belong to that input, and the composer binds
the resulting bundle to the supplied bytes. Search output is a discovery aid,
not an authenticated selection token. No source is edited. Existing 2 MiB and
10000-cue limits apply. Empty matches are valid; the importer refuses empty
selections. Tests: `python3 -B -m unittest discover -s scripts -p 'test_review_vtt*.py' -v`.
Set `MOONCHAT_COMPOSER` to exercise native bundle/preview as well. Host screens,
accessibility and authenticated decisions remain unqualified.
