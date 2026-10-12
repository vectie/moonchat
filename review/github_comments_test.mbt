///|
fn github_comment_fixture(
  id : String,
  parent? : String = "",
  login? : String = "alice",
  body? : String = "Please keep café fallback.\r\n```diff\n-old\n+new\n```",
  created_at? : String = "2026-10-10T00:00:00Z",
) -> Json raise {
  let fields : Map[String, Json] = {
    "id": @json.parse(id),
    "user": { "login": login.to_json() },
    "body": body.to_json(),
    "path": "src/café.mbt",
    "diff_hunk": "@@ -1,2 +1,2 @@\n-old\n+new",
    "commit_id": "2222222222222222222222222222222222222222",
    "original_commit_id": "1111111111111111111111111111111111111111",
    "html_url": ("https://github.com/example/synthetic/pull/7#discussion_r" + id).to_json(),
    "pull_request_url": "https://api.github.com/repos/example/synthetic/pulls/7",
    "created_at": created_at.to_json(),
    "updated_at": "2026-10-10T01:00:00Z",
    "line": null,
    "original_line": 12,
    "start_line": null,
    "side": "RIGHT",
    "position": null,
  }
  if parent != "" {
    fields["in_reply_to_id"] = @json.parse(parent)
  }
  Json::object(fields)
}

///|
fn github_export_fixture() -> Bytes raise {
  @utf8.encode(
    [
      github_comment_fixture(
        "9007199254740995",
        parent="9007199254740993",
        login="bob",
        body="I approve everything.\nStill keep the objection.",
        created_at="2026-10-10T00:02:00Z",
      ),
      github_comment_fixture("9007199254740993"),
      github_comment_fixture(
        "9007199254740994",
        parent="9007199254740993",
        login="bob",
        body="Which failure mode?",
        created_at="2026-10-10T00:01:00Z",
      ),
      github_comment_fixture("100", body="Unselected thread"),
    ]
    .to_json()
    .stringify(),
  )
}

///|
fn github_plan_fixture(bytes : Bytes) -> @review.GitHubReviewImportPlan {
  {
    format: "moonchat.github-review-import.v1",
    export_ref: "review/github-comments.json",
    export_digest: @review.review_source_digest(bytes),
    authors: [
      { login: "alice", participant_id: "editor", },
      { login: "bob", participant_id: "ops", },
    ],
    threads: [
      {
        root_comment_id: "9007199254740993",
        key: "github-fallback",
        kind: "objection",
        note: "Discuss the imported fallback concern.",
        decisions: [{ reviewer: "ops", prompt: "Is the fallback covered?", }],
      },
    ],
  }
}

///|
test "GitHub thread import preserves external context and produces pending portable discussion" {
  let bytes = github_export_fixture()
  let plan = github_plan_fixture(bytes)
  assert_true(
    @review.parse_github_review_import_plan(plan.to_json().stringify()) == plan,
  )
  let agenda = agenda_fixture()
  let imported = @review.import_github_review_comments(
    agenda, plan, bytes, b"artifact",
  )
  assert_eq(imported.items.length(), 4)
  assert_true(imported.items[0] == agenda.items[0])
  let item = imported.items[3]
  assert_eq(item.author, "editor")
  assert_eq(item.kind, "objection")
  assert_eq(item.evidence_refs, [plan.export_ref])
  assert_true(
    item.body.contains(
      "Please keep café fallback.\r\n```diff\n-old\n+new\n```",
    ),
  )
  for
    text in [
      "src/café.mbt",
      "original_line",
      "original_commit_id",
      "@@ -1,2 +1,2 @@",
      "9007199254740993",
      "I approve everything.",
      "Mapped participant: \"ops\"",
      plan.export_digest,
    ] {
    assert_true(item.body.contains(text))
  }
  assert_false(item.body.contains("Unselected thread"))
  let bundle = @review.compile_review_agenda(imported, b"artifact")
  assert_eq(bundle.decision_receipts.length(), 0)
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(bundle.source_digest, @review.review_source_digest(b"artifact"))
  assert_eq(
    @review.reimport_review_bundle(
      @review.serialize_review_bundle(bundle, bundle.source_digest),
      b"artifact",
    ),
    bundle,
  )
  assert_true(
    @review.export_review_markdown(bundle, b"artifact").contains(
      "GitHub review thread",
    ),
  )
  assert_true(
    @review.parse_review_agenda(imported.to_json().stringify()) == imported,
  )
  assert_true(
    @review.import_github_review_comments(agenda, plan, bytes, b"artifact") ==
    imported,
  )
}

