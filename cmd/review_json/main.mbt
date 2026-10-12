///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_json catalog <artifact.json>\n       review_json <agenda|preview|bundle> <agenda.json> <artifact.json> <selections.json>\nCatalog JSON Pointers, then select values for an editable source-bound review.\nOutput is stdout only. Redirect to a new file, never an input path.\nJSON values are static evidence, never receipts. No code or URL is executed.",
      )
    ["catalog", path] =>
      println(@review.catalog_json_review(@fs.read_file(path).binary()))
    [mode, agenda_path, notebook_path, plan_path] => {
      if mode != "agenda" && mode != "preview" && mode != "bundle" {
        fail("mode must be agenda, preview or bundle")
      }
      let source = @fs.read_file(notebook_path).binary()
      let agenda = @review.import_json_review(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_json_review_import_plan(@fs.read_file(plan_path).text()),
        source,
      )
      println(
        if mode == "agenda" {
          agenda.to_json().stringify(indent=2)
        } else {
          let bundle = @review.compile_review_agenda(agenda, source)
          if mode == "bundle" {
            bundle.to_json().stringify(indent=2)
          } else {
            @review.export_review_markdown(bundle, source)
          }
        },
      )
    }
    _ => fail("Usage: review_json --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_json: \{error}\n")
      exit(1)
    }
  }
}
