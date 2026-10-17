///|
/// An explicit choice supplied by a reviewer, never an authentication proof.
/// Empty outcome leaves this requirement undecided; no approval is defaulted.
pub(all) struct ReviewDecisionChoice {
  decision_id : String
  subject_entry_id : String
  prompt : String
  outcome : String
  rationale : String
  receipt_id : String
  decided_at : String
  evidence_refs : Array[String]
} derive(Eq, ToJson, @json.FromJson)

///|
/// A local, unverified submission bound to the exact displayed bundle bytes.
/// Discussion is read-only context, including objections by other participants.
pub(all) struct ReviewDecisionForm {
  format : String
  base_bundle_digest : String
  review_id : String
  source_artifact_ref : String
  source_revision_id : String
  source_digest : String
  reviewer_participant_id : String
  reviewer_name : String
  entries : Array[ReviewEntry]
  choices : Array[ReviewDecisionChoice]
} derive(Eq, ToJson, @json.FromJson)

///|
/// Prepare only outstanding requirements for one named human. The host must
/// display the source and all discussion, and obtain explicit choices itself.
pub fn prepare_review_decisions(
  bundle_text : String,
  source : Bytes,
  reviewer_participant_id : String,
) -> ReviewDecisionForm raise {
  let bundle = reimport_review_bundle(bundle_text, source)
  guard participant(bundle.participants, reviewer_participant_id)
    is Some(reviewer) &&
    reviewer.participant_kind == "human" else {
    fail("decision form requires a named human participant")
  }
  let choices : Array[ReviewDecisionChoice] = []
  for required in bundle.required_decisions {
    if required.reviewer_participant_id == reviewer_participant_id &&
      receipt(bundle.decision_receipts, required.decision_id) is None {
      choices.push({
        decision_id: required.decision_id,
        subject_entry_id: required.subject_entry_id,
        prompt: required.prompt,
        outcome: "",
        rationale: "",
        receipt_id: "",
        decided_at: "",
        evidence_refs: [],
      })
    }
  }
  if choices.is_empty() {
    fail(
      "reviewer has no outstanding decisions; existing receipts cannot be overwritten",
    )
  }
  {
    format: "moonchat.review-decision-form.v1",
    base_bundle_digest: review_source_digest(@utf8.encode(bundle_text)),
    review_id: bundle.review_id,
    source_artifact_ref: bundle.source_artifact_ref,
    source_revision_id: bundle.source_revision_id,
    source_digest: bundle.source_digest,
    reviewer_participant_id,
    reviewer_name: reviewer.display_name,
    entries: bundle.entries,
    choices,
  }
}

///|
pub fn parse_review_decisions(text : String) -> ReviewDecisionForm raise {
  let value = @json.parse(text)
  guard value is Object(fields) else { fail("decision form must be an object") }
  let allowed = [
    "format", "base_bundle_digest", "review_id", "source_artifact_ref", "source_revision_id",
    "source_digest", "reviewer_participant_id", "reviewer_name", "entries", "choices",
  ]
  for key, _ in fields {
    if !allowed.contains(key) {
      fail("unsupported decision form field: " + key)
    }
  }
  if fields.get("choices") is Some(Array(choices)) {
    for choice in choices {
      guard choice is Object(choice_fields) else {
        fail("decision choice must be an object")
      }
      for key, _ in choice_fields {
        if ![
            "decision_id", "subject_entry_id", "prompt", "outcome", "rationale",
            "receipt_id", "decided_at", "evidence_refs",
          ].contains(key) {
          fail("unsupported decision choice field: " + key)
        }
      }
    }
  }
  let form : ReviewDecisionForm = @json.from_json(value)
  if form.format != "moonchat.review-decision-form.v1" {
    fail("unsupported decision form format")
  }
  form
}

