///|
async fn validate_durable_receipt(
  root : String,
  request : FlowRequest,
  bundle : @review.ConversationReviewBundle,
  observed_source_digest : String,
  receipt : Json,
) -> (@review.ConversationReviewRecord, String, String) {
  let fields = json_object(receipt, "durable receipt")
  if json_string_field(fields, "contract_id") !=
    "moonchat.review-native-receipt.v1" ||
    json_string_field(fields, "operation_ref") != operation_ref() ||
    json_string_field(fields, "idempotency_key") != request.idempotency_key ||
    json_string_field(fields, "input_digest") != request.input_digest ||
    json_string_field(fields, "review_id") != bundle.review_id {
    fail("MoonChat idempotency receipt belongs to a different input")
  }
  let record_ref = json_string_field(fields, "record_ref")
  let (record, digest) = validate_record(
    root, bundle, observed_source_digest, record_ref,
  )
  if json_string_field(fields, "record_digest") != digest {
    fail("MoonChat idempotency receipt record digest changed")
  }
  (record, record_ref, digest)
}

///|
fn result_status(
  record : @review.ConversationReviewRecord,
  required_claim : String,
) -> (String, String) {
  if required_claim == "accepted-knowledge" && !record.accepted {
    let kind = if record.review_status == "rejected" {
      "named-human-review-rejected"
    } else {
      "named-human-decisions-incomplete"
    }
    ("failed", kind)
  } else {
    ("succeeded", "")
  }
}

///|
async fn adapter_result(
  root : String,
  request : FlowRequest,
  record : @review.ConversationReviewRecord,
  record_ref : String,
  record_digest : String,
  result_ref : String,
) -> Json {
  let (status, error_kind) = result_status(record, request.required_claim)
  let result : Json = {
    "result_id": "result-\{request.attempt_id}-\{status}",
    "request_id": request.request_id,
    "attempt_id": request.attempt_id,
    "idempotency_key": request.idempotency_key,
    "input_digest": request.input_digest,
    "product_id": "moonchat",
    "external_job_id": "moonchat-review-\{record.review_id}",
    "status": status,
    "output_digest": record_digest,
    "output_artifacts": [record_ref],
    "error_kind": error_kind,
    "compensable": false,
    "recorded_at": request.created_at,
    "actual_claim": record.claim_class,
    "review_status": record.review_status,
  }
  ignore(immutable_json_ref(root, result_ref, result))
  result
}

///|
async fn validate_existing_result(
  root : String,
  request : FlowRequest,
  bundle : @review.ConversationReviewBundle,
  observed_source_digest : String,
  result : Json,
) -> Unit {
  let fields = json_object(result, "adapter result")
  if json_string_field(fields, "request_id") != request.request_id ||
    json_string_field(fields, "attempt_id") != request.attempt_id ||
    json_string_field(fields, "idempotency_key") != request.idempotency_key ||
    json_string_field(fields, "input_digest") != request.input_digest ||
    json_string_field(fields, "product_id") != "moonchat" {
    fail("MoonChat adapter result belongs to a different request")
  }
  guard fields.get("output_artifacts") is Some(Array([String(record_ref)])) else {
    fail("MoonChat adapter result must name exactly one review record")
  }
  if digest_ref(root, record_ref) != json_string_field(fields, "output_digest") {
    fail("MoonChat adapter result output digest changed")
  }
  ignore(validate_record(root, bundle, observed_source_digest, record_ref))
}

///|
async fn execute_or_resume(
  workspace : String,
  request_ref : String,
  result_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let request = decode_flow_request(read_json_ref(root, request_ref))
  if declared_input_digest(root, request.input_artifacts) !=
    request.input_digest {
    fail("MoonChat Flow request input digest does not match its artifacts")
  }
  let (bundle_ref, bundle) = find_bundle(root, request)
  let observed_source_digest = validate_bundle_evidence(
    root, request, bundle_ref, bundle,
  )
  match read_optional_json_ref(root, result_ref) {
    Some(result) => {
      validate_existing_result(
        root, request, bundle, observed_source_digest, result,
      )
      return result
    }
    None => ()
  }
  match read_optional_json_ref(root, durable_receipt_ref(request)) {
    Some(receipt) => {
      let (record, record_ref, record_digest) = validate_durable_receipt(
        root, request, bundle, observed_source_digest, receipt,
      )
      return adapter_result(
        root, request, record, record_ref, record_digest, result_ref,
      )
    }
    None => ()
  }
  let journal = materialize_journal(
    root, request, bundle, observed_source_digest,
  )
  let record = @review.project_review_record(
    bundle, observed_source_digest, journal,
  )
  let record_ref = review_record_ref(request, bundle.review_id)
  let record_text = immutable_json_ref(root, record_ref, record.to_json())
  let record_digest = sha256_text(record_text)
  let receipt : Json = {
    "contract_id": "moonchat.review-native-receipt.v1",
    "operation_ref": operation_ref(),
    "idempotency_key": request.idempotency_key,
    "input_digest": request.input_digest,
    "review_id": bundle.review_id,
    "source_digest": observed_source_digest,
    "record_ref": record_ref,
    "record_digest": record_digest,
    "review_status": record.review_status,
    "actual_claim": record.claim_class,
    "recorded_at": request.created_at,
  }
  ignore(immutable_json_ref(root, durable_receipt_ref(request), receipt))
  adapter_result(root, request, record, record_ref, record_digest, result_ref)
}

///|
pub async fn execute(
  workspace : String,
  request_ref : String,
  result_ref : String,
) -> Json {
  execute_or_resume(workspace, request_ref, result_ref)
}

///|
pub async fn reconcile(
  workspace : String,
  request_ref : String,
  result_ref : String,
) -> Json {
  // Every MoonChat effect is a content-addressed, create-new workspace write.
  // Replaying the projection therefore completes an interrupted attempt without
  // duplicating an external or physical effect.
  execute_or_resume(workspace, request_ref, result_ref)
}
