# MoonChat responsibility and testability

MoonChat is portable review functionality, not a chat application. It owns the
versioned review overlay and deterministic evidence projection consumed by
other applications.

| Responsibility | Owner | Primary evidence | Proportional verification |
| --- | --- | --- | --- |
| Review bundle, participants, decisions and receipts | `review/types.mbt`, `review/validation.mbt` | versioned JSON record and validation issues | `moon test review` |
| Plain-language outcome and recovery guidance | `review/operator_guidance.mbt` | final `review_projected` event body | focused pending, rejected and accepted projections |
| Append-only materialization | `flow_adapter/` | content-addressed events, record and native receipt | native execute/reconcile tests |
| Visible forms and navigation | Producer/receiver application | its UI state and screenshots | consumer-owned UI-to-UI qualification |
| Agent execution | MoonClaw | MoonClaw evidence | excluded |

MoonFind or another producer collects the decision. MoonBook or another
receiver decides whether the accepted review can become durable domain truth.
MoonChat never supplies reviewer authority and never creates `/apps/moonchat`.

Authoritative references:

- [Product contract](PRODUCT_CONTRACT.md)
- [Consumer UX contract](CONSUMER_UX.md)
- [UI-to-UI qualification](qualification/UI_TO_UI_USE_CASES.md)
