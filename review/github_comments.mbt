///|
/// Curated local import of GitHub REST pull-request review comments.
/// Login mappings describe imported authors; they do not authenticate anyone.
pub(all) struct GitHubReviewImportPlan {
  format : String
  export_ref : String
  export_digest : String
  authors : Array[GitHubReviewAuthor]
  threads : Array[GitHubReviewThread]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct GitHubReviewAuthor {
  login : String
  participant_id : String
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct GitHubReviewThread {
  root_comment_id : String
  key : String
  kind : String
  note : String
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
priv struct GitHubComment {
  id : String
  parent : String
  login : String
  body : String
  path : String
  created_at : String
  pull_request_url : String
  context : Json
} derive(Eq)

///|
fn github_decimal_id(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 20 &&
  value[0] != '0' &&
  value.iter().all(c => c >= '0' && c <= '9')
}

///|
fn github_id(value : Json) -> String raise {
  guard value is Number(_, ..) else {
    fail("GitHub comment IDs must be positive integer JSON numbers")
  }
  // Large number tokens retain their exact representation in the JSON parser.
  // Small exact integer forms may normalize; never convert IDs through Double.
  let id = value.stringify()
  if !github_decimal_id(id) {
    fail(
      "GitHub comment IDs must be positive integral values with at most 20 decimal digits",
    )
  }
  id
}

///|
fn github_text(fields : Map[String, Json], key : String) -> String raise {
  match fields.get(key) {
    Some(String(value)) if non_empty(value) => value
    _ => fail("GitHub review comment requires nonempty string field: " + key)
  }
}

///|
fn github_timestamp(value : String) -> Bool {
  if !canonical_utc_timestamp(value) {
    return false
  }
  for index in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
    if value[index] < '0' || value[index] > '9' {
      return false
    }
  }
  true
}

///|
priv struct GitHubCommentSnapshot {
  comments : Array[GitHubComment]
  roots : Map[String, String]
}

///|
fn github_comments(bytes : Bytes) -> GitHubCommentSnapshot raise {
  if bytes.length() > 1048576 {
    fail("GitHub comment export exceeds 1 MiB")
  }
  let text = @utf8.decode(bytes, ignore_bom=true)
  guard @json.parse(text) is Array(values) else {
    fail(
      "expected a flat GitHub REST review-comment JSON array, not issue comments or a GraphQL export",
    )
  }
  if values.is_empty() || values.length() > 1000 {
    fail("GitHub comment export must contain 1–1000 comments")
  }
  let comments : Array[GitHubComment] = []
  let ids : Map[String, Bool] = Map([])
  let mut pull_request = ""
  for value in values {
    guard value is Object(fields) else {
      fail("each GitHub review comment must be an object")
    }
    let id = match fields.get("id") {
      Some(value) => github_id(value)
      None => fail("GitHub review comment is missing id")
    }
    if ids.contains(id) {
      fail("duplicate GitHub comment id: " + id)
    }
    ids[id] = true
    let parent = match fields.get("in_reply_to_id") {
      None | Some(Null) => ""
      Some(value) => github_id(value)
    }
    let login = match fields.get("user") {
      Some(Object(user)) => github_text(user, "login")
      _ => fail("GitHub review comment requires user.login")
    }
    let body = github_text(fields, "body")
    let path = github_text(fields, "path")
    let created_at = github_text(fields, "created_at")
    let updated_at = github_text(fields, "updated_at")
    if !github_timestamp(created_at) || !github_timestamp(updated_at) {
      fail("GitHub comment times must be canonical UTC timestamps")
    }
    let pull_request_url = github_text(fields, "pull_request_url")
    if pull_request != "" && pull_request != pull_request_url {
      fail("GitHub comment export must describe one pull request")
    }
    pull_request = pull_request_url
    let context : Map[String, Json] = Map([])
    for
      key in [
        "html_url", "pull_request_url", "path", "diff_hunk", "commit_id", "original_commit_id",
        "created_at", "updated_at",
      ] {
      context[key] = if key == "diff_hunk" {
        match fields.get(key) {
          Some(String(value)) => value.to_json()
          _ => fail("GitHub review comment requires string diff_hunk")
        }
      } else {
        github_text(fields, key).to_json()
      }
    }
    context["id"] = fields["id"]
    if parent != "" {
      context["in_reply_to_id"] = fields["in_reply_to_id"]
    }
    for
      key in [
        "line", "original_line", "start_line", "original_start_line", "position",
        "original_position", "pull_request_review_id",
      ] {
      match fields.get(key) {
        None => ()
        Some(Null) => context[key] = null
        Some(value) => {
          github_id(value) |> ignore
          context[key] = value
        }
      }
    }
    for key in ["side", "start_side", "subject_type"] {
      match fields.get(key) {
        None => ()
        Some(Null) => context[key] = null
        Some(String(value)) => context[key] = value.to_json()
        _ => fail("GitHub location field must be a string or null: " + key)
      }
    }
    comments.push({
      id,
      parent,
      login,
      body,
      path,
      created_at,
      pull_request_url,
      context: Json::object(context),
    })
  }
  let by_id : Map[String, GitHubComment] = Map([])
  for comment in comments {
    by_id[comment.id] = comment
  }
  let roots : Map[String, String] = Map([])
  for comment in comments {
    let path : Array[String] = []
    let mut current = comment
    let root = for steps = 0; steps <= comments.length(); steps = steps + 1 {
      if roots.get(current.id) is Some(root) {
        break root
      }
      if current.parent == "" {
        break current.id
      }
      path.push(current.id)
      current = match by_id.get(current.parent) {
        Some(parent) => parent
        None =>
          fail(
            "GitHub reply references a missing parent; retain all export pages: " +
            current.parent,
          )
      }
    } nobreak {
      fail("GitHub comment reply cycle")
    }
    roots[current.id] = root
    for id in path {
      roots[id] = root
    }
  }
  { comments, roots, }
}

///|
fn github_thread(
  root : String,
  snapshot : GitHubCommentSnapshot,
) -> Array[GitHubComment] {
  let selected : Array[GitHubComment] = []
  for comment in snapshot.comments {
    if snapshot.roots[comment.id] == root {
      selected.push(comment)
    }
  }
  selected.sort_by((a, b) => {
    if a.id == b.id {
      0
    } else if a.id == root {
      -1
    } else if b.id == root {
      1
    } else {
      let time_order = a.created_at.compare(b.created_at)
      if time_order != 0 {
        time_order
      } else if a.id.length() != b.id.length() {
        a.id.length().compare(b.id.length())
      } else {
        a.id.compare(b.id)
      }
    }
  })
  selected
}

///|
/// List root IDs, authors, paths and complete local thread sizes for selection.
/// Text is JSON-escaped for a safe terminal reading view.
pub fn catalog_github_review_comments(export_bytes : Bytes) -> String raise {
  let snapshot = github_comments(export_bytes)
  let comments = snapshot.comments
  let out = StringBuilder()
  out.write_string(
    "GitHub export SHA-256: " + review_source_digest(export_bytes) + "\n",
  )
  out.write_string(
    "Pull request: " + comments[0].pull_request_url.to_json().stringify() + "\n",
  )
  out.write_string(
    "Local snapshot only; completeness against GitHub is not known.\n",
  )
  for comment in comments {
    if comment.parent == "" {
      let thread = github_thread(comment.id, snapshot)
      out.write_string(
        "\nRoot " +
        comment.id +
        " | comments: \{thread.length()} | path: " +
        comment.path.to_json().stringify() +
        "\n",
      )
      for item in thread {
        out.write_string(
          "  " +
          item.id +
          " | " +
          item.login.to_json().stringify() +
          " | " +
          item.body.to_json().stringify() +
          "\n",
        )
      }
    }
  }
  out.to_string()
}

///|
pub fn parse_github_review_import_plan(
  text : String,
) -> GitHubReviewImportPlan raise {
  let plan : GitHubReviewImportPlan = @json.from_json(@json.parse(text))
  if plan.format != "moonchat.github-review-import.v1" {
    fail("GitHub import plan format must be moonchat.github-review-import.v1")
  }
  plan
}

///|
/// Append selected complete discussion threads to editable agenda data. The
/// root author's mapping supplies the entry author; every reply retains its
/// own explicit mapped attribution inside the body. No receipt is imported.
pub fn import_github_review_comments(
  agenda : ReviewAgenda,
  plan : GitHubReviewImportPlan,
  export_bytes : Bytes,
  source_bytes : Bytes,
) -> ReviewAgenda raise {
  if plan.format != "moonchat.github-review-import.v1" {
    fail("GitHub import plan format must be moonchat.github-review-import.v1")
  }
  if !safe_artifact_ref(plan.export_ref) {
    fail("export_ref must be a workspace-relative artifact reference")
  }
  if plan.export_digest != review_source_digest(export_bytes) {
    fail("GitHub export bytes do not match the import plan digest")
  }
  if plan.export_ref == agenda.source_artifact_ref &&
    plan.export_digest != review_source_digest(source_bytes) {
    fail(
      "GitHub export and review source cannot assign different bytes to one reference",
    )
  }
  if plan.threads.is_empty() || plan.threads.length() > 100 {
    fail("GitHub import plan must select 1–100 threads")
  }
  let snapshot = github_comments(export_bytes)
  let comments = snapshot.comments
  let authors : Map[String, String] = Map([])
  for author in plan.authors {
    if !non_empty(author.login) || authors.contains(author.login) {
      fail("GitHub author logins must be nonempty and unique")
    }
    if participant(agenda.participants, author.participant_id) is None {
      fail(
        "unknown MoonChat participant in GitHub author mapping: " +
        author.participant_id,
      )
    }
    authors[author.login] = author.participant_id
  }
  let selected_roots : Map[String, Bool] = Map([])
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  for selection in plan.threads {
    if selected_roots.contains(selection.root_comment_id) {
      fail(
        "GitHub thread selected more than once: " + selection.root_comment_id,
      )
    }
    selected_roots[selection.root_comment_id] = true
    let root = match
      comments
      .iter()
      .find_first(comment => {
        comment.id == selection.root_comment_id && comment.parent == ""
      }) {
      Some(root) => root
      None =>
        fail(
          "selected root_comment_id is not an exported thread root: " +
          selection.root_comment_id,
        )
    }
    if !non_empty(selection.note) {
      fail("each imported GitHub thread requires an operator note")
    }
    let body = StringBuilder()
    body.write_string(
      "Operator note:\n" +
      selection.note +
      "\n\nImported GitHub review thread (local snapshot, not a decision receipt)\n",
    )
    body.write_string(
      "Export: " +
      plan.export_ref +
      "\nExport SHA-256: " +
      plan.export_digest +
      "\nThread root: " +
      root.id +
      "\n",
    )
    for comment in github_thread(root.id, snapshot) {
      let author = match authors.get(comment.login) {
        Some(author) => author
        None =>
          fail(
            "missing explicit participant mapping for GitHub login: " +
            comment.login,
          )
      }
      body.write_string(
        "\nComment " +
        comment.id +
        "\nGitHub login: " +
        comment.login.to_json().stringify() +
        "\nMapped participant: " +
        author.to_json().stringify() +
        "\nContext: " +
        comment.context.stringify(indent=2) +
        "\nBody (verbatim):\n" +
        comment.body +
        "\n",
      )
    }
    items.push({
      key: selection.key,
      kind: selection.kind,
      author: authors[root.login],
      body: body.to_string(),
      evidence_refs: [plan.export_ref],
      decisions: selection.decisions.copy(),
    })
  }
  let imported = { ..agenda, participants: agenda.participants.copy(), items, }
  compile_review_agenda(imported, source_bytes) |> ignore
  imported
}
