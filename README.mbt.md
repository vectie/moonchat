# MoonChat

> **Portable review-contract pack · not a chat application or agent runtime.**
> Read the [product contract](docs/PRODUCT_CONTRACT.md) for the authority and
> ownership boundary.

MoonChat records reviewable conversations as portable, append-only evidence.
It consumes MoonLib's shared `moonsuite-conversation.v1` identity contract and
adds only the review-specific layer: questions, objections, proposals,
required decisions and named-human receipts.

The canonical capability is:

```text
moonchat/conversation.review.record@0.1.0
```

It can emit a pending or rejected research record. It emits
`accepted-knowledge` only when every required decision has a valid approval
receipt from its named human reviewer.

## Scope And Boundary

MoonChat owns:

- product identity for `moonchat`
- shared MoonSuite state, service, cache, temp, and accepted-output paths
- the versioned conversation-review bundle and record contracts
- append-only review events and content-addressed version lineage
- agent-suggestion versus human-decision authority checks
- the pack-local MoonFlow v2 execute, reconcile and short-lived health adapter

MoonChat does not own agent execution, model routing, desktop UI, durable
book truth, or town scheduling. MoonClaw owns execution, Moondesk owns the
desktop projection, MoonBook owns durable accepted material, and Moontown owns
coordination.

## Implementation Map

- `moonchat.mbt`: product identity.
- `moonsuite_layout.mbt`: thin adapters over `@moonsuite` for MoonChat product
  paths.
- `review/`: portable review contracts, validation and deterministic
  projection.
- `flow_adapter/` and `cmd/moonflow_adapter/`: durable MoonFlow v2 adapter.
- `pack.json`, `schemas/`, `policies/`, `workflows/`, `providers/`: capability
  truth and operating boundary.
- `cmd/main/`: minimal CLI entrypoint.
- `moonchat_test.mbt`, `review/*_test.mbt` and
  `flow_adapter/*_wbtest.mbt`: focused contract and restart tests.
- `scripts/fresh-suite-product-home-smoke.sh`: shell smoke for fresh-suite
  product-home behavior.

## Testing Guidance

Run focused checks before changing the review contracts:

```sh
moon check
moon test review
moon test flow_adapter --target native
moon info
moon fmt
```

For layout changes, also run:

```sh
scripts/fresh-suite-product-home-smoke.sh
```

Review `pkg.generated.mbti` after `moon info`; any new public type or function
should be deliberate because other MoonSuite products may consume it.

## Worth Noticing

- Product paths must go through MoonLib `@moonsuite`, not local string
  concatenation.
- Selected `books/<book-id>` roots should resolve product state through the
  owning suite root, while accepted outputs remain book-scoped.
- MoonLib owns the base conversation DTO contract; MoonChat does not fork it.
- Agent-authored proposals and objections never count as decision receipts.
- Keep the package independent from UI frameworks and model-provider code.

## Intended consumers

- MoonFind exports a stakeholder-review bundle and consumes the resulting
  pending/accepted record in a compiled MoonFlow graph.
- MoonBook may import an accepted record as evidence for Bookkeeper closure,
  but performs its own closure and acceptance checks.

These product integrations are consumers of this contract, not new MoonChat
runtimes or applications.
