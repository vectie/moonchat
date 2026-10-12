///|
async fn run() -> Unit {
  let usage = "Usage: review_explore <bundle.json> <source-file> [--text literal] [--kind question|objection|proposal] [--reviewer participant-id] [--outcome pending|approve|reject|defer|none]\nWrites a filtered source-bound reading view to stdout. Filters combine with AND."
  let args = @env.args()[1:]
  if args is (["--help"] | ["-h"]) {
    println(usage)
    return
  }
  guard args.length() >= 2 else { fail(usage) }
  let options : Map[String, String] = {}
  for i = 2; i < args.length(); i = i + 2 {
    guard i + 1 < args.length() else { fail("missing filter value; " + usage) }
    let key = args[i]
    guard key == "--text" ||
      key == "--kind" ||
      key == "--reviewer" ||
      key == "--outcome" else {
      fail("unknown filter: " + key)
    }
    guard !options.contains(key) else { fail("repeated filter: " + key) }
    guard args[i + 1] != "" else { fail("empty filter: " + key) }
    options[key] = args[i + 1]
  }
  let source = @fs.read_file(args[1]).binary()
  let bundle = @review.reimport_review_bundle(
    @fs.read_file(args[0]).text(),
    source,
  )
  println(
    @review.explore_review(
      bundle,
      source,
      text=options.get("--text").unwrap_or(""),
      kind=options.get("--kind").unwrap_or(""),
      reviewer=options.get("--reviewer").unwrap_or(""),
      outcome=options.get("--outcome").unwrap_or(""),
    ),
  )
}

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("review_explore: \{error}\n")
      exit(1)
    }
  }
}
