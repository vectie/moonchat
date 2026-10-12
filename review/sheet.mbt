///|
fn review_sheet_columns() -> Array[String] {
  ["key", "kind", "author", "body", "evidence_ref", "reviewer", "prompt"]
}

///|
/// Export an editable seven-column UTF-8 CSV. Repeat an item's core fields for
/// additional evidence or decision requests. All fields are quoted, with a
/// reversible apostrophe marker for formula-like text and leading apostrophes.
pub fn export_review_sheet(
  agenda : ReviewAgenda,
  source_bytes : Bytes,
) -> String raise {
  compile_review_agenda(agenda, source_bytes) |> ignore
  let out = StringBuilder()
  out.write_string(review_sheet_columns().join(",") + "\r\n")
  for item in agenda.items {
    let count = item.evidence_refs.length().max(item.decisions.length()).max(1)
    for index = 0; index < count; index = index + 1 {
      let (reviewer, prompt) = match item.decisions.get(index) {
        Some(decision) => (decision.reviewer, decision.prompt)
        None => ("", "")
      }
      let cells = [
        item.key,
        item.kind,
        item.author,
        item.body,
        item.evidence_refs.get(index).unwrap_or(""),
        reviewer,
        prompt,
      ]
      out.write_string(cells.map(sheet_csv_cell).join(",") + "\r\n")
    }
  }
  let csv = out.to_string()
  // Ensure every successful export is inside the same import bounds.
  sheet_csv_rows(@utf8.encode(csv)) |> ignore
  csv
}

///|
/// Replace an agenda's items with CSV rows, keeping source metadata and the
/// participant roster from the supplied template. First occurrence determines
/// item order; repeat keys to add references and named decision requests.
/// Validate against actual source bytes before returning detached authoring data.
pub fn import_review_sheet(
  agenda : ReviewAgenda,
  csv_bytes : Bytes,
  source_bytes : Bytes,
) -> ReviewAgenda raise {
  let rows = sheet_csv_rows(csv_bytes)
  if rows.is_empty() || rows[0] != review_sheet_columns() {
    fail(
      "review sheet header must be key,kind,author,body,evidence_ref,reviewer,prompt",
    )
  }
  let items : Array[ReviewAgendaItem] = []
  let indices : Map[String, Int] = Map([])
  for index = 1; index < rows.length(); index = index + 1 {
    let row = rows[index]
    if row.length() != 7 {
      fail(
        "CSV record \{index + 1}: expected seven columns, got \{row.length()}",
      )
    }
    let cells = row.map(sheet_decode_cell)
    let key = cells[0]
    let item = match indices.get(key) {
      Some(position) => {
        let existing = items[position]
        if existing.kind != cells[1] ||
          existing.author != cells[2] ||
          existing.body != cells[3] {
          fail(
            "CSV record \{index + 1}: repeated key \{key} has conflicting kind, author or body",
          )
        }
        existing
      }
      None => {
        let item : ReviewAgendaItem = {
          key,
          kind: cells[1],
          author: cells[2],
          body: cells[3],
          evidence_refs: [],
          decisions: [],
        }
        indices[key] = items.length()
        items.push(item)
        item
      }
    }
    if !cells[4].is_empty() {
      item.evidence_refs.push(cells[4])
    }
    if cells[5].is_empty() != cells[6].is_empty() {
      fail(
        "CSV record \{index + 1}: reviewer and prompt must be supplied together",
      )
    }
    if !cells[5].is_empty() {
      item.decisions.push({ reviewer: cells[5], prompt: cells[6], })
    }
  }
  let imported = { ..agenda, participants: agenda.participants.copy(), items, }
  compile_review_agenda(imported, source_bytes) |> ignore
  imported
}
