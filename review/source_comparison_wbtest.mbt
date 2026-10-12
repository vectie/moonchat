///|
fn source_edit_distance(a : Array[String], b : Array[String]) -> Int {
  // Independent recursive oracle, deliberately tiny inputs only.
  if a.is_empty() {
    return b.length()
  }
  if b.is_empty() {
    return a.length()
  }
  if a[0] == b[0] {
    source_edit_distance(a[1:].to_owned(), b[1:].to_owned())
  } else {
    1 +
    Int::min(
      source_edit_distance(a[1:].to_owned(), b),
      source_edit_distance(a, b[1:].to_owned()),
    )
  }
}

///|
test "source diff reconstructs both sides and has minimal edits for all short binary alphabets" {
  let inputs : Array[Array[String]] = [[]]
  for length = 1; length <= 4; length = length + 1 {
    for bits = 0; bits < 1 << length; bits = bits + 1 {
      let value : Array[String] = []
      for i = 0; i < length; i = i + 1 {
        value.push(if ((bits >> i) & 1) == 0 { "a\n" } else { "b\n" })
      }
      inputs.push(value)
    }
  }
  for before in inputs {
    for after in inputs {
      let rows = source_comparison_rows(before, after)
      let old : Array[String] = []
      let next : Array[String] = []
      let mut edits = 0
      for row in rows {
        if row.kind != "+" {
          old.push(row.text)
          assert_eq(row.before_line, old.length())
        } else {
          assert_eq(row.before_line, 0)
        }
        if row.kind != "-" {
          next.push(row.text)
          assert_eq(row.after_line, next.length())
        } else {
          assert_eq(row.after_line, 0)
        }
        if row.kind != "=" {
          edits += 1
        }
      }
      assert_eq(old, before)
      assert_eq(next, after)
      assert_eq(edits, source_edit_distance(before, after))
    }
  }
}
