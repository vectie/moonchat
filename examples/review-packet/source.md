# Café search release proposal 🌙

Synthetic demonstration, not an authorization to deploy.

## Proposed change
Ship Unicode-normalized matching for café and cafe queries.
The literal example <search query="café"> must remain text in this packet.

## Staged rollout
1. Run the accented-query fixture set in the staging environment.
2. Ask the release reviewer whether the evidence supports rollout.
3. Keep rollback available until the monitored window closes.

## Open issue
The named rollback owner and rehearsal date are not yet recorded.
Approval of the query examples does not resolve that objection.
