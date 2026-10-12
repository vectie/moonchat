///|
/// Select cells from one exact notebook snapshot. Cell indexes are zero-based.
pub(all) struct NotebookReviewImportPlan {
  format : String
  notebook_digest : String
  cells : Array[NotebookReviewSelection]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct NotebookReviewSelection {
  cell_index : Int
  key : String
  kind : String
  author : String
  note : String
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
/// A static JSON reading catalog. Rich MIME payloads stay in the original file;
/// text/plain, stream and error content are exposed as escaped data, never run.
pub fn catalog_notebook_review(notebook_bytes : Bytes) -> String raise {
  let document = notebook_document(notebook_bytes)
  Json::object({
    "format": "moonchat.notebook-catalog.v1".to_json(),
    "notebook_digest": review_source_digest(notebook_bytes).to_json(),
    "nbformat": (4).to_json(),
    "nbformat_minor": document.minor.to_json(),
    "notice": "Static saved evidence only. Outputs may be stale; nothing was executed or rendered.".to_json(),
    "metadata": document.metadata,
    "cells": document.cells.map(notebook_cell_summary).to_json(),
  }).stringify(indent=2)
}

///|
pub fn parse_notebook_review_import_plan(
  text : String,
) -> NotebookReviewImportPlan raise {
  let raw = @json.parse(text)
  let fields = notebook_object(raw, "selection plan")
  for
    selection in notebook_array(
      notebook_required(fields, "cells"),
      "selected cells",
    ) {
    let fields = notebook_object(selection, "selection")
    notebook_index(notebook_required(fields, "cell_index"), "cell_index")
    |> ignore
  }
  let plan : NotebookReviewImportPlan = @json.from_json(raw)
  if plan.format != "moonchat.review-notebook.v1" {
    fail("Notebook plan format must be moonchat.review-notebook.v1")
  }
  plan
}

///|
/// Append selected cells to an ordinary editable agenda, bound to the original
/// notebook bytes. Saved output, metadata and kernel names are evidence only.
pub fn import_notebook_review(
  agenda : ReviewAgenda,
  plan : NotebookReviewImportPlan,
  notebook_bytes : Bytes,
) -> ReviewAgenda raise {
  if plan.format != "moonchat.review-notebook.v1" {
    fail("Notebook plan format must be moonchat.review-notebook.v1")
  }
  if plan.notebook_digest != review_source_digest(notebook_bytes) {
    fail("Notebook bytes do not match the selected notebook digest")
  }
  if plan.cells.is_empty() || plan.cells.length() > 100 {
    fail("Notebook plan must select 1–100 cells")
  }
  let document = notebook_document(notebook_bytes)
  let items = agenda.items.map(item => {
    ..item,
    evidence_refs: item.evidence_refs.copy(),
    decisions: item.decisions.copy(),
  })
  let selected : Map[Int, Bool] = Map([])
  let mut body_bytes = 0
  for selection in plan.cells {
    if selected.contains(selection.cell_index) {
      fail("Notebook cell selected more than once")
    }
    selected[selection.cell_index] = true
    guard document.cells.get(selection.cell_index) is Some(cell) else {
      fail("Notebook selected cell_index is outside this snapshot")
    }
    if !non_empty(selection.note) {
      fail("Notebook selection requires an operator note")
    }
    let evidence = Json::object({
      "notebook_ref": agenda.source_artifact_ref.to_json(),
      "notebook_digest": plan.notebook_digest.to_json(),
      "cell_pointer": "/cells/\{cell.index}".to_json(),
      "nbformat": (4).to_json(),
      "nbformat_minor": document.minor.to_json(),
      "notebook_metadata": document.metadata,
      "decoded_cell": notebook_cell_summary(cell),
      "original_cell": cell.original,
    })
    let body = "Operator note:\n" +
      selection.note +
      "\n\nDecoded cell source (literal text):\n" +
      cell.source +
      "\n\nSaved outputs (not rerun; may be stale):\n" +
      notebook_saved_text(cell.outputs) +
      "\n\nNotebook cell evidence (static saved content; not executed, rendered or verified as current):\n" +
      evidence.stringify(indent=2)
    body_bytes += @utf8.encode(body).length()
    if body_bytes > 16777216 {
      fail("Notebook imported bodies exceed 16 MiB")
    }
    items.push({
      key: selection.key,
      kind: selection.kind,
      author: selection.author,
      body,
      evidence_refs: [agenda.source_artifact_ref],
      decisions: selection.decisions.copy(),
    })
  }
  let imported = { ..agenda, participants: agenda.participants.copy(), items, }
  compile_review_agenda(imported, notebook_bytes) |> ignore
  imported
}