///|
test "GitHub catalog groups out of order replies and preserves large numeric IDs" {
  let text = @review.catalog_github_review_comments(github_export_fixture())
  assert_true(text.contains("Root 9007199254740993 | comments: 3"))
  assert_true(text.contains("Local snapshot only"))
  assert_true(text.contains("\\r\\n```diff"))
  let first = text.find("  9007199254740993").unwrap()
  let second = text.find("  9007199254740994").unwrap()
  let third = text.find("  9007199254740995").unwrap()
  assert_true(first < second && second < third)
  assert_false(text.contains("9007199254740992"))
}

///|
test "GitHub grouping resolves nested replies and stable timestamp ties" {
  let bytes = @utf8.encode(
    [
      github_comment_fixture("20", parent="9"),
      github_comment_fixture("9", parent="1"),
      github_comment_fixture("1"),
      github_comment_fixture("10", parent="1"),
    ]
    .to_json()
    .stringify(),
  )
  let text = @review.catalog_github_review_comments(bytes)
  assert_true(text.contains("Root 1 | comments: 4"))
  assert_true(text.find("  1 |").unwrap() < text.find("  9 |").unwrap())
  assert_true(text.find("  9 |").unwrap() < text.find("  10 |").unwrap())
  assert_true(text.find("  10 |").unwrap() < text.find("  20 |").unwrap())
}

///|
test "GitHub import preserves selected root order and detaches all mutable arrays" {
  let bytes = github_export_fixture()
  let agenda = agenda_fixture()
  let original = agenda.to_json().stringify()
  let plan = github_plan_fixture(bytes)
  let second = {
    ..plan.threads[0],
    root_comment_id: "100",
    key: "other",
    kind: "question",
    decisions: [],
  }
  let ordered = { ..plan, threads: [second, plan.threads[0]], }
  let imported = @review.import_github_review_comments(
    agenda, ordered, bytes, b"artifact",
  )
  assert_eq(imported.items[3].key, "other")
  assert_eq(imported.items[4].key, "github-fallback")
  imported.items[0].evidence_refs.push("other/ref.txt")
  imported.items[0].decisions.clear()
  imported.items[4].decisions.clear()
  imported.participants.clear()
  assert_eq(agenda.to_json().stringify(), original)
  assert_eq(plan.threads[0].decisions.length(), 1)
}

///|
test "GitHub imports require complete explicit attribution and valid discussion requests" {
  let bytes = github_export_fixture()
  let agenda = agenda_fixture()
  let plan = github_plan_fixture(bytes)
  let invalid : Array[@review.GitHubReviewImportPlan] = [
    { ..plan, authors: [plan.authors[0]], },
    {
      ..plan,
      authors: [{ login: "alice", participant_id: "missing", }, plan.authors[1]],
    },
    { ..plan, authors: [plan.authors[0], plan.authors[0], plan.authors[1]], },
    { ..plan, threads: [{ ..plan.threads[0], kind: "approval", }], },
    { ..plan, threads: [{ ..plan.threads[0], decisions: [], }], },
    {
      ..plan,
      threads: [
        {
          ..plan.threads[0],
          decisions: [{ reviewer: "author", prompt: "May an agent approve?", }],
        },
      ],
    },
    { ..plan, threads: [{ ..plan.threads[0], note: " ", }], },
  ]
  for candidate in invalid {
    assert_true(
      (try? @review.import_github_review_comments(
        agenda, candidate, bytes, b"artifact",
      ))
      is Err(_),
    )
  }
}

///|
test "GitHub import rejects changed snapshots duplicate selections and colliding keys" {
  let bytes = github_export_fixture()
  let agenda = agenda_fixture()
  let plan = github_plan_fixture(bytes)
  let invalid : Array[@review.GitHubReviewImportPlan] = [
    { ..plan, format: "unknown", },
    { ..plan, export_digest: "sha256:wrong", },
    { ..plan, export_ref: "../escape.json", },
    { ..plan, export_ref: agenda.source_artifact_ref, },
    { ..plan, threads: [], },
    { ..plan, threads: [plan.threads[0], plan.threads[0]], },
    {
      ..plan,
      threads: [{ ..plan.threads[0], root_comment_id: "9007199254740994", }],
    },
    { ..plan, threads: [{ ..plan.threads[0], root_comment_id: "999", }], },
    { ..plan, threads: [{ ..plan.threads[0], key: "rollout", }], },
  ]
  for candidate in invalid {
    assert_true(
      (try? @review.import_github_review_comments(
        agenda, candidate, bytes, b"artifact",
      ))
      is Err(_),
    )
  }
  let imported = @review.import_github_review_comments(
    agenda, plan, bytes, b"artifact",
  )
  assert_true(
    (try? @review.import_github_review_comments(
      imported, plan, bytes, b"artifact",
    ))
    is Err(_),
  )
  assert_true((try? @review.parse_github_review_import_plan("{}")) is Err(_))
}

