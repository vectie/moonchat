# Narrow a synthetic pilot configuration

The source proposes an enabled pilot for 500 users in two regions with no named
rollback owner. The retained review objects to its breadth and asks for an
owner. `selected-edits.json` explicitly prepares a disabled 50-user, west-only
candidate and names a synthetic role. These changes do not resolve either
question or grant permission to launch anything.

Follow [the guide](../../docs/REVIEW_JSON_EDITS.md) to catalog, draft, preview,
export, and reopen the candidate in existing review consumers. `review.json`
was composed from `agenda.json` and the exact `source.json` fixture. Generated
`candidate-source.json`, `candidate-review.json` and `preview.md` demonstrate
the result; keep the source and bundle's exact bytes together. The checked-in
readable preview trims presentation-only trailing spaces and blank lines.

The untouched `allocation_id` and `reference_ratio` demonstrate preserving
values beyond binary floating-point precision while other fields change.
All identities and decisions are synthetic; there are no authenticated receipts.
