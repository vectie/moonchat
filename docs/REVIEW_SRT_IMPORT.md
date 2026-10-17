# Review original SubRip cues

Use this bounded local workflow for MOONCHAT-W01/W04 preparation. It catalogs the original SRT bytes, lets the curator explicitly select cue ordinals, and passes the exact original snapshot to the ordinary native review composer. No synthetic WEBVTT source is created.

## Select, preview, compose

From the source root, set `COMPOSER` to an independently verified native `review_compose` executable compatible with this source. The batch's `COMPOSER_VERIFICATION.json` records the retained executable and unchanged native inputs; no new native build is claimed.

```
python3 -B scripts/review_srt.py catalog examples/review-srt/meeting.srt
python3 -B scripts/review_srt.py agenda examples/review-srt/agenda.json examples/review-srt/meeting.srt examples/review-srt/selection.json --composer "$COMPOSER" > /your/new/candidate.json
python3 -B scripts/review_srt.py preview examples/review-srt/agenda.json examples/review-srt/meeting.srt examples/review-srt/selection.json --composer "$COMPOSER" > /your/new/preview.md
python3 -B scripts/review_srt.py bundle examples/review-srt/agenda.json examples/review-srt/meeting.srt examples/review-srt/selection.json --composer "$COMPOSER" > /your/new/bundle.json
```

Inspect the catalog before editing the selection. Copy its exact `source_digest`, then explicitly choose one-based `cues`, a unique item key, kind, existing curator, note and decision requests to existing human participants. Duplicate supplied SRT identifiers are supported: `srt/cue/2` identifies ordinal 2 within the pinned source, never identifier “2”. Original half-open byte spans and cue digests can be checked against the source. Separator blank lines are excluded from cue spans; the complete source digest includes every byte, including BOM and line endings. The application/x-subrip media type and ordinal locator provide a format-specific equivalent of a logical MIME locator.

Preview and bundle use the same native composer as ordinary review agendas. The emitted agenda has a source digest constraint, so native reuse with changed original bytes fails. All validation finishes before stdout; choose new redirect paths because the shell can truncate an existing file before the program validates. The wrapper reads each input once and never writes to those inputs.

## Supported profile and exact bounds

- UTF-8, optional UTF-8 BOM, LF or CRLF; no bare CR, NUL or lossy decoding.
- Numeric cue identifiers of 1–12 digits; strict `HH:MM:SS,mmm --> HH:MM:SS,mmm` timing without positioning settings; minutes/seconds 00–59. Start times nondecreasing and end greater than start; overlapping cues are allowed.
- Nonempty multiline cue text. Markup remains quoted literal text; it does not identify a speaker or approve a decision.
- Each input is at most 2 MiB. Source contains 1–10,000 cues. Selection contains 1–100 items, each explicitly choosing 1–100 distinct existing cue ordinals. Imported evidence totals at most 8 MiB.
- Selection must match exact current original source bytes; stale digest and stale agenda constraints fail. Existing agenda item keys and participants remain subject to ordinary native validation.

This is a local development workflow, not a player, subtitle editor, complete SubRip conformance claim, sender authentication, receipt delivery, provider integration or release qualification. No human decision receipts are synthesized. No native source was changed, so MoonBit formatting/interface regeneration and native test/build gates were not run in this bounded allocation; required unrun broader gates remain blocking.
