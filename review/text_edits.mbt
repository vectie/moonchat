///|
/// Explicit source replacements selected by an editor, not review decisions.
/// Both digests bind the exact retained input, including serialization/newlines.
pub(all) struct ReviewTextEditPlan {
  format : String
  base_bundle_digest : String
  source_digest : String
  next_source_artifact_ref : String
  next_source_revision_id : String
  recorded_at : String
  edits : Array[ReviewTextEdit]
} derive(Eq, ToJson, @json.FromJson)

///|
/// One-based inclusive physical LF-delimited lines, including their terminators.
/// An empty replacement deletes the selected range. No fuzzy matching occurs.
pub(all) struct ReviewTextEdit {
  key : String
  entry_id : String
  start_line : Int
  end_line : Int
  quote : String
  replacement : String
} derive(Eq, ToJson, @json.FromJson)

///|
/// Candidate content and its linked pending review. Neither is saved by this API.
pub(all) struct ReviewTextEditResult {
  source_text : String
  bundle : ConversationReviewBundle
} derive(Eq, ToJson)

///|
fn editable_source_lines(bytes : Bytes) -> Array[String] raise {
  let lines = transcript_lines(bytes)
  for line in lines {
    for ch in line {
      if (ch < ' ' && ch != '\t' && ch != '\n' && ch != '\r') || ch == '\u{7f}' {
        fail(
          "text edits require UTF-8 text without unsupported control characters",
        )
      }
    }
    // Bare CR has different display-line meanings in readers. Preserve CRLF,
    // but do not offer misleading physical line coordinates for CR-only files.
    if line.replace_all(old="\r\n", new="").contains("\r") {
      fail("text edits support LF and CRLF line endings, not bare CR")
    }
  }
  lines
}

///|
/// Start an empty plan from a validated review. The editor must supply the new
/// artifact reference, revision, timestamp and selected replacements explicitly.
pub fn prepare_review_text_edits(
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
) -> ReviewTextEditPlan raise {
  let previous = reimport_review_bundle(
    previous_bundle_text, previous_source_bytes,
  )
  ignore(editable_source_lines(previous_source_bytes))
  {
    format: "moonchat.review-text-edits.v1",
    base_bundle_digest: review_source_digest(@utf8.encode(previous_bundle_text)),
    source_digest: previous.source_digest,
    next_source_artifact_ref: "",
    next_source_revision_id: "",
    recorded_at: "",
    edits: [],
  }
}

///|
pub fn parse_review_text_edits(text : String) -> ReviewTextEditPlan raise {
  let json = @json.parse(text)
  guard json is Object(fields) else { fail("text edit plan must be an object") }
  for key, _ in fields {
    if ![
        "format", "base_bundle_digest", "source_digest", "next_source_artifact_ref",
        "next_source_revision_id", "recorded_at", "edits",
      ].contains(key) {
      fail("unsupported text edit plan field: " + key)
    }
  }
  let plan : ReviewTextEditPlan = @json.from_json(json)
  if plan.format != "moonchat.review-text-edits.v1" {
    fail("text edit format must be moonchat.review-text-edits.v1")
  }
  plan
}

