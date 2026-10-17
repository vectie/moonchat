///|
fn patch_fixture() -> Bytes {
  @utf8.encode(
    (
      #|diff --git a/release.md b/release.md
      #|index 1111111..2222222 100644
      #|--- a/release.md
      #|+++ b/release.md
      #|@@ -1,3 +1,3 @@ release policy
      #| # Launch
      #|-Owner: unassigned
      #|+Owner: café 🌙 operations
      #| Ready after review.
      #|@@ -8 +8,2 @@ monitoring
      #| Keep rollback ready.
      #|+Watch errors for 30 minutes.
      #|diff --git a/checklist.txt b/checklist.txt
      #|new file mode 100644
      #|--- /dev/null
      #|+++ b/checklist.txt
      #|@@ -0,0 +1,2 @@
      #|+Confirm owner
      #|+Confirm rollback
      #|\ No newline at end of file
      #|
    ),
  )
}

///|
fn patch_plan(bytes : Bytes) -> @review.PatchReviewImportPlan {
  {
    format: "moonchat.review-patch.v1",
    source_digest: @review.review_source_digest(bytes),
    selections: [
      {
        file: 1,
        hunk: 1,
        key: "assign-owner",
        kind: "proposal",
        author: "editor",
        note: "Confirm the named rollout owner before applying these changes.",
        decisions: [
          { reviewer: "ops", prompt: "Is this owner assignment correct?", },
        ],
      },
    ],
  }
}

///|
test "patch catalog preserves files hunks coordinates additions deletions and metadata" {
  let bytes = patch_fixture()
  let catalog = @review.catalog_patch_review(bytes)
  assert_eq(catalog, @review.catalog_patch_review(bytes))
  guard @json.parse(catalog) is { "files": Array(files), .. } else {
    fail("files")
  }
  assert_eq(files.length(), 2)
  guard files[0] is { "hunks": Array(hunks), "headers": String(headers), .. } else {
    fail("hunks")
  }
  assert_eq(hunks.length(), 2)
  assert_true(headers.contains("index 1111111..2222222 100644"))
  assert_true(
    hunks[0]
    is {
      "change": {
        "old_start": Number(1, ..),
        "old_count": Number(3, ..),
        "new_start": Number(1, ..),
        "new_count": Number(3, ..),
        "added": Number(1, ..),
        "removed": Number(1, ..),
        ..
      },
      ..
    },
  )
  assert_true(
    hunks[1]
    is {
      "change": {
        "old_start": Number(8, ..),
        "old_count": Number(1, ..),
        "new_count": Number(2, ..),
        ..
      },
      ..
    },
  )
  for
    text in [
      "café 🌙", "new file mode", "No newline at end of file", "@@ -8 +8,2",
    ] {
    assert_true(catalog.contains(text))
  }
}

///|
test "patch selection composes editable pending evidence and existing decision forms" {
  let bytes = patch_fixture()
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  let plan = patch_plan(bytes)
  assert_true(
    @review.parse_patch_review_import_plan(plan.to_json().stringify()) == plan,
  )
  let imported = @review.import_patch_review(agenda, plan, bytes)
  assert_eq(agenda.to_json().stringify(), before)
  assert_eq(imported.items.length(), 4)
  let item = imported.items[3]
  assert_eq(item.evidence_refs, [agenda.source_artifact_ref])
  for
    text in [
      "Owner: unassigned", "Owner: café 🌙 operations", "not applied", "release policy",
    ] {
    assert_true(item.body.contains(text))
  }
  assert_false(item.body.contains("Watch errors"))
  assert_false(item.body.contains("Confirm rollback"))
  let bundle = @review.compile_review_agenda(imported, bytes)
  assert_eq(bundle.source_digest, plan.source_digest)
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  let serialized = @review.serialize_review_bundle(bundle, bundle.source_digest)
  assert_eq(@review.reimport_review_bundle(serialized, bytes), bundle)
  let form = @review.prepare_review_decisions(serialized, bytes, "ops")
  assert_eq(form.choices.length(), 3)
  assert_true(
    form.choices.all(choice => choice.outcome == "" && choice.receipt_id == ""),
  )
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  assert_true(
    @review.export_review_markdown(bundle, bytes).contains(
      "Is this owner assignment correct?",
    ),
  )
}

