///|
// One pass over template characters. Inserted values are literal, never parsed
// again. $$ writes one dollar sign, so $${name} writes a literal ${name}.
fn checklist_text(
  text : String,
  values : Map[String, String],
  used : Array[String],
) -> String raise {
  let chars = text.iter().collect()
  let output = StringBuilder()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '$' && chars.get(i + 1) == Some('$') {
      output.write_char('$')
      continue i + 2
    }
    if chars[i] == '$' && chars.get(i + 1) == Some('{') {
      let name = StringBuilder()
      let mut end = i + 2
      while end < chars.length() && chars[end] != '}' {
        name.write_char(chars[end])
        end = end + 1
      }
      if end == chars.length() || !safe_identifier(name.to_string()) {
        fail("invalid or unterminated checklist variable")
      }
      let key = name.to_string()
      let value = match values.get(key) {
        Some(value) => value
        None => fail("undeclared checklist variable: " + key)
      }
      if !used.contains(key) {
        used.push(key)
      }
      output.write_string(value)
      continue end + 1
    }
    output.write_char(chars[i])
  }
  output.to_string()
}

///|
fn checklist_names(label : String, names : Array[String]) -> Unit raise {
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if !safe_identifier(name) || seen.contains(name) {
      fail("checklist " + label + " must have unique safe names: " + name)
    }
    seen[name] = true
  }
}

///|
fn validate_checklist(checklist : ReviewChecklist) -> Unit raise {
  if checklist.format != "moonchat.review-checklist.v1" {
    fail("unsupported review checklist format")
  }
  if !safe_identifier(checklist.checklist_id) || !non_empty(checklist.title) {
    fail("checklist needs an id and title")
  }
  if checklist.roles.is_empty() || checklist.items.is_empty() {
    fail("checklist needs roles and items")
  }
  checklist_names("roles", checklist.roles)
  checklist_names("variables", checklist.variables)
  checklist_names("item keys", checklist.items.map(item => item.key))
  let variables : Map[String, String] = Map([])
  for name in checklist.variables {
    variables[name] = "value"
  }
  let used : Array[String] = []
  let mut decisions = 0
  for item in checklist.items {
    if !["question", "objection", "proposal"].contains(item.kind) ||
      !checklist.roles.contains(item.author_role) ||
      !non_empty(item.body) {
      fail("invalid checklist item: " + item.key)
    }
    ignore(checklist_text(item.body, variables, used))
    let reviewers : Array[String] = []
    for decision in item.decisions {
      if !checklist.roles.contains(decision.reviewer_role) ||
        reviewers.contains(decision.reviewer_role) ||
        !non_empty(decision.prompt) {
        fail("invalid checklist decision: " + item.key)
      }
      reviewers.push(decision.reviewer_role)
      ignore(checklist_text(decision.prompt, variables, used))
      decisions = decisions + 1
    }
    if item.kind == "objection" && item.decisions.is_empty() {
      fail("checklist objection requires a named decision: " + item.key)
    }
  }
  if decisions == 0 {
    fail("checklist needs at least one named decision")
  }
  for name in checklist.variables {
    if !used.contains(name) {
      fail("unused checklist variable: " + name)
    }
  }
}
