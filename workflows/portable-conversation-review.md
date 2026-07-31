# Portable conversation review

Contract: `moonchat.portable-conversation-review.v1`

1. A producer exports a `moonchat/conversation-review-bundle@1.0.0`.
2. The bundle binds one immutable source artifact and digest, the MoonLib
   `moonsuite-conversation.v1` identity, participants and exact turn IDs.
3. Questions, objections and proposals are recorded as separate entries.
   Every objection must be named by a required human decision.
4. MoonChat validates the source digest, preserves the bundle as immutable
   events and emits a deterministic review record.
5. The record stays `pending_review` while a required receipt is absent or
   deferred. A complete rejection stays `research-evidence`. Only unanimous
   named approvals for all required decisions produce `accepted-knowledge`.
6. A later version imports the previous artifact and digest, then appends a new
   content-addressed version. Existing event evidence is never rewritten.

MoonChat records the review. It does not conduct the conversation, call a
model, choose reviewers or publish accepted material into a book.
