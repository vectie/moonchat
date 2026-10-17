///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_checklist catalog <checklist.json>\n       review_checklist digest <source>\n       review_checklist <agenda|bundle|preview> <checklist.json> <input.json> <source>\nReuse a checklist with explicit roles, literal values and new source bindings.\nAll decisions remain pending. No role assignment verifies identity or approval.\nOutput is stdout only. Redirect to a new file, never an input path.",
      )
    ["catalog", path] =>
      println(
        @review.catalog_review_checklist(
          @review.parse_review_checklist(@fs.read_file(path).text()),
        ),
      )
    ["digest", path] =>
      println(@review.review_source_digest(@fs.read_file(path).binary()))
    [mode, checklist_path, input_path, source_path] => {
      if !["agenda", "bundle", "preview"].contains(mode) {
        fail("mode must be agenda, bundle or preview")
      }
      let bytes = @fs.read_file(source_path).binary()
      let agenda = @review.instantiate_review_checklist(
        @review.parse_review_checklist(@fs.read_file(checklist_path).text()),
        @review.parse_review_checklist_input(@fs.read_file(input_path).text()),
        bytes,
      )
      let output = if mode == "agenda" {
        agenda.to_json().stringify(indent=2)
      } else {
        let bundle = @review.compile_review_agenda(agenda, bytes)
        if mode == "bundle" {
          @review.serialize_review_bundle(bundle, bundle.source_digest)
        } else {
          @review.export_review_markdown(bundle, bytes)
        }
      }
      println(output)
    }
    _ => fail("Usage: review_checklist --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_checklist: \{error}\n")
      exit(1)
    }
  }
}
