///|
fn option(args : ArrayView[String], name : String) -> String raise {
  for index in 0..<(args.length() - 1) {
    if args[index] == name {
      return args[index + 1]
    }
  }
  fail("MoonChat Flow adapter requires \{name}")
}

///|
fn int64_option(args : ArrayView[String], name : String) -> Int64 raise {
  @string.parse_int64(option(args, name)) catch {
    _ => fail("MoonChat Flow adapter requires integer \{name}")
  }
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let output = match args {
    [] | ["capability"] => @flow_adapter.capability_json()
    ["execute", .. rest] =>
      @flow_adapter.execute(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--result"),
      )
    ["reconcile", .. rest] =>
      @flow_adapter.reconcile(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--result"),
      )
    ["health", .. rest] =>
      @flow_adapter.publish_health(
        option(rest, "--workspace"),
        option(rest, "--checked-at"),
        option(rest, "--valid-until"),
        int64_option(rest, "--checked-at-epoch-seconds"),
        int64_option(rest, "--valid-until-epoch-seconds"),
        option(rest, "--evidence"),
        option(rest, "--attestation"),
      )
    _ =>
      fail(
        "usage: moonflow_adapter <capability|execute|reconcile|health> [options]",
      )
  }
  println(output.stringify(indent=2))
}
