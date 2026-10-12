///|
/// A conflicting edit retains all three values. Null means the item or decision
/// was absent. No candidate agenda is returned until all conflicts are resolved.
pub(all) struct ReviewSheetConflict {
  item_key : String
  field : String
  base : Json
  left : Json
  right : Json
} derive(Eq, ToJson)

///|
pub(all) struct ReviewSheetMerge {
  format : String
  conflicts : Array[ReviewSheetConflict]
  merged_agenda : ReviewAgenda?
} derive(Eq)

///|
fn[T : ToJson] sheet_merge_optional_json(value : T?) -> Json {
  match value {
    Some(value) => value.to_json()
    None => Json::null()
  }
}

///|
pub impl ToJson for ReviewSheetMerge with fn to_json(self : ReviewSheetMerge) -> Json {
  {
    "format": self.format.to_json(),
    "conflicts": self.conflicts.to_json(),
    "merged_agenda": sheet_merge_optional_json(self.merged_agenda),
  }
}

///|
fn[T : Eq + ToJson] sheet_merge_optional(
  base : T?,
  left : T?,
  right : T?,
  key : String,
  field : String,
  conflicts : Array[ReviewSheetConflict],
) -> T? {
  if left == right {
    left
  } else if left == base {
    right
  } else if right == base {
    left
  } else {
    conflicts.push({
      item_key: key,
      field,
      base: sheet_merge_optional_json(base),
      left: sheet_merge_optional_json(left),
      right: sheet_merge_optional_json(right),
    })
    base
  }
}

///|
fn[T : Eq + ToJson] sheet_merge_value(
  base : T,
  left : T,
  right : T,
  key : String,
  field : String,
  conflicts : Array[ReviewSheetConflict],
) -> T {
  if left == right {
    left
  } else if left == base {
    right
  } else if right == base {
    left
  } else {
    conflicts.push({
      item_key: key,
      field,
      base: base.to_json(),
      left: left.to_json(),
      right: right.to_json(),
    })
    // Internal placeholder only. Any conflict suppresses the whole output agenda.
    base
  }
}

///|
fn sheet_merge_keys(
  base : Array[String],
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let seen : Map[String, Bool] = {}
  let keys : Array[String] = []
  for group in [base, left, right] {
    for key in group {
      if !seen.contains(key) {
        seen[key] = true
        keys.push(key)
      }
    }
  }
  keys
}

///|
fn sheet_merge_order(
  base : Array[String],
  left : Array[String],
  right : Array[String],
  retained : Array[String],
  key : String,
  field : String,
  conflicts : Array[ReviewSheetConflict],
) -> Array[String] {
  // Missing identities already have a deletion/content conflict, if any. They
  // cannot also express a reorder and must not produce a spurious order conflict.
  let existing = fn(value) {
    base.contains(value) &&
    retained.contains(value) &&
    left.contains(value) &&
    right.contains(value)
  }
  let order = sheet_merge_value(
    base.filter(existing),
    left.filter(existing),
    right.filter(existing),
    key,
    field,
    conflicts,
  ).copy()
  // New identities have no common-base position: append left-only then right-only
  // additions, retaining each branch's order and coalescing identical additions.
  for value in retained {
    if !base.contains(value) {
      order.push(value)
    }
  }
  order
}

///|
fn sheet_merge_decisions(
  base : Array[ReviewAgendaDecision],
  left : Array[ReviewAgendaDecision],
  right : Array[ReviewAgendaDecision],
  key : String,
  conflicts : Array[ReviewSheetConflict],
) -> Array[ReviewAgendaDecision] {
  let b = Map::from_array(base.map(d => (d.reviewer, d.prompt)))
  let l = Map::from_array(left.map(d => (d.reviewer, d.prompt)))
  let r = Map::from_array(right.map(d => (d.reviewer, d.prompt)))
  let bk = base.map(d => d.reviewer)
  let lk = left.map(d => d.reviewer)
  let rk = right.map(d => d.reviewer)
  let merged : Map[String, String] = {}
  let retained : Array[String] = []
  for reviewer in sheet_merge_keys(bk, lk, rk) {
    match
      sheet_merge_optional(
        b.get(reviewer),
        l.get(reviewer),
        r.get(reviewer),
        key,
        "decision:" + reviewer,
        conflicts,
      ) {
      Some(prompt) => {
        merged[reviewer] = prompt
        retained.push(reviewer)
      }
      None => ()
    }
  }
  sheet_merge_order(bk, lk, rk, retained, key, "decision_order", conflicts).map(reviewer => {
      ({ reviewer, prompt: merged[reviewer], } : ReviewAgendaDecision)
    },
  )
}

