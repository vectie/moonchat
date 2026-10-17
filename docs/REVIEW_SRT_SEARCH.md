# Find transcript passages before review

MoonChat supplies source-bound artifact review to other products. For a long
SubRip transcript, discover the relevant original cues before curating a review
item (MOONCHAT-W01/W04).

From the repository root:

```
python3 -B scripts/review_srt.py search examples/review-srt/meeting.srt --text rollback --context 1
python3 -B scripts/review_srt.py search examples/review-srt/meeting.srt --start-ms 1000 --end-ms 6000
```

Search uses casefolded literal text, optionally ANDed with an overlapping time
window. Time bounds are milliseconds and the window is half-open: a cue ending
exactly at the start or beginning exactly at the end is excluded. Omit either
bound for an open end. Context adds up to five neighboring cues on either side.
No regex, tokenization, fuzzy inference or speaker authentication occurs.

The result retains the complete source digest, exact original cue byte spans,
digests and ordinal locators. `matched_ordinals` distinguishes actual hits from
neighbor context. Copy only the ordinals you choose into an item in the existing
SRT selection JSON, with the source digest and your own author/note/decisions.
Then follow [the existing agenda, preview and native bundle workflow](REVIEW_SRT_IMPORT.md).
Search itself never creates a review item or human approval.

No matches returns an empty list. Invalid windows, empty criteria and malformed
SRT fail. Existing SRT input limits apply; results include all matching cues
within the 10,000-cue source limit. Use fresh output paths when redirecting.

Focused Python and retained native composer tests qualify this local journey.
Native source and interfaces are unchanged; no new native build, graphical host
UI, accessibility, provider or full release qualification is claimed.
