///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_sarif catalog <results.sarif>\n       review_sarif <agenda|preview|bundle> <agenda.json> <source-file> <results.sarif> <selections.json>\nCatalog local SARIF 2.1.0 results, then select findings for an editable pending review.\nOutput is stdout only. Redirect to a new file, never an input path.\nNo analyzer, suggested fix, URI or provider is executed; findings never create human receipts.",
      )
    ["catalog", path] =>
      println(@review.catalog_sarif_review(@fs.read_file(path).binary()))
    [mode, agenda_path, source_path, sarif_path, plan_path] => {
      if mode != "agenda" && mode != "preview" && mode != "bundle" {
        fail("mode must be agenda, preview or bundle")
      }
      let source = @fs.read_file(source_path).binary()
      let agenda = @review.import_sarif_review(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_sarif_review_import_plan(@fs.read_file(plan_path).text()),
        @fs.read_file(sarif_path).binary(),
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
    _ => fail("Usage: review_sarif --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_sarif: \{error}\n")
      exit(1)
    }
  }
}