///|
fn sheet_merge_item(
  base : ReviewAgendaItem,
  left : ReviewAgendaItem,
  right : ReviewAgendaItem,
  conflicts : Array[ReviewSheetConflict],
) -> ReviewAgendaItem {
  let key = base.key
  {
    key,
    kind: sheet_merge_value(
      base.kind,
      left.kind,
      right.kind,
      key,
      "kind",
      conflicts,
    ),
    author: sheet_merge_value(
      base.author,
      left.author,
      right.author,
      key,
      "author",
      conflicts,
    ),
    body: sheet_merge_value(
      base.body,
      left.body,
      right.body,
      key,
      "body",
      conflicts,
    ),
    evidence_refs: sheet_merge_value(
      base.evidence_refs,
      left.evidence_refs,
      right.evidence_refs,
      key,
      "evidence_refs",
      conflicts,
    ).copy(),
    decisions: sheet_merge_decisions(
      base.decisions,
      left.decisions,
      right.decisions,
      key,
      conflicts,
    ),
  }
}

///|
fn sheet_merge_copy_item(item : ReviewAgendaItem) -> ReviewAgendaItem {
  {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  }
}

///|
/// Merge two independently edited CSV copies of the same base agenda. Scalars
/// merge per field, named requests per reviewer; evidence arrays are atomic.
/// Deletion versus modification and incompatible new identities are conflicts.
/// Existing-item reorders merge separately; new items append in left/right order.
/// The input agenda, CSVs and source bytes are never modified. Validation errors
/// raise; edit conflicts return a complete report with no partial agenda.
pub fn merge_review_sheets(
  base : ReviewAgenda,
  left_csv : Bytes,
  right_csv : Bytes,
  source_bytes : Bytes,
) -> ReviewSheetMerge raise {
  compile_review_agenda(base, source_bytes) |> ignore
  let left = import_review_sheet(base, left_csv, source_bytes)
  let right = import_review_sheet(base, right_csv, source_bytes)
  merge_agenda_items(base, left, right, source_bytes)
}

///|
// Shared by spreadsheet edits and local GitHub snapshot refresh. Each caller
// validates its branch inputs and keeps their non-item metadata identical.
fn merge_agenda_items(
  base : ReviewAgenda,
  left : ReviewAgenda,
  right : ReviewAgenda,
  source_bytes : Bytes,
) -> ReviewSheetMerge raise {
  let b = Map::from_array(base.items.map(item => (item.key, item)))
  let l = Map::from_array(left.items.map(item => (item.key, item)))
  let r = Map::from_array(right.items.map(item => (item.key, item)))
  let bk = base.items.map(item => item.key)
  let lk = left.items.map(item => item.key)
  let rk = right.items.map(item => item.key)
  let conflicts : Array[ReviewSheetConflict] = []
  let merged : Map[String, ReviewAgendaItem] = {}
  let retained : Array[String] = []
  for key in sheet_merge_keys(bk, lk, rk) {
    let item = match (b.get(key), l.get(key), r.get(key)) {
      (Some(base), Some(left), Some(right)) =>
        Some(sheet_merge_item(base, left, right, conflicts))
      (base, left, right) =>
        sheet_merge_optional(base, left, right, key, "item", conflicts)
    }
    if item is Some(value) {
      merged[key] = sheet_merge_copy_item(value)
      retained.push(key)
    }
  }
  let order = sheet_merge_order(
    bk, lk, rk, retained, "", "item_order", conflicts,
  )
  let candidate = {
    ..base,
    participants: base.participants.copy(),
    items: order.map(key => merged[key]),
  }
  let merged_agenda = if conflicts.is_empty() {
    // Independent valid edits can interact (for example, deleting the final two
    // required decisions on separate branches). Validate their combined result.
    compile_review_agenda(candidate, source_bytes) |> ignore
    Some(candidate)
  } else {
    None
  }
  { format: "moonchat.review-sheet-merge.v1", conflicts, merged_agenda, }
}
