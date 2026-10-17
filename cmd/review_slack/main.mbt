///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_slack catalog <daily.json>\n       review_slack <agenda|bundle|preview|html> <agenda.json> <daily.json> <selections.json>\nSelect quoted Slack daily-export messages for an editable source-bound pending review.\nOrdinal positions include unsupported records. Catalog before selecting; copy the exact source digest.\nNo Slack access, identity inference, fetched attachments, thread reconstruction or approval inference.\nOutput is stdout only. Redirect to a new file, never an input path.",
      )
    ["catalog", path] =>
      println(@review.catalog_slack_review(@fs.read_file(path).binary()))
    [mode, agenda_path, source_path, plan_path] => {
      if !["agenda", "bundle", "preview", "html"].contains(mode) {
        fail("mode must be agenda, bundle, preview or html")
      }
      let bytes = @fs.read_file(source_path).binary()
      let imported = @review.import_slack_review(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_slack_review_import_plan(@fs.read_file(plan_path).text()),
        bytes,
      )
      let output = if mode == "agenda" {
        imported.to_json().stringify(indent=2)
      } else {
        let bundle = @review.compile_review_agenda(imported, bytes)
        match mode {
          "bundle" =>
            @review.serialize_review_bundle(bundle, bundle.source_digest)
          "html" => @review.export_review_html(bundle, bytes)
          _ => @review.export_review_markdown(bundle, bytes)
        }
      }
      println(output)
    }
    _ => fail("Usage: review_slack --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_slack: \{error}\n")
      exit(1)
    }
  }
}
