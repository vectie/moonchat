///|
pub fn bundle_contract_id() -> String {
  "moonchat.conversation-review-bundle.v1"
}

///|
pub fn record_contract_id() -> String {
  "moonchat.conversation-review-record.v1"
}

///|
pub fn event_contract_id() -> String {
  "moonchat.conversation-review-event.v1"
}

///|
pub fn operation_ref() -> String {
  "moonchat/conversation.review.record@0.1.0"
}

///|
pub fn input_schema_ref() -> String {
  "moonchat/conversation-review-bundle@1.0.0"
}

///|
pub fn output_schema_ref() -> String {
  "moonchat/conversation-review-record@1.0.0"
}

///|
pub fn conversation_contract_id() -> String {
  @conversation.contract_id()
}

///|
pub fn conversation_identity_fields() -> Array[String] {
  @conversation.identity_fields()
}
