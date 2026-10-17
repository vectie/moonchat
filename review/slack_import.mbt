///|
/// Curated selections from one exact local Slack daily JSON array. Participants
/// describe the curator and requested reviewers, never inferred Slack identity.
pub(all) struct SlackReviewImportPlan {
  format : String
  source_digest : String
  selections : Array[SlackReviewSelection]
} derive(Eq, ToJson, @json.FromJson)

///|
/// Ordinals are one-based positions in the complete array, including unsupported
/// records. Every selection must use the catalog's exact source digest.
pub(all) struct SlackReviewSelection {
  ordinal : Int
  key : String
  kind : String
  author : String
  note : String
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
priv struct SlackReviewMessage {
  raw : String
  recorded : Json
  classification : String
  reason : String
}

///|
fn slack_timestamp(value : Json?) -> Bool {
  guard value is Some(String(text)) else { return false }
  guard text.split_once(".") is Some((seconds, fraction)) else { return false }
  !seconds.is_empty() &&
  seconds.length() <= 20 &&
  fraction.length() == 6 &&
  seconds.iter().all(c => c >= '0' && c <= '9') &&
  fraction.iter().all(c => c >= '0' && c <= '9')
}

///|
fn slack_string(value : Json?) -> Bool {
  match value {
    Some(String(text)) => non_empty(text)
    _ => false
  }
}

///|
fn slack_classify(fields : Map[String, Json]) -> (String, String) {
  if fields.get("type") != Some("message".to_json()) {
    return ("unsupported", "record type must be message")
  }
  let subtype = match fields.get("subtype") {
    None => "ordinary"
    Some(String(value)) => value
    _ => return ("unsupported", "subtype must be absent or a supported string")
  }
  if subtype == "message_changed" || subtype == "message_deleted" {
    return (
      "archival_" + subtype,
      "archival edit/deletion is not a selectable message snapshot",
    )
  }
  if !["ordinary", "me_message", "bot_message", "file_share"].contains(subtype) ||
    (subtype == "ordinary" && fields.contains("subtype")) {
    return ("unsupported", "unsupported message subtype")
  }
  for
    key in [
      "previous", "previous_message", "original_ts", "deleted_ts", "message",
    ] {
    if fields.contains(key) {
      return (
        "archival_ambiguous", "archival/envelope fields require a supported archival adapter",
      )
    }
  }
  match fields.get("hidden") {
    None | Some(False) => ()
    _ => return ("unsupported", "hidden records are not selectable")
  }
  if !slack_timestamp(fields.get("ts")) {
    return (
      "unsupported", "ts must be a decimal-seconds string with six fractional digits",
    )
  }
  if fields.contains("thread_ts") && !slack_timestamp(fields.get("thread_ts")) {
    return (
      "unsupported", "thread_ts must use the same string timestamp profile",
    )
  }
  if !(fields.get("text") is Some(String(_))) {
    return (
      "unsupported", "text must be a string, including empty attachment-only text",
    )
  }
  if fields.contains("user") && !slack_string(fields.get("user")) {
    return (
      "unsupported", "recorded user must be a nonempty string when present",
    )
  }
  if !slack_string(fields.get("user")) &&
    !(subtype == "bot_message" && slack_string(fields.get("bot_id"))) {
    return (
      "unsupported", "recorded user is required, or bot_id for bot_message",
    )
  }
  if fields.contains("edited") {
    guard fields.get("edited") is Some(Object(edited)) else {
      return ("unsupported", "edited metadata must be an object")
    }
    if !slack_string(edited.get("user")) || !slack_timestamp(edited.get("ts")) {
      return (
        "unsupported", "edited metadata requires recorded user and string ts",
      )
    }
    return (subtype + "_edited_snapshot", "")
  }
  (subtype + "_snapshot", "")
}

///|
// Only called after complete JSON validation. String escaping is skipped while
// scanning balanced containers, so braces and quotes inside text stay literal.
fn slack_raw_objects(text : String) -> Array[String] {
  let raw : Array[String] = []
  let mut depth = 0
  let mut start = 0
  let mut i = 0
  while i < text.length() {
    match text[i] {
      '"' => {
        i += 1
        while i < text.length() && text[i] != '"' {
          if text[i] == '\\' {
            i += 2
          } else {
            i += 1
          }
        }
      }
      '[' | '{' => {
        if depth == 1 {
          start = i
        }
        depth += 1
      }
      ']' | '}' => {
        depth -= 1
        if depth == 1 {
          raw.push(text[start:i + 1].to_owned())
        }
      }
      _ => ()
    }
    i += 1
  }
  raw
}

///|
fn slack_messages(bytes : Bytes) -> Array[SlackReviewMessage] raise {
  if bytes.length() > 1048576 {
    fail("Slack export exceeds 1 MiB")
  }
  let text = @utf8.decode(bytes, ignore_bom=false)
  guard @json.parse(text, max_nesting_depth=64) is Array(values) else {
    fail(
      "expected one local Slack daily JSON array, not ZIP, TXT or API envelope",
    )
  }
  if values.length() > 1000 {
    fail("Slack export exceeds 1000 records")
  }
  json_review_unique_keys(text)
  for value in values {
    guard value is Object(_) else {
      fail("each Slack export record must be an object")
    }
  }
  let raw = slack_raw_objects(text)
  assert_eq(raw.length(), values.length())
  let messages : Array[SlackReviewMessage] = []
  for index, value in values {
    guard value is Object(fields) else { fail("expected object") }
    let (classification, reason) = slack_classify(fields)
    let recorded : Map[String, Json] = {}
    for
      key in [
        "type", "subtype", "ts", "thread_ts", "user", "bot_id", "text", "edited",
        "reactions", "attachments", "files",
      ] {
      if fields.get(key) is Some(value) {
        recorded[key] = value
      }
    }
    messages.push({
      raw: raw[index],
      recorded: Json::object(recorded),
      classification,
      reason,
    })
  }
  messages
}

///|
/// Catalog every record in file order, including explicit unsupported reasons.
/// raw_message is a JSON string containing the exact original object slice.
/// Reactions, links, metadata and quoted claims are evidence, never approval.
pub fn catalog_slack_review(bytes : Bytes) -> String raise {
  let rows : Array[Json] = []
  for index, message in slack_messages(bytes) {
    rows.push(
      Json::object({
        "ordinal": (index + 1).to_json(),
        "selectable": message.reason.is_empty().to_json(),
        "classification": message.classification.to_json(),
        "reason": message.reason.to_json(),
        "recorded": message.recorded,
        "raw_message": message.raw.to_json(),
      }),
    )
  }
  Json::object({
    "format": "moonchat.slack-catalog.v1".to_json(),
    "source_digest": review_source_digest(bytes).to_json(),
    "scope": "Local daily snapshot only; no current-state, completeness or identity verification".to_json(),
    "messages": rows.to_json(),
  }).stringify(indent=2)
}

///|
pub fn parse_slack_review_import_plan(
  text : String,
) -> SlackReviewImportPlan raise {
  if @utf8.encode(text).length() > 1048576 {
    fail("Slack import plan exceeds 1 MiB")
  }
  let value = @json.parse(text, max_nesting_depth=64)
  json_review_unique_keys(text)
  slack_validate_ordinal_tokens(text)
  let plan : SlackReviewImportPlan = @json.from_json(value)
  if plan.format != "moonchat.review-slack.v1" {
    fail("Slack plan format must be moonchat.review-slack.v1")
  }
  plan
}

///|
/// Append explicit source-bound quoted message evidence to an editable agenda.
/// The entire daily file is the reviewed source; no thread is fetched, stitched,
/// replayed or marked current. Existing authoring rules require named decisions.
pub fn import_slack_review(
  agenda : ReviewAgenda,
  plan : SlackReviewImportPlan,
  bytes : Bytes,
) -> ReviewAgenda raise {
  validate_agenda_source_constraint(agenda, bytes)
  if plan.format != "moonchat.review-slack.v1" {
    fail("Slack plan format must be moonchat.review-slack.v1")
  }
  if plan.source_digest != review_source_digest(bytes) {
    fail("Slack bytes do not match the selected source digest")
  }
  if plan.selections.is_empty() || plan.selections.length() > 100 {
    fail("Slack plan must select 1–100 messages")
  }
  let messages = slack_messages(bytes)
  let selected : Map[Int, Bool] = {}
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  let mut total = 0
  for selection in plan.selections {
    if selection.ordinal < 1 {
      fail("Slack ordinals must be positive")
    }
    if selected.contains(selection.ordinal) {
      fail("Slack message selected more than once")
    }
    selected[selection.ordinal] = true
    guard messages.get(selection.ordinal - 1) is Some(message) else {
      fail("selected Slack message does not exist")
    }
    if !message.reason.is_empty() {
      fail(
        "Slack ordinal \{selection.ordinal} is not selectable: " +
        message.reason,
      )
    }
    if !non_empty(selection.note) {
      fail("Slack selection requires a curator note")
    }
    let evidence = Json::object({
      "source_ref": agenda.source_artifact_ref.to_json(),
      "source_digest": plan.source_digest.to_json(),
      "ordinal": selection.ordinal.to_json(),
      "classification": message.classification.to_json(),
      "recorded": message.recorded,
      "raw_message": message.raw.to_json(),
    })
    let body = "Curator note:\n" +
      selection.note +
      "\n\nQuoted Slack message evidence (local snapshot; not a decision receipt):\n" +
      "Agenda author is the curator, not a verified mapping of the recorded Slack user.\n" +
      "Reactions do not establish approval. Thread context and current state are unknown.\n" +
      evidence.stringify(indent=2)
    let size = @utf8.encode(body).length()
    if size > 8388608 - total {
      fail("selected Slack evidence exceeds 8 MiB")
    }
    total += size
    items.push({
      key: selection.key,
      kind: selection.kind,
      author: selection.author,
      body,
      evidence_refs: [agenda.source_artifact_ref],
      decisions: selection.decisions.copy(),
    })
  }
  let imported = {
    ..agenda,
    source_digest_constraint: plan.source_digest,
    participants: agenda.participants.copy(),
    items,
  }
  compile_review_agenda(imported, bytes) |> ignore
  imported
}
