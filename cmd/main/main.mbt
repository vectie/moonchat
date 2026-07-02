///|
fn print_layout(root : String, book_id : String) -> Unit {
  let home = @moonchat.moonsuite_product_home_for_workspace_root(root, book_id~)
  println(home.to_json().stringify(indent=2))
}

///|
fn print_usage() -> Unit {
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
      println("unknown MoonChat command: \{unknown}")
      print_usage()
    }
  }
}
