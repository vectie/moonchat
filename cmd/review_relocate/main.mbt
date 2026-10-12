///|
async fn run() -> Unit {
  let usage = "Usage: review_relocate <report|preview|locations> <previous-bundle.json> <previous-source> <previous-locations.json> <next-bundle.json> <next-source>"
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        usage +
        "\nRelocates unchanged discussion's exact quoted source passages offline.\nReport is JSON; preview is Markdown; locations emits the partial suggested map.\nAmbiguous, edited, removed or colliding ranges stay unresolved in the report.\nRead the report before using locations with review_packet --locations.\nNo input files, discussion, receipts or decisions are changed.\nRedirect stdout to a new file, never an input path.",
      )
    [
      mode,
      previous_path,
      previous_source_path,
      locations_path,
      next_path,
      next_source_path,
    ] => {
      if mode != "report" && mode != "preview" && mode != "locations" {
        fail(usage)
      }
      let previous_source = @fs.read_file(previous_source_path).binary()
      let next_source = @fs.read_file(next_source_path).binary()
      let previous = @review.reimport_review_bundle(
        @fs.read_file(previous_path).text(),
        previous_source,
      )
      let next = @review.reimport_review_bundle(
        @fs.read_file(next_path).text(),
        next_source,
      )
      let locations = @review.parse_review_source_locations(
        @fs.read_file(locations_path).text(),
      )
      let result = @review.relocate_review_source_locations(
        previous, previous_source, locations, next, next_source,
      )
      let output = match mode {
        "preview" => result.to_markdown()
        "locations" =>
          result.suggested_locations.to_json().stringify(indent=2) + "\n"
        _ => result.to_json().stringify(indent=2) + "\n"
      }
      @stdio.stdout.write(output)
    }
    _ => fail(usage)
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_relocate: \{error}\n")
      exit(1)
    }
  }
}
