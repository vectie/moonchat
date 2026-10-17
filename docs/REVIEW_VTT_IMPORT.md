# Review selected WebVTT meeting cues

For long transcripts, [find cues by voice, words and time](REVIEW_VTT_SEARCH.md)
before choosing evidence for the review.

Use the local CLI to turn recorded meeting cues into a source-bound pending
MoonChat review. No transcription service, media playback, speaker authentication,
model, network request, or approval is involved. This workflow requires Python 3
and the existing native `cmd/review_compose` executable.

1. Retain the original UTF-8 `.vtt` file. List its one-based cue numbers:
   `python3 scripts/review_vtt.py cues examples/review-vtt/meeting.vtt`
2. Copy `examples/review-vtt/selection.json`. Set review/conversation IDs, source
   reference and revision, explicit timestamp, participants, and review items.
   Each item names `cues`, a written question/proposal/objection, an author, and
   explicit named-human decision requests. Cue speaker labels do not select a
   participant or grant identity. Only selected cues are included; this is not a
   claim that all meeting dissent has been captured. Review the full cue listing.
3. Prepare an editable ordinary agenda:
   `python3 scripts/review_vtt.py agenda meeting.vtt selection.json > agenda.json`
4. Preview or compile directly through the existing composer:
   `python3 scripts/review_vtt.py preview meeting.vtt selection.json --composer /absolute/path/review_compose.exe`
   `python3 scripts/review_vtt.py bundle meeting.vtt selection.json --composer /absolute/path/review_compose.exe > pending-review.json`

Do not redirect output over an input. Keep the exact VTT alongside the review at
its declared source reference. Bundle creation uses an immutable in-memory-read
snapshot copied byte-for-byte to the local composer, including original BOM and
line endings. The composer hashes that exact source and enforces the established
participant, decision, and pending-review contract. It never adds decision receipts.
Later source changes require a new source revision and the existing linked agenda
revision workflow. The intermediate `agenda` mode is authoring data; the composer
remains the canonical validator and preview.

Timing labels and verbatim multiline text are retained in source order. Repeated
cue identifiers and overlapping cues are valid; one-based ordinal selection makes
them unambiguous. WEBVTT metadata, NOTE, STYLE and REGION blocks are not executed
or included as cue evidence. Voice markup stays literal recorded text. Empty,
malformed, backwards-timed, non-UTF-8, NUL-containing or oversized inputs fail
without invoking the composer. Limits: 2 MiB per input, 10,000 cues, 256 items,
and 256 selected cues per item. This is a bounded text reader, not a full WebVTT
renderer or media validator; unsupported timing syntax is rejected.

Continue with [review agendas](REVIEW_AGENDA.md), then the existing
[source-bound reviewer choices](REVIEW_DECISIONS.md) in an identity-verifying host.

## Build the existing composer in another checkout

Use the project's pinned MoonBit installation and exact dependencies in
`moon.mod`, already resolved into the checkout. Do not update dependencies for
this workflow. From the source root, set absolute, external build/private-home
paths and retain the installed toolchain in `MOON_HOME`/`PATH`:

```sh
export WORKER_ROOT=/absolute/external/moonchat-worker
export HOME="$WORKER_ROOT/home"
export XDG_CACHE_HOME="$WORKER_ROOT/cache" XDG_CONFIG_HOME="$WORKER_ROOT/config"
export XDG_DATA_HOME="$WORKER_ROOT/data" XDG_STATE_HOME="$WORKER_ROOT/state"
export XDG_RUNTIME_DIR="$WORKER_ROOT/runtime" TMPDIR="$WORKER_ROOT/tmp"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$TMPDIR"
export BUILD_ROOT=/absolute/external/moonchat-build
export MOON_NATIVE_LOCK=/absolute/external/moon-native.lock
flock "$MOON_NATIVE_LOCK" moon build cmd/review_compose --frozen --target native --strip -j 1 --target-dir "$BUILD_ROOT"
export MOONCHAT_COMPOSER="$BUILD_ROOT/native/debug/build/cmd/review_compose/review_compose.exe"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_review_vtt.py
```

Use that executable with `--composer`. The batch replay runner separately verifies
its retained compiler output; a fresh local build runs the same source tests via
the final command above and does not need the batch's retained binary.
