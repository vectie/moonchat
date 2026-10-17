///|
/// Explicit typed replacements in one retained JSON artifact, linked to its
/// review discussion. This is authoring data, never a reviewer receipt.
pub(all) struct ReviewJsonEditPlan {
  format : String
  base_bundle_digest : String
  source_digest : String
  next_source_artifact_ref : String
  next_source_revision_id : String
  recorded_at : String
  edits : Array[ReviewJsonEdit]
} derive(Eq, ToJson, @json.FromJson)

///|
/// Pointers name existing canonical locations. Expected and replacement values
/// retain JSON types and parser-preserved numeric precision; no interpolation.
pub(all) struct ReviewJsonEdit {
  key : String
  entry_id : String
  pointer : String
  expected_value : Json
  replacement : Json
} derive(Eq, ToJson, @json.FromJson)

///|
/// Begin a bound blank plan. The editor selects changes and new source identity.
pub fn prepare_review_json_edits(
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
) -> ReviewJsonEditPlan raise {
  let previous = reimport_review_bundle(previous_bundle_text, previous_source_bytes)
  ignore(json_review_nodes(previous_source_bytes))
  {
    format: "moonchat.review-json-edits.v1",
    base_bundle_digest: review_source_digest(@utf8.encode(previous_bundle_text)),
    source_digest: previous.source_digest,
    next_source_artifact_ref: "",
    next_source_revision_id: "",
    recorded_at: "",
    edits: [],
  }
}

///|
pub fn parse_review_json_edits(text : String) -> ReviewJsonEditPlan raise {
  if @utf8.encode(text).length() > 8388608 { fail("JSON edit plan exceeds 8 MiB") }
  let value = review_parse_exact_json(text)
  json_review_unique_keys(text)
  guard value is Object(fields) else { fail("JSON edit plan must be an object") }
  for key, _ in fields {
    if !["format", "base_bundle_digest", "source_digest", "next_source_artifact_ref", "next_source_revision_id", "recorded_at", "edits"].contains(key) {
      fail("unsupported JSON edit plan field: " + key)
    }
  }
  guard fields.get("edits") is Some(Array(edits)) else { fail("JSON edit plan requires edits") }
  for edit in edits {
    guard edit is Object(values) else { fail("JSON edit must be an object") }
    for key, _ in values {
      if !["key", "entry_id", "pointer", "expected_value", "replacement"].contains(key) {
        fail("unsupported JSON edit field: " + key)
      }
    }
  }
  let plan : ReviewJsonEditPlan = @json.from_json(value)
  if plan.format != "moonchat.review-json-edits.v1" { fail("unsupported JSON edit format") }
  plan
}

///|
fn json_edit_rebuild(value : Json, pointer : String, edits : Map[String, Json]) -> Json {
  if edits.get(pointer) is Some(replacement) { return replacement }
  match value {
    Object(fields) => {
      let result : Map[String, Json] = {}
      for key, child in fields {
        let escaped = key.replace(old="~", new="~0").replace(old="/", new="~1")
        result[key] = json_edit_rebuild(child, pointer + "/" + escaped, edits)
      }
      Json::object(result)
    }
    Array(values) => Json::array(values.mapi((index, child) => json_edit_rebuild(child, pointer + "/\{index}", edits)))
    _ => value
  }
}

