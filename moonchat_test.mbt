///|
test "product name" {
  assert_eq(@moonchat.product_name(), "moonchat")
}

///|
test "root facade exposes moonsuite product home contract" {
  let home = @moonchat.moonsuite_product_home(book_id="idea-room")
  assert_eq(home.product_id, "moonchat")
  assert_eq(home.state_path, ".moonsuite/products/moonchat")
  assert_eq(home.service_path, ".moonsuite/products/moonchat/service.json")
  assert_eq(home.cache_path, ".moonsuite/products/moonchat/cache")
  assert_eq(home.tmp_path, ".tmp/products/moonchat")
  assert_eq(home.accepted_output_path, "books/idea-room/outputs/moonchat")
  let suite_root = "/tmp/moonchat-suite"
  let book_root = suite_root + "/books/idea-room"
  let suite_home = @moonchat.moonsuite_product_home_for_workspace_root(
    book_root,
    book_id="idea-room",
  )
  assert_eq(
    suite_home.state_path,
    "/tmp/moonchat-suite/.moonsuite/products/moonchat",
  )
  assert_eq(
    suite_home.service_path,
    "/tmp/moonchat-suite/.moonsuite/products/moonchat/service.json",
  )
  assert_eq(
    suite_home.cache_path,
    "/tmp/moonchat-suite/.moonsuite/products/moonchat/cache",
  )
  assert_eq(suite_home.tmp_path, "/tmp/moonchat-suite/.tmp/products/moonchat")
  assert_eq(
    suite_home.accepted_output_path,
    "/tmp/moonchat-suite/books/idea-room/outputs/moonchat",
  )
  assert_false(suite_home.state_path.contains("books/idea-room/.moonsuite"))
  let inferred_home = @moonchat.moonsuite_product_home_for_workspace_root(
    book_root,
  )
  assert_eq(
    inferred_home.state_path,
    "/tmp/moonchat-suite/.moonsuite/products/moonchat",
  )
  assert_eq(
    inferred_home.tmp_path,
    "/tmp/moonchat-suite/.tmp/products/moonchat",
  )
  assert_eq(
    inferred_home.accepted_output_path,
    "/tmp/moonchat-suite/books/idea-room/outputs/moonchat",
  )
  assert_false(inferred_home.state_path.contains("books/idea-room/.moonsuite"))
}
