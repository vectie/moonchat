///|
pub fn parse_review_checklist(text : String) -> ReviewChecklist raise {
  let checklist : ReviewChecklist = @json.from_json(@json.parse(text))
  validate_checklist(checklist)
  checklist
}

///|
pub fn parse_review_checklist_input(
  text : String,
) -> ReviewChecklistInput raise {
  let input : ReviewChecklistInput = @json.from_json(@json.parse(text))
  if input.format != "moonchat.review-checklist-input.v1" {
    fail("unsupported review checklist input format")
  }
  input
}

///|
/// Discover the input slots and their actual uses before assigning people.
pub fn catalog_review_checklist(checklist : ReviewChecklist) -> String raise {
  validate_checklist(checklist)
  let values : Map[String, String] = Map([])
  for name in checklist.variables {
    values[name] = "value"
  }
  let roles = checklist.roles.map(role => {
    let authors = checklist.items
      .filter(item => item.author_role == role)
      .map(item => item.key)
    let decisions = checklist.items
      .filter(item => item.decisions.any(d => d.reviewer_role == role))
      .map(item => item.key)
    {
      "role": role.to_json(),
      "authors_items": authors.to_json(),
      "decides_items": decisions.to_json(),
      "requires_human": (!decisions.is_empty()).to_json(),
    }
  })
  let variables : Array[Json] = []
  for name in checklist.variables {
    let locations : Array[String] = []
    for item in checklist.items {
      let body_uses : Array[String] = []
      ignore(checklist_text(item.body, values, body_uses))
      if body_uses.contains(name) {
        locations.push(item.key + "/body")
      }
      for decision in item.decisions {
        let prompt_uses : Array[String] = []
        ignore(checklist_text(decision.prompt, values, prompt_uses))
        if prompt_uses.contains(name) {
          locations.push(item.key + "/decision/" + decision.reviewer_role)
        }
      }
    }
    variables.push({
      "variable": name.to_json(),
      "used_in": locations.to_json(),
    })
  }
  (
    {
      "format": "moonchat.review-checklist-catalog.v1".to_json(),
      "checklist_id": checklist.checklist_id.to_json(),
      "title": checklist.title.to_json(),
      "roles": roles.to_json(),
      "variables": variables.to_json(),
      "items": checklist.items.to_json(),
      "status": "preparation_only".to_json(),
    } : Json).stringify(indent=2)
}

///|
/// Bind a reusable checklist to new source bytes, literal values and named
/// participants. The returned agenda is editable and has no decision receipts.
pub fn instantiate_review_checklist(
  checklist : ReviewChecklist,
  input : ReviewChecklistInput,
  source_bytes : Bytes,
) -> ReviewAgenda raise {
  validate_checklist(checklist)
  if input.format != "moonchat.review-checklist-input.v1" ||
    input.checklist_id != checklist.checklist_id {
    fail("checklist input format or checklist id does not match")
  }
  if input.source_digest != review_source_digest(source_bytes) {
    fail("checklist source bytes do not match the explicit input digest")
  }
  let roles : Map[String, String] = Map([])
  for assignment in input.role_assignments {
    if !checklist.roles.contains(assignment.role) ||
      roles.contains(assignment.role) {
      fail("unknown or duplicate checklist role assignment: " + assignment.role)
    }
    if participant(input.participants, assignment.participant_id) is None {
      fail("unknown checklist participant: " + assignment.participant_id)
    }
    roles[assignment.role] = assignment.participant_id
  }
  for role in checklist.roles {
    if !roles.contains(role) {
      fail("missing checklist role assignment: " + role)
    }
  }
  let values : Map[String, String] = Map([])
  for binding in input.values {
    if !checklist.variables.contains(binding.variable) ||
      values.contains(binding.variable) {
      fail("unknown or duplicate checklist value: " + binding.variable)
    }
    if !non_empty(binding.value) {
      fail("empty checklist value: " + binding.variable)
    }
    values[binding.variable] = binding.value
  }
  for variable in checklist.variables {
    if !values.contains(variable) {
      fail("missing checklist value: " + variable)
    }
  }
  let items : Array[ReviewAgendaItem] = []
  for item in checklist.items {
    let decisions : Array[ReviewAgendaDecision] = []
    for decision in item.decisions {
      decisions.push({
        reviewer: roles[decision.reviewer_role],
        prompt: checklist_text(decision.prompt, values, []),
      })
    }
    items.push({
      key: item.key,
      kind: item.kind,
      author: roles[item.author_role],
      body: checklist_text(item.body, values, []),
      evidence_refs: [input.source_artifact_ref],
      decisions,
    })
  }
  let agenda : ReviewAgenda = {
    review_id: input.review_id,
    conversation_id: input.conversation_id,
    source_artifact_ref: input.source_artifact_ref,
    source_revision_id: input.source_revision_id,
    source_digest_constraint: "",
    recorded_at: input.recorded_at,
    participants: input.participants.copy(),
    items,
  }
  // Existing authoring rules verify named humans, explicit bindings, timestamp,
  // duplicate resolved reviewers and required decisions for objections.
  ignore(compile_review_agenda(agenda, source_bytes))
  agenda
}
