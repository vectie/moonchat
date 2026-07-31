# MoonFlow review adapter port

Adapter: `moonchat-review-v1`
Protocol: `moonflow.adapter.v2`

The native adapter exposes:

- `capability`
- `execute --workspace --request --result`
- `reconcile --workspace --request --result`
- `health --workspace --checked-at --valid-until
  --checked-at-epoch-seconds --valid-until-epoch-seconds --evidence
  --attestation`

Execution and reconciliation use content-addressed, create-new workspace
artifacts plus an idempotency receipt. Reconciliation may safely finish an
interrupted projection because MoonChat has no external or physical effect.
Health attestations expire within 300 seconds and bind exact operation and
schema identities.
