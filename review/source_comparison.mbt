///|
priv struct SourceComparisonRow {
  kind : String
  before_line : Int
  after_line : Int
  text : String
}

///|
// Keep physical line terminators in the comparison keys. A newline-only edit
// must stay visible even when its source would look identical in Markdown.
fn source_comparison_lines(bytes : Bytes) -> Array[String] raise {
  if bytes.length() > 1048576 {
    fail("source text comparison exceeds the 1 MiB limit per source")
  }
  let text = @utf8.decode(bytes, ignore_bom=false) catch {
    _ => fail("source text comparison requires valid UTF-8 on both sides")
  }
  let lines : Array[String] = []
  let mut start = 0
  for i = 0; i < text.length(); {
    let end = if text[i] == '\r' {
      if i + 1 < text.length() && text[i + 1] == '\n' {
        i + 2
      } else {
        i + 1
      }
    } else if text[i] == '\n' {
      i + 1
    } else {
      0
    }
    if end > 0 {
      lines.push(text[start:end].to_owned())
      start = end
      continue end
    } else {
      continue i + 1
    }
  }
  if start < text.length() {
    lines.push(text[start:].to_owned())
  }
  if lines.length() > 2000 {
    fail(
      "source text comparison exceeds the 2000 physical-line limit per source",
    )
  }
  lines
}

///|
// Bounded LCS: at most 2001 * 2001 integer cells. Deletion wins an equal-length
// choice, so repeated lines have a stable alignment on all supported targets.
fn source_comparison_rows(
  before : Array[String],
  after : Array[String],
) -> Array[SourceComparisonRow] {
  let n = before.length()
  let m = after.length()
  let lengths = FixedArray::make((n + 1) * (m + 1), 0)
  for i = n - 1; i >= 0; i = i - 1 {
    for j = m - 1; j >= 0; j = j - 1 {
      lengths[i * (m + 1) + j] = if before[i] == after[j] {
        1 + lengths[(i + 1) * (m + 1) + j + 1]
      } else {
        Int::max(lengths[(i + 1) * (m + 1) + j], lengths[i * (m + 1) + j + 1])
      }
    }
  }
  let rows : Array[SourceComparisonRow] = []
  for i = 0, j = 0; i < n || j < m; {
    if i < n && j < m && before[i] == after[j] {
      rows.push({
        kind: "=",
        before_line: i + 1,
        after_line: j + 1,
        text: before[i],
      })
      continue i + 1, j + 1
    } else if i < n &&
      (j == m || lengths[(i + 1) * (m + 1) + j] >= lengths[i * (m + 1) + j + 1]) {
      rows.push({
        kind: "-",
        before_line: i + 1,
        after_line: 0,
        text: before[i],
      })
      continue i + 1, j
    } else {
      rows.push({
        kind: "+",
        before_line: 0,
        after_line: j + 1,
        text: after[j],
      })
      continue i, j + 1
    }
  }
  rows
}

///|
fn compare_review_source_text(
  out : StringBuilder,
  before : Bytes,
  after : Bytes,
  context : Int,
) -> Unit raise {
  if context < 0 || context > 20 {
    fail("source text context must be between 0 and 20 lines")
  }
  let old_lines = source_comparison_lines(before)
  let new_lines = source_comparison_lines(after)
  let rows = source_comparison_rows(old_lines, new_lines)
  let mut added = 0
  let mut removed = 0
  for row in rows {
    if row.kind == "+" {
      added += 1
    } else if row.kind == "-" {
      removed += 1
    }
  }
  out.write_string("## Source text changes\n\n")
  out.write_string(
    "\{old_lines.length()} before lines; \{new_lines.length()} after lines; \{added} added; \{removed} removed. Context: \{context} unchanged lines per side.\n\n",
  )
  out.write_string(
    "Literal physical lines, including their terminators, are compared exactly. Rows show change (= context, - removed, + added), before line, after line, and a JSON string. Escapes expose tabs, CR/LF and controls; \\uFEFF exposes a BOM. Empty sources have zero lines.\n\n",
  )
  if added == 0 && removed == 0 {
    out.write_string("No source text changes.\n\n")
    return
  }
  // Expand each changed row by context, union adjacent intervals, and emit
  // every change once. No changed line is hidden by the context setting.
  let selected = FixedArray::make(rows.length(), false)
  for i, row in rows {
    if row.kind != "=" {
      let start = Int::max(0, i - context)
      let end = Int::min(rows.length(), i + context + 1)
      for k = start; k < end; k = k + 1 {
        selected[k] = true
      }
    }
  }
  let mut hunk = 0
  let mut omitted = 0
  for i, row in rows {
    if !selected[i] {
      omitted += 1
      continue
    }
    if i == 0 || !selected[i - 1] {
      if omitted > 0 {
        out.write_string("\{omitted} unchanged lines omitted.\n\n")
        omitted = 0
      }
      hunk += 1
      out.write_string("### Source hunk \{hunk}\n\n")
      out.write_string("    change | before | after | exact line\n")
    }
    let old_number = if row.before_line == 0 {
      "-"
    } else {
      row.before_line.to_string()
    }
    let new_number = if row.after_line == 0 {
      "-"
    } else {
      row.after_line.to_string()
    }
    let literal = row.text
      .to_json()
      .stringify()
      .replace_all(old="\u{feff}", new="\\uFEFF")
    out.write_string(
      "    \{row.kind} | \{old_number} | \{new_number} | \{literal}\n",
    )
    if i + 1 == rows.length() || !selected[i + 1] {
      out.write_string("\n")
    }
  }
  if omitted > 0 {
    out.write_string("\{omitted} unchanged lines omitted.\n\n")
  }
}
