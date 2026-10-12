///|
// Literal blocks keep multiline source text readable without turning it into
// headings, links, HTML, or Markdown fences in the surrounding report.
fn review_markdown_field(
  out : StringBuilder,
  label : String,
  value : String,
) -> Unit {
  out.write_string(label + ":\n\n")
  if value.is_empty() {
    out.write_string("    (none)\n")
  } else {
    for
      line in value
      .replace(old="\r\n", new="\n")
      .replace(old="\r", new="\n")
      .split("\n") {
      out.write_string("    " + line.to_owned() + "\n")
    }
  }
  out.write_string("\n")
}

///|
/// Export a source-bound review as readable Markdown. This is a derived view,
/// not a new receipt, stored journal, or importable replacement for bundle JSON.
/// Event order is the existing deterministic review projection, not wall-clock
/// chronology. The caller retains the original bundle and source separately.
pub fn export_review_markdown(
  bundle : ConversationReviewBundle,
  observed_source_bytes : Bytes,
) -> String raise {
  let digest = review_source_digest(observed_source_bytes)
  let events = review_events(bundle, digest)
  let record = project_review_record(bundle, digest, [])
  let out = StringBuilder()
  out.write_string("# MoonChat review handoff\n\n")
  out.write_string(
    "Derived readable view. Retain the original bundle JSON and source bytes.\n\n",
  )
  review_markdown_field(out, "Review", record.review_id)
  review_markdown_field(out, "Status", record.review_status)
  review_markdown_field(out, "Claim class", record.claim_class)
  review_markdown_field(out, "Outcome", review_outcome_message(bundle))
  out.write_string("## Source and conversation\n\n")
  review_markdown_field(out, "Source artifact", record.source_artifact_ref)
  review_markdown_field(out, "Source SHA-256", record.source_digest)
  review_markdown_field(out, "Source revision", record.source_revision_id)
  review_markdown_field(out, "Previous bundle", record.previous_bundle_ref)
  review_markdown_field(
    out,
    "Previous bundle SHA-256",
    record.previous_bundle_digest,
  )
  review_markdown_field(
    out,
    "Conversation",
    record.conversation.conversation_id,
  )
  review_markdown_field(
    out,
    "Conversation contract",
    record.conversation.contract_id,
  )
  review_markdown_field(out, "Protocol", record.conversation.protocol)
  review_markdown_field(out, "Product", record.conversation.product_id)
  review_markdown_field(out, "Recorded at", record.recorded_at)
  out.write_string("## Participants\n\n")
  for index, participant in record.participants {
    out.write_string("### Participant \{index + 1}\n\n")
    review_markdown_field(out, "Name", participant.display_name)
    review_markdown_field(out, "ID", participant.participant_id)
    review_markdown_field(out, "Kind", participant.participant_kind)
  }
  out.write_string("## Conversation entries\n\n")
  for index, entry in record.entries {
    out.write_string("### Entry \{index + 1}\n\n")
    review_markdown_field(out, "ID", entry.entry_id)
    review_markdown_field(out, "Kind", entry.entry_kind)
    review_markdown_field(out, "Author", entry.author_participant_id)
    review_markdown_field(out, "Body", entry.body)
    review_markdown_field(out, "Turn", entry.turn.turn_id)
    review_markdown_field(out, "Client turn", entry.turn.client_turn_id)
    review_markdown_field(out, "Command", entry.turn.command_id)
    review_markdown_field(
      out,
      "Evidence references",
      entry.evidence_refs.join("\n"),
    )
  }
  out.write_string("## Decisions\n\n")
  for index, required in record.required_decisions {
    out.write_string("### Decision \{index + 1}\n\n")
    review_markdown_field(out, "ID", required.decision_id)
    review_markdown_field(out, "Subject entry", required.subject_entry_id)
    review_markdown_field(
      out,
      "Named reviewer",
      required.reviewer_participant_id,
    )
    review_markdown_field(out, "Prompt", required.prompt)
    let receipts = record.decision_receipts.filter(receipt => {
      receipt.decision_id == required.decision_id
    })
    if receipts.is_empty() {
      review_markdown_field(out, "Decision outcome", "awaiting receipt")
    }
    for receipt in receipts {
      review_markdown_field(out, "Decision outcome", receipt.decision)
      review_markdown_field(out, "Receipt", receipt.receipt_id)
      review_markdown_field(out, "Reviewer name", receipt.reviewer_name)
      review_markdown_field(out, "Reviewer ID", receipt.reviewer_participant_id)
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
  review_markdown_field(
    out,
    "Missing decisions",
    record.missing_decision_ids.join("\n"),
  )
  review_markdown_field(
    out,
    "Rejected decisions",
    record.rejected_decision_ids.join("\n"),
  )
  out.write_string("## Projected event timeline\n\n")
  out.write_string(
    "Deterministic projection order; not a persisted execution journal or chronological sort.\n\n",
  )
  for event in events {
    out.write_string("### Event \{event.sequence}\n\n")
    review_markdown_field(out, "ID", event.event_id)
    review_markdown_field(out, "Kind", event.event_kind)
    review_markdown_field(out, "Actor", event.actor_participant_id)
    review_markdown_field(out, "Subject", event.subject_id)
    review_markdown_field(out, "Decision", event.decision)
    review_markdown_field(out, "Body", event.body)
    review_markdown_field(out, "Recorded at", event.recorded_at)
  }
  out.to_string()
}
