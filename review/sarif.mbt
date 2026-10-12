///|
/// A local selection plan. Run/result indexes refer to this exact export digest,
/// never to another analyzer execution. The curator is an existing participant.
pub(all) struct SarifReviewImportPlan {
  format : String
  export_ref : String
  export_digest : String
  findings : Array[SarifReviewSelection]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct SarifReviewSelection {
  run_index : Int
  result_index : Int
  key : String
  kind : String
  author : String
  note : String
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
priv struct SarifFinding {
  run_index : Int
  result_index : Int
  tool : String
  rule : String
  level : String
  message : String
  result : Json
  context : Json
}

///|
fn sarif_object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("SARIF " + label + " must be an object")
  }
}

///|
fn sarif_required(fields : Map[String, Json], key : String) -> Json raise {
  match fields.get(key) {
    Some(value) => value
    None => fail("SARIF requires " + key)
  }
}

///|
fn sarif_text(fields : Map[String, Json], key : String) -> String raise {
  match fields.get(key) {
    Some(String(value)) if non_empty(value) => value
    _ => fail("SARIF requires a nonempty string: " + key)
  }
}

///|
fn sarif_optional_text(
  fields : Map[String, Json],
  key : String,
) -> String raise {
  if fields.contains(key) {
    sarif_text(fields, key)
  } else {
    ""
  }
}

///|
fn sarif_array(fields : Map[String, Json], key : String) -> Array[Json] raise {
  match fields.get(key) {
    Some(Array(values)) => values
    None => []
    _ => fail("SARIF " + key + " must be an array")
  }
}

///|
fn sarif_index(value : Json, label : String) -> Int raise {
  guard value is Number(number, ..) &&
    number >= 0.0 &&
    number <= 2147483647.0 &&
    number.to_int().to_double() == number else {
    fail("SARIF " + label + " must be a nonnegative integer")
  }
  number.to_int()
}

///|
// Resolve primary physical-location indexes for reading. Keep the whole raw
// result as evidence too, including logical locations, code flows and fixes.
fn sarif_locations(
  result : Map[String, Json],
  artifacts : Array[Json],
) -> Array[Json] raise {
  sarif_array(result, "locations").map(location => {
    let fields = sarif_object(location, "location")
    match fields.get("physicalLocation") {
      None => location
      Some(value) => {
        let physical = sarif_object(value, "physicalLocation")
        match physical.get("artifactLocation") {
          None => location
          Some(value) => {
            let artifact = sarif_object(value, "artifactLocation")
            let uri = sarif_optional_text(artifact, "uri")
            let base = sarif_optional_text(artifact, "uriBaseId")
            let resolved = match artifact.get("index") {
              None => {
                if uri == "" {
                  fail("SARIF artifactLocation needs uri or index")
                }
                value
              }
              Some(value) => {
                let index = sarif_index(value, "artifact index")
                guard artifacts.get(index) is Some(target) else {
                  fail("SARIF artifact index is outside this run's artifacts")
                }
                let entry = sarif_object(target, "artifact")
                let target = sarif_required(entry, "location")
                let target_fields = sarif_object(target, "artifact location")
                let target_uri = sarif_text(target_fields, "uri")
                let target_base = sarif_optional_text(
                  target_fields, "uriBaseId",
                )
                if (uri != "" && uri != target_uri) ||
                  (base != "" && base != target_base) {
                  fail(
                    "SARIF inline artifact location disagrees with its artifact index",
                  )
                }
                target
              }
            }
            Json::object({ "location": location, "resolved_artifact": resolved })
          }
        }
      }
    }
  })
}

