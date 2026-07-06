# MoonChat

MoonChat is the lightweight conversation contract product for MoonSuite. Its
current implementation is intentionally small: it names the product, exposes
MoonSuite product-home helpers through MoonLib, and provides the first place to
keep chat-oriented contracts from being mixed into Moondesk UI code or
MoonClaw runtime code.

## Scope And Boundary

MoonChat owns chat-shaped product contracts:

- product identity for `moonchat`
- shared MoonSuite state, service, cache, temp, and accepted-output paths
- future conversation/session DTOs that are not specific to Moondesk MoonCode
  or MoonClaw jobs
- future chat import/export surfaces that can be reused by multiple products

MoonChat does not own agent execution, model routing, desktop UI, durable
book truth, or town scheduling. MoonClaw owns execution, Moondesk owns the
desktop projection, MoonBook owns durable accepted material, and Moontown owns
coordination.

## Implementation Map

- `moonchat.mbt`: product identity.
- `moonsuite_layout.mbt`: thin adapters over `@moonsuite` for MoonChat product
  paths.
- `cmd/main/`: minimal CLI entrypoint.
- `moonchat_test.mbt` and `moonchat_wbtest.mbt`: contract and whitebox tests.
- `scripts/fresh-suite-product-home-smoke.sh`: shell smoke for fresh-suite
  product-home behavior.

## Testing Guidance

Run the MoonBit checks before changing public contracts:

```sh
moon check
moon test
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
- Keep the package independent from UI frameworks and model-provider code.

## Future Plan

- Add shared append-only conversation DTOs once Moondesk MoonCode and MoonClaw
  stream contracts stabilize.
- Add import/export helpers for plain chat archives and book-linked chat
  summaries.
- Keep execution controls outside MoonChat; this package should describe
  conversations, not run them.
