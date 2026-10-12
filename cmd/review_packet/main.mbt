///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_packet [--locations locations.json] <bundle.json> <source-file>\nWrites a self-contained, read-only HTML packet with the bound UTF-8 source.\nSource limit: 1 MiB and 10000 display lines; no binary control characters.\nOpen the output locally in a browser; Find, section links and Print need no network.\nOptional locations link entries to exact quoted display-line ranges.\nRetain original JSON and source bytes. No receipts or decisions are created.\nRedirect stdout to a new path, never either input file.",
      )
    ["--locations", locations_path, bundle_path, source_path] => {
      let source = @fs.read_file(source_path).binary()
      let bundle = @review.reimport_review_bundle(
        @fs.read_file(bundle_path).text(),
        source,
      )
      let locations = @review.parse_review_source_locations(
        @fs.read_file(locations_path).text(),
      )
      @stdio.stdout.write(
        @review.export_review_html(bundle, source, locations~),
      )
    }
    [bundle_path, source_path] => {
      let source = @fs.read_file(source_path).binary()
      let bundle = @review.reimport_review_bundle(
        @fs.read_file(bundle_path).text(),
        source,
      )
      @stdio.stdout.write(@review.export_review_html(bundle, source))
    }
    _ =>
      fail(
        "Usage: review_packet [--locations locations.json] <bundle.json> <source-file>",
      )
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_packet: \{error}\n")
      exit(1)
    }
  }
}
