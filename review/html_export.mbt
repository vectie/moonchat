///|
fn review_html_source_lines(bytes : Bytes) -> Array[String] raise {
  if bytes.length() > 1048576 {
    fail("HTML packet source exceeds the 1 MiB UTF-8 limit")
  }
  let text = @utf8.decode(bytes, ignore_bom=false) catch {
    _ => fail("HTML packet requires a valid UTF-8 text source")
  }
  for ch in text {
    if (ch < ' ' && ch != '\t' && ch != '\n' && ch != '\r') || ch == '\u{7f}' {
      fail("HTML packet source contains unsupported text control characters")
    }
  }
  let lines = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .map(line => line.to_owned())
    .collect()
  if lines.length() > 10000 {
    fail("HTML packet source exceeds the 10000 display-line limit")
  }
  lines
}

///|
fn review_html_decision(
  out : StringBuilder,
  bundle : ConversationReviewBundle,
  required : RequiredDecision,
  index : Int,
) -> Unit {
  out.write_string(
    "<section class=\"decision\" id=\"decision-\{index + 1}\"><h3>Decision \{index + 1}</h3><dl>\n",
  )
  review_html_field(out, "Decision ID", required.decision_id)
  review_html_field(
    out,
    "Named reviewer",
    exploration_person(bundle, required.reviewer_participant_id),
  )
  review_html_field(out, "Prompt", required.prompt)
  review_html_field(
    out,
    "Outcome",
    exploration_outcome(bundle, required.decision_id),
  )
  match receipt(bundle.decision_receipts, required.decision_id) {
    None =>
      out.write_string("</dl><p>No receipt recorded for this decision.</p>\n")
    Some(found) => {
      review_html_field(out, "Receipt ID", found.receipt_id)
      review_html_field(out, "Receipt reviewer", found.reviewer_name)
      review_html_field(
        out,
        "Receipt reviewer ID",
        found.reviewer_participant_id,
      )
      review_html_field(out, "Rationale", found.rationale)
      review_html_field(out, "Decided at", found.decided_at)
      review_html_field(out, "Receipt source SHA-256", found.source_digest)
      review_html_field(
        out,
        "Receipt evidence references (not opened)",
        found.evidence_refs.join("\n"),
      )
      out.write_string("</dl>\n")
    }
  }
  out.write_string(
    "<p class=\"back\"><a href=\"#decision-index\">Back to decision index</a></p></section>\n",
  )
}

