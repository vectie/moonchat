///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_patch catalog <changes.diff>\n       review_patch <agenda|bundle|preview> <agenda.json> <changes.diff> <selections.json>\nCatalog unified-diff hunks, then select changes for a source-bound pending review.\nThe reviewed source is the exact diff, not a checkout or resulting file. No patch is applied.\nOutput is stdout only. Redirect to a new file, never an input path.",
      )
    ["catalog", source_path] =>
      println(@review.catalog_patch_review(@fs.read_file(source_path).binary()))
    [mode, agenda_path, source_path, plan_path] => {
      if mode != "agenda" && mode != "bundle" && mode != "preview" {
        fail("mode must be agenda, bundle or preview")
      }
      let bytes = @fs.read_file(source_path).binary()
      let imported = @review.import_patch_review(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_patch_review_import_plan(@fs.read_file(plan_path).text()),
        bytes,
      )
      let result = if mode == "agenda" {
        imported.to_json().stringify(indent=2)
      } else {
        let bundle = @review.compile_review_agenda(imported, bytes)
        if mode == "bundle" {
          @review.serialize_review_bundle(bundle, bundle.source_digest)
        } else {
          @review.export_review_markdown(bundle, bytes)
        }
      }
      println(result)
    }
    _ => fail("Usage: review_patch --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_patch: \{error}\n")
      exit(1)
    }
  }
}
