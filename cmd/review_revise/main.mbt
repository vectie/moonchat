///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_revise draft <previous-bundle.json> <previous-source>\n       review_revise <bundle|preview> <edited-draft.json> <next-source> <previous-bundle.json> <previous-source> <previous-bundle-ref>\nReopen an imported host review, edit its discussion, then create a linked pending revision.\nHost conversation, entry, turn and decision identities are copied into the draft.\nPrior decisions stay in the retained predecessor and are never carried forward.\nOutput is stdout only. Redirect to a new path, never an input file.",
      )
    ["draft", previous_path, previous_source_path] =>
      println(
        @review.prepare_review_revision(
          @fs.read_file(previous_path).text(),
          @fs.read_file(previous_source_path).binary(),
        )
        .to_json()
        .stringify(indent=2),
      )
    [
      mode,
      draft_path,
      source_path,
      previous_path,
      previous_source_path,
      previous_ref,
    ] => {
      if mode != "bundle" && mode != "preview" {
        fail("mode must be draft, bundle or preview")
      }
      let source = @fs.read_file(source_path).binary()
      let bundle = @review.compile_review_revision(
        @review.parse_review_revision(@fs.read_file(draft_path).text()),
        source,
        previous_bundle_text=@fs.read_file(previous_path).text(),
        previous_source_bytes=@fs.read_file(previous_source_path).binary(),
        previous_bundle_ref=previous_ref,
      )
      println(
        if mode == "preview" {
          @review.export_review_markdown(bundle, source)
        } else {
          @review.serialize_review_bundle(bundle, bundle.source_digest)
        },
      )
    }
    _ => fail("Usage: review_revise --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_revise: \{error}\n")
      exit(1)
    }
  }
}