///|
fn checked_decision_bundle(
  form : ReviewDecisionForm,
  bundle_text : String,
  source : Bytes,
) -> ConversationReviewBundle raise {
  let expected = prepare_review_decisions(
    bundle_text,
    source,
    form.reviewer_participant_id,
  )
  if form.format != expected.format ||
    form.base_bundle_digest != expected.base_bundle_digest ||
    form.review_id != expected.review_id ||
    form.source_artifact_ref != expected.source_artifact_ref ||
    form.source_revision_id != expected.source_revision_id ||
    form.source_digest != expected.source_digest ||
    form.reviewer_name != expected.reviewer_name ||
    form.entries != expected.entries {
    fail(
      "decision form scope or displayed discussion changed; reopen the current review",
    )
  }
  let bundle = reimport_review_bundle(bundle_text, source)
  let receipts = bundle.decision_receipts.copy()
  let seen : Array[String] = []
  let mut added = 0
  for choice in form.choices {
    if seen.contains(choice.decision_id) {
      fail("duplicate decision choice")
    }
    seen.push(choice.decision_id)
    guard expected.choices
      .filter(c => c.decision_id == choice.decision_id)
      .get(0)
      is Some(required) else {
      fail("choice is not an outstanding decision owned by this reviewer")
    }
    if choice.subject_entry_id != required.subject_entry_id ||
      choice.prompt != required.prompt {
      fail("decision subject or prompt changed; reopen the current review")
    }
    if choice.outcome.is_empty() {
      if !choice.rationale.is_empty() ||
        !choice.receipt_id.is_empty() ||
        !choice.decided_at.is_empty() ||
        !choice.evidence_refs.is_empty() {
        fail("incomplete choice: select approve, reject or defer explicitly")
      }
      continue
    }
    receipts.push({
      receipt_id: choice.receipt_id,
      decision_id: choice.decision_id,
      reviewer_participant_id: form.reviewer_participant_id,
      reviewer_name: form.reviewer_name,
      decision: choice.outcome,
      rationale: choice.rationale,
      source_digest: bundle.source_digest,
      decided_at: choice.decided_at,
      evidence_refs: choice.evidence_refs.copy(),
    })
    added += 1
  }
  if added == 0 {
    fail("no explicit decision choices supplied")
  }
  let result = { ..bundle, decision_receipts: receipts, }
  require_valid_bundle(result, review_source_digest(source))
  result
}

///|
/// Validate without returning a bundle or an acceptance claim. CLI/local input
/// is unverified; this summary cannot be used as a qualifying review record.
pub fn preview_review_decisions(
  form : ReviewDecisionForm,
  bundle_text : String,
  source : Bytes,
) -> String raise {
  let _ = checked_decision_bundle(form, bundle_text, source)
  let lines = [
    "UNVERIFIED DECISION SUBMISSION — not a review receipt",
    "Reviewer: " + form.reviewer_name,
    "Source: " + form.source_artifact_ref + " @ " + form.source_revision_id,
    "Digest: " + form.source_digest,
    "Discussion (retained):",
  ]
  for e in form.entries {
    lines.push(e.entry_kind + " " + e.entry_id + ": " + e.body)
  }
  lines.push("Explicit choices:")
  for c in form.choices {
    if !c.outcome.is_empty() {
      lines.push(c.decision_id + ": " + c.outcome + " — " + c.rationale)
    }
  }
  lines.push(
    "The host must authenticate the named reviewer, confirm these choices, and retain the resulting bundle before delivery.",
  )
  lines.join("\n") + "\n"
}

///|
/// Host trust boundary: call ONLY after authenticating this human and obtaining
/// their explicit confirmation of the displayed form. The verified identity
/// must come from trusted host session state, never from form JSON. This pure
/// API cannot authenticate a person. CLI intentionally exposes no apply mode.
/// Produces a detached bundle; existing receipts and dissent remain unchanged.
/// Retain the prior and returned bundle; journal/storage/delivery are host-owned.
pub fn apply_verified_review_decisions(
  form : ReviewDecisionForm,
  bundle_text : String,
  source : Bytes,
  verified_reviewer_participant_id~ : String,
) -> ConversationReviewBundle raise {
  if verified_reviewer_participant_id != form.reviewer_participant_id {
    fail("verified host reviewer does not match the decision submission")
  }
  checked_decision_bundle(form, bundle_text, source)
}
