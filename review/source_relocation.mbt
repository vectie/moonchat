///|
/// A complete display-line match. Reports retain the first 20 candidates per
/// original range; candidate_count always counts all matches, including overlaps.
pub(all) struct ReviewLocationCandidate {
  start_line : Int
  end_line : Int
} derive(Eq, ToJson)

///|
/// A reader association is carried only when its entry is unchanged and its
/// exact quote has one unambiguous destination, with no collapsed old ranges.
pub(all) struct ReviewLocationRelocation {
  original : ReviewSourceLocation
  status : String
  candidate_count : Int
  candidates : Array[ReviewLocationCandidate]
} derive(Eq, ToJson)

///|
pub(all) struct ReviewSourceRelocation {
  format : String
  source_artifact_ref : String
  previous_review_id : String
  previous_source_revision_id : String
  previous_source_digest : String
  next_review_id : String
  next_source_revision_id : String
  next_source_digest : String
  mapped_count : Int
  unresolved_count : Int
  results : Array[ReviewLocationRelocation]
  suggested_locations : ReviewSourceLocations
} derive(Eq, ToJson)

///|
/// KMP over whole display lines avoids a repeated-prefix quadratic scan. Every
/// match is counted, but only the first 20 line ranges are retained for display.
fn relocation_candidates(
  lines : Array[String],
  quote_lines : Array[String],
) -> (Int, Array[ReviewLocationCandidate]) {
  let prefix = Array::make(quote_lines.length(), 0)
  let mut matched = 0
  for i = 1; i < quote_lines.length(); i = i + 1 {
    while matched > 0 && quote_lines[i] != quote_lines[matched] {
      matched = prefix[matched - 1]
    }
    if quote_lines[i] == quote_lines[matched] {
      matched += 1
    }
    prefix[i] = matched
  }
  matched = 0
  let mut count = 0
  let candidates = []
  for i, line in lines {
    while matched > 0 && line != quote_lines[matched] {
      matched = prefix[matched - 1]
    }
    if line == quote_lines[matched] {
      matched += 1
    }
    if matched == quote_lines.length() {
      count += 1
      if candidates.length() < 20 {
        candidates.push({
          start_line: i - quote_lines.length() + 2,
          end_line: i + 1,
        })
      }
      matched = prefix[matched - 1]
    }
  }
  (count, candidates)
}

