///|
/// A local three-way refresh report. Left values are the current edited agenda;
/// right values are regenerated from the newer snapshot. Conflicts suppress the
/// entire candidate agenda; snapshot references remain ordinary provenance.
pub(all) struct GitHubReviewRefresh {
  format : String
  review_id : String
  source_digest : String
  previous_export_ref : String
  previous_export_digest : String
  next_export_ref : String
  next_export_digest : String
  added_comment_ids : Array[String]
  changed_comment_ids : Array[String]
  conflicts : Array[ReviewSheetConflict]
  merged_agenda : ReviewAgenda?
} derive(Eq)

///|
pub impl ToJson for GitHubReviewRefresh with fn to_json(
  self : GitHubReviewRefresh,
) -> Json {
  {
    "format": self.format.to_json(),
    "review_id": self.review_id.to_json(),
    "source_digest": self.source_digest.to_json(),
    "previous_export_ref": self.previous_export_ref.to_json(),
    "previous_export_digest": self.previous_export_digest.to_json(),
    "next_export_ref": self.next_export_ref.to_json(),
    "next_export_digest": self.next_export_digest.to_json(),
    "added_comment_ids": self.added_comment_ids.to_json(),
    "changed_comment_ids": self.changed_comment_ids.to_json(),
    "conflicts": self.conflicts.to_json(),
    "merged_agenda": sheet_merge_optional_json(self.merged_agenda),
  }
}

///|
/// Refresh previously selected GitHub threads without overwriting independent
/// local agenda edits. Keep the original plan and snapshot as the common base;
/// use a new retained reference for changed snapshot bytes. Thread selections
/// stay fixed, while explicit mappings may be added for new reply authors.
/// Missing old selected comments are rejected because an incomplete export is
/// not evidence that dissent was deleted. This never creates decision receipts.
pub fn refresh_github_review_comments(
  current : ReviewAgenda,
  previous_plan : GitHubReviewImportPlan,
  previous_export : Bytes,
  next_plan : GitHubReviewImportPlan,
  next_export : Bytes,
  source_bytes : Bytes,
) -> GitHubReviewRefresh raise {
  compile_review_agenda(current, source_bytes) |> ignore
  if previous_plan.threads != next_plan.threads {
    fail(
      "refresh must retain the original thread selections, keys, notes and requests; edit the agenda instead",
    )
  }
  if previous_plan.export_ref == next_plan.export_ref &&
    previous_export != next_export {
    fail("changed GitHub snapshot bytes need a distinct retained export_ref")
  }
  for author in previous_plan.authors {
    if !next_plan.authors.contains(author) {
      fail(
        "refresh must retain previous explicit author mappings; add mappings for new authors",
      )
    }
  }
  let previous = github_comments(previous_export)
  let next = github_comments(next_export)
  if previous.comments[0].pull_request_url != next.comments[0].pull_request_url {
    fail("refresh snapshots must describe the same pull request")
  }
  let next_by_id = Map::from_array(next.comments.map(c => (c.id, c)))
  let previous_by_id = Map::from_array(previous.comments.map(c => (c.id, c)))
  let added : Array[String] = []
  let changed : Array[String] = []
  for selection in previous_plan.threads {
    for comment in github_thread(selection.root_comment_id, previous) {
      let updated = match next_by_id.get(comment.id) {
        Some(value) => value
        None =>
          fail(
            "new GitHub snapshot omits previously selected comment " +
            comment.id +
            "; retain all export pages or resolve outside refresh",
          )
      }
      if next.roots[comment.id] != selection.root_comment_id {
        fail(
          "a previously selected comment moved to a different thread: " +
          comment.id,
        )
      }
      if updated != comment {
        changed.push(comment.id)
      }
    }
    for comment in github_thread(selection.root_comment_id, next) {
      if !previous_by_id.contains(comment.id) {
        added.push(comment.id)
      } else if previous.roots[comment.id] != selection.root_comment_id {
        fail("an existing comment moved into a selected thread: " + comment.id)
      }
    }
  }
  // Reconstruct only imported items from the retained recipe. Unrelated local
  // items and all current scope/participant metadata pass through unchanged.
  let selected_keys = previous_plan.threads.map(t => t.key)
  let seed = {
    ..current,
    items: current.items.filter(item => !selected_keys.contains(item.key)),
  }
  let base = import_github_review_comments(
    seed, previous_plan, previous_export, source_bytes,
  )
  let updated = import_github_review_comments(
    seed, next_plan, next_export, source_bytes,
  )
  let result = merge_agenda_items(base, current, updated, source_bytes)
  {
    format: "moonchat.github-review-refresh.v1",
    review_id: current.review_id,
    source_digest: review_source_digest(source_bytes),
    previous_export_ref: previous_plan.export_ref,
    previous_export_digest: previous_plan.export_digest,
    next_export_ref: next_plan.export_ref,
    next_export_digest: next_plan.export_digest,
    added_comment_ids: added,
    changed_comment_ids: changed,
    conflicts: result.conflicts,
    merged_agenda: result.merged_agenda,
  }
}
