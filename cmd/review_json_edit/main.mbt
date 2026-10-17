///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] => println("Usage: review_json_edit catalog <source.json>\n       review_json_edit draft <previous-bundle.json> <previous-source.json>\n       review_json_edit <preview|source|bundle> <edit-plan.json> <previous-bundle.json> <previous-source.json> <previous-bundle-ref>\nReplace explicit existing JSON values linked to review entries. Outputs a candidate and pending review, never approvals. Stdout only; redirect to NEW paths, never inputs.")
    ["catalog", source_path] => println(@review.catalog_json_review(@fs.read_file(source_path).binary()))
    ["draft", bundle_path, source_path] => println(@review.prepare_review_json_edits(@fs.read_file(bundle_path).text(), @fs.read_file(source_path).binary()).to_json().stringify(indent=2))
    [mode, plan_path, bundle_path, source_path, previous_ref] => {
      if mode != "preview" && mode != "source" && mode != "bundle" { fail("mode must be catalog, draft, preview, source or bundle") }
      let plan = @review.parse_review_json_edits(@fs.read_file(plan_path).text())
      let previous = @fs.read_file(bundle_path).text()
      let source = @fs.read_file(source_path).binary()
      if mode == "preview" {
        @stdio.stdout.write(@review.preview_review_json_edits(plan, previous, source, previous_bundle_ref=previous_ref))
      } else {
        let result = @review.apply_review_json_edits(plan, previous, source, previous_bundle_ref=previous_ref)
        @stdio.stdout.write(if mode == "source" { result.source_text } else { @review.serialize_review_bundle(result.bundle, result.bundle.source_digest) })
      }
    }
    _ => fail("Usage: review_json_edit --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch { error => { @stdio.stderr.write("review_json_edit: \{error}\n"); exit(1) } }
}