///|
/// Apply only exact, nonoverlapping selected replacements to retained source.
/// Every discussion entry and named request survives unchanged; all old receipts
/// stay in the predecessor. Changing text never resolves an objection by itself.
pub fn apply_review_text_edits(
  plan : ReviewTextEditPlan,
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
  previous_bundle_ref~ : String,
) -> ReviewTextEditResult raise {
  let draft = prepare_review_revision(
    previous_bundle_text, previous_source_bytes,
  )
  if plan.format != "moonchat.review-text-edits.v1" ||
    plan.base_bundle_digest != draft.base_bundle_digest ||
    plan.source_digest != review_source_digest(previous_source_bytes) {
    fail("text edit plan does not match the exact retained review and source")
  }
  if plan.next_source_artifact_ref == draft.source_artifact_ref {
    fail(
      "text edits require a new source artifact reference; retain the original",
    )
  }
  if plan.next_source_revision_id == draft.source_revision_id {
    fail("text edits require a new source revision identity")
  }
  if plan.edits.is_empty() || plan.edits.length() > 100 {
    fail("text edit plan must contain between 1 and 100 selected edits")
  }
  let lines = editable_source_lines(previous_source_bytes)
  let edits = plan.edits.copy()
  edits.sort_by((a, b) => a.start_line.compare(b.start_line))
  let keys : Map[String, Bool] = {}
  let mut cursor = 0
  let mut size = previous_source_bytes.length()
  for edit in edits {
    if !safe_identifier(edit.key) || keys.contains(edit.key) {
      fail("text edit keys must be unique safe identifiers")
    }
    keys[edit.key] = true
    if !draft.entries.any(entry => entry.entry_id == edit.entry_id) {
      fail("text edit refers to an unknown discussion entry: " + edit.key)
    }
    if edit.start_line < 1 ||
      edit.end_line < edit.start_line ||
      edit.end_line > lines.length() {
      fail(
        "text edit has an invalid inclusive physical-line range: " + edit.key,
      )
    }
    if edit.start_line - 1 < cursor {
      fail("text edits overlap; select one replacement for each source range")
    }
    let selected = lines[edit.start_line - 1:edit.end_line].to_owned().join("")
    if edit.quote != selected {
      fail(
        "text edit quote differs from the exact selected source lines: " +
        edit.key,
      )
    }
    if edit.replacement == edit.quote {
      fail("text edit does not change its selected source: " + edit.key)
    }
    let replacement_bytes = @utf8.encode(edit.replacement)
    if !edit.replacement.is_empty() {
      ignore(editable_source_lines(replacement_bytes))
    }
    size = size - @utf8.encode(selected).length() + replacement_bytes.length()
    cursor = edit.end_line
  }
  // Validate the complete plan before constructing candidate bytes. A later
  // deletion can offset an earlier expansion; intermediate source sizes are
  // not candidate artifacts and must not determine whether the plan fits.
  if size > 1048576 {
    fail("edited source exceeds the 1 MiB UTF-8 limit")
  }
  let out = StringBuilder()
  cursor = 0
  for edit in edits {
    for index = cursor; index < edit.start_line - 1; index = index + 1 {
      out.write_string(lines[index])
    }
    out.write_string(edit.replacement)
    cursor = edit.end_line
  }
  for index = cursor; index < lines.length(); index = index + 1 {
    out.write_string(lines[index])
  }
  let source_text = out.to_string()
  let source_bytes = @utf8.encode(source_text)
  ignore(editable_source_lines(source_bytes))
  if review_source_digest(source_bytes) == plan.source_digest {
    fail("selected text edits leave the complete source unchanged")
  }
  let next_draft = {
    ..draft,
    source_artifact_ref: plan.next_source_artifact_ref,
    source_revision_id: plan.next_source_revision_id,
    recorded_at: plan.recorded_at,
  }
  let bundle = compile_review_revision(
    next_draft,
    source_bytes,
    previous_bundle_text~,
    previous_source_bytes~,
    previous_bundle_ref~,
  )
  { source_text, bundle, }
}

///|
/// Read every selected before/after replacement followed by the complete pending
/// review. This report does not claim the linked concern has been resolved.
pub fn preview_review_text_edits(
  plan : ReviewTextEditPlan,
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
  previous_bundle_ref~ : String,
) -> String raise {
  let result = apply_review_text_edits(
    plan,
    previous_bundle_text,
    previous_source_bytes,
    previous_bundle_ref~,
  )
  let out = StringBuilder()
  out.write_string("# Selected candidate text edits\n\n")
  out.write_string(
    "Draft content changes only. Every objection and named decision remains for fresh review.\n\n",
  )
  for edit in plan.edits {
    review_markdown_field(out, "Edit", edit.key)
    review_markdown_field(out, "Linked discussion entry", edit.entry_id)
    out.write_string(
      "Original physical lines: \{edit.start_line}–\{edit.end_line}\n\n",
    )
    review_markdown_field(
      out,
      "Before (JSON string, exact terminators)",
      edit.quote.to_json().stringify(),
    )
    review_markdown_field(
      out,
      "After (JSON string, exact terminators)",
      edit.replacement.to_json().stringify(),
    )
  }
  review_markdown_field(out, "Complete candidate source", result.source_text)
  out.write_string(
    export_review_markdown(result.bundle, @utf8.encode(result.source_text)),
  )
  out.to_string()
}