///|
fn sarif_findings(bytes : Bytes) -> Array[SarifFinding] raise {
  if bytes.length() > 1048576 {
    fail("SARIF export exceeds 1 MiB")
  }
  let document = sarif_object(
    @json.parse(@utf8.decode(bytes, ignore_bom=true)),
    "log",
  )
  if sarif_text(document, "version") != "2.1.0" {
    fail("SARIF version must be 2.1.0")
  }
  let runs = sarif_array(document, "runs")
  if runs.is_empty() || runs.length() > 100 {
    fail("SARIF export must contain 1–100 runs")
  }
  let findings : Array[SarifFinding] = []
  for run_index, value in runs {
    let run = sarif_object(value, "run")
    // Externalized result/property files cannot be silently mistaken for a
    // complete local snapshot. This importer does not fetch any referenced data.
    if run.contains("externalPropertyFileReferences") {
      fail(
        "SARIF external property files are unsupported; use a self-contained log",
      )
    }
    let tool = sarif_object(sarif_required(run, "tool"), "tool")
    let driver_json = sarif_required(tool, "driver")
    let driver = sarif_object(driver_json, "tool.driver")
    let name = sarif_text(driver, "name")
    let rules = sarif_array(driver, "rules")
    let artifacts = sarif_array(run, "artifacts")
    let results = sarif_array(run, "results")
    if findings.length() + results.length() > 1000 {
      fail("SARIF export exceeds 1000 results")
    }
    for result_index, raw in results {
      let result = sarif_object(raw, "result")
      let message = sarif_object(
        sarif_required(result, "message"),
        "result.message",
      )
      let text = match message.get("text") {
        Some(String(text)) if non_empty(text) => text
        _ =>
          fail(
            "SARIF result.message.text is required; expand message IDs before import",
          )
      }
      if message.contains("arguments") {
        fail(
          "SARIF message arguments are unsupported; expand message text before import",
        )
      }
      if result.contains("rule") {
        fail(
          "SARIF result.rule references are unsupported; use driver ruleId/ruleIndex",
        )
      }
      let id = sarif_optional_text(result, "ruleId")
      let (rule_id, rule_json) = match result.get("ruleIndex") {
        None => {
          let matches = rules.filter(rule => {
            let fields = sarif_object(rule, "driver rule")
            id != "" && sarif_text(fields, "id") == id
          })
          if matches.length() > 1 {
            fail("SARIF driver rules contain an ambiguous ruleId")
          }
          (id, matches.get(0).or(Json::null()))
        }
        Some(value) => {
          let index = sarif_index(value, "ruleIndex")
          guard rules.get(index) is Some(rule) else {
            fail("SARIF ruleIndex is outside tool.driver.rules")
          }
          let rule_fields = sarif_object(rule, "driver rule")
          let target_id = sarif_text(rule_fields, "id")
          if id != "" && id != target_id {
            fail("SARIF ruleId disagrees with ruleIndex")
          }
          (target_id, rule)
        }
      }
      let level = sarif_optional_text(result, "level")
      if level != "" &&
        level != "none" &&
        level != "note" &&
        level != "warning" &&
        level != "error" {
        fail("SARIF result level must be none, note, warning or error")
      }
      let driver_context : Map[String, Json] = Map([])
      for key, value in driver {
        if key != "rules" {
          driver_context[key] = value
        }
      }
      let context : Map[String, Json] = {
        "tool_driver": Json::object(driver_context),
        "driver_rule": rule_json,
        "primary_locations": Json::array(sarif_locations(result, artifacts)),
      }
      for
        key in [
          "automationDetails", "originalUriBaseIds", "versionControlProvenance",
          "columnKind",
        ] {
        if run.get(key) is Some(value) {
          context[key] = value
        }
      }
      findings.push({
        run_index,
        result_index,
        tool: name,
        rule: rule_id,
        level,
        message: text,
        result: raw,
        context: Json::object(context),
      })
    }
  }
  findings
}

///|
/// Catalog local analyzer results with zero-based run/result coordinates. All
/// external text is JSON-escaped, and no paths, URLs or suggested fixes are used.
pub fn catalog_sarif_review(sarif_bytes : Bytes) -> String raise {
  let findings = sarif_findings(sarif_bytes)
  let out = StringBuilder()
  out.write_string("SARIF SHA-256: " + review_source_digest(sarif_bytes) + "\n")
  out.write_string(
    "Results: \{findings.length()} (zero-based run/result indexes; exact snapshot only)\n",
  )
  out.write_string(
    "Machine findings are evidence, not human decisions. Levels below are explicit values only.\n",
  )
  for finding in findings {
    out.write_string(
      "\nRun \{finding.run_index}, result \{finding.result_index}\n",
    )
    out.write_string("Tool: " + finding.tool.to_json().stringify() + "\n")
    out.write_string("Rule: " + finding.rule.to_json().stringify() + "\n")
    out.write_string(
      "Explicit level: " + finding.level.to_json().stringify() + "\n",
    )
    out.write_string("Message: " + finding.message.to_json().stringify() + "\n")
    out.write_string("Context: " + finding.context.stringify() + "\n")
    out.write_string("Original result: " + finding.result.stringify() + "\n")
  }
  out.to_string()
}

