///|
fn print_layout(root : String, book_id : String) -> Unit {
  let home = @moonchat.moonsuite_product_home_for_workspace_root(root, book_id~)
  println(home.to_json().stringify(indent=2))
}

///|
fn print_usage() -> Unit {
  println(if interface_is_chinese() { "用法" } else { "Usage" })
  println("moon run cmd/main -- summary")
  println("moon run cmd/main -- layout [workspace-root] [book-id]")
}

///|
fn main {
  match @env.args()[1:] {
    [] | ["summary", ..] => println(@moonchat.product_name())
    ["layout", root, book_id, ..] => print_layout(root, book_id)
    ["layout", root] => print_layout(root, "<book-id>")
    ["layout"] => print_layout(".", "<book-id>")
    ["help", ..] | ["--help", ..] | ["-h", ..] => print_usage()
    [unknown, ..] => {
      println(
        if interface_is_chinese() {
          "未知的 MoonChat 命令：\{unknown}"
        } else {
          "Unknown MoonChat command: \{unknown}"
        },
      )
      print_usage()
    }
  }
}

///|
fn interface_is_chinese() -> Bool {
  let raw = match @env.get_env_var("MOONSUITE_LANG") {
    Some(value) => value
    None =>
      match @env.get_env_var("LC_ALL") {
        Some(value) => value
        None => @env.get_env_var("LANG").unwrap_or("en-US")
      }
  }
  let raw = raw.to_lower()
  raw.has_prefix("zh")
}
