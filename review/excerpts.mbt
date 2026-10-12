///|
/// Explicit operator selections from one retained UTF-8 transcript. Speaker
/// labels in the transcript never establish a participant or decision identity.
pub(all) struct ReviewExcerptPlan {
  format : String
  transcript_ref : String
  transcript_digest : String
  excerpts : Array[ReviewExcerptSelection]
} derive(Eq, ToJson, @json.FromJson)

///|
/// Line numbers are one-based and inclusive. The author is the person/agent
/// curating this review item, not an inferred speaker in the selected text.
pub(all) struct ReviewExcerptSelection {
  key : String
  kind : String
  author : String
  note : String
  start_line : Int
  end_line : Int
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
fn transcript_lines(bytes : Bytes) -> Array[String] raise {
  if bytes.length() > 1048576 {
    fail("transcript exceeds the 1 MiB UTF-8 input limit")
  }
  let text = @utf8.decode(bytes, ignore_bom=false)
  if text.is_empty() {
    fail("transcript is empty")
  }
  // Retain every original line terminator. A final LF terminates the last
  // physical line; it does not introduce a phantom selectable empty line.
  let parts = text.split("\n").map(part => part.to_string()).collect()
  let lines : Array[String] = []
  for index, part in parts {
    if index < parts.length() - 1 {
      lines.push(part + "\n")
    } else if !part.is_empty() {
      lines.push(part)
    }
  }
  if lines.length() > 10000 {
    fail("transcript exceeds the 10000 line limit")
  }
  lines
}

///|
/// Number source lines before writing a selection plan. JSON string literals
/// make CRLF, tabs, blank lines and control characters visible without executing
/// terminal escapes. The digest covers original bytes, including line endings.
pub fn catalog_review_transcript(transcript_bytes : Bytes) -> String raise {
  let lines = transcript_lines(transcript_bytes)
  let out = StringBuilder()
  out.write_string(
    "Transcript SHA-256: " + review_source_digest(transcript_bytes) + "\n",
  )
  out.write_string(
    "Lines: \{lines.length()} (one-based, inclusive; text is JSON-escaped)\n\n",
  )
  for index, line in lines {
    out.write_string("\{index + 1} | " + line.to_json().stringify() + "\n")
  }
  out.to_string()
}

///|
pub fn parse_review_excerpt_plan(text : String) -> ReviewExcerptPlan raise {
  let plan : ReviewExcerptPlan = @json.from_json(@json.parse(text))
  if plan.format != "moonchat.review-excerpts.v1" {
    fail("excerpt plan format must be moonchat.review-excerpts.v1")
  }
  plan
}

///|
/// Append explicitly curated source excerpts to an agenda, validating the
/// complete result with the existing composer. Returns detached authoring data;
/// no receipts, participants, permissions or source-file changes are created.
/// Each body retains the exact selected text plus source digest and line range.
pub fn import_review_excerpts(
  agenda : ReviewAgenda,
  plan : ReviewExcerptPlan,
  transcript_bytes : Bytes,
  source_bytes : Bytes,
) -> ReviewAgenda raise {
  if plan.format != "moonchat.review-excerpts.v1" {
    fail("excerpt plan format must be moonchat.review-excerpts.v1")
  }
  if !safe_artifact_ref(plan.transcript_ref) {
    fail("transcript_ref must be a workspace-relative artifact reference")
  }
  if plan.transcript_digest != review_source_digest(transcript_bytes) {
    fail("transcript bytes do not match the selected transcript digest")
  }
  if plan.transcript_ref == agenda.source_artifact_ref &&
    plan.transcript_digest != review_source_digest(source_bytes) {
    fail(
      "the transcript and review source cannot give one artifact reference different bytes",
    )
  }
  if plan.excerpts.is_empty() || plan.excerpts.length() > 100 {
    fail("excerpt plan must select between 1 and 100 excerpts")
  }
  let lines = transcript_lines(transcript_bytes)
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  for selection in plan.excerpts {
    if selection.start_line < 1 ||
      selection.end_line < selection.start_line ||
      selection.end_line > lines.length() {
      fail("excerpt \{selection.key} has an invalid inclusive line range")
    }
    if !non_empty(selection.note) {
      fail("excerpt \{selection.key} requires an operator note")
    }
    let excerpt = lines[selection.start_line - 1:selection.end_line]
      .to_owned()
      .join("")
    let body = "Operator note:\n" +
      selection.note +
      "\n\nSelected source: " +
      plan.transcript_ref +
      "\nSource SHA-256: " +
      plan.transcript_digest +
      "\nLines: \{selection.start_line}-\{selection.end_line} (inclusive)" +
      "\nExcerpt (verbatim source text, not a decision receipt):\n" +
      excerpt
    items.push({
      key: selection.key,
      kind: selection.kind,
      author: selection.author,
      body,
      evidence_refs: [plan.transcript_ref],
      decisions: selection.decisions.copy(),
    })
  }
  let imported = { ..agenda, participants: agenda.participants.copy(), items, }
  compile_review_agenda(imported, source_bytes) |> ignore
  imported
}
