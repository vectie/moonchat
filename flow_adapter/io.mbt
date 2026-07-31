///|
fn safe_artifact_ref(reference : String) -> Bool {
  let normalized = reference.trim().replace(old="\\", new="/")
  !normalized.is_empty() &&
  !normalized.has_prefix("/") &&
  !normalized
  .split("/")
  .any(part => part.is_empty() || part == "." || part == "..")
}

///|
fn scoped_path(root : String, reference : String) -> String raise {
  if !safe_artifact_ref(reference) {
    fail("MoonChat Flow artifact must be workspace-relative: \{reference}")
  }
  @pathx.join(root, reference)
}

///|
async fn resolve_workspace(workspace : String) -> String {
  @fs.realpath(@pathx.normalize(workspace))
}

///|
async fn read_json_ref(root : String, reference : String) -> Json {
  @json.parse(@fs.read_file(scoped_path(root, reference)).text())
}

///|
async fn read_optional_json_ref(root : String, reference : String) -> Json? {
  let path = scoped_path(root, reference)
  if !@fs.exists(path) {
    return None
  }
  Some(@json.parse(@fs.read_file(path).text())) catch {
    _ => None
  }
}

///|
fn sha256_bytes(bytes : Bytes) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(bytes))}"
}

///|
fn sha256_text(text : String) -> String {
  sha256_bytes(@utf8.encode(text))
}

///|
async fn digest_ref(root : String, reference : String) -> String {
  sha256_bytes(@fs.read_file(scoped_path(root, reference)).binary())
}

///|
async fn immutable_json_ref(
  root : String,
  reference : String,
  value : Json,
) -> String {
  let path = scoped_path(root, reference)
  let text = value.stringify(indent=2) + "\n"
  if @fs.exists(path) {
    if @fs.read_file(path).text() != text {
      fail("MoonChat immutable artifact conflicts: \{reference}")
    }
    return text
  }
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fs.write_file(path, text, create_mode=CreateNew, permission=0o644, sync=Full) catch {
    _ =>
      if !@fs.exists(path) || @fs.read_file(path).text() != text {
        fail("MoonChat could not create immutable artifact: \{reference}")
      }
  }
  text
}

///|
async fn declared_input_digest(
  root : String,
  artifacts : Array[String],
) -> String {
  let identities : Array[String] = []
  for reference in artifacts {
    identities.push("\{reference}|\{digest_ref(root, reference)}")
  }
  sha256_text(identities.join("\n"))
}