///|
pub fn parse_sarif_review_import_plan(
  text : String,
) -> SarifReviewImportPlan raise {
  let raw = @json.parse(text)
  let fields = sarif_object(raw, "import plan")
  for selection in sarif_array(fields, "findings") {
    let fields = sarif_object(selection, "selection")
    sarif_index(sarif_required(fields, "run_index"), "run_index") |> ignore
    sarif_index(sarif_required(fields, "result_index"), "result_index")
    |> ignore
  }
  let plan : SarifReviewImportPlan = @json.from_json(raw)
  if plan.format != "moonchat.review-sarif.v1" {
    fail("SARIF plan format must be moonchat.review-sarif.v1")
  }
  plan
}

///|
/// Append explicitly selected analyzer findings to the existing agenda. Keep
/// complete selected result JSON and original snapshot provenance. Selection
/// order determines agenda order; nothing creates or implies an approval.
pub fn import_sarif_review(
  agenda : ReviewAgenda,
  plan : SarifReviewImportPlan,
  sarif_bytes : Bytes,
  source_bytes : Bytes,
) -> ReviewAgenda raise {
  if plan.format != "moonchat.review-sarif.v1" {
    fail("SARIF plan format must be moonchat.review-sarif.v1")
  }
  if !safe_artifact_ref(plan.export_ref) {
    fail("SARIF export_ref must be a workspace-relative artifact reference")
  }
  if plan.export_digest != review_source_digest(sarif_bytes) {
    fail("SARIF bytes do not match the selected export digest")
  }
  if plan.export_ref == agenda.source_artifact_ref &&
    plan.export_digest != review_source_digest(source_bytes) {
    fail(
      "SARIF export and review source cannot give one artifact reference different bytes",
    )
  }
  if plan.findings.is_empty() || plan.findings.length() > 100 {
    fail("SARIF plan must select between 1 and 100 findings")
  }
  let findings = sarif_findings(sarif_bytes)
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  let selected : Map[String, Bool] = Map([])
  for selection in plan.findings {
    let pointer = "/runs/\{selection.run_index}/results/\{selection.result_index}"
    if selected.contains(pointer) {
      fail("SARIF result selected more than once: " + pointer)
    }
    selected[pointer] = true
    guard findings
      .iter()
      .find_first(f => {
        f.run_index == selection.run_index &&
        f.result_index == selection.result_index
      })
      is Some(finding) else {
      fail("SARIF selection does not identify an exported result: " + pointer)
    }
    if !non_empty(selection.note) {
      fail("SARIF selection requires an operator note")
    }
    let body = "Operator note:\n" +
      selection.note +
      "\n\nSARIF export: " +
      plan.export_ref +
      "\nExport SHA-256: " +
      plan.export_digest +
      "\nResult JSON pointer: " +
      pointer +
      "\nAnalyzer: " +
      finding.tool.to_json().stringify() +
      "\nRule: " +
      finding.rule.to_json().stringify() +
      "\nExplicit level: " +
      finding.level.to_json().stringify() +
      "\nAnalyzer message (verbatim text, not a decision receipt):\n" +
      finding.message +
      "\n\nRun/rule/location context (JSON):\n" +
      finding.context.stringify(indent=2) +
      "\n\nOriginal selected result (JSON; fixes are evidence, never executed):\n" +
      finding.result.stringify(indent=2)
    items.push({
      key: selection.key,
      kind: selection.kind,
      author: selection.author,
      body,
      evidence_refs: [plan.export_ref],
      decisions: selection.decisions.copy(),
    })
  }
  let imported = { ..agenda, participants: agenda.participants.copy(), items, }
  compile_review_agenda(imported, source_bytes) |> ignore
  imported
}
