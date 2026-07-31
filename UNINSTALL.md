# MoonChat uninstall contract

Uninstalling the executable pack may remove code, declarations and generated
cache, but must preserve user-owned review evidence:

- `.moonsuite/products/moonchat/reviews/`
- `.moonsuite/products/moonchat/idempotency/`

Upgrade migrations must remain able to read v1 bundle, event, receipt and
record contracts. Destructive evidence cleanup requires a separately
authorized user action.
