# MoonChat UI-to-UI qualification

Last reviewed: 2026-07-31

MoonChat intentionally has no standalone application entrypoint. It is a
portable review-contract pack, not a second chat UI or agent runtime. Operators
see its input in MoonFind's existing Rabbita research-review panel and see the
accepted deliverable in MoonBook's existing Rabbita Bookkeeper console.
MoonClaw remains the only agent runtime and MoonFlow remains the generic
orchestrator.

Therefore “MoonChat UI-to-UI” means:

```text
MoonFind review form
  → MoonChat append-only review operation
  → MoonFind verified result state
  → MoonBook existing Bookkeeper UI
```

It does not mean creating `/apps/moonchat`.

## MC-01 — accepted portable review

Prerequisites:

- MoonFind MF-03 produced `moonchat-review-bundle.json`.
- The bound source artifact is unchanged.
- Every required decision has a receipt from its named human owner.
- The MoonChat adapter is invoked by MoonFlow, or with the equivalent
  pack-local adapter command documented in
  MoonFind's cross-product qualification guide.

Operator-visible sequence:

1. In MoonFind, confirm the durable state is `awaiting-moonchat`.
2. Confirm the shown operation is
   `moonchat/conversation.review.record@0.1.0`.
3. Execute/reconcile that exact operation through MoonFlow.
4. Reload MoonFind.
5. Confirm the durable state is `ready-for-bookkeeper`, with an exact review
   record and MoonBook submission reference.
6. Open MoonBook's existing Rabbita console; do not look for a MoonChat app.

Expected evidence:

```text
<workspace>/.moonsuite/products/moonchat/reviews/<review-id>/versions/<digest>/conversation-review-record.json
<workspace>/.moonsuite/products/moonchat/reviews/<review-id>/versions/<digest>/events/
<workspace>/.moonsuite/products/moonchat/idempotency/<key>/native-receipt.json
```

Expected status:

- `accepted` only if every required decision has a valid named-human approval;
- claim class `accepted-knowledge` only for that complete accepted record;
- no MoonBook authority, capability activation, or publication receipt.

## MC-N1 — missing or deferred decision

Use a valid bundle whose required decision has no receipt, or whose named human
chose `defer`.

Expected result:

- the append-only record is projected and retained;
- review status is `pending_review`;
- claim class remains `research-evidence`;
- a work item requiring only `research-evidence` succeeds, while a work item
  requiring `accepted-knowledge` fails with
  `named-human-decisions-incomplete`;
- MoonFind cannot prepare the MoonBook outcome submission.

The retained record is a governed result. Failure against an
`accepted-knowledge` requirement is the correct claim-boundary denial, not
loss of the review evidence.

## MC-N2 — rejection

Use a valid named-human `reject` receipt.

Expected result:

- review status is `rejected`;
- the rejected decision id is preserved;
- no accepted-knowledge claim is emitted;
- MoonFind does not promote the synthesis to MoonBook.

## MC-N3 — malicious or mismatched evidence

After bundle creation, change the bound source bytes, substitute a record from
another run, or let an agent participant sign a human-owned decision.

Expected result:

- MoonChat fails closed before producing a valid record;
- no previous append-only event is overwritten;
- reconciliation cannot turn mismatched evidence into success.

Recovery is to restore the exact bound artifact or create a new versioned
bundle and attempt. Never edit an accepted record in place.

## 2026-07-31 consolidated observation

The `humanoid-cross-paper-demo` qualification used a synthetic operator
identity to choose **Request changes** in MoonFind. MoonChat retained the
append-only conversation record with:

- review status `pending_review`;
- claim class `research-evidence`;
- decision `defer`;
- all three exact rejected idea ids and the Three-Gap rationale;
- an immutable native receipt and event journal.

The MoonFlow-equivalent request required `accepted-knowledge`, so the adapter
correctly returned `named-human-decisions-incomplete`. MoonFind rejected that
failed result and did not create a MoonBook outcome submission. This qualifies
MC-N1 and the claim ceiling; it does not qualify MC-01 or MoonBook acceptance.
No human approval or Bookkeeper authority was invented for the test.

Retained evidence:

```text
_build/ui-to-ui/2026-07-31-consolidated/moonchat-result.json
_build/ui-to-ui/2026-07-31-consolidated/conversation-review-record.json
_build/ui-to-ui/2026-07-31-consolidated/native-receipt.json
```

## Qualification record

```text
date:
operator:
MoonChat commit:
producer run:
review id:
bundle digest:
MC-01: PASS | FAIL | BLOCKED
MC-N1: PASS | FAIL | BLOCKED
MC-N2: PASS | FAIL | BLOCKED
MC-N3: PASS | FAIL | BLOCKED
record ref:
native receipt ref:
MoonFind visible state:
MoonBook visible state:
notes:
```