///|
/// Export a self-contained, script-free review packet with the observed UTF-8
/// source and every discussion item and receipt. Existing review validation
/// runs before rendering; the HTML is a reading view, never an authority input.
/// Source display accepts up to 1 MiB / 10000 display lines and normalizes line
/// endings only for presentation. Original bytes determine the source digest.
/// Optional reader-authored locations add verified quotes and bidirectional
/// source/discussion navigation without modifying the bundle or receipts.
pub fn export_review_html(
  bundle : ConversationReviewBundle,
  observed_source_bytes : Bytes,
  locations? : ReviewSourceLocations,
) -> String raise {
  let record = project_review_record(
    bundle,
    review_source_digest(observed_source_bytes),
    [],
  )
  let lines = review_html_source_lines(observed_source_bytes)
  let located = locations.map(value => {
    index_source_locations(bundle, lines, value)
  })
  let out = StringBuilder()
  review_html_header(out, bundle.review_id)
  out.write_string(
    "<section class=\"panel\" id=\"summary\"><h2>Review scope</h2><dl>\n",
  )
  review_html_field(out, "Review ID", bundle.review_id)
  review_html_field(out, "Overall review status", record.review_status)
  review_html_field(out, "Contract claim class", record.claim_class)
  review_html_field(out, "Outcome guidance", review_outcome_message(bundle))
  review_html_field(out, "Source artifact", bundle.source_artifact_ref)
  review_html_field(out, "Source revision", bundle.source_revision_id)
  review_html_field(out, "Source SHA-256", bundle.source_digest)
  review_html_field(
    out,
    "Previous bundle reference (not opened)",
    bundle.previous_bundle_ref,
  )
  review_html_field(
    out,
    "Previous bundle SHA-256",
    bundle.previous_bundle_digest,
  )
  review_html_field(out, "Conversation ID", bundle.conversation.conversation_id)
  review_html_field(
    out,
    "Conversation contract",
    bundle.conversation.contract_id,
  )
  review_html_field(out, "Host product", bundle.conversation.product_id)
  review_html_field(out, "Host protocol", bundle.conversation.protocol)
  review_html_field(out, "Recorded at", bundle.recorded_at)
  review_html_field(
    out,
    "Missing or deferred decisions",
    record.missing_decision_ids.join("\n"),
  )
  review_html_field(
    out,
    "Rejected decisions",
    record.rejected_decision_ids.join("\n"),
  )
  out.write_string(
    "</dl><p>\{bundle.entries.length()} discussion entries; \{bundle.required_decisions.length()} required decisions; \{bundle.decision_receipts.length()} recorded receipts. Every current-bundle objection is shown below, including when the overall status is accepted.</p></section>\n",
  )
  if located is Some(index) {
    out.write_string(
      "<p class=\"notice\">Source-linked reading: \{index.locations.length()} ranges across \{index.by_entry.length()} of \{bundle.entries.length()} entries. Every supplied quote matches the exact bound source's display lines. Associations are reader-supplied, not proof that a claim is correct or an objection resolved. Unlocated entries and all decisions are retained.</p>\n",
    )
  }
  out.write_string(
    "<section class=\"panel\" id=\"decision-index\"><h2>Decision index</h2><ol>\n",
  )
  for index, required in bundle.required_decisions {
    out.write_string("<li><a href=\"#decision-\{index + 1}\">")
    out.write_string(
      review_html_escape(
        required.decision_id +
        " — " +
        exploration_person(bundle, required.reviewer_participant_id),
      ),
    )
    out.write_string(
      "</a>: " +
      review_html_escape(exploration_outcome(bundle, required.decision_id)) +
      "</li>\n",
    )
  }
  out.write_string("</ol><h3>Discussion index</h3><ol>\n")
  for index, item in bundle.entries {
    out.write_string(
      "<li><a href=\"#entry-\{index + 1}\">" +
      review_html_escape(item.entry_kind + ": " + item.entry_id) +
      "</a></li>\n",
    )
  }
  out.write_string(
    "</ol></section>\n<div class=\"columns\">\n<section class=\"panel\" id=\"source\"><h2>Source text</h2>\n",
  )
  out.write_string(
    "<p>The digest above covers all \{observed_source_bytes.length()} original bytes. Line numbers describe this display only. CRLF and CR are displayed as LF; a final newline produces an empty final display line. Source markup is literal text.</p>\n<ol class=\"source-lines\">\n",
  )
  for index, line in lines {
    out.write_string(
      "<li id=\"source-line-\{index + 1}\"><a aria-label=\"Source line \{index + 1}\" href=\"#source-line-\{index + 1}\">\{index + 1}</a><span>" +
      review_html_escape(line) +
      "</span>",
    )
    if located is Some(locations) {
      review_html_line_locations(out, bundle, index + 1, locations)
    }
    out.write_string("</li>\n")
  }
  out.write_string(
    "</ol></section>\n<section id=\"discussion\"><h2>Discussion and receipts</h2>\n",
  )
  for index, item in bundle.entries {
    let style = if item.entry_kind == "objection" {
      " class=\"objection\""
    } else {
      ""
    }
    out.write_string(
      "<article id=\"entry-\{index + 1}\"" +
      style +
      "><h3>" +
      review_html_escape(item.entry_kind + ": " + item.entry_id) +
      "</h3><dl>\n",
    )
    review_html_field(
      out,
      "Author",
      exploration_person(bundle, item.author_participant_id),
    )
    review_html_field(out, "Discussion text", item.body)
    review_html_field(
      out,
      "Evidence references (not opened)",
      item.evidence_refs.join("\n"),
    )
    review_html_field(out, "Turn ID", item.turn.turn_id)
    review_html_field(out, "Client turn ID", item.turn.client_turn_id)
    review_html_field(out, "Command ID", item.turn.command_id)
    out.write_string("</dl>\n")
    if located is Some(locations) {
      review_html_entry_locations(out, item.entry_id, locations)
    }
    let mut count = 0
    for decision_index, required in bundle.required_decisions {
      if required.subject_entry_id == item.entry_id {
        review_html_decision(out, bundle, required, decision_index)
        count += 1
      }
    }
    if count == 0 {
      out.write_string("<p>No decision requested for this entry.</p>\n")
    }
    out.write_string(
      "<p class=\"back\"><a href=\"#source\">Read bound source</a> · <a href=\"#top\">Back to top</a></p></article>\n",
    )
  }
  out.write_string(
    "</section></div>\n<section class=\"panel\" id=\"participants\"><h2>Participants</h2>\n",
  )
  for person in bundle.participants {
    out.write_string("<dl>\n")
    review_html_field(out, "Name", person.display_name)
    review_html_field(out, "Participant ID", person.participant_id)
    review_html_field(out, "Kind", person.participant_kind)
    out.write_string("</dl>\n")
  }
  out.write_string(
    "</section></main>\n<footer><p>Generated locally by MoonChat. No scripts, external resources or active evidence links. Use your browser's Find and Print commands. Previous revisions and their dissent remain in separately retained bundles; this packet displays only the current supplied bundle.</p></footer>\n</body>\n</html>\n",
  )
  out.to_string()
}
