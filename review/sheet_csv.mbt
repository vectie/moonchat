///|
priv enum SheetCsvState {
  Start
  Bare
  Quoted
  Closed
} derive(Eq)

///|
fn sheet_csv_rows(bytes : Bytes) -> Array[Array[String]] raise {
  if bytes.length() > 1048576 {
    fail("review sheet exceeds the 1 MiB UTF-8 limit")
  }
  let chars = @utf8.decode(bytes, ignore_bom=true).iter().collect()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let field = StringBuilder()
  let mut state = Start
  for index = 0; index < chars.length(); index = index + 1 {
    let ch = chars[index]
    if state == Quoted {
      if ch == '"' {
        state = Closed
      } else {
        field.write_char(ch)
      }
    } else if ch == ',' {
      row.push(field.to_string())
      field.reset()
      state = Start
    } else if ch == '\r' || ch == '\n' {
      // Empty physical lines are harmless; an explicitly quoted empty field
      // is still a record and will receive the normal column-count diagnostic.
      if !row.is_empty() || state != Start {
        row.push(field.to_string())
        rows.push(row)
      }
      row = []
      field.reset()
      state = Start
      if ch == '\r' && chars.get(index + 1) == Some('\n') {
        continue index + 2
      }
    } else if ch == '"' {
      match state {
        Start => state = Quoted
        Closed => {
          field.write_char('"')
          state = Quoted
        }
        _ =>
          fail(
            "CSV record \{rows.length() + 1}: quote inside an unquoted field",
          )
      }
    } else {
      if state == Closed {
        fail(
          "CSV record \{rows.length() + 1}: unexpected text after a closing quote",
        )
      }
      field.write_char(ch)
      state = Bare
    }
    if rows.length() > 5001 || row.length() > 7 {
      fail("review sheet supports seven columns and at most 5000 data records")
    }
  }
  if state == Quoted {
    fail("CSV record \{rows.length() + 1}: unterminated quoted field")
  }
  if !row.is_empty() || state != Start {
    row.push(field.to_string())
    rows.push(row)
  }
  if rows.length() > 5001 {
    fail("review sheet exceeds the 5000 data record limit")
  }
  rows
}

///|
// A reversible text marker prevents generated cells from starting with a
// spreadsheet formula introducer. Original leading apostrophes are escaped too.
fn sheet_text_needs_marker(value : String) -> Bool {
  if value.has_prefix("'") {
    return true
  }
  for ch in value {
    match ch {
      ' ' | '\t' | '\r' | '\n' => continue
      '=' | '+' | '-' | '@' => return true
      _ => return false
    }
  }
  false
}

///|
fn sheet_csv_cell(value : String) -> String {
  let text = if sheet_text_needs_marker(value) { "'" + value } else { value }
  "\"" + text.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn sheet_decode_cell(value : String) -> String {
  if value.has_prefix("'") {
    let rest = value[1:].to_owned()
    if sheet_text_needs_marker(rest) {
      return rest
    }
  }
  value
}