///|
test "patch selections reorder without changing authored entry identities" {
  let bytes = patch_fixture()
  let plan = patch_plan(bytes)
  let second = { ..plan.selections[0], file: 2, key: "checklist", }
  let first = @review.import_patch_review(
    agenda_fixture(),
    { ..plan, selections: [plan.selections[0], second], },
    bytes,
  )
  let reordered = @review.import_patch_review(
    agenda_fixture(),
    { ..plan, selections: [second, plan.selections[0]], },
    bytes,
  )
  let a = @review.compile_review_agenda(first, bytes)
  let b = @review.compile_review_agenda(reordered, bytes)
  assert_eq(a.entries[3], b.entries[4])
  assert_eq(a.entries[4], b.entries[3])
}

///|
test "patch deletion zero-context additions CRLF timestamps and literal paths are supported" {
  for
    text in [
      "--- old\t2026-10-13 00:00:00\n+++ /dev/null\t2026-10-13 00:00:00\n@@ -1,2 +0,0 @@\n-old\n-last\n",
      "--- a/path with spaces\r\n+++ b/path with spaces\r\n@@ -5,0 +6 @@\r\n+new café 🌙\r\n",
      "--- a/../../../label-only\n+++ b/../../../label-only\n@@ -1 +1 @@\n-old\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n--- header-like content\n+++ header-like content\n",
    ] {
    let bytes = @utf8.encode(text)
    let catalog = @review.catalog_patch_review(bytes)
    assert_true(catalog.contains(@review.review_source_digest(bytes)))
    let imported = @review.import_patch_review(
      agenda_fixture(),
      patch_plan(bytes),
      bytes,
    )
    assert_eq(imported.items.length(), 4)
  }
}

///|
test "patch rejects truncated overflow empty and wrong-count hunks" {
  for
    text in [
      "--- a/x\n+++ b/x\n@@ -1,2 +1 @@\n-old\n+new\n", "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n-too much\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n same\n", "--- a/x\n+++ b/x\n@@ -0,0 +0,0 @@\n",
      "--- a/x\n+++ b/x\n@@ -0 +1 @@\n-old\n+new\n", "--- a/x\n+++ b/x\n@@ -1000000001 +1 @@\n-old\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1,10001 +1 @@\n-old\n+new\n", "--- a/x\n+++ b/x\n@@ -1 +1 @@invalid\n-old\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n\n-old\n+new\n",
    ] {
    assert_true(
      (try? @review.catalog_patch_review(@utf8.encode(text))) is Err(_),
      msg=text,
    )
  }
}

///|
test "patch rejects unsupported formats and any trailing nonpatch content" {
  for
    text in [
      "", "not a patch\n", "diff --git a/x b/x\nold mode 100644\nnew mode 100755\n",
      "diff --git a/x b/x\nBinary files a/x and b/x differ\n", "diff --git a/x b/x\nGIT binary patch\nliteral 1\nX\n",
      "--- a/x\n+++ b/x\n@@@ -1 -1 +1 @@@\n-old\n+new\n", "--- \"a/quoted\\tpath\"\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\ntrailing text\n", "--- /dev/null\n+++ /dev/null\n@@ -1 +1 @@\n-old\n+new\n",
      "--- /dev/null\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n",
    ] {
    assert_true(
      (try? @review.catalog_patch_review(@utf8.encode(text))) is Err(_),
      msg=text,
    )
  }
}

///|
test "patch rejects overlapping or reversed hunks and malformed newline markers" {
  for
    text in [
      "--- a/x\n+++ b/x\n@@ -2 +2 @@\n-old\n+new\n@@ -1 +1 @@\n-old\n+new\n", "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n@@ -1 +1 @@\n-old\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n\\ No newline at end of file\n-old\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n\\ No newline at end of file\n",
      "--- a/x\n+++ b/x\n@@ -1,2 +1 @@\n-old\n\\ No newline at end of file\n-old2\n+new\n",
      "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n@@ -2,0 +3 @@\n+later\n",
    ] {
    assert_true(
      (try? @review.catalog_patch_review(@utf8.encode(text))) is Err(_),
      msg=text,
    )
  }
}

