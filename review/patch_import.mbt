///|
/// Explicit hunk selections from an exact UTF-8 unified diff. The patch is
/// evidence, never an instruction to apply files or an authenticated decision.
pub(all) struct PatchReviewImportPlan {
  format : String
  source_digest : String
  selections : Array[PatchReviewSelection]
} derive(Eq, ToJson, @json.FromJson)

///|
/// File and hunk numbers are one-based, as shown by catalog_patch_review.
pub(all) struct PatchReviewSelection {
  file : Int
  hunk : Int
  key : String
  kind : String
  author : String
  note : String
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
priv struct PatchHunk {
  old_start : Int
  old_count : Int
  new_start : Int
  new_count : Int
  added : Int
  removed : Int
  text : String
} derive(ToJson)

///|
priv struct PatchFile {
  old_path : String
  new_path : String
  headers : String
  hunks : Array[PatchHunk]
}

///|
fn patch_line_text(line : String) -> String {
  if line.has_suffix("\r\n") {
    line[:line.length() - 2].to_owned()
  } else if line.has_suffix("\n") {
    line[:line.length() - 1].to_owned()
  } else {
    line
  }
}

///|
fn patch_lines(bytes : Bytes) -> Array[String] raise {
  if bytes.length() > 1048576 {
    fail("unified diff exceeds 1 MiB")
  }
  let text = @utf8.decode(bytes, ignore_bom=false)
  if text.contains("\u{0000}") {
    fail("unified diff must be text without NUL bytes")
  }
  let lines : Array[String] = []
  let mut start = 0
  for i in 0..<text.length() {
    if text[i] == '\n' {
      lines.push(text[start:i + 1].to_owned())
      start = i + 1
    }
  }
  if start < text.length() {
    lines.push(text[start:].to_owned())
  }
  if lines.is_empty() || lines.length() > 10000 {
    fail("unified diff must contain 1–10000 physical lines")
  }
  lines
}

///|
fn patch_number(text : String, start : Int) -> (Int, Int) raise {
  let mut cursor = start
  let mut number = 0
  while cursor < text.length() && text[cursor] >= '0' && text[cursor] <= '9' {
    let digit = text[cursor].to_int() - 48
    if number > (1000000000 - digit) / 10 {
      fail("unified diff coordinates exceed 1000000000")
    }
    number = number * 10 + digit
    cursor += 1
  }
  if cursor == start {
    fail("unified diff hunk requires decimal coordinates")
  }
  (number, cursor)
}

///|
fn patch_range(text : String, cursor : Int) -> (Int, Int, Int) raise {
  let (start, next) = patch_number(text, cursor)
  let (count, end) = if next < text.length() && text[next] == ',' {
    patch_number(text, next + 1)
  } else {
    (1, next)
  }
  if count > 10000 || (count > 0 && start == 0) {
    fail("unified diff hunk has an invalid or oversized range")
  }
  (start, count, end)
}

///|
fn patch_header(text : String) -> (Int, Int, Int, Int) raise {
  if !text.has_prefix("@@ -") {
    fail(
      "expected ordinary unified diff hunk header; combined diffs are unsupported",
    )
  }
  let (old_start, old_count, cursor) = patch_range(text, 4)
  if !text[cursor:].has_prefix(" +") {
    fail("unified diff hunk is missing its new range")
  }
  let (new_start, new_count, cursor) = patch_range(text, cursor + 2)
  let suffix = text[cursor:]
  if suffix != " @@" && !suffix.has_prefix(" @@ ") {
    fail("unified diff hunk has an invalid closing delimiter")
  }
  (old_start, old_count, new_start, new_count)
}

///|
fn patch_path(line : String, prefix : String) -> String raise {
  if !line.has_prefix(prefix) {
    fail("unified diff requires paired --- and +++ file headers")
  }
  let remainder = line[prefix.length():].to_owned()
  let path = match remainder.split_once("\t") {
    Some((path, _)) => path.to_owned()
    None => remainder
  }
  if !non_empty(path) || path.has_prefix("\"") {
    fail(
      "unified diff requires nonempty unquoted paths; quoted Git paths are unsupported",
    )
  }
  path
}

///|
fn patch_metadata(line : String) -> Bool {
  [
    "index ", "new file mode ", "deleted file mode ", "old mode ", "new mode ", "similarity index ",
    "dissimilarity index ", "rename from ", "rename to ", "copy from ", "copy to ",
  ].any(prefix => line.has_prefix(prefix))
}

///|
fn patch_files(bytes : Bytes) -> Array[PatchFile] raise {
  let lines = patch_lines(bytes)
  let files : Array[PatchFile] = []
  let mut cursor = 0
  let mut hunk_total = 0
  while cursor < lines.length() {
    if files.length() >= 100 {
      fail("unified diff exceeds 100 files")
    }
    let header_start = cursor
    if patch_line_text(lines[cursor]).has_prefix("diff --git ") {
      cursor += 1
      while cursor < lines.length() &&
            patch_metadata(patch_line_text(lines[cursor])) {
        cursor += 1
      }
    }
    if cursor + 1 >= lines.length() {
      fail(
        "expected textual unified diff; binary, combined and metadata-only changes are unsupported",
      )
    }
    let old_path = patch_path(patch_line_text(lines[cursor]), "--- ")
    let new_path = patch_path(patch_line_text(lines[cursor + 1]), "+++ ")
    if old_path == "/dev/null" && new_path == "/dev/null" {
      fail("unified diff cannot have /dev/null on both sides")
    }
    cursor += 2
    let headers = lines[header_start:cursor].to_owned().join("")
    let hunks : Array[PatchHunk] = []
    let mut old_end = -1
    let mut new_end = -1
    let mut old_eof = false
    let mut new_eof = false
    while cursor < lines.length() &&
          patch_line_text(lines[cursor]).has_prefix("@@") {
      if hunk_total >= 1000 {
        fail("unified diff exceeds 1000 hunks")
      }
      hunk_total += 1
      let start = cursor
      let (old_start, old_count, new_start, new_count) = patch_header(
        patch_line_text(lines[cursor]),
      )
      let old_boundary = if old_count == 0 { old_start } else { old_start - 1 }
      let new_boundary = if new_count == 0 { new_start } else { new_start - 1 }
      if old_boundary < old_end || new_boundary < new_end {
        fail("unified diff hunks overlap or are out of order")
      }
      if (old_path == "/dev/null" && old_count != 0) ||
        (new_path == "/dev/null" && new_count != 0) {
        fail("unified diff /dev/null side must have an empty range")
      }
      old_end = old_boundary + old_count
      new_end = new_boundary + new_count
      cursor += 1
      let mut old_seen = 0
      let mut new_seen = 0
      let mut added = 0
      let mut removed = 0
      let mut previous = ""
      while cursor < lines.length() {
        let line = patch_line_text(lines[cursor])
        if line == "\\ No newline at end of file" {
          if previous == "" {
            fail(
              "unified diff newline marker requires a preceding content line",
            )
          }
          if previous == " " || previous == "-" {
            old_eof = true
          }
          if previous == " " || previous == "+" {
            new_eof = true
          }
          previous = ""
          cursor += 1
          continue
        }
        if old_seen == old_count && new_seen == new_count {
          break
        }
        if line.is_empty() {
          fail("unified diff content lines require a space, + or - prefix")
        }
        let prefix = line[:1].to_owned()
        if prefix != " " && prefix != "+" && prefix != "-" {
          fail(
            "unified diff hunk is truncated or contains an unsupported content line",
          )
        }
        if prefix != "+" {
          if old_eof {
            fail("unified diff has old content after its no-newline marker")
          }
          old_seen += 1
        }
        if prefix != "-" {
          if new_eof {
            fail("unified diff has new content after its no-newline marker")
          }
          new_seen += 1
        }
        if old_seen > old_count || new_seen > new_count {
          fail("unified diff content exceeds its declared hunk counts")
        }
        if prefix == "+" {
          added += 1
        }
        if prefix == "-" {
          removed += 1
        }
        previous = prefix
        cursor += 1
      }
      if old_seen != old_count || new_seen != new_count || added + removed == 0 {
        fail(
          "unified diff hunk must contain complete counts and at least one change",
        )
      }
      hunks.push({
        old_start,
        old_count,
        new_start,
        new_count,
        added,
        removed,
        text: lines[start:cursor].to_owned().join(""),
      })
    }
    if hunks.is_empty() {
      fail(
        "unified diff file has no textual hunks; metadata-only changes are unsupported",
      )
    }
    files.push({ old_path, new_path, headers, hunks, })
  }
  files
}

///|
/// Catalog every file and hunk, including literal headers and hunk text. Paths
/// are labels only: this function never opens, follows or modifies those paths.
pub fn catalog_patch_review(bytes : Bytes) -> String raise {
  let files = patch_files(bytes)
  let rows : Array[Json] = []
  for index, file in files {
    let hunks : Array[Json] = []
    for number, hunk in file.hunks {
      hunks.push(
        Json::object({
          "hunk": (number + 1).to_json(),
          "change": ToJson::to_json(hunk),
        }),
      )
    }
    rows.push(
      Json::object({
        "file": (index + 1).to_json(),
        "old_path": file.old_path.to_json(),
        "new_path": file.new_path.to_json(),
        "headers": file.headers.to_json(),
        "hunks": hunks.to_json(),
      }),
    )
  }
  Json::object({
    "format": "moonchat.patch-catalog.v1".to_json(),
    "source_digest": review_source_digest(bytes).to_json(),
    "files": rows.to_json(),
  }).stringify(indent=2)
}

///|
pub fn parse_patch_review_import_plan(
  text : String,
) -> PatchReviewImportPlan raise {
  let plan : PatchReviewImportPlan = @json.from_json(@json.parse(text))
  if plan.format != "moonchat.review-patch.v1" {
    fail("patch plan format must be moonchat.review-patch.v1")
  }
  plan
}

///|
/// Append curated changes to an editable agenda bound to the exact patch bytes.
/// Hunk text, file headers and requested decisions survive normal composition.
/// Import does not apply a patch, verify a checkout or create reviewer receipts.
pub fn import_patch_review(
  agenda : ReviewAgenda,
  plan : PatchReviewImportPlan,
  bytes : Bytes,
) -> ReviewAgenda raise {
  if plan.format != "moonchat.review-patch.v1" {
    fail("patch plan format must be moonchat.review-patch.v1")
  }
  if plan.source_digest != review_source_digest(bytes) {
    fail("patch bytes do not match the selected source digest")
  }
  if plan.selections.is_empty() || plan.selections.length() > 100 {
    fail("patch plan must select 1–100 hunks")
  }
  let files = patch_files(bytes)
  let selected : Map[(Int, Int), Bool] = Map([])
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  let mut total = 0
  for selection in plan.selections {
    if selection.file < 1 || selection.hunk < 1 {
      fail("patch file and hunk numbers must be positive")
    }
    let identity = (selection.file, selection.hunk)
    if selected.contains(identity) {
      fail("patch hunk selected more than once")
    }
    selected[identity] = true
    guard files.get(selection.file - 1) is Some(file) else {
      fail("selected patch file does not exist")
    }
    guard file.hunks.get(selection.hunk - 1) is Some(hunk) else {
      fail("selected patch hunk does not exist")
    }
    if !non_empty(selection.note) {
      fail("patch selection requires an operator note")
    }
    let body = "Operator note:\n" +
      selection.note +
      "\n\nSelected unified diff evidence (not applied; not a decision receipt):\n" +
      Json::object({
        "source_ref": agenda.source_artifact_ref.to_json(),
        "source_digest": plan.source_digest.to_json(),
        "file": selection.file.to_json(),
        "hunk": selection.hunk.to_json(),
        "old_path": file.old_path.to_json(),
        "new_path": file.new_path.to_json(),
        "file_headers": file.headers.to_json(),
        "change": ToJson::to_json(hunk),
      }).stringify(indent=2)
    if @utf8.encode(body).length() > 8388608 - total {
      fail("selected patch evidence exceeds 8 MiB")
    }
    total += @utf8.encode(body).length()
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
