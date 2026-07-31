# MoonChat product contract

Class: portable review-contract pack and library
Maturity: native v1 capability; consumer wiring remains product-owned
Last reviewed: 2026-07-31

## Outcome

MoonChat turns a versioned conversation review bundle into replayable,
append-only review evidence without creating another conversation or agent
runtime.

## Ownership

MoonLib continues to own the base `moonsuite-conversation.v1` contract.
MoonChat owns only the overlay required to review a source artifact:
participant and turn bindings, questions, objections, proposals, decision
requirements, named-human receipts, immutable event evidence and the projected
review status.

MoonClaw owns live agent conversations and execution. MoonDesk owns their
desktop projection. MoonBook owns accepted durable book knowledge. MoonChat
does not call any of them and does not need its own Rabbita application.

## Capability status

| Capability | Status |
| --- | --- |
| Product identity and suite-layout helpers | available |
| MoonLib conversation identity consumption | available |
| Portable review bundle/record v1 | available |
| Append-only, content-addressed review journal | available |
| MoonFlow v2 execute/reconcile/health adapter | available |
| MoonFind stakeholder-review consumption | intended integration |
| MoonBook closure/import consumption | intended integration |
| Standalone chat application | excluded |
| Agent or model runtime | excluded |

## Canonical identities

- Operation: `moonchat/conversation.review.record@0.1.0`
- Input: `moonchat/conversation-review-bundle@1.0.0`
- Output: `moonchat/conversation-review-record@1.0.0`
- Adapter: `moonchat-review-v1`
- Protocol: `moonflow.adapter.v2`

The adapter claim ceiling is `accepted-knowledge`, but that is a ceiling rather
than a default. Missing/deferred decisions remain `pending_review`; a rejection
remains research evidence. Only complete approvals from the named human
reviewers produce an accepted record.

## Import, export and versioning

The JSON input and output schemas are the portable import/export boundary.
Every version binds the source artifact, source digest and source revision.
Later versions may bind a previous bundle artifact and digest. The adapter
writes create-new event files under a content-addressed version directory and
never updates an earlier event.

Consumer-specific projection remains outside MoonChat:

- MoonFind may construct the bundle and bind its review work item to this
  operation.
- MoonBook may use an accepted record as closure evidence, but separately
  decides whether and how to import material into a book.

## Verification

```sh
moon test review
moon test flow_adapter --target native
moon check
moon info
moon fmt
scripts/fresh-suite-product-home-smoke.sh
```

## Product decision

MoonChat is now a callable contract pack, not a standalone application.
Promotion to a user-facing application is still unjustified. A future UI would
require a distinct user journey that cannot be cleanly projected by an
existing host; repository existence alone is not a reason to create one.
