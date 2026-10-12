///|
fn github_refresh_next() -> Bytes raise {
  @utf8.encode(
    [
      github_comment_fixture(
        "9007199254740993",
        body="Keep café fallback and record its owner.",
      ),
      github_comment_fixture(
        "9007199254740994",
        parent="9007199254740993",
        login="bob",
        body="Which failure mode?",
        created_at="2026-10-10T00:01:00Z",
      ),
      github_comment_fixture(
        "9007199254740995",
        parent="9007199254740993",
        login="bob",
        body="I approve everything.\nStill keep the objection.",
        created_at="2026-10-10T00:02:00Z",
      ),
      github_comment_fixture(
        "9007199254740996",
        parent="9007199254740993",
        login="bob",
        body="New reply: include 夜間 support.",
        created_at="2026-10-10T00:03:00Z",
      ),
      github_comment_fixture("100", body="Unselected thread changed."),
    ]
    .to_json()
    .stringify(),
  )
}

///|
fn github_refresh_plan(bytes : Bytes) -> @review.GitHubReviewImportPlan {
  { ..github_plan_fixture(bytes), export_ref: "review/github-next.json", }
}

///|
fn github_refresh_current() -> @review.ReviewAgenda raise {
  let bytes = github_export_fixture()
  @review.import_github_review_comments(
    agenda_fixture(),
    github_plan_fixture(bytes),
    bytes,
    b"artifact",
  )
}

///|
test "GitHub refresh integrates new replies and changed comments with local decisions and ordering" {
  let old = github_export_fixture()
  let next = github_refresh_next()
  let current = github_refresh_current()
  current.items[3] = {
    ..current.items[3],
    decisions: [{ reviewer: "ops", prompt: "Locally revised request", }],
  }
  current.items[0] = { ..current.items[0], body: "Locally edited proposal", }
  let item = current.items.remove(3)
  current.items.insert(0, item)
  let unchanged = current.to_json().stringify()
  let result = @review.refresh_github_review_comments(
    current,
    github_plan_fixture(old),
    old,
    github_refresh_plan(next),
    next,
    b"artifact",
  )
  assert_eq(result.added_comment_ids, ["9007199254740996"])
  assert_eq(result.changed_comment_ids, ["9007199254740993"])
  assert_true(result.conflicts.is_empty())
  let agenda = result.merged_agenda.unwrap()
  assert_eq(agenda.items[0].key, "github-fallback")
  assert_eq(agenda.items[1].body, "Locally edited proposal")
  assert_eq(agenda.items[0].decisions[0].prompt, "Locally revised request")
  assert_true(
    agenda.items[0].body.contains("New reply: include 夜間 support."),
  )
  assert_true(agenda.items[0].body.contains("I approve everything."))
  assert_eq(agenda.items[0].evidence_refs, ["review/github-next.json"])
  let bundle = @review.compile_review_agenda(agenda, b"artifact")
  assert_true(bundle.decision_receipts.is_empty())
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(current.to_json().stringify(), unchanged)
  assert_eq(
    @review.reimport_review_bundle(
      @review.serialize_review_bundle(bundle, bundle.source_digest),
      b"artifact",
    ),
    bundle,
  )
}

///|
test "GitHub refresh reports every overlapping field conflict and supports explicit reconciliation" {
  let old = github_export_fixture()
  let next = github_refresh_next()
  let current = github_refresh_current()
  current.items[3] = {
    ..current.items[3],
    body: "Local rewritten objection",
    evidence_refs: ["local/notes.txt"],
  }
  let result = @review.refresh_github_review_comments(
    current,
    github_plan_fixture(old),
    old,
    github_refresh_plan(next),
    next,
    b"artifact",
  )
  assert_true(result.merged_agenda is None)
  assert_eq(result.conflicts.map(c => c.field), ["body", "evidence_refs"])
  assert_eq(result.conflicts[0].left, "Local rewritten objection".to_json())
  assert_true(result.conflicts[0].right.stringify().contains("New reply"))
  assert_true(
    result.conflicts[0].base.stringify().contains("Please keep café"),
  )
  let regenerated = github_refresh_current()
  regenerated.items[3] = {
    ..regenerated.items[3],
    body: @json.from_json(result.conflicts[0].right),
    evidence_refs: @json.from_json(result.conflicts[1].right),
  }
  let fixed = @review.refresh_github_review_comments(
    regenerated,
    github_plan_fixture(old),
    old,
    github_refresh_plan(next),
    next,
    b"artifact",
  )
  assert_true(fixed.conflicts.is_empty())
  assert_true(fixed.merged_agenda is Some(_))
}

///|
test "GitHub refresh is deterministic and repeating or chaining never duplicates replies" {
  let old = github_export_fixture()
  let next = github_refresh_next()
  let old_plan = github_plan_fixture(old)
  let next_plan = github_refresh_plan(next)
  let current = github_refresh_current()
  let result = @review.refresh_github_review_comments(
    current, old_plan, old, next_plan, next, b"artifact",
  )
  assert_true(
    @review.refresh_github_review_comments(
      current, old_plan, old, next_plan, next, b"artifact",
    ) ==
    result,
  )
  let refreshed = result.merged_agenda.unwrap()
  assert_true(
    @review.refresh_github_review_comments(
      refreshed, old_plan, old, next_plan, next, b"artifact",
    ).merged_agenda ==
    Some(refreshed),
  )
  let same = @review.refresh_github_review_comments(
    refreshed, next_plan, next, next_plan, next, b"artifact",
  )
  assert_true(same.added_comment_ids.is_empty())
  assert_true(same.changed_comment_ids.is_empty())
  assert_true(same.merged_agenda == Some(refreshed))
}

