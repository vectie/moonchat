///|
/// Explicit JSON Pointer selections from one exact UTF-8 JSON artifact.
pub(all) struct JsonReviewImportPlan {
  format : String
  source_digest : String
  selections : Array[JsonReviewSelection]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct JsonReviewSelection {
  pointer : String
  key : String
  kind : String
  author : String
  note : String
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
// Parsing has already validated syntax. Scan string tokens to reject duplicate
// decoded object names, which would otherwise hide evidence behind the last key.
fn json_review_unique_keys(text : String) -> Unit raise {
  let objects : Array[Map[String, Bool]] = []
  let mut i = 0
  while i < text.length() {
    match text[i] {
      '{' => {
        objects.push({})
        i += 1
      }
      '}' => {
        objects.pop() |> ignore
        i += 1
      }
      '"' => {
        let start = i
        i += 1
        while i < text.length() && text[i] != '"' {
          if text[i] == '\\' {
            i += 2
          } else {
            i += 1
          }
        }
        i += 1
        let end = i
        while i < text.length() &&
              (
                text[i] == ' ' ||
                text[i] == '\n' ||
                text[i] == '\r' ||
                text[i] == '\t'
              ) {
          i += 1
        }
        if i < text.length() && text[i] == ':' {
          let key : String = @json.from_json(@json.parse(text[start:end]))
          let keys = objects[objects.length() - 1]
          if keys.contains(key) {
            fail("JSON artifact contains a duplicate object key")
          }
          keys[key] = true
        }
      }
      _ => i += 1
    }
  }
}

///|
fn json_review_walk(
  value : Json,
  pointer : String,
  nodes : Map[String, Json],
) -> Unit raise {
  if nodes.length() >= 10000 {
    fail("JSON artifact exceeds 10000 nodes")
  }
  nodes[pointer] = value
  match value {
    Object(fields) =>
      for key, child in fields {
        let escaped = key.replace(old="~", new="~0").replace(old="/", new="~1")
        json_review_walk(child, pointer + "/" + escaped, nodes)
      }
    Array(values) =>
      for index, child in values {
        json_review_walk(child, pointer + "/\{index}", nodes)
      }
    _ => ()
  }
}

///|
fn json_review_nodes(bytes : Bytes) -> Map[String, Json] raise {
  if bytes.length() > 1048576 {
    fail("JSON artifact exceeds 1 MiB")
  }
  let text = @utf8.decode(bytes, ignore_bom=false)
  let value = @json.parse(text, max_nesting_depth=64)
  json_review_unique_keys(text)
  let nodes : Map[String, Json] = {}
  json_review_walk(value, "", nodes)
  nodes
}

///|
/// Catalog canonical RFC 6901 string pointers. Empty pointer selects the root;
/// ~0 and ~1 escape tilde and slash. URI fragment syntax is not accepted.
pub fn catalog_json_review(bytes : Bytes) -> String raise {
  let nodes = json_review_nodes(bytes)
  let rows : Array[Json] = []
  for pointer, value in nodes {
    let summary = match value {
      Object(fields) =>
        Json::object({
          "type": "object".to_json(),
          "children": fields.length().to_json(),
        })
      Array(values) =>
        Json::object({
          "type": "array".to_json(),
          "children": values.length().to_json(),
        })
      _ => Json::object({ "type": "value".to_json(), "value": value })
    }
    rows.push(
      Json::object({ "pointer": pointer.to_json(), "summary": summary }),
    )
  }
  Json::object({
    "format": "moonchat.json-catalog.v1".to_json(),
    "source_digest": review_source_digest(bytes).to_json(),
    "nodes": rows.to_json(),
  }).stringify(indent=2)
}

///|
pub fn parse_json_review_import_plan(
  text : String,
) -> JsonReviewImportPlan raise {
  let plan : JsonReviewImportPlan = @json.from_json(@json.parse(text))
  if plan.format != "moonchat.review-json.v1" {
    fail("JSON plan format must be moonchat.review-json.v1")
  }
  plan
}

///|
/// Append selected JSON values as evidence, never as participant authority or
/// receipts. Serialized values are decoded JSON, not verbatim source excerpts.
pub fn import_json_review(
  agenda : ReviewAgenda,
  plan : JsonReviewImportPlan,
  bytes : Bytes,
) -> ReviewAgenda raise {
  if plan.format != "moonchat.review-json.v1" {
    fail("JSON plan format must be moonchat.review-json.v1")
  }
  if plan.source_digest != review_source_digest(bytes) {
    fail("JSON bytes do not match the selected source digest")
  }
  if plan.selections.is_empty() || plan.selections.length() > 100 {
    fail("JSON plan must select 1–100 pointers")
  }
  let nodes = json_review_nodes(bytes)
  let selected : Map[String, Bool] = {}
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  let mut total = 0
  for selection in plan.selections {
    if selected.contains(selection.pointer) {
      fail("JSON pointer selected more than once")
    }
    selected[selection.pointer] = true
    guard nodes.get(selection.pointer) is Some(value) else {
      fail("JSON pointer does not identify a value in this artifact")
    }
    if !non_empty(selection.note) {
      fail("JSON selection requires an operator note")
    }
    let evidence = Json::object({
      "source_ref": agenda.source_artifact_ref.to_json(),
      "source_digest": plan.source_digest.to_json(),
      "pointer": selection.pointer.to_json(),
      "value": value,
    })
    let body = "Operator note:\n" +
      selection.note +
      "\n\nSelected JSON evidence (decoded value; not a decision receipt):\n" +
      evidence.stringify(indent=2)
    total += @utf8.encode(body).length()
    if total > 8388608 {
      fail("JSON selected evidence exceeds 8 MiB")
    }
    items.push({
      key: selection.key,
      kind: selection.kind,
      author: selection.author,
      body,
      evidence_refs: [agenda.source_artifact_ref],
      decisions: selection.decisions.copy(),
    })
  }
  let imported = { ..agenda, participants: agenda.participants.copy(), items, }
  compile_review_agenda(imported, bytes) |> ignore
  imported
}