///|
/// Generate candidate JSON and a linked pending review. Every discussion entry
/// and named decision survives; historical receipts never approve changed data.
pub fn apply_review_json_edits(
  plan : ReviewJsonEditPlan,
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
  previous_bundle_ref~ : String,
) -> ReviewTextEditResult raise {
  let draft = prepare_review_revision(previous_bundle_text, previous_source_bytes)
  if plan.format != "moonchat.review-json-edits.v1" ||
    plan.base_bundle_digest != draft.base_bundle_digest ||
    plan.source_digest != review_source_digest(previous_source_bytes) {
    fail("JSON edit plan does not match the exact retained review and source")
  }
  if plan.next_source_artifact_ref == draft.source_artifact_ref ||
    plan.next_source_revision_id == draft.source_revision_id {
    fail("JSON edits require a new source reference and revision; retain the original")
  }
  if plan.edits.is_empty() || plan.edits.length() > 100 { fail("JSON edit plan must contain 1..100 edits") }
  let nodes = json_review_nodes(previous_source_bytes)
  let keys : Map[String, Bool] = {}
  let edits : Map[String, Json] = {}
  let mut compact_bytes = @utf8.encode(nodes[""].stringify()).length()
  for edit in plan.edits {
    if !safe_identifier(edit.key) || keys.contains(edit.key) { fail("JSON edit keys must be unique safe identifiers") }
    keys[edit.key] = true
    if !draft.entries.any(entry => entry.entry_id == edit.entry_id) { fail("JSON edit refers to an unknown discussion entry: " + edit.key) }
    guard nodes.get(edit.pointer) is Some(original) else { fail("JSON edit pointer does not identify an existing canonical location: " + edit.key) }
    for prior, _ in edits {
      if prior == edit.pointer || prior == "" || edit.pointer == "" ||
        prior.has_prefix(edit.pointer + "/") || edit.pointer.has_prefix(prior + "/") {
        fail("JSON edits overlap; choose one replacement per source location")
      }
    }
    if original.stringify() != edit.expected_value.stringify() { fail("JSON edit expected value differs from the selected source: " + edit.key) }
    if original.stringify() == edit.replacement.stringify() { fail("JSON edit leaves its selected value unchanged: " + edit.key) }
    // Detach externally supplied mutable JSON and apply the ordinary JSON source
    // limits to each proposed value before constructing the complete candidate.
    let replacement_nodes = json_review_nodes(@utf8.encode(edit.replacement.stringify()))
    edits[edit.pointer] = replacement_nodes[""]
    compact_bytes += @utf8.encode(edit.replacement.stringify()).length() - @utf8.encode(original.stringify()).length()
  }
  if compact_bytes > 1048576 { fail("edited JSON source exceeds 1 MiB") }
  let source_text = json_edit_rebuild(nodes[""], "", edits).stringify(indent=2) + "\n"
  let source_bytes = @utf8.encode(source_text)
  ignore(json_review_nodes(source_bytes))
  let bundle = compile_review_revision(
    { ..draft, source_artifact_ref: plan.next_source_artifact_ref, source_revision_id: plan.next_source_revision_id, recorded_at: plan.recorded_at },
    source_bytes, previous_bundle_text~, previous_source_bytes~, previous_bundle_ref~,
  )
  { source_text, bundle }
}

///|
/// Show each typed before/after value and its linked discussion, followed by the
/// complete candidate and pending review. No concern is automatically resolved.
pub fn preview_review_json_edits(
  plan : ReviewJsonEditPlan,
  previous_bundle_text : String,
  previous_source_bytes : Bytes,
  previous_bundle_ref~ : String,
) -> String raise {
  let result = apply_review_json_edits(plan, previous_bundle_text, previous_source_bytes, previous_bundle_ref~)
  let out = StringBuilder()
  out.write_string("# Selected candidate JSON edits\n\nDraft content changes only. Every objection and named decision remains for fresh review.\n\n")
  for edit in plan.edits {
    review_markdown_field(out, "Edit", edit.key)
    review_markdown_field(out, "Linked discussion entry", edit.entry_id)
    review_markdown_field(out, "JSON Pointer (empty means root)", edit.pointer)
    review_markdown_field(out, "Expected typed value", edit.expected_value.stringify(indent=2))
    review_markdown_field(out, "Replacement typed value", edit.replacement.stringify(indent=2))
  }
  review_markdown_field(out, "Complete candidate JSON", result.source_text)
  out.write_string(export_review_markdown(result.bundle, @utf8.encode(result.source_text)))
  out.to_string()
}
