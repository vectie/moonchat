///|
/// Reusable preparation content. Roles are slots, not verified people.
pub(all) struct ReviewChecklist {
  format : String
  checklist_id : String
  title : String
  roles : Array[String]
  variables : Array[String]
  items : Array[ReviewChecklistItem]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct ReviewChecklistItem {
  key : String
  kind : String
  author_role : String
  body : String
  decisions : Array[ReviewChecklistDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct ReviewChecklistDecision {
  reviewer_role : String
  prompt : String
} derive(Eq, ToJson, @json.FromJson)

///|
/// Explicit values for one new source-bound review. It carries no receipts.
pub(all) struct ReviewChecklistInput {
  format : String
  checklist_id : String
  review_id : String
  conversation_id : String
  source_artifact_ref : String
  source_revision_id : String
  source_digest : String
  recorded_at : String
  participants : Array[ReviewParticipant]
  role_assignments : Array[ReviewChecklistRole]
  values : Array[ReviewChecklistValue]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct ReviewChecklistRole {
  role : String
  participant_id : String
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct ReviewChecklistValue {
  variable : String
  value : String
} derive(Eq, ToJson, @json.FromJson)
