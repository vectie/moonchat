///|
fn non_empty(value : String) -> Bool {
  !value.trim().is_empty()
}

///|
fn sha256_digest(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for ch in value[7:] {
    if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
      return false
    }
  }
  true
}

///|
fn safe_identifier(value : String) -> Bool {
  if value.is_empty() || value == "." || value == ".." {
    return false
  }
  for ch in value {
    if !((ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.') {
      return false
    }
  }
  true
}

///|
fn safe_artifact_ref(reference : String) -> Bool {
  let normalized = reference.trim().replace(old="\\", new="/")
  !normalized.is_empty() &&
  !normalized.has_prefix("/") &&
  !normalized
  .split("/")
  .any(part => part.is_empty() || part == "." || part == "..")
}

///|
fn canonical_utc_timestamp(value : String) -> Bool {
  value.length() == 20 &&
  value[4] == '-' &&
  value[7] == '-' &&
  value[10] == 'T' &&
  value[13] == ':' &&
  value[16] == ':' &&
  value[19] == 'Z'
}

///|
fn participant(
  participants : Array[ReviewParticipant],
  participant_id : String,
) -> ReviewParticipant? {
  for candidate in participants {
    if candidate.participant_id == participant_id {
      return Some(candidate)
    }
  }
  None
}

///|
fn entry(entries : Array[ReviewEntry], entry_id : String) -> ReviewEntry? {
  for candidate in entries {
    if candidate.entry_id == entry_id {
      return Some(candidate)
    }
  }
  None
}

///|
fn requirement(
  requirements : Array[RequiredDecision],
  decision_id : String,
) -> RequiredDecision? {
  for candidate in requirements {
    if candidate.decision_id == decision_id {
      return Some(candidate)
    }
  }
  None
}

///|
fn receipt(
  receipts : Array[HumanDecisionReceipt],
  decision_id : String,
) -> HumanDecisionReceipt? {
  for candidate in receipts {
    if candidate.decision_id == decision_id {
      return Some(candidate)
    }
  }
  None
}

///|
fn duplicate(values : Array[String], value : String) -> Bool {
  values.contains(value)
}

///|
fn validate_ref_array(
  label : String,
  references : Array[String],
  issues : Array[String],
) -> Unit {
  for reference in references {
    if !safe_artifact_ref(reference) {
      issues.push("\{label} contains unsafe artifact ref: \{reference}")
    }
  }
}

///|
pub fn bundle_issues(
  bundle : ConversationReviewBundle,
  observed_source_digest : String,
) -> Array[String] {
  let issues : Array[String] = []
  if bundle.contract_id != bundle_contract_id() {
    issues.push("bundle contract_id must be \{bundle_contract_id()}")
  }
  if !safe_identifier(bundle.review_id) {
    issues.push("review_id must be a safe stable identifier")
  }
  if !safe_artifact_ref(bundle.source_artifact_ref) {
    issues.push("source_artifact_ref must be workspace-relative")
  }
  if !sha256_digest(bundle.source_digest) {
    issues.push("source_digest must be a lowercase sha256 digest")
  } else if bundle.source_digest != observed_source_digest {
    issues.push("source artifact is stale or has been replaced")
  }
  if !non_empty(bundle.source_revision_id) {
    issues.push("source_revision_id is required")
  }
  if bundle.previous_bundle_ref.is_empty() !=
    bundle.previous_bundle_digest.is_empty() {
    issues.push("previous bundle ref and digest must be supplied together")
  }
  if !bundle.previous_bundle_ref.is_empty() &&
    (
      !safe_artifact_ref(bundle.previous_bundle_ref) ||
      !sha256_digest(bundle.previous_bundle_digest)
    ) {
    issues.push("previous bundle identity is invalid")
  }
  if bundle.conversation.contract_id != conversation_contract_id() {
    issues.push(
      "conversation binding must consume \{conversation_contract_id()}",
    )
  }
  if !non_empty(bundle.conversation.protocol) ||
    !non_empty(bundle.conversation.product_id) ||
    !safe_identifier(bundle.conversation.conversation_id) {
    issues.push("conversation protocol, product and stable id are required")
  }
  if bundle.participants.is_empty() {
    issues.push("at least one review participant is required")
  }
  let participant_ids : Array[String] = []
  for candidate in bundle.participants {
    if !safe_identifier(candidate.participant_id) {
      issues.push("participant id is invalid: \{candidate.participant_id}")
    }
    if duplicate(participant_ids, candidate.participant_id) {
      issues.push("duplicate participant id: \{candidate.participant_id}")
    } else {
      participant_ids.push(candidate.participant_id)
    }
    if !non_empty(candidate.display_name) {
      issues.push(
        "participant requires a display name: \{candidate.participant_id}",
      )
    }
    if !["human", "agent"].contains(candidate.participant_kind) {
      issues.push(
        "participant kind must be human or agent: \{candidate.participant_id}",
      )
    }
  }
  if bundle.entries.is_empty() {
    issues.push("at least one review entry is required")
  }
  let entry_ids : Array[String] = []
  for candidate in bundle.entries {
    if !safe_identifier(candidate.entry_id) {
      issues.push("review entry id is invalid: \{candidate.entry_id}")
    }
    if duplicate(entry_ids, candidate.entry_id) {
      issues.push("duplicate review entry id: \{candidate.entry_id}")
    } else {
      entry_ids.push(candidate.entry_id)
    }
    if !["question", "objection", "proposal"].contains(candidate.entry_kind) {
      issues.push("review entry kind is invalid: \{candidate.entry_id}")
    }
    if participant(bundle.participants, candidate.author_participant_id) is None {
      issues.push(
        "review entry author is unknown: \{candidate.author_participant_id}",
      )
    }
    if !non_empty(candidate.body) {
      issues.push("review entry body is empty: \{candidate.entry_id}")
    }
    if !non_empty(candidate.turn.turn_id) ||
      !non_empty(candidate.turn.client_turn_id) ||
      !non_empty(candidate.turn.command_id) {
      issues.push(
        "review entry requires MoonLib turn identities: \{candidate.entry_id}",
      )
    }
    validate_ref_array(
      "review entry \{candidate.entry_id}",
      candidate.evidence_refs,
      issues,
    )
    for prior in bundle.entries {
      if prior.entry_id == candidate.entry_id {
        break
      }
      if prior.turn.turn_id == candidate.turn.turn_id &&
        prior.turn != candidate.turn {
        issues.push(
          "turn_id maps to conflicting client_turn_id or command_id: \{candidate.turn.turn_id}",
        )
      }
      if prior.turn.client_turn_id == candidate.turn.client_turn_id &&
        prior.turn.turn_id != candidate.turn.turn_id {
        issues.push(
          "client_turn_id is reused by another turn: \{candidate.turn.client_turn_id}",
        )
      }
      if prior.turn.command_id == candidate.turn.command_id &&
        prior.turn.turn_id != candidate.turn.turn_id {
        issues.push(
          "command_id is reused by another turn: \{candidate.turn.command_id}",
        )
      }
    }
  }
  if bundle.required_decisions.is_empty() {
    issues.push("at least one named human decision is required")
  }
  let decision_ids : Array[String] = []
  for required in bundle.required_decisions {
    if !safe_identifier(required.decision_id) {
      issues.push("decision id is invalid: \{required.decision_id}")
    }
    if duplicate(decision_ids, required.decision_id) {
      issues.push("duplicate required decision: \{required.decision_id}")
    } else {
      decision_ids.push(required.decision_id)
    }
    if entry(bundle.entries, required.subject_entry_id) is None {
      issues.push(
        "required decision subject is unknown: \{required.subject_entry_id}",
      )
    }
    match participant(bundle.participants, required.reviewer_participant_id) {
      Some(reviewer) =>
        if reviewer.participant_kind != "human" {
          issues.push(
            "only a human may own required decision: \{required.decision_id}",
          )
        }
      None =>
        issues.push(
          "required decision reviewer is unknown: \{required.reviewer_participant_id}",
        )
    }
    if !non_empty(required.prompt) {
      issues.push("required decision prompt is empty: \{required.decision_id}")
    }
  }
  for candidate in bundle.entries {
    if candidate.entry_kind == "objection" &&
      !bundle.required_decisions.any(required => {
        required.subject_entry_id == candidate.entry_id
      }) {
      issues.push(
        "objection is not preserved as a required decision: \{candidate.entry_id}",
      )
    }
  }
  let receipt_ids : Array[String] = []
  let receipt_decisions : Array[String] = []
  for candidate in bundle.decision_receipts {
    if !safe_identifier(candidate.receipt_id) {
      issues.push("decision receipt id is invalid: \{candidate.receipt_id}")
    }
    if duplicate(receipt_ids, candidate.receipt_id) {
      issues.push("duplicate decision receipt id: \{candidate.receipt_id}")
    } else {
      receipt_ids.push(candidate.receipt_id)
    }
    if duplicate(receipt_decisions, candidate.decision_id) {
      issues.push(
        "a required decision has more than one receipt: \{candidate.decision_id}",
      )
    } else {
      receipt_decisions.push(candidate.decision_id)
    }
    match requirement(bundle.required_decisions, candidate.decision_id) {
      Some(required) =>
        if required.reviewer_participant_id != candidate.reviewer_participant_id {
          issues.push(
            "decision receipt reviewer does not own decision: \{candidate.decision_id}",
          )
        }
      None =>
        issues.push(
          "decision receipt has no requirement: \{candidate.decision_id}",
        )
    }
    match participant(bundle.participants, candidate.reviewer_participant_id) {
      Some(reviewer) => {
        if reviewer.participant_kind != "human" {
          issues.push(
            "agent suggestions cannot become human decisions: \{candidate.receipt_id}",
          )
        }
        if reviewer.display_name != candidate.reviewer_name {
          issues.push(
            "decision receipt must preserve the named reviewer: \{candidate.receipt_id}",
          )
        }
      }
      None =>
        issues.push(
          "decision receipt reviewer is unknown: \{candidate.reviewer_participant_id}",
        )
    }
    if !["approve", "reject", "defer"].contains(candidate.decision) {
      issues.push(
        "decision receipt outcome is invalid: \{candidate.receipt_id}",
      )
    }
    if !non_empty(candidate.rationale) {
      issues.push(
        "decision receipt rationale is empty: \{candidate.receipt_id}",
      )
    }
    if candidate.source_digest != bundle.source_digest {
      issues.push(
        "decision receipt is stale for the bound source: \{candidate.receipt_id}",
      )
    }
    if !canonical_utc_timestamp(candidate.decided_at) {
      issues.push(
        "decision receipt timestamp is not canonical UTC: \{candidate.receipt_id}",
      )
    }
    validate_ref_array(
      "decision receipt \{candidate.receipt_id}",
      candidate.evidence_refs,
      issues,
    )
  }
  if !canonical_utc_timestamp(bundle.recorded_at) {
    issues.push("recorded_at must be a canonical UTC timestamp")
  }
  issues
}

///|
pub fn missing_decision_ids(bundle : ConversationReviewBundle) -> Array[String] {
  let missing : Array[String] = []
  for required in bundle.required_decisions {
    match receipt(bundle.decision_receipts, required.decision_id) {
      Some(found) =>
        if found.decision == "defer" {
          missing.push(required.decision_id)
        }
      None => missing.push(required.decision_id)
    }
  }
  missing
}

///|
pub fn rejected_decision_ids(
  bundle : ConversationReviewBundle,
) -> Array[String] {
  let rejected : Array[String] = []
  for candidate in bundle.decision_receipts {
    if candidate.decision == "reject" {
      rejected.push(candidate.decision_id)
    }
  }
  rejected
}

///|
pub fn review_status(bundle : ConversationReviewBundle) -> String {
  if !missing_decision_ids(bundle).is_empty() {
    "pending_review"
  } else if !rejected_decision_ids(bundle).is_empty() {
    "rejected"
  } else {
    "accepted"
  }
}

///|
pub fn claim_class(bundle : ConversationReviewBundle) -> String {
  if review_status(bundle) == "accepted" {
    "accepted-knowledge"
  } else {
    "research-evidence"
  }
}
