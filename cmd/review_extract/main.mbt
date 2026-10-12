///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_extract catalog <transcript.txt>\n       review_extract <agenda|preview> <agenda.json> <source-file> <transcript.txt> <selections.json>\nCatalog exact source lines, then append explicitly selected excerpts to an editable pending agenda.\nOutput is stdout only. Redirect to a new file, never an input path.\nAuthors, item kinds and decision prompts must be explicit; transcript text cannot create a receipt.",
      )
    ["catalog", transcript_path] =>
      println(
        @review.catalog_review_transcript(
          @fs.read_file(transcript_path).binary(),
        ),
      )
    [mode, agenda_path, source_path, transcript_path, plan_path] => {
      if mode != "agenda" && mode != "preview" {
        fail("mode must be agenda or preview")
      }
      let source = @fs.read_file(source_path).binary()
      let imported = @review.import_review_excerpts(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_review_excerpt_plan(@fs.read_file(plan_path).text()),
        @fs.read_file(transcript_path).binary(),
        source,
      )
      println(
        if mode == "agenda" {
          imported.to_json().stringify(indent=2)
        } else {
          @review.export_review_markdown(
            @review.compile_review_agenda(imported, source),
            source,
          )
        },
      )
    }
    _ => fail("Usage: review_extract --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_extract: \{error}\n")
      exit(1)
    }
  }
}