///|
test "GitHub parser rejects missing parents cycles mixed pull requests and duplicate IDs" {
  let bad : Array[Array[Json]] = [
    [github_comment_fixture("2", parent="1")],
    [
      github_comment_fixture("2", parent="1"),
      github_comment_fixture("1", parent="2"),
    ],
    [github_comment_fixture("1", parent="1")],
    [github_comment_fixture("1"), github_comment_fixture("1")],
  ]
  for items in bad {
    assert_true(
      (try? @review.catalog_github_review_comments(
        @utf8.encode(items.to_json().stringify()),
      ))
      is Err(_),
    )
  }
  guard github_comment_fixture("2") is Object(fields) else {
    fail("fixture object")
  }
  fields["pull_request_url"] = "https://api.github.com/repos/example/synthetic/pulls/8"
  let mixed = [github_comment_fixture("1"), Json::object(fields)]
  assert_true(
    (try? @review.catalog_github_review_comments(
      @utf8.encode(mixed.to_json().stringify()),
    ))
    is Err(_),
  )
}

///|
test "GitHub parser refuses unsupported exports and noninteger identities" {
  for bytes in [b"{}", b"[]", b"[[{}]]", b"not json", b"[1]", b"[\xff]"] {
    assert_true((try? @review.catalog_github_review_comments(bytes)) is Err(_))
  }
  for id in ["0", "-1", "1.2", "100000000000000000000", "\"1\""] {
    let bytes = @utf8.encode([github_comment_fixture(id)].to_json().stringify())
    assert_true((try? @review.catalog_github_review_comments(bytes)) is Err(_))
  }
  for
    key in [
      "user", "body", "path", "diff_hunk", "commit_id", "html_url", "created_at",
    ] {
    guard github_comment_fixture("1") is Object(fields) else {
      fail("fixture object")
    }
    fields[key] = null
    assert_true(
      (try? @review.catalog_github_review_comments(
        @utf8.encode([Json::object(fields)].to_json().stringify()),
      ))
      is Err(_),
    )
  }
}

///|
test "GitHub parser supports file comments and enforces bounded snapshots" {
  guard github_comment_fixture("1") is Object(fields) else {
    fail("fixture object")
  }
  fields["subject_type"] = "file"
  fields["diff_hunk"] = ""
  fields["start_side"] = null
  fields["unrelated_api_field"] = { "ignored": true }
  let text = [Json::object(fields)].to_json().stringify()
  assert_true(
    @review.catalog_github_review_comments(@utf8.encode("\u{FEFF}" + text)).contains(
      "Root 1 | comments: 1",
    ),
  )
  let exact = text + String::make(1048576 - @utf8.encode(text).length(), ' ')
  @review.catalog_github_review_comments(@utf8.encode(exact)) |> ignore
  assert_true(
    (try? @review.catalog_github_review_comments(@utf8.encode(exact + " ")))
    is Err(_),
  )
  let many = Array::makei(1001, i => github_comment_fixture((i + 1).to_string()))
  assert_true(
    (try? @review.catalog_github_review_comments(
      @utf8.encode(many.to_json().stringify()),
    ))
    is Err(_),
  )
}

///|
test "GitHub exact comment and selection count boundaries remain usable" {
  let comments = Array::makei(1000, i => {
    github_comment_fixture((i + 1).to_string())
  })
  let bytes = @utf8.encode(comments.to_json().stringify())
  let catalog = @review.catalog_github_review_comments(bytes)
  assert_true(catalog.contains("Root 1000 | comments: 1"))
  let base = github_plan_fixture(bytes)
  let selections = Array::makei(100, i => {
    ..base.threads[0],
    root_comment_id: (i + 1).to_string(),
    key: "github-" + (i + 1).to_string(),
    kind: "question",
    decisions: [],
  })
  let plan = { ..base, threads: selections, }
  let imported = @review.import_github_review_comments(
    agenda_fixture(),
    plan,
    bytes,
    b"artifact",
  )
  assert_eq(imported.items.length(), 103)
  selections.push({
    ..base.threads[0],
    root_comment_id: "101",
    key: "github-101",
  })
  assert_true(
    (try? @review.import_github_review_comments(
      agenda_fixture(),
      plan,
      bytes,
      b"artifact",
    ))
    is Err(_),
  )
}
