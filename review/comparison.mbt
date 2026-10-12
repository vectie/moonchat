///|
fn[T : Eq] compare_review_section(
  out : StringBuilder,
  title : String,
  before : Array[T],
  after : Array[T],
  identity : (T) -> String,
  render : (T) -> String,
) -> Unit {
  out.write_string("## " + title + "\n\n")
  let old : Map[String, T] = {}
  let next : Map[String, T] = {}
  for item in before {
    old[identity(item)] = item
  }
  for item in after {
    next[identity(item)] = item
  }
  let mut added = 0
  let mut changed = 0
  let mut removed = 0
  let mut unchanged = 0
  for item in before {
    let id = identity(item)
    match next.get(id) {
      None => {
        removed += 1
        out.write_string("### Removed\n\n")
        review_markdown_field(out, "ID", id)
        review_markdown_field(out, "Before", render(item))
      }
      Some(value) =>
        if item != value {
          changed += 1
          out.write_string("### Changed\n\n")
          review_markdown_field(out, "ID", id)
          review_markdown_field(out, "Before", render(item))
          review_markdown_field(out, "After", render(value))
        } else {
          unchanged += 1
        }
    }
  }
  for item in after {
    if !old.contains(identity(item)) {
      added += 1
      out.write_string("### Added\n\n")
      review_markdown_field(out, "ID", identity(item))
      review_markdown_field(out, "After", render(item))
    }
  }
  out.write_string(
    "\{added} added; \{changed} changed; \{removed} removed; \{unchanged} unchanged.\n\n",
  )
  let old_order = before.map(identity)
  let next_order = after.map(identity)
  if old_order != next_order {
    review_markdown_field(out, "Before order", old_order.join("\n"))
    review_markdown_field(out, "After order", next_order.join("\n"))
  }
}

///|
fn comparison_entry(entry : ReviewEntry) -> String {
  "Kind: " +
  entry.entry_kind +
  "\nAuthor: " +
  entry.author_participant_id +
  "\nTurn: " +
  entry.turn.turn_id +
  "\nClient turn: " +
  entry.turn.client_turn_id +
  "\nCommand: " +
  entry.turn.command_id +
  "\nBody:\n" +
  entry.body +
  "\nEvidence references:\n" +
  entry.evidence_refs.join("\n")
}

///|
/// Compare two verified snapshots of the same artifact and conversation.
/// Stable IDs match objects; no fuzzy matching or approval transfer occurs.
/// This derived report neither proves ancestry nor edits either input.
/// Supply source_context (0..20) to include a bounded exact UTF-8 line diff.
/// Omit it to retain the existing comparison, including binary source support.
pub fn export_review_comparison(
  before : ConversationReviewBundle,
  before_source : Bytes,
  after : ConversationReviewBundle,
  after_source : Bytes,
  source_context? : Int,
) -> String raise {
  let old_record = project_review_record(
    before,
    review_source_digest(before_source),
    [],
  )
  let next_record = project_review_record(
    after,
    review_source_digest(after_source),
    [],
  )
  if before.source_artifact_ref != after.source_artifact_ref ||
    before.conversation != after.conversation {
    fail(
      "comparison requires the same source artifact reference and conversation binding",
    )
  }
  let out = StringBuilder()
  out.write_string("# MoonChat review comparison\n\n")
  out.write_string(
    "Verified snapshots, compared by stable IDs. This report does not establish ancestry, transfer approval, or replace either retained bundle. Removed objections remain visible below.\n\n",
  )
  review_markdown_field(out, "Source artifact", before.source_artifact_ref)
  review_markdown_field(out, "Before review", before.review_id)
  review_markdown_field(out, "After review", after.review_id)
  review_markdown_field(out, "Before revision", before.source_revision_id)
  review_markdown_field(out, "After revision", after.source_revision_id)
  review_markdown_field(out, "Before SHA-256", before.source_digest)
  review_markdown_field(out, "After SHA-256", after.source_digest)
  review_markdown_field(
    out,
    "Source bytes",
    if before.source_digest == after.source_digest {
      "unchanged"
    } else {
      "changed; prior receipts cover only their original digest"
    },
  )
  review_markdown_field(out, "Before status", old_record.review_status)
  review_markdown_field(out, "After status", next_record.review_status)
  review_markdown_field(out, "Before recorded at", before.recorded_at)
  review_markdown_field(out, "After recorded at", after.recorded_at)
  review_markdown_field(
    out,
    "Before previous bundle",
    before.previous_bundle_ref + "\n" + before.previous_bundle_digest,
  )
  review_markdown_field(
    out,
    "After previous bundle",
    after.previous_bundle_ref + "\n" + after.previous_bundle_digest,
  )
  if source_context is Some(context) {
    compare_review_source_text(out, before_source, after_source, context)
  }
  compare_review_section(
    out,
    "Participants",
    before.participants,
    after.participants,
    p => p.participant_id,
    p => "Name: " + p.display_name + "\nKind: " + p.participant_kind,
  )
  compare_review_section(
    out,
    "Typed entries and evidence",
    before.entries,
    after.entries,
    e => e.entry_id,
    comparison_entry,
  )
  compare_review_section(
    out,
    "Required decisions",
    before.required_decisions,
    after.required_decisions,
    d => d.decision_id,
    d => {
      "Subject: " +
      d.subject_entry_id +
      "\nReviewer: " +
      d.reviewer_participant_id +
      "\nPrompt:\n" +
      d.prompt
    },
  )
  compare_review_section(
    out,
    "Decision receipts",
    before.decision_receipts,
    after.decision_receipts,
    r => r.receipt_id,
    r => {
      "Decision: " +
      r.decision +
      "\nRequired decision: " +
      r.decision_id +
      "\nReviewer: " +
      r.reviewer_participant_id +
      "\nName: " +
      r.reviewer_name +
      "\nSource SHA-256: " +
      r.source_digest +
      "\nDecided at: " +
      r.decided_at +
      "\nRationale:\n" +
      r.rationale +
      "\nEvidence references:\n" +
      r.evidence_refs.join("\n")
    },
  )
  out.to_string()
}
