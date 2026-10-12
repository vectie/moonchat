///|
/// Draft a question, objection or proposal without recording a human decision.
/// The host supplies stable turn identities and explicitly chooses the author.
/// Evidence arrays are copied, so later edits to a form cannot change the draft.
pub fn draft_review_entry(
  entry_kind : String,
  entry_id~ : String,
  author_participant_id~ : String,
  turn~ : ConversationTurnIdentity,
  body~ : String,
  evidence_refs? : Array[String] = [],
) -> ReviewEntry raise {
  if !["question", "objection", "proposal"].contains(entry_kind) {
    fail("review entry kind must be question, objection or proposal")
  }
  if !safe_identifier(entry_id) || !safe_identifier(author_participant_id) {
    fail("review entry and author require safe stable identifiers")
  }
  if !non_empty(body) {
    fail("review entry body is required")
  }
  if !non_empty(turn.turn_id) ||
    !non_empty(turn.client_turn_id) ||
    !non_empty(turn.command_id) {
    fail("review entry requires all MoonLib turn identities")
  }
  let issues : Array[String] = []
  validate_ref_array("review entry", evidence_refs, issues)
  if !issues.is_empty() {
    fail(issues.join("; "))
  }
  {
    entry_id,
    entry_kind,
    author_participant_id,
    turn,
    body,
    evidence_refs: evidence_refs.copy(),
  }
}

///|
/// Name the human who must decide. The objection author is never selected
/// automatically. This is a requirement, not a receipt or authorization grant.
pub fn draft_required_decision(
  decision_id~ : String,
  subject_entry_id~ : String,
  reviewer~ : ReviewParticipant,
  prompt~ : String,
) -> RequiredDecision raise {
  if !safe_identifier(decision_id) || !safe_identifier(subject_entry_id) {
    fail("required decision and subject require safe stable identifiers")
  }
  if reviewer.participant_kind != "human" ||
    !safe_identifier(reviewer.participant_id) ||
    !non_empty(reviewer.display_name) {
    fail("required decision owner must be an explicitly named human")
  }
  if !non_empty(prompt) {
    fail("required decision prompt is required")
  }
  {
    decision_id,
    subject_entry_id,
    reviewer_participant_id: reviewer.participant_id,
    prompt,
  }
}

///|
/// Hash the exact observed source bytes, including whitespace and newlines.
///
/// ```mbt check
/// test {
///   assert_eq(
///     @review.review_source_digest(b"abc"),
///     "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
///   )
/// }
/// ```
pub fn review_source_digest(source_bytes : Bytes) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(source_bytes))}"
}

///|
/// Produce a validated, pending v1 bundle bound to observed source bytes.
/// No authoring API creates decision receipts. Storage, constituent snapshot
/// verification, human identity and any later decision UI remain host-owned.
pub fn draft_review_bundle(
  review_id~ : String,
  source_artifact_ref~ : String,
  source_bytes~ : Bytes,
  source_revision_id~ : String,
  conversation~ : ConversationBinding,
  participants~ : Array[ReviewParticipant],
  entries~ : Array[ReviewEntry],
  required_decisions~ : Array[RequiredDecision],
  recorded_at~ : String,
) -> ConversationReviewBundle raise {
  let bundle : ConversationReviewBundle = {
    contract_id: bundle_contract_id(),
    review_id,
    source_artifact_ref,
    source_digest: review_source_digest(source_bytes),
    source_revision_id,
    previous_bundle_ref: "",
    previous_bundle_digest: "",
    conversation,
    participants: participants.copy(),
    entries: entries.map(candidate => {
      ..candidate,
      evidence_refs: candidate.evidence_refs.copy(),
    }),
    required_decisions: required_decisions.copy(),
    decision_receipts: [],
    recorded_at,
  }
  require_valid_bundle(bundle, bundle.source_digest)
  bundle
}

///|
fn require_valid_bundle(
  bundle : ConversationReviewBundle,
  observed_source_digest : String,
) -> Unit raise {
  let issues = bundle_issues(bundle, observed_source_digest)
  if !issues.is_empty() {
    fail("invalid MoonChat review bundle: \{issues.join("; ")}")
  }
}
