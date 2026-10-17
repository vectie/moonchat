///|
async fn run() -> Unit {
  match @env.args()[1:] {
    ["--help"] | ["-h"] =>
      println(
        "Usage: review_decide prepare <bundle.json> <source> <reviewer-id>\n       review_decide preview <form.json> <bundle.json> <source>\nPrepare blank choices with retained discussion; edit explicit choices and preview.\nLocal input is unverified. No CLI command creates authoritative receipts.\nHost integrations must authenticate the reviewer before applying choices.\nOutput is stdout only; redirect to a new file, never an input.",
      )
    ["prepare", bundle_path, source_path, reviewer] =>
      println(
        @review.prepare_review_decisions(
          @fs.read_file(bundle_path).text(),
          @fs.read_file(source_path).binary(),
          reviewer,
        )
        .to_json()
        .stringify(indent=2),
      )
    ["preview", form_path, bundle_path, source_path] =>
      println(
        @review.preview_review_decisions(
          @review.parse_review_decisions(@fs.read_file(form_path).text()),
          @fs.read_file(bundle_path).text(),
          @fs.read_file(source_path).binary(),
        ),
      )
    _ => fail("Usage: review_decide --help")
  }
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_decide: \{error}\n")
      exit(1)
    }
  }
}
