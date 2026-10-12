///|
/// Optional reading annotations for one exact source, separate from the review
/// contract. Entry associations are supplied by the reader, not inferred.
pub(all) struct ReviewSourceLocations {
  format : String
  review_id : String
  source_digest : String
  locations : Array[ReviewSourceLocation]
} derive(Eq, ToJson, @json.FromJson)

///|
/// One-based inclusive HTML display lines. Quote is the complete selected
/// display text joined with LF, without an added final newline.
pub(all) struct ReviewSourceLocation {
  entry_id : String
  start_line : Int
  end_line : Int
  quote : String
} derive(Eq, ToJson, @json.FromJson)

///|
pub fn parse_review_source_locations(
  text : String,
) -> ReviewSourceLocations raise {
  let locations : ReviewSourceLocations = @json.from_json(@json.parse(text))
  if locations.format != "moonchat.review-source-locations.v1" {
    fail("location format must be moonchat.review-source-locations.v1")
  }
  locations
}

///|
priv struct SourceLocationIndex {
  locations : Array[ReviewSourceLocation]
  by_entry : Map[String, Array[Int]]
  by_line : Map[Int, Array[Int]]
}

///|
fn index_source_locations(
  bundle : ConversationReviewBundle,
  lines : Array[String],
  locations : ReviewSourceLocations,
) -> SourceLocationIndex raise {
  if locations.format != "moonchat.review-source-locations.v1" {
    fail("location format must be moonchat.review-source-locations.v1")
  }
  if locations.review_id != bundle.review_id {
    fail("locations do not match the supplied review ID")
  }
  if locations.source_digest != bundle.source_digest {
    fail("locations do not match the exact source digest")
  }
  if locations.locations.length() > 1000 {
    fail("source locations exceed the 1000 range limit")
  }
  let by_entry : Map[String, Array[Int]] = {}
  let by_line : Map[Int, Array[Int]] = {}
  let seen : Map[(String, Int, Int), Bool] = {}
  let mut selected_lines = 0
  let mut quote_units = 0
  for index, location in locations.locations {
    if !bundle.entries.any(entry => entry.entry_id == location.entry_id) {
      fail("location \{index + 1} names an unknown review entry")
    }
    if location.start_line < 1 ||
      location.end_line < location.start_line ||
      location.end_line > lines.length() {
      fail("location \{index + 1} has an invalid inclusive display-line range")
    }
    let key = (location.entry_id, location.start_line, location.end_line)
    if seen.contains(key) {
      fail("location \{index + 1} duplicates an entry and range")
    }
    seen[key] = true
    selected_lines += location.end_line - location.start_line + 1
    // UTF-16 units are inexpensive to count and bound repeated display output.
    if location.quote.length() > 1048576 - quote_units {
      fail("source location quotes exceed the 1048576 UTF-16 code-unit limit")
    }
    quote_units += location.quote.length()
    if selected_lines > 10000 {
      fail("source locations exceed the 10000 selected-line limit")
    }
    let expected = lines[location.start_line - 1:location.end_line]
      .to_owned()
      .join("\n")
    if location.quote != expected {
      fail(
        "location \{index + 1} quote does not match the selected source lines",
      )
    }
    match by_entry.get(location.entry_id) {
      Some(indices) => indices.push(index)
      None => by_entry[location.entry_id] = [index]
    }
    for line = location.start_line; line <= location.end_line; line = line + 1 {
      match by_line.get(line) {
        Some(indices) => indices.push(index)
        None => by_line[line] = [index]
      }
    }
  }
  { locations: locations.locations, by_entry, by_line, }
}

///|
fn review_html_entry_locations(
  out : StringBuilder,
  entry_id : String,
  locations : SourceLocationIndex,
) -> Unit {
  match locations.by_entry.get(entry_id) {
    None =>
      out.write_string(
        "<p>No source location supplied for this entry. Its full discussion and decisions are retained.</p>\n",
      )
    Some(indices) => {
      out.write_string(
        "<section aria-label=\"Linked source excerpts\"><h4>Linked source excerpts</h4>\n",
      )
      for index in indices {
        let location = locations.locations[index]
        out.write_string(
          "<div id=\"location-\{index + 1}\"><p><a href=\"#source-line-\{location.start_line}\">Read source lines \{location.start_line}–\{location.end_line}</a></p><pre style=\"white-space:pre-wrap;overflow-wrap:anywhere;tab-size:4\"><code>",
        )
        out.write_string(review_html_escape(location.quote))
        out.write_string("</code></pre></div>\n")
      }
      out.write_string("</section>\n")
    }
  }
}

///|
fn review_html_line_locations(
  out : StringBuilder,
  bundle : ConversationReviewBundle,
  line : Int,
  locations : SourceLocationIndex,
) -> Unit {
  match locations.by_line.get(line) {
    None => ()
    Some(indices) => {
      out.write_string(
        "<nav aria-label=\"Discussion for source line \{line}\" style=\"grid-column:2;font:0.85rem/1.5 system-ui,sans-serif\">Linked discussion: ",
      )
      for order, index in indices {
        if order > 0 {
          out.write_string(" · ")
        }
        let location = locations.locations[index]
        let kind = entry(bundle.entries, location.entry_id).unwrap().entry_kind
        out.write_string(
          "<a href=\"#location-\{index + 1}\">" +
          review_html_escape(kind + ": " + location.entry_id) +
          "</a>",
        )
      }
      out.write_string("</nav>")
    }
  }
}
