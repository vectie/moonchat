# MoonChat documentation

- [Product contract](PRODUCT_CONTRACT.md) — ownership, authority, canonical
  IDs, consumers and promotion boundary.
- [Portable review workflow](../workflows/portable-conversation-review.md) —
  import, decision and projection lifecycle.
- [Review authority policy](../policies/conversation-review-authority.md) —
  agent-versus-human decision boundary.
- [MoonFlow adapter port](../providers/moonflow-review-adapter.port.md) —
  execute, reconcile and short-lived health contract.
- [Root README](../README.mbt.md) — implementation map and focused checks.
- [UI-to-UI use cases](qualification/UI_TO_UI_USE_CASES.md) — qualification
  through MoonFind and MoonBook's existing Rabbita surfaces, with no duplicate
  MoonChat application.

MoonChat intentionally has no standalone application. MoonFind and MoonBook
consume its portable artifacts through their own product workflows.
