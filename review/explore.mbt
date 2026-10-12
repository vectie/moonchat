///|
fn exploration_person(bundle : ConversationReviewBundle, id : String) -> String {
  for participant in bundle.participants {
    if participant.participant_id == id {
      return participant.display_name + " (" + id + ")"
    }
  }
  id
}

///|
fn exploration_outcome(
  bundle : ConversationReviewBundle,
  id : String,
) -> String {
  for receipt in bundle.decision_receipts {
    if receipt.decision_id == id {
      return receipt.decision
    }
  }
  "pending"
}

///|
/// Read-only, literal case-sensitive exploration of a fully validated review.
/// Filters narrow entries, never the underlying review status or decision set.
pub fn explore_review(
  bundle : ConversationReviewBundle,
  observed_source_bytes : Bytes,
  text? : String = "",
  kind? : String = "",
  reviewer? : String = "",
  outcome? : String = "",
) -> String raise {
  let record = project_review_record(
    bundle,
    review_source_digest(observed_source_bytes),
    [],
  )
  guard kind == "" ||
    kind == "question" ||
    kind == "objection" ||
    kind == "proposal" else {
    fail("kind must be question, objection or proposal")
  }
  guard outcome == "" ||
    outcome == "pending" ||
    outcome == "approve" ||
    outcome == "reject" ||
    outcome == "defer" ||
    outcome == "none" else {
    fail("outcome must be pending, approve, reject, defer or none")
  }
  if reviewer != "" {
    guard bundle.participants.any(p => p.participant_id == reviewer) else {
      fail("reviewer must be an existing participant ID")
    }
  }
  let matches = bundle.entries.filter(entry => {
    if kind != "" && kind != entry.entry_kind {
      return false
    }
    let decisions = bundle.required_decisions.filter(d => {
      d.subject_entry_id == entry.entry_id
    })
    if reviewer != "" || outcome != "" {
      if outcome == "none" {
        if reviewer != "" || !decisions.is_empty() {
          return false
        }
      } else if !decisions.any(d => {
          (reviewer == "" || reviewer == d.reviewer_participant_id) &&
          (
            outcome == "" ||
            outcome == exploration_outcome(bundle, d.decision_id)
          )
        }) {
        return false
      }
    }
    if text == "" {
      return true
    }
    let fields = [
      entry.entry_id,
      entry.entry_kind,
      entry.author_participant_id,
      exploration_person(bundle, entry.author_participant_id),
      entry.body,
      entry.turn.turn_id,
      entry.turn.client_turn_id,
      entry.turn.command_id,
    ]
    for reference in entry.evidence_refs {
      fields.push(reference)
    }
    for decision in decisions {
      fields.push(decision.decision_id)
      fields.push(decision.prompt)
      fields.push(exploration_person(bundle, decision.reviewer_participant_id))
      for receipt in bundle.decision_receipts {
        if receipt.decision_id == decision.decision_id {
          fields.push(receipt.receipt_id)
          fields.push(receipt.reviewer_name)
          fields.push(receipt.rationale)
          for reference in receipt.evidence_refs {
            fields.push(reference)
          }
        }
      }
    }
    fields.any(field => field.contains(text))
  })
  let out = StringBuilder()
  out.write_string("# MoonChat review exploration\n\n")
  out.write_string(
    "Filtered reading view, not a complete handoff or importable bundle. Overall status below covers the full original review. Retain original JSON and exact source bytes.\n\n",
  )
  review_markdown_field(out, "Review", bundle.review_id)
  review_markdown_field(out, "Overall review status", record.review_status)
  review_markdown_field(out, "Overall claim class", record.claim_class)
  review_markdown_field(out, "Source artifact", bundle.source_artifact_ref)
  review_markdown_field(out, "Source revision", bundle.source_revision_id)
  review_markdown_field(out, "Source SHA-256", bundle.source_digest)
  review_markdown_field(out, "Literal text filter (case-sensitive)", text)
  review_markdown_field(out, "Kind filter", kind)
  review_markdown_field(out, "Reviewer ID filter", reviewer)
  review_markdown_field(out, "Outcome filter", outcome)
  out.write_string(
    "Matched \{matches.length()} of \{bundle.entries.length()} entries. All decisions for each matched entry are shown, including those outside the filters.\n\n",
  )
  if matches.is_empty() {
    out.write_string(
      "No matching entries. This does not mean the review has no unresolved decisions.\n\n",
    )
  }
  for entry in matches {
    out.write_string("## Matching entry\n\n")
    review_markdown_field(out, "Entry ID", entry.entry_id)
    review_markdown_field(out, "Kind", entry.entry_kind)
    review_markdown_field(
      out,
      "Author",
      exploration_person(bundle, entry.author_participant_id),
    )
    review_markdown_field(out, "Body", entry.body)
    review_markdown_field(out, "Turn", entry.turn.turn_id)
    review_markdown_field(out, "Client turn", entry.turn.client_turn_id)
    review_markdown_field(out, "Command", entry.turn.command_id)
    review_markdown_field(
      out,
      "Evidence references",
      entry.evidence_refs.join("\n"),
    )
    let decisions = bundle.required_decisions.filter(d => {
      d.subject_entry_id == entry.entry_id
    })
    if decisions.is_empty() {
      out.write_string("No decisions requested for this entry.\n\n")
    }
    for decision in decisions {
      out.write_string("### Associated decision\n\n")
      review_markdown_field(out, "Decision ID", decision.decision_id)
      review_markdown_field(
        out,
        "Named reviewer",
        exploration_person(bundle, decision.reviewer_participant_id),
      )
      review_markdown_field(out, "Prompt", decision.prompt)
      review_markdown_field(
        out,
        "Outcome",
        exploration_outcome(bundle, decision.decision_id),
      )
      for receipt in bundle.decision_receipts {
        if receipt.decision_id == decision.decision_id {
          review_markdown_field(out, "Receipt ID", receipt.receipt_id)
          review_markdown_field(out, "Receipt reviewer", receipt.reviewer_name)
          review_markdown_field(out, "Rationale", receipt.rationale)
          review_markdown_field(
            out,
            "Receipt source SHA-256",
            receipt.source_digest,
          )
          review_markdown_field(out, "Decided at", receipt.decided_at)
          review_markdown_field(
            out,
            "Receipt evidence references",
            receipt.evidence_refs.join("\n"),
          )
        }
      }
    }
  }
  out.to_string()
}
