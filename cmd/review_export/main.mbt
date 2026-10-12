///|
async fn main {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_export <bundle.json> <source-file>\nWrites a source-bound review Markdown handoff to stdout.",
      )
    [bundle_path, source_path] => {
      let source = @fs.read_file(source_path).binary()
      let bundle = @review.reimport_review_bundle(
        @fs.read_file(bundle_path).text(),
        source,
      )
      println(@review.export_review_markdown(bundle, source))
    }
    _ => fail("Usage: review_export <bundle.json> <source-file>")
  }
}
