///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_github catalog <github-comments.json>\n       review_github <agenda|preview|bundle> <agenda.json> <source-file> <github-comments.json> <import-plan.json>\n       review_github <refresh-report|refresh-agenda|refresh-preview|refresh-bundle> <current-agenda.json> <source-file> <old-comments.json> <old-plan.json> <new-comments.json> <new-plan.json>\nImport selected GitHub REST pull-request review-comment threads from local files.\nMap each selected comment's login to an existing participant; choose item kinds and decision requests explicitly.\nNo network, login, GitHub mutations or approval inference.\nOutput is stdout only. Redirect to a new path, never an input file.",
      )
    ["catalog", export_path] =>
      println(
        @review.catalog_github_review_comments(
          @fs.read_file(export_path).binary(),
        ),
      )
    [
      mode,
      agenda_path,
      source_path,
      old_export_path,
      old_plan_path,
      new_export_path,
      new_plan_path,
    ] => {
      if ![
          "refresh-report", "refresh-agenda", "refresh-preview", "refresh-bundle",
        ].contains(mode) {
        fail(
          "refresh mode must be refresh-report, refresh-agenda, refresh-preview or refresh-bundle",
        )
      }
      let source = @fs.read_file(source_path).binary()
      let result = @review.refresh_github_review_comments(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_github_review_import_plan(
          @fs.read_file(old_plan_path).text(),
        ),
        @fs.read_file(old_export_path).binary(),
        @review.parse_github_review_import_plan(
          @fs.read_file(new_plan_path).text(),
        ),
        @fs.read_file(new_export_path).binary(),
        source,
      )
      let output = if mode == "refresh-report" {
        result.to_json().stringify(indent=2)
      } else {
        let agenda = match result.merged_agenda {
          Some(value) => value
          None =>
            fail(
              "conflicting local and GitHub edits; use refresh-report to inspect base/left/right values, reconcile the agenda, then retry",
            )
        }
        if mode == "refresh-agenda" {
          agenda.to_json().stringify(indent=2)
        } else {
          let bundle = @review.compile_review_agenda(agenda, source)
          if mode == "refresh-preview" {
            @review.export_review_markdown(bundle, source)
          } else {
            @review.serialize_review_bundle(bundle, bundle.source_digest)
          }
        }
      }
      println(output)
    }
    [mode, agenda_path, source_path, export_path, plan_path] => {
      if !["agenda", "preview", "bundle"].contains(mode) {
        fail("mode must be catalog, agenda, preview or bundle")
      }
      let source = @fs.read_file(source_path).binary()
      let imported = @review.import_github_review_comments(
        @review.parse_review_agenda(@fs.read_file(agenda_path).text()),
        @review.parse_github_review_import_plan(@fs.read_file(plan_path).text()),
        @fs.read_file(export_path).binary(),
        source,
      )
      let output = if mode == "agenda" {
        imported.to_json().stringify(indent=2)
      } else {
        let bundle = @review.compile_review_agenda(imported, source)
        if mode == "preview" {
          @review.export_review_markdown(bundle, source)
        } else {
          @review.serialize_review_bundle(bundle, bundle.source_digest)
        }
      }
      println(output)
    }
    _ => fail("Usage: review_github --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_github: \{error}\n")
      exit(1)
    }
  }
}
