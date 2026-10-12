///|
async fn run() -> Unit {
  let usage = "Usage: review_compare [--source-text [--context <0..20>]] <before.json> <before-source> <after.json> <after-source>\nWrites a verified stable-ID comparison to stdout. --source-text also shows exact UTF-8 line changes (default context: 3)."
  let args = @env.args()
  match args[1:] {
    ["--help"] | ["-h"] => {
      println(usage)
      return
    }
    _ => ()
  }
  let (paths, source_context) : (ArrayView[String], Int?) = match args[1:] {
    ["--source-text", "--context", value, .. paths] => {
      let context = @string.parse_int(value) catch {
        _ => fail("source text context must be an integer from 0 to 20")
      }
      if context < 0 || context > 20 {
        fail("source text context must be between 0 and 20 lines")
      }
      (paths, Some(context))
    }
    ["--source-text", .. paths] => (paths, Some(3))
    paths => (paths, None)
  }
  match paths {
    [before_path, before_source_path, after_path, after_source_path] => {
      let before_source = @fs.read_file(before_source_path).binary()
      let after_source = @fs.read_file(after_source_path).binary()
      let before = @review.reimport_review_bundle(
        @fs.read_file(before_path).text(),
        before_source,
      )
      let after = @review.reimport_review_bundle(
        @fs.read_file(after_path).text(),
        after_source,
      )
      println(
        @review.export_review_comparison(
          before,
          before_source,
          after,
          after_source,
          source_context?,
        ),
      )
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
      @stdio.stderr.write("review_compare: \{error}\n")
      exit(1)
    }
  }
}