///|
test "patch import rejects stale nonexistent duplicated and late invalid selections atomically" {
  let bytes = patch_fixture()
  let plan = patch_plan(bytes)
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  assert_true(
    (try? @review.import_patch_review(
      agenda,
      plan,
      @utf8.encode(@utf8.decode(bytes) + "\n"),
    ))
    is Err(_),
  )
  for
    selection in [
      { ..plan.selections[0], file: 0, },
      { ..plan.selections[0], hunk: 0, },
      { ..plan.selections[0], file: 3, },
      { ..plan.selections[0], hunk: 3, },
      { ..plan.selections[0], author: "unknown", },
      { ..plan.selections[0], kind: "approve", },
      { ..plan.selections[0], note: " ", },
      { ..plan.selections[0], key: "", },
      {
        ..plan.selections[0],
        decisions: [{ reviewer: "author", prompt: "Approve?", }],
      },
    ] {
    assert_true(
      (try? @review.import_patch_review(
        agenda,
        { ..plan, selections: [selection], },
        bytes,
      ))
      is Err(_),
    )
  }
  for
    selections in [
      [],
      [plan.selections[0], plan.selections[0]],
      [plan.selections[0], { ..plan.selections[0], file: 99, key: "late", }],
      Array::make(101, plan.selections[0]),
    ] {
    assert_true(
      (try? @review.import_patch_review(agenda, { ..plan, selections, }, bytes))
      is Err(_),
    )
  }
  assert_eq(agenda.to_json().stringify(), before)
}

///|
test "patch import isolates mutable output arrays from input agenda and plan" {
  let bytes = patch_fixture()
  let plan = patch_plan(bytes)
  let agenda = agenda_fixture()
  let before = agenda.to_json().stringify()
  let plan_before = plan.to_json().stringify()
  let imported = @review.import_patch_review(agenda, plan, bytes)
  imported.items[0].evidence_refs.push("new/evidence")
  imported.items[0].decisions.clear()
  imported.items[3].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.to_json().stringify(), before)
  assert_eq(plan.to_json().stringify(), plan_before)
}

///|
test "patch markup remains literal evidence and source path is never interpreted" {
  let bytes = @utf8.encode(
    "--- a/<script>bad()</script>\n+++ b/<script>bad()</script>\n@@ -1 +1 @@\n-old\n+<script>bad()</script>\n",
  )
  let imported = @review.import_patch_review(
    agenda_fixture(),
    patch_plan(bytes),
    bytes,
  )
  let html = @review.export_review_html(
    @review.compile_review_agenda(imported, bytes),
    bytes,
  )
  assert_true(html.contains("&lt;script&gt;bad()&lt;/script&gt;"))
  assert_false(html.contains("<script>bad()</script>"))
}

///|
test "patch bounds enforce bytes lines files hunks and UTF8 before selection" {
  let one = "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n"
  for
    bytes in [
      Bytes::from_array([0xff]),
      @utf8.encode(one + "\u{0000}"),
      @utf8.encode(one + "x".repeat(1048576)),
      @utf8.encode(one + "\n".repeat(10000)),
      @utf8.encode(one.repeat(101)),
    ] {
    assert_true((try? @review.catalog_patch_review(bytes)) is Err(_))
  }
  let hunks : Array[String] = []
  for i in 1..<=1001 {
    hunks.push("@@ -\{i} +\{i} @@\n-old\n+new\n")
  }
  assert_true(
    (try? @review.catalog_patch_review(
      @utf8.encode("--- a/x\n+++ b/x\n" + hunks.join("")),
    ))
    is Err(_),
  )
}

///|
test "patch preparation schema and item keys retain normal authoring validation" {
  let bytes = patch_fixture()
  let plan = patch_plan(bytes)
  let wrong = { ..plan, format: "moonchat.review-patch.v2", }
  assert_true(
    (try? @review.parse_patch_review_import_plan(wrong.to_json().stringify()))
    is Err(_),
  )
  assert_true(
    (try? @review.import_patch_review(agenda_fixture(), wrong, bytes)) is Err(_),
  )
  let imported = @review.import_patch_review(agenda_fixture(), plan, bytes)
  assert_true(
    (try? @review.import_patch_review(imported, plan, bytes)) is Err(_),
  )
}