///|
/// Carry reader-authored source links to a verified related snapshot. This does
/// not infer semantic relevance, validate journal ancestry, edit discussion or
/// copy receipts. Unresolved associations remain in the report, not the map.
pub fn relocate_review_source_locations(
  previous : ConversationReviewBundle,
  previous_source : Bytes,
  locations : ReviewSourceLocations,
  next : ConversationReviewBundle,
  next_source : Bytes,
) -> ReviewSourceRelocation raise {
  ignore(
    project_review_record(previous, review_source_digest(previous_source), []),
  )
  ignore(project_review_record(next, review_source_digest(next_source), []))
  if previous.source_artifact_ref != next.source_artifact_ref ||
    previous.conversation != next.conversation {
    fail(
      "source relocation requires the same source artifact reference and conversation binding",
    )
  }
  let old_lines = review_html_source_lines(previous_source)
  let next_lines = review_html_source_lines(next_source)
  ignore(index_source_locations(previous, old_lines, locations))
  let preliminary = []
  let destinations : Map[(String, Int, Int), Int] = {}
  for original in locations.locations {
    let quote_lines = old_lines[original.start_line - 1:original.end_line].to_owned()
    let (candidate_count, candidates) = relocation_candidates(
      next_lines, quote_lines,
    )
    let status = match entry(next.entries, original.entry_id) {
      None => "entry-removed"
      Some(found) =>
        if found != entry(previous.entries, original.entry_id).unwrap() {
          "entry-changed"
        } else if candidate_count == 0 {
          "quote-not-found"
        } else if candidate_count > 1 {
          "ambiguous"
        } else {
          "relocated"
        }
    }
    if status == "relocated" {
      let candidate = candidates[0]
      let key = (original.entry_id, candidate.start_line, candidate.end_line)
      destinations[key] = destinations.get(key).unwrap_or(0) + 1
    }
    preliminary.push({ original, status, candidate_count, candidates, })
  }
  let results = []
  let mapped = []
  for result in preliminary {
    if result.status == "relocated" {
      let candidate = result.candidates[0]
      let key = (
        result.original.entry_id,
        candidate.start_line,
        candidate.end_line,
      )
      if destinations[key] > 1 {
        results.push({ ..result, status: "range-collision", })
        continue
      }
      mapped.push({
        entry_id: result.original.entry_id,
        start_line: candidate.start_line,
        end_line: candidate.end_line,
        quote: result.original.quote,
      })
    }
    results.push(result)
  }
  let suggested_locations : ReviewSourceLocations = {
    format: "moonchat.review-source-locations.v1",
    review_id: next.review_id,
    source_digest: next.source_digest,
    locations: mapped,
  }
  // Same validator as the final HTML consumer, including duplicate/size checks.
  ignore(index_source_locations(next, next_lines, suggested_locations))
  {
    format: "moonchat.review-source-relocation.v1",
    source_artifact_ref: next.source_artifact_ref,
    previous_review_id: previous.review_id,
    previous_source_revision_id: previous.source_revision_id,
    previous_source_digest: previous.source_digest,
    next_review_id: next.review_id,
    next_source_revision_id: next.source_revision_id,
    next_source_digest: next.source_digest,
    mapped_count: mapped.length(),
    unresolved_count: results.length() - mapped.length(),
    results,
    suggested_locations,
  }
}

///|
/// Format the complete relocation result as a reading aid. The report and map
/// are navigation suggestions; neither changes the source-bound review evidence.
pub fn ReviewSourceRelocation::to_markdown(
  self : ReviewSourceRelocation,
) -> String {
  let out = StringBuilder()
  out.write_string("# Review source-link relocation\n\n")
  review_markdown_field(out, "Source artifact", self.source_artifact_ref)
  review_markdown_field(
    out,
    "Previous review / revision",
    self.previous_review_id + " / " + self.previous_source_revision_id,
  )
  review_markdown_field(
    out,
    "Previous source SHA-256",
    self.previous_source_digest,
  )
  review_markdown_field(
    out,
    "Next review / revision",
    self.next_review_id + " / " + self.next_source_revision_id,
  )
  review_markdown_field(out, "Next source SHA-256", self.next_source_digest)
  out.write_string(
    "\{self.mapped_count} ranges mapped; \{self.unresolved_count} unresolved.\n\n",
  )
  out.write_string(
    "Only unchanged entry records with one exact display-line match are carried forward. Inspect context before using these reader-authored associations. Unresolved ranges are omitted from the suggested map; all next-review discussion stays visible in the complete packet. Keep the original review, source and location map. No decisions, receipts or journal ancestry are inferred.\n\n",
  )
  for i, result in self.results {
    out.write_string("## Range \{i + 1}: \{result.status}\n\n")
    review_markdown_field(out, "Entry ID", result.original.entry_id)
    out.write_string(
      "Previous lines: \{result.original.start_line}–\{result.original.end_line}.\n\n",
    )
    review_markdown_field(out, "Original exact quote", result.original.quote)
    out.write_string("\{result.candidate_count} exact matches in next source")
    if result.candidate_count > result.candidates.length() {
      out.write_string("; first \{result.candidates.length()} shown")
    }
    out.write_string(".\n\n")
    for candidate in result.candidates {
      out.write_string(
        "- Next lines \{candidate.start_line}–\{candidate.end_line}\n",
      )
    }
    out.write_string("\n")
  }
  out.to_string()
}
