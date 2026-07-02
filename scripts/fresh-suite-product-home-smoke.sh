#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
moon_bin="${MOON_BIN:-/Users/kq/.moon/bin/moon}"
tmp_parent="${TMPDIR:-/tmp}"
tmp_parent="${tmp_parent%/}"
suite_root="$(mktemp -d "$tmp_parent/moonchat-fresh-suite-product-home.XXXXXX")"
suite_root="$(cd "$suite_root" && pwd)"

cleanup() {
  rm -rf "$suite_root"
}
trap cleanup EXIT

book_id="idea-room"
book_root="$suite_root/books/$book_id"
layout_json="$suite_root/layout.json"

mkdir -p "$suite_root/.moonsuite" "$suite_root/.tmp" "$book_root"

assert_contains() {
  local path="$1"
  local needle="$2"
  if ! /usr/bin/grep -Fq "$needle" "$path"; then
    echo "expected $path to contain: $needle" >&2
    exit 1
  fi
}

assert_absent_text() {
  local path="$1"
  local needle="$2"
  if /usr/bin/grep -Fq "$needle" "$path"; then
    echo "unexpected stale text in $path: $needle" >&2
    exit 1
  fi
}

cd "$repo_root"
"$moon_bin" run cmd/main --target native -- layout "$book_root" "$book_id" > "$layout_json"

assert_contains "$layout_json" "\"product_id\": \"moonchat\""
assert_contains "$layout_json" "\"state_path\": \"$suite_root/.moonsuite/products/moonchat\""
assert_contains "$layout_json" "\"service_path\": \"$suite_root/.moonsuite/products/moonchat/service.json\""
assert_contains "$layout_json" "\"cache_path\": \"$suite_root/.moonsuite/products/moonchat/cache\""
assert_contains "$layout_json" "\"tmp_path\": \"$suite_root/.tmp/products/moonchat\""
assert_contains "$layout_json" "\"accepted_output_path\": \"$suite_root/books/$book_id/outputs/moonchat\""
assert_absent_text "$layout_json" "$book_root/.moonsuite/products/moonchat"
assert_absent_text "$layout_json" "$suite_root/.moonchat"

echo "MoonChat fresh-suite product-home smoke passed on $suite_root"
