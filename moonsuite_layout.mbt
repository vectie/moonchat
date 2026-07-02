///|
pub(all) struct MoonChatMoonSuiteProductHome {
  product_id : String
  state_path : String
  service_path : String
  cache_path : String
  tmp_path : String
  accepted_output_path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn moonsuite_product_id() -> String {
  product_name()
}

///|
fn moonsuite_active_workspace_root() -> String {
  "."
}

///|
fn moonsuite_shared_product_home_for_workspace_root(
  root : String,
  book_id? : String = "<book-id>",
) -> @moonsuite.ProductHome {
  @moonsuite.product_home_for_workspace_root(
    root,
    moonsuite_product_id(),
    book_id~,
  )
}

///|
fn moonchat_product_home_from_shared(
  home : @moonsuite.ProductHome,
) -> MoonChatMoonSuiteProductHome {
  {
    product_id: home.product_id,
    state_path: home.state_path,
    service_path: home.service_path,
    cache_path: home.cache_path,
    tmp_path: home.tmp_path,
    accepted_output_path: home.accepted_output_path,
  }
}

///|
pub fn moonsuite_product_state_path_for_workspace_root(root : String) -> String {
  moonsuite_shared_product_home_for_workspace_root(root).state_path
}

///|
pub fn moonsuite_product_state_path() -> String {
  moonsuite_product_state_path_for_workspace_root(
    moonsuite_active_workspace_root(),
  )
}

///|
pub fn moonsuite_product_service_path_for_workspace_root(
  root : String,
) -> String {
  moonsuite_shared_product_home_for_workspace_root(root).service_path
}

///|
pub fn moonsuite_product_service_path() -> String {
  moonsuite_product_service_path_for_workspace_root(
    moonsuite_active_workspace_root(),
  )
}

///|
pub fn moonsuite_product_cache_path_for_workspace_root(root : String) -> String {
  moonsuite_shared_product_home_for_workspace_root(root).cache_path
}

///|
pub fn moonsuite_product_cache_path() -> String {
  moonsuite_product_cache_path_for_workspace_root(
    moonsuite_active_workspace_root(),
  )
}

///|
pub fn moonsuite_product_tmp_path_for_workspace_root(root : String) -> String {
  moonsuite_shared_product_home_for_workspace_root(root).tmp_path
}

///|
pub fn moonsuite_product_tmp_path() -> String {
  moonsuite_product_tmp_path_for_workspace_root(
    moonsuite_active_workspace_root(),
  )
}

///|
pub fn moonsuite_product_accepted_output_path_for_workspace_root(
  root : String,
  book_id? : String = "<book-id>",
) -> String {
  moonsuite_shared_product_home_for_workspace_root(root, book_id~).accepted_output_path
}

///|
pub fn moonsuite_product_accepted_output_path(
  book_id? : String = "<book-id>",
) -> String {
  moonsuite_product_accepted_output_path_for_workspace_root(
    moonsuite_active_workspace_root(),
    book_id~,
  )
}

///|
pub fn moonsuite_product_home_for_workspace_root(
  root : String,
  book_id? : String = "<book-id>",
) -> MoonChatMoonSuiteProductHome {
  moonchat_product_home_from_shared(
    moonsuite_shared_product_home_for_workspace_root(root, book_id~),
  )
}

///|
pub fn moonsuite_product_home(
  book_id? : String = "<book-id>",
) -> MoonChatMoonSuiteProductHome {
  moonsuite_product_home_for_workspace_root(
    moonsuite_active_workspace_root(),
    book_id~,
  )
}
