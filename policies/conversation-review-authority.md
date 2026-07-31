# Conversation review authority

The operation `moonchat/conversation.review.record@0.1.0` requires only
`workspace-mutation` authority.

- Agent participants may ask questions, object and propose.
- Agents cannot sign decision receipts or promote their own suggestions.
- Each required decision binds one participant declared as `human`; the
  receipt must preserve that participant's stable ID and display name.
- Missing and deferred decisions remain `pending_review`.
- A human rejection closes the review as `rejected`, without an
  `accepted-knowledge` claim.
- All named human approvals promote only the bound review record. MoonBook
  still owns durable accepted book material and any later closure/import.
- MoonChat never requests external-effect, physical-effect, provider, model or
  publication authority.