///|
test "GitHub refresh preserves local deletions only when the imported item did not change" {
  let old = github_export_fixture()
  let next = github_refresh_next()
  let current = github_refresh_current()
  current.items.remove(3) |> ignore
  let deleted = @review.refresh_github_review_comments(
    current,
    github_plan_fixture(old),
    old,
    github_plan_fixture(old),
    old,
    b"artifact",
  )
  assert_true(deleted.merged_agenda == Some(current))
  let conflict = @review.refresh_github_review_comments(
    current,
    github_plan_fixture(old),
    old,
    github_refresh_plan(next),
    next,
    b"artifact",
  )
  assert_true(conflict.merged_agenda is None)
  assert_eq(conflict.conflicts[0].field, "item")
  assert_eq(conflict.conflicts[0].left, Json::null())
}

///|
test "GitHub refresh refuses incomplete snapshots without dropping earlier dissent" {
  let old = github_export_fixture()
  let current = github_refresh_current()
  let next = @utf8.encode(
    [github_comment_fixture("9007199254740993")].to_json().stringify(),
  )
  let result = try? @review.refresh_github_review_comments(
    current,
    github_plan_fixture(old),
    old,
    github_refresh_plan(next),
    next,
    b"artifact",
  )
  guard result is Err(Failure(message)) else {
    fail("expected omitted comment error")
  }
  assert_true(message.contains("omits previously selected comment"))
  assert_true(current.items[3].body.contains("Still keep the objection."))
}

///|
test "GitHub refresh rejects stale snapshots reused references changed selections and reassigned attribution" {
  let old = github_export_fixture()
  let next = github_refresh_next()
  let current = github_refresh_current()
  let previous_plan = github_plan_fixture(old)
  let plan = github_refresh_plan(next)
  let invalid : Array[@review.GitHubReviewImportPlan] = [
    { ..plan, export_digest: previous_plan.export_digest, },
    { ..plan, export_ref: previous_plan.export_ref, },
    { ..plan, threads: [{ ..plan.threads[0], key: "other-key", }], },
    {
      ..plan,
      threads: [{ ..plan.threads[0], note: "Different original recipe", }],
    },
    {
      ..plan,
      authors: [{ ..plan.authors[0], participant_id: "ops", }, plan.authors[1]],
    },
    { ..plan, authors: plan.authors + [plan.authors[0]], },
    { ..plan, format: "unknown", },
  ]
  for candidate in invalid {
    assert_true(
      (try? @review.refresh_github_review_comments(
        current, previous_plan, old, candidate, next, b"artifact",
      ))
      is Err(_),
    )
  }
  assert_true(
    (try? @review.refresh_github_review_comments(
      current,
      { ..previous_plan, export_digest: "bad", },
      old,
      plan,
      next,
      b"artifact",
    ))
    is Err(_),
  )
}

///|
test "GitHub refresh requires explicit attribution for a new reply author and detaches arrays" {
  let old = github_export_fixture()
  guard @json.parse(@utf8.decode(github_refresh_next())) is Array(values) else {
    fail("fixture array")
  }
  values.push(
    github_comment_fixture(
      "9007199254740997",
      parent="9007199254740993",
      login="carol",
    ),
  )
  let next = @utf8.encode(values.to_json().stringify())
  let current = github_refresh_current()
  let plan = github_refresh_plan(next)
  assert_true(
    (try? @review.refresh_github_review_comments(
      current,
      github_plan_fixture(old),
      old,
      plan,
      next,
      b"artifact",
    ))
    is Err(_),
  )
  let mapped = {
    ..plan,
    authors: plan.authors + [{ login: "carol", participant_id: "editor", }],
  }
  let before = current.to_json().stringify()
  let result = @review.refresh_github_review_comments(
    current,
    github_plan_fixture(old),
    old,
    mapped,
    next,
    b"artifact",
  )
  let agenda = result.merged_agenda.unwrap()
  agenda.participants.clear()
  agenda.items[0].evidence_refs.push("more/evidence.txt")
  agenda.items[3].decisions.clear()
  assert_eq(current.to_json().stringify(), before)
  assert_eq(mapped.threads[0].decisions.length(), 1)
}

///|
test "GitHub refresh refuses cross pull requests and moved comment membership" {
  let old = github_export_fixture()
  let current = github_refresh_current()
  guard @json.parse(@utf8.decode(github_refresh_next())) is Array(values) else {
    fail("fixture array")
  }
  let other_pr = values.map(value => {
    guard value is Object(fields) else { fail("fixture object") }
    fields["pull_request_url"] = "https://api.github.com/repos/example/synthetic/pulls/9"
    Json::object(fields)
  })
  let next = @utf8.encode(other_pr.to_json().stringify())
  assert_true(
    (try? @review.refresh_github_review_comments(
      current,
      github_plan_fixture(old),
      old,
      github_refresh_plan(next),
      next,
      b"artifact",
    ))
    is Err(_),
  )
  guard @json.parse(@utf8.decode(github_refresh_next())) is Array(moved) else {
    fail("fixture array")
  }
  guard moved[1] is Object(fields) else { fail("fixture object") }
  fields["in_reply_to_id"] = 100
  let moved_bytes = @utf8.encode(moved.to_json().stringify())
  assert_true(
    (try? @review.refresh_github_review_comments(
      current,
      github_plan_fixture(old),
      old,
      github_refresh_plan(moved_bytes),
      moved_bytes,
      b"artifact",
    ))
    is Err(_),
  )
}
