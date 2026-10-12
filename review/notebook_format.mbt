///|
priv struct NotebookReviewCell {
  index : Int
  id : String
  kind : String
  source : String
  execution_count : Json
  outputs : Array[Json]
  original : Json
}

///|
priv struct NotebookReviewDocument {
  minor : Int
  metadata : Json
  cells : Array[NotebookReviewCell]
}

///|
fn notebook_object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("Notebook " + label + " must be an object")
  }
}

///|
fn notebook_required(fields : Map[String, Json], key : String) -> Json raise {
  match fields.get(key) {
    Some(value) => value
    None => fail("Notebook requires " + key)
  }
}

///|
fn notebook_string(value : Json, label : String) -> String raise {
  match value {
    String(text) => text
    _ => fail("Notebook " + label + " must be a string")
  }
}

///|
fn notebook_array(value : Json, label : String) -> Array[Json] raise {
  match value {
    Array(values) => values
    _ => fail("Notebook " + label + " must be an array")
  }
}

///|
// Jupyter splits multiline fields into arbitrary fragments, not necessarily
// whole lines. Join without inventing a separator, including for MIME text.
fn notebook_multiline(value : Json, label : String) -> String raise {
  match value {
    String(text) => text
    Array(parts) => parts.map(part => notebook_string(part, label)).join("")
    _ => fail("Notebook " + label + " must be a string or array of strings")
  }
}

///|
fn notebook_index(value : Json, label : String) -> Int raise {
  guard value is Number(number, ..) &&
    number >= 0.0 &&
    number <= 2147483647.0 &&
    number.to_int().to_double() == number else {
    fail("Notebook " + label + " must be a nonnegative 32-bit integer")
  }
  number.to_int()
}

///|
fn notebook_mime(value : Json) -> Map[String, Json] raise {
  let fields = notebook_object(value, "MIME data")
  for name, value in fields {
    if name != "application/json" && !name.has_suffix("+json") {
      notebook_multiline(value, "MIME value") |> ignore
    }
  }
  fields
}

///|
fn notebook_outputs(values : Array[Json]) -> Array[Json] raise {
  let summaries : Array[Json] = []
  for index, raw in values {
    let fields = notebook_object(raw, "output")
    let kind = notebook_string(
      notebook_required(fields, "output_type"),
      "output_type",
    )
    let summary : Map[String, Json] = {
      "output_index": index.to_json(),
      "output_type": kind.to_json(),
    }
    match kind {
      "stream" => {
        let name = notebook_string(
          notebook_required(fields, "name"),
          "stream name",
        )
        if name != "stdout" && name != "stderr" {
          fail("Notebook stream name must be stdout or stderr")
        }
        summary["name"] = name.to_json()
        summary["text"] = notebook_multiline(
          notebook_required(fields, "text"),
          "stream text",
        ).to_json()
      }
      "error" => {
        for key in ["ename", "evalue"] {
          summary[key] = notebook_string(notebook_required(fields, key), key).to_json()
        }
        let frames = notebook_array(
          notebook_required(fields, "traceback"),
          "traceback",
        )
        summary["traceback"] = frames
          .map(frame => notebook_string(frame, "traceback frame"))
          .to_json()
      }
      "display_data" | "execute_result" => {
        notebook_object(
          notebook_required(fields, "metadata"),
          "output metadata",
        )
        |> ignore
        let data = notebook_mime(notebook_required(fields, "data"))
        let types : Array[String] = []
        for name, _ in data {
          types.push(name)
        }
        summary["mime_types"] = types.to_json()
        if data.get("text/plain") is Some(text) {
          summary["text_plain"] = notebook_multiline(text, "text/plain").to_json()
        }
        if kind == "execute_result" {
          summary["execution_count"] = notebook_index(
            notebook_required(fields, "execution_count"),
            "output execution_count",
          ).to_json()
        }
      }
      _ => fail("Notebook has an unsupported output_type")
    }
    summaries.push(Json::object(summary))
  }
  summaries
}

