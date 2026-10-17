///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_edit catalog <source>\n       review_edit draft <previous-bundle.json> <previous-source>\n       review_edit <preview|source|bundle> <edit-plan.json> <previous-bundle.json> <previous-source> <previous-bundle-ref>\nApply explicit exact-quote text replacements linked to discussion entries.\nOutputs candidate content and a linked pending review; never resolves objections or copies receipts.\nRetain the original source, bundle and edit plan. Stdout only; redirect to NEW paths, never inputs.",
      )
    ["catalog", source_path] =>
      println(
        @review.catalog_review_transcript(@fs.read_file(source_path).binary()),
      )
    ["draft", bundle_path, source_path] =>
      println(
        @review.prepare_review_text_edits(
          @fs.read_file(bundle_path).text(),
          @fs.read_file(source_path).binary(),
        )
        .to_json()
        .stringify(indent=2),
      )
    [mode, plan_path, bundle_path, source_path, previous_ref] => {
      if mode != "preview" && mode != "source" && mode != "bundle" {
        fail("mode must be catalog, draft, preview, source or bundle")
      }
      let plan = @review.parse_review_text_edits(
        @fs.read_file(plan_path).text(),
      )
      let previous = @fs.read_file(bundle_path).text()
      let source = @fs.read_file(source_path).binary()
      if mode == "preview" {
        @stdio.stdout.write(
          @review.preview_review_text_edits(
            plan,
            previous,
            source,
            previous_bundle_ref=previous_ref,
          ),
        )
      } else {
        let result = @review.apply_review_text_edits(
          plan,
          previous,
          source,
          previous_bundle_ref=previous_ref,
        )
        @stdio.stdout.write(
          if mode == "source" {
            result.source_text
          } else {
            @review.serialize_review_bundle(
              result.bundle,
              result.bundle.source_digest,
            )
          },
        )
      }
    }
    _ => fail("Usage: review_edit --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_edit: \{error}\n")
      exit(1)
    }
  }
}
