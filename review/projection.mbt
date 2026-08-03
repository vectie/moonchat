///|
pub fn review_events(
  bundle : ConversationReviewBundle,
  observed_source_digest : String,
) -> Array[ConversationReviewEvent] raise {
  let issues = bundle_issues(bundle, observed_source_digest)
  if !issues.is_empty() {
    fail("invalid MoonChat review bundle: \{issues.join("; ")}")
  }
  let events : Array[ConversationReviewEvent] = []
  let mut sequence = 0
  events.push({
    contract_id: event_contract_id(),
    review_id: bundle.review_id,
    sequence,
    event_id: "review-opened",
    event_kind: "review_opened",
    actor_participant_id: "moonchat",
    turn_id: "",
    client_turn_id: "",
    command_id: "",
    subject_id: bundle.source_revision_id,
    decision: "",
    body: "Review opened for immutable source evidence.",
    source_digest: bundle.source_digest,
    recorded_at: bundle.recorded_at,
  })
  sequence += 1
  for candidate in bundle.entries {
    events.push({
      contract_id: event_contract_id(),
      review_id: bundle.review_id,
      sequence,
      event_id: "entry-\{candidate.entry_id}",
      event_kind: "entry_recorded",
      actor_participant_id: candidate.author_participant_id,
      turn_id: candidate.turn.turn_id,
      client_turn_id: candidate.turn.client_turn_id,
      command_id: candidate.turn.command_id,
      subject_id: candidate.entry_id,
      decision: "",
      body: candidate.body,
      source_digest: bundle.source_digest,
      recorded_at: bundle.recorded_at,
    })
    sequence += 1
  }
  for required in bundle.required_decisions {
    events.push({
      contract_id: event_contract_id(),
      review_id: bundle.review_id,
      sequence,
      event_id: "required-\{required.decision_id}",
      event_kind: "decision_required",
      actor_participant_id: required.reviewer_participant_id,
      turn_id: "",
      client_turn_id: "",
      command_id: "",
      subject_id: required.subject_entry_id,
      decision: "",
      body: required.prompt,
      source_digest: bundle.source_digest,
      recorded_at: bundle.recorded_at,
    })
    sequence += 1
  }
  for candidate in bundle.decision_receipts {
    events.push({
      contract_id: event_contract_id(),
      review_id: bundle.review_id,
      sequence,
      event_id: "receipt-\{candidate.receipt_id}",
      event_kind: "human_decision_recorded",
      actor_participant_id: candidate.reviewer_participant_id,
      turn_id: "",
      client_turn_id: "",
      command_id: "",
      subject_id: candidate.decision_id,
      decision: candidate.decision,
      body: candidate.rationale,
      source_digest: bundle.source_digest,
      recorded_at: candidate.decided_at,
    })
    sequence += 1
  }
  events.push({
    contract_id: event_contract_id(),
    review_id: bundle.review_id,
    sequence,
    event_id: "review-projected",
    event_kind: "review_projected",
    actor_participant_id: "moonchat",
    turn_id: "",
    client_turn_id: "",
    command_id: "",
    subject_id: bundle.review_id,
    decision: review_status(bundle),
    body: review_outcome_message(bundle),
    source_digest: bundle.source_digest,
    recorded_at: bundle.recorded_at,
  })
  events
}

///|
pub fn project_review_record(
  bundle : ConversationReviewBundle,
  observed_source_digest : String,
  journal_evidence : Array[ReviewEvidence],
) -> ConversationReviewRecord raise {
  let issues = bundle_issues(bundle, observed_source_digest)
  if !issues.is_empty() {
    fail("invalid MoonChat review bundle: \{issues.join("; ")}")
  }
  let status = review_status(bundle)
  {
    contract_id: record_contract_id(),
    operation_ref: operation_ref(),
    input_schema_ref: input_schema_ref(),
    output_schema_ref: output_schema_ref(),
    review_id: bundle.review_id,
    source_artifact_ref: bundle.source_artifact_ref,
    source_digest: bundle.source_digest,
    source_revision_id: bundle.source_revision_id,
    previous_bundle_ref: bundle.previous_bundle_ref,
    previous_bundle_digest: bundle.previous_bundle_digest,
    conversation: bundle.conversation,
    participants: bundle.participants,
    entries: bundle.entries,
    required_decisions: bundle.required_decisions,
    decision_receipts: bundle.decision_receipts,
    review_status: status,
    accepted: status == "accepted",
    claim_class: claim_class(bundle),
    missing_decision_ids: missing_decision_ids(bundle),
    rejected_decision_ids: rejected_decision_ids(bundle),
    journal_evidence,
    recorded_at: bundle.recorded_at,
  }
}

///|
pub fn decode_review_bundle(value : Json) -> ConversationReviewBundle raise {
  @json.from_json(value) catch {
    _ => fail("MoonChat review bundle does not match the portable v1 contract")
  }
}

///|
pub fn decode_review_record(value : Json) -> ConversationReviewRecord raise {
  @json.from_json(value) catch {
    _ => fail("MoonChat review record does not match the portable v1 contract")
  }
}
