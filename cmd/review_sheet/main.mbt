///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_sheet export <agenda.json> <source-file>\n       review_sheet <import|preview> <agenda.json> <source-file> <sheet.csv>\n       review_sheet <merge|merge-report|merge-preview> <base-agenda.json> <source-file> <left.csv> <right.csv>\nExport an editable CSV or replace agenda items with spreadsheet rows.\nImport retains the template's source metadata and participant roster.\nColumns: key,kind,author,body,evidence_ref,reviewer,prompt\nOutput is stdout only. Redirect to a new file, never an input path.\nImport CSV columns as text in your spreadsheet. No decision receipts are created.",
      )
    ["export", agenda_path, source_path] =>
      @stdio.stdout.write(
        @review.export_review_sheet(
          @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
          @fs.read_file(source_path).binary(),
        ),
      )
    [mode, agenda_path, source_path, left_path, right_path] => {
      if mode != "merge" && mode != "merge-report" && mode != "merge-preview" {
        fail("mode must be merge, merge-report or merge-preview")
      }
      let source = @fs.read_file(source_path).binary()
      let result = @review.merge_review_sheets(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @fs.read_file(left_path).binary(),
        @fs.read_file(right_path).binary(),
        source,
      )
      if mode == "merge-report" {
        println(result.to_json().stringify(indent=2))
      } else {
        let agenda = match result.merged_agenda {
          Some(value) => value
          None =>
            fail(
              "conflicting spreadsheet edits; use merge-report to inspect all base/left/right values, edit the CSVs, then retry",
            )
        }
        println(
          if mode == "merge" {
            agenda.to_json().stringify(indent=2)
          } else {
            @review.export_review_markdown(
              @review.compile_review_agenda(agenda, source),
              source,
            )
          },
        )
      }
    }
    [mode, agenda_path, source_path, sheet_path] => {
      if mode != "import" && mode != "preview" {
        fail("mode must be import or preview")
      }
      let source = @fs.read_file(source_path).binary()
      let imported = @review.import_review_sheet(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @fs.read_file(sheet_path).binary(),
        source,
      )
      println(
        if mode == "import" {
          imported.to_json().stringify(indent=2)
        } else {
          @review.export_review_markdown(
            @review.compile_review_agenda(imported, source),
            source,
          )
        },
      )
    }
    _ => fail("Usage: review_sheet --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_sheet: \{error}\n")
      exit(1)
    }
  }
}
