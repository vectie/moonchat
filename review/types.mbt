///|
pub(all) struct ConversationBinding {
  contract_id : String
  protocol : String
  product_id : String
  conversation_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReviewParticipant {
  participant_id : String
  display_name : String
  participant_kind : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ConversationTurnIdentity {
  turn_id : String
  client_turn_id : String
  command_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReviewEntry {
  entry_id : String
  entry_kind : String
  author_participant_id : String
  turn : ConversationTurnIdentity
  body : String
  evidence_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RequiredDecision {
  decision_id : String
  subject_entry_id : String
  reviewer_participant_id : String
  prompt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct HumanDecisionReceipt {
  receipt_id : String
  decision_id : String
  reviewer_participant_id : String
  reviewer_name : String
  decision : String
  rationale : String
  source_digest : String
  decided_at : String
  evidence_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ConversationReviewBundle {
  contract_id : String
  review_id : String
  source_artifact_ref : String
  source_digest : String
  source_revision_id : String
  previous_bundle_ref : String
  previous_bundle_digest : String
  conversation : ConversationBinding
  participants : Array[ReviewParticipant]
  entries : Array[ReviewEntry]
  required_decisions : Array[RequiredDecision]
  decision_receipts : Array[HumanDecisionReceipt]
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ReviewEvidence {
  artifact_ref : String
  digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ConversationReviewEvent {
  contract_id : String
  review_id : String
  sequence : Int
  event_id : String
  event_kind : String
  actor_participant_id : String
  turn_id : String
  client_turn_id : String
  command_id : String
  subject_id : String
  decision : String
  body : String
  source_digest : String
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ConversationReviewRecord {
  contract_id : String
  operation_ref : String
  input_schema_ref : String
  output_schema_ref : String
  review_id : String
  source_artifact_ref : String
  source_digest : String
  source_revision_id : String
  previous_bundle_ref : String
  previous_bundle_digest : String
  conversation : ConversationBinding
  participants : Array[ReviewParticipant]
  entries : Array[ReviewEntry]
  required_decisions : Array[RequiredDecision]
  decision_receipts : Array[HumanDecisionReceipt]
  review_status : String
  accepted : Bool
  claim_class : String
  missing_decision_ids : Array[String]
  rejected_decision_ids : Array[String]
  journal_evidence : Array[ReviewEvidence]
  recorded_at : String
} derive(Debug, Eq, ToJson, FromJson)
