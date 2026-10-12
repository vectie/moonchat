///|
async fn main {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_compose <bundle|preview> <agenda.json> <source-file> [<previous-bundle.json> <previous-source-file> <previous-bundle-ref>]\nCompile an editable agenda into pending review JSON or readable Markdown on stdout.\nOptional predecessor arguments create a linked pending revision.\nKeep item keys stable when editing. No human decisions are created.",
      )
    [mode, agenda_path, source_path] => {
      if mode != "bundle" && mode != "preview" {
        fail("mode must be bundle or preview")
      }
      let agenda = @review.parse_review_agenda(
        @fs.read_file(agenda_path).text(),
      )
      let source = @fs.read_file(source_path).binary()
      let bundle = @review.compile_review_agenda(agenda, source)
      println(
        if mode == "preview" {
          @review.export_review_markdown(bundle, source)
        } else {
          @review.serialize_review_bundle(bundle, bundle.source_digest)
        },
      )
    }
    [
      mode,
      agenda_path,
      source_path,
      previous_path,
      previous_source_path,
      previous_ref,
    ] => {
      if mode != "bundle" && mode != "preview" {
        fail("mode must be bundle or preview")
      }
      let agenda = @review.parse_review_agenda(
        @fs.read_file(agenda_path).text(),
      )
      let source = @fs.read_file(source_path).binary()
      let draft = @review.compile_review_agenda(agenda, source)
      let bundle = @review.supersede_review_bundle(
        @fs.read_file(previous_path).text(),
        previous_bundle_ref=previous_ref,
        previous_source_bytes=@fs.read_file(previous_source_path).binary(),
        next_bundle=draft,
        next_source_bytes=source,
      )
      println(
        if mode == "preview" {
          @review.export_review_markdown(bundle, source)
        } else {
          @review.serialize_review_bundle(bundle, bundle.source_digest)
        },
      )
    }
    _ =>
      fail("Usage: review_compose <bundle|preview> <agenda.json> <source-file>")
  }
}
