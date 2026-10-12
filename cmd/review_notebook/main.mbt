///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_notebook catalog <notebook.ipynb>\n       review_notebook <agenda|preview|bundle> <agenda.json> <notebook.ipynb> <selections.json>\nCatalog saved notebook cells, then select cells for an editable source-bound review.\nOutput is stdout only. Redirect to a new file, never an input path.\nNo kernel, code, HTML, attachment or URL is executed or rendered. Saved output may be stale.",
      )
    ["catalog", path] =>
      println(@review.catalog_notebook_review(@fs.read_file(path).binary()))
    [mode, agenda_path, notebook_path, plan_path] => {
      if mode != "agenda" && mode != "preview" && mode != "bundle" {
        fail("mode must be agenda, preview or bundle")
      }
      let source = @fs.read_file(notebook_path).binary()
      let agenda = @review.import_notebook_review(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_notebook_review_import_plan(
          @fs.read_file(plan_path).text(),
        ),
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
    _ => fail("Usage: review_notebook --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_notebook: \{error}\n")
      exit(1)
    }
  }
}