///|
fn notebook_document(bytes : Bytes) -> NotebookReviewDocument raise {
  if bytes.length() > 4194304 {
    fail("Notebook exceeds 4 MiB")
  }
  let fields = notebook_object(
    @json.parse(@utf8.decode(bytes, ignore_bom=true)),
    "document",
  )
  if notebook_index(notebook_required(fields, "nbformat"), "nbformat") != 4 {
    fail("Notebook nbformat must be 4")
  }
  let minor = notebook_index(
    notebook_required(fields, "nbformat_minor"),
    "nbformat_minor",
  )
  if minor > 5 {
    fail("Notebook supports nbformat 4.0 through 4.5")
  }
  let metadata = notebook_required(fields, "metadata")
  notebook_object(metadata, "metadata") |> ignore
  let raw_cells = notebook_array(notebook_required(fields, "cells"), "cells")
  if raw_cells.length() > 1000 {
    fail("Notebook exceeds 1000 cells")
  }
  let cells : Array[NotebookReviewCell] = []
  let ids : Map[String, Bool] = Map([])
  let mut output_count = 0
  for index, raw in raw_cells {
    let cell = notebook_object(raw, "cell")
    let id = match cell.get("id") {
      None if minor < 5 => ""
      None => fail("Notebook 4.5 cell requires id")
      Some(value) => {
        let id = notebook_string(value, "cell id")
        if id.length() == 0 ||
          id.length() > 64 ||
          !id
          .iter()
          .all(c => c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_')) {
          fail("Notebook cell id must be 1–64 ASCII letters, digits, - or _")
        }
        if ids.contains(id) {
          fail("Notebook cell IDs must be unique")
        }
        ids[id] = true
        id
      }
    }
    let kind = notebook_string(
      notebook_required(cell, "cell_type"),
      "cell_type",
    )
    notebook_object(notebook_required(cell, "metadata"), "cell metadata")
    |> ignore
    let source = notebook_multiline(
      notebook_required(cell, "source"),
      "cell source",
    )
    let outputs = match kind {
      "code" => {
        let count = notebook_required(cell, "execution_count")
        if count != Json::null() {
          notebook_index(count, "cell execution_count") |> ignore
        }
        if cell.contains("attachments") {
          fail("Notebook code cell attachments are unsupported")
        }
        let raw_outputs = notebook_array(
          notebook_required(cell, "outputs"),
          "outputs",
        )
        output_count += raw_outputs.length()
        if output_count > 1000 {
          fail("Notebook exceeds 1000 saved outputs")
        }
        notebook_outputs(raw_outputs)
      }
      "markdown" | "raw" => {
        if cell.contains("outputs") || cell.contains("execution_count") {
          fail("Notebook non-code cell cannot carry execution fields")
        }
        if cell.get("attachments") is Some(attachments) {
          for _, data in notebook_object(attachments, "attachments") {
            notebook_mime(data) |> ignore
          }
        }
        []
      }
      _ => fail("Notebook supports code, markdown and raw cells only")
    }
    cells.push({
      index,
      id,
      kind,
      source,
      execution_count: cell.get("execution_count").unwrap_or(Json::null()),
      outputs,
      original: raw,
    })
  }
  { minor, metadata, cells, }
}

///|
fn notebook_cell_summary(cell : NotebookReviewCell) -> Json {
  Json::object({
    "cell_index": cell.index.to_json(),
    "cell_id": cell.id.to_json(),
    "cell_type": cell.kind.to_json(),
    "source": cell.source.to_json(),
    "execution_count": cell.execution_count,
    "saved_outputs": cell.outputs.to_json(),
  })
}

///|
fn notebook_saved_text(outputs : Array[Json]) -> String raise {
  if outputs.is_empty() {
    return "[No saved outputs]\n"
  }
  let out = StringBuilder()
  for index, output in outputs {
    let fields = notebook_object(output, "decoded output")
    out.write_string(
      "Output \{index}: " +
      notebook_required(fields, "output_type").stringify() +
      "\n",
    )
    if fields.get("name") is Some(name) {
      out.write_string("Stream: " + name.stringify() + "\n")
    }
    if fields.get("mime_types") is Some(types) {
      out.write_string("MIME types: " + types.stringify() + "\n")
    }
    match
      (fields.get("text"), fields.get("text_plain"), fields.get("traceback")) {
      (Some(String(text)), _, _) | (_, Some(String(text)), _) =>
        out.write_string(text + "\n")
      (_, _, Some(Array(frames))) => {
        out.write_string(
          "Error: " + notebook_required(fields, "ename").stringify() + "\n",
        )
        out.write_string(
          notebook_string(notebook_required(fields, "evalue"), "evalue") + "\n",
        )
        out.write_string(
          frames
          .map(frame => notebook_string(frame, "traceback frame"))
          .join("\n") +
          "\n",
        )
      }
      _ =>
        out.write_string(
          "[No text/plain representation; rich data retained in original cell JSON]\n",
        )
    }
  }
  out.to_string()
}
