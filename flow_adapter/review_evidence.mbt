///|
fn decode_bundle(value : Json) -> @review.ConversationReviewBundle? {
  Some(@review.decode_review_bundle(value)) catch {
    _ => None
  }
}

///|
async fn find_bundle(
  root : String,
  request : FlowRequest,
) -> (String, @review.ConversationReviewBundle) {
  for reference in request.input_artifacts {
    let parsed = read_json_ref(root, reference) catch { _ => continue }
    match decode_bundle(parsed) {
      Some(bundle) if bundle.contract_id == @review.bundle_contract_id() =>
        return (reference, bundle)
      _ => ()
    }
  }
  fail("MoonChat Flow request has no valid conversation review bundle input")
}

///|
async fn validate_bundle_evidence(
  root : String,
  request : FlowRequest,
  bundle_ref : String,
  bundle : @review.ConversationReviewBundle,
) -> String {
  if !request.input_artifacts.contains(bundle_ref) ||
    !request.input_artifacts.contains(bundle.source_artifact_ref) {
    fail("MoonChat request must carry both bundle and bound source artifact")
  }
  let observed_source_digest = digest_ref(root, bundle.source_artifact_ref)
  let issues = @review.bundle_issues(bundle, observed_source_digest)
  if !issues.is_empty() {
    fail("MoonChat review bundle failed validation: \{issues.join("; ")}")
  }
  if !bundle.previous_bundle_ref.is_empty() {
    if !request.input_artifacts.contains(bundle.previous_bundle_ref) {
      fail("MoonChat previous review bundle must be a declared input artifact")
    }
    if digest_ref(root, bundle.previous_bundle_ref) !=
      bundle.previous_bundle_digest {
      fail("MoonChat previous review bundle digest changed")
    }
  }
  observed_source_digest
}

///|
async fn materialize_journal(
  root : String,
  request : FlowRequest,
  bundle : @review.ConversationReviewBundle,
  observed_source_digest : String,
) -> Array[@review.ReviewEvidence] {
  let evidence : Array[@review.ReviewEvidence] = []
  for event in @review.review_events(bundle, observed_source_digest) {
    let reference = review_event_ref(request, event)
    let text = immutable_json_ref(root, reference, event.to_json())
    evidence.push({ artifact_ref: reference, digest: sha256_text(text) })
  }
  evidence
}

///|
async fn validate_record(
  root : String,
  bundle : @review.ConversationReviewBundle,
  observed_source_digest : String,
  record_ref : String,
) -> (@review.ConversationReviewRecord, String) {
  let text = @fs.read_file(scoped_path(root, record_ref)).text()
  let record = @review.decode_review_record(@json.parse(text))
  if record.review_id != bundle.review_id ||
    record.source_digest != observed_source_digest ||
    record.operation_ref != operation_ref() {
    fail("MoonChat durable review record identity does not match the request")
  }
  for evidence in record.journal_evidence {
    if digest_ref(root, evidence.artifact_ref) != evidence.digest {
      fail(
        "MoonChat append-only review evidence changed: \{evidence.artifact_ref}",
      )
    }
    let event : @review.ConversationReviewEvent = @json.from_json(
      read_json_ref(root, evidence.artifact_ref),
    )
    if event.contract_id != @review.event_contract_id() ||
      event.review_id != bundle.review_id ||
      event.source_digest != observed_source_digest {
      fail("MoonChat review event identity is inconsistent")
    }
  }
  let expected = @review.project_review_record(
    bundle,
    observed_source_digest,
    record.journal_evidence,
  )
  if expected != record {
    fail("MoonChat durable review record is not a deterministic projection")
  }
  (record, sha256_text(text))
}
