///|
/// Serialize the existing v1 wire shape after validating the observed source.
/// Imported historical receipts are preserved, never synthesized or removed.
/// Hash these exact returned bytes if retaining this version as a predecessor.
pub fn serialize_review_bundle(
  bundle : ConversationReviewBundle,
  observed_source_digest : String,
) -> String raise {
  require_valid_bundle(bundle, observed_source_digest)
  bundle.to_json().stringify(indent=2) + "\n"
}

///|
/// Decode with the production v1 decoder and verify against observed bytes.
/// This returns a detached value: importing history cannot mutate its source.
pub fn reimport_review_bundle(
  text : String,
  observed_source_bytes : Bytes,
) -> ConversationReviewBundle raise {
  let bundle = decode_review_bundle(@json.parse(text))
  require_valid_bundle(bundle, review_source_digest(observed_source_bytes))
  bundle
}

///|
/// Link a new pending scope to the exact retained predecessor JSON and source.
/// Both source versions must be supplied as observed bytes. The caller must
/// retain the previous bundle and source at their declared artifact references.
/// No historical decision is inherited, even when the filename is unchanged.
/// Previous entries and receipts remain intact in the referenced old bundle.
pub fn supersede_review_bundle(
  previous_bundle_text : String,
  previous_bundle_ref~ : String,
  previous_source_bytes~ : Bytes,
  next_bundle~ : ConversationReviewBundle,
  next_source_bytes~ : Bytes,
) -> ConversationReviewBundle raise {
  if !safe_artifact_ref(previous_bundle_ref) {
    fail("previous bundle must have a workspace-relative artifact reference")
  }
  let previous = reimport_review_bundle(
    previous_bundle_text, previous_source_bytes,
  )
  require_valid_bundle(next_bundle, review_source_digest(next_source_bytes))
  if previous.review_id != next_bundle.review_id ||
    previous.conversation != next_bundle.conversation {
    fail("supersession must retain the review and conversation identity")
  }
  if previous.source_digest != next_bundle.source_digest &&
    previous.source_revision_id == next_bundle.source_revision_id {
    fail("changed source bytes require a new source revision identity")
  }
  if !next_bundle.decision_receipts.is_empty() {
    fail("a superseding draft cannot inherit or author decision receipts")
  }
  if !next_bundle.previous_bundle_ref.is_empty() ||
    !next_bundle.previous_bundle_digest.is_empty() {
    fail("supersession requires a fresh draft without a predecessor")
  }
  if previous_bundle_ref == previous.source_artifact_ref ||
    previous_bundle_ref == next_bundle.source_artifact_ref {
    fail("previous bundle and both source versions must be separate artifacts")
  }
  let detached = decode_review_bundle(next_bundle.to_json())
  {
    ..detached,
    previous_bundle_ref,
    previous_bundle_digest: review_source_digest(
      @utf8.encode(previous_bundle_text),
    ),
    decision_receipts: [],
  }
}
