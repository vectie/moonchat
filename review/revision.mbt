///|
/// Editable preparation data for an imported review, never a decision receipt.
/// The base digest covers exact predecessor JSON bytes, including whitespace.
/// Keep existing host entry, turn and decision identities when editing a point.
pub(all) struct ReviewRevisionDraft {
  format : String
  base_bundle_digest : String
  review_id : String
  conversation : ConversationBinding
  source_artifact_ref : String
  source_revision_id : String
  recorded_at : String
  participants : Array[ReviewParticipant]
  entries : Array[ReviewEntry]
  required_decisions : Array[RequiredDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
/// Reopen a valid received review without its original authoring agenda.
/// Copies all editable discussion data and host identities, not old receipts.
/// Retain the original bundle and source to compile a linked pending revision.
pub fn prepare_review_revision(
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
) -> ReviewRevisionDraft raise {
  let previous = reimport_review_bundle(
    previous_bundle_text, previous_source_bytes,
  )
  {
    format: "moonchat.review-revision.v1",
    base_bundle_digest: review_source_digest(@utf8.encode(previous_bundle_text)),
    review_id: previous.review_id,
    conversation: previous.conversation,
    source_artifact_ref: previous.source_artifact_ref,
    source_revision_id: previous.source_revision_id,
    recorded_at: previous.recorded_at,
    participants: previous.participants,
    entries: previous.entries,
    required_decisions: previous.required_decisions,
  }
}

///|
pub fn parse_review_revision(text : String) -> ReviewRevisionDraft raise {
  let json = @json.parse(text)
  guard json is Object(fields) else {
    fail("review revision draft must be a JSON object")
  }
  let allowed = [
    "format", "base_bundle_digest", "review_id", "conversation", "source_artifact_ref",
    "source_revision_id", "recorded_at", "participants", "entries", "required_decisions",
  ]
  for key, _ in fields {
    if !allowed.contains(key) {
      fail("unsupported review revision field: " + key)
    }
  }
  let draft : ReviewRevisionDraft = @json.from_json(json)
  if draft.format != "moonchat.review-revision.v1" {
    fail("review revision format must be moonchat.review-revision.v1")
  }
  draft
}

///|
/// Compile edited discussion into the existing v1 bundle, preserving its host
/// conversation and exact predecessor link. All decisions must be made anew.
/// This never modifies the supplied draft or the retained predecessor evidence.
pub fn compile_review_revision(
  draft : ReviewRevisionDraft,
  source_bytes : Bytes,
  previous_bundle_text~ : String,
  previous_source_bytes~ : Bytes,
  previous_bundle_ref~ : String,
) -> ConversationReviewBundle raise {
  if draft.format != "moonchat.review-revision.v1" {
    fail("review revision format must be moonchat.review-revision.v1")
  }
  if draft.base_bundle_digest !=
    review_source_digest(@utf8.encode(previous_bundle_text)) {
    fail("revision draft does not match the exact predecessor bundle bytes")
  }
  // The existing supersession API validates both source scopes, requires the
  // original complete host conversation identity, and rejects receipt reuse.
  let next = draft_review_bundle(
    review_id=draft.review_id,
    source_artifact_ref=draft.source_artifact_ref,
    source_bytes~,
    source_revision_id=draft.source_revision_id,
    conversation=draft.conversation,
    participants=draft.participants,
    entries=draft.entries,
    required_decisions=draft.required_decisions,
    recorded_at=draft.recorded_at,
  )
  supersede_review_bundle(
    previous_bundle_text,
    previous_bundle_ref~,
    previous_source_bytes~,
    next_bundle=next,
    next_source_bytes=source_bytes,
  )
}
