///|
pub fn pack_version() -> String {
  "0.1.0"
}

///|
pub fn adapter_id() -> String {
  "moonchat-review-v1"
}

///|
pub fn operation_ref() -> String {
  @review.operation_ref()
}

///|
pub fn input_schema_ref() -> String {
  @review.input_schema_ref()
}

///|
pub fn output_schema_ref() -> String {
  @review.output_schema_ref()
}

///|
pub fn capability_json(healthy? : Bool = false) -> Json {
  {
    "adapter_id": adapter_id(),
    "product_id": "moonchat",
    "protocol": "moonflow.adapter.v2",
    "operations": [operation_ref()],
    "authority_classes": ["workspace-mutation"],
    "input_contracts": [input_schema_ref()],
    "output_contracts": [output_schema_ref()],
    "claim_ceiling": "accepted-knowledge",
    "healthy": healthy,
    "supports_cancel": false,
    "supports_reconcile": true,
  }
}

///|
struct FlowRequest {
  request_id : String
  run_id : String
  book_id : String
  work_item_id : String
  declaration_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  operation : String
  requested_authority : String
  acceptance_criteria : Array[String]
  input_contracts : Array[String]
  output_contracts : Array[String]
  required_claim : String
  input_digest : String
  input_artifacts : Array[String]
  timeout_ms : Int
  created_at : String
} derive(Debug, Eq)

///|
fn json_object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("MoonChat Flow adapter requires \{label} to be an object")
  }
}

///|
fn json_string_field(
  fields : Map[String, Json],
  name : String,
  allow_empty? : Bool = false,
) -> String raise {
  match fields.get(name) {
    Some(String(value)) if allow_empty || !value.trim().is_empty() => value
    _ => fail("MoonChat Flow adapter requires \{name}")
  }
}

///|
fn json_int_field(fields : Map[String, Json], name : String) -> Int raise {
  match fields.get(name) {
    Some(Number(value, ..)) => value.to_int()
    _ => fail("MoonChat Flow adapter requires integer \{name}")
  }
}

///|
fn json_strings_field(
  fields : Map[String, Json],
  name : String,
  required? : Bool = true,
) -> Array[String] raise {
  match fields.get(name) {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(text) if !text.trim().is_empty() => text
          _ =>
            fail("MoonChat Flow adapter requires non-empty strings in \{name}")
        }
      })
    None if !required => []
    _ => fail("MoonChat Flow adapter requires array \{name}")
  }
}

///|
fn safe_path_segment(value : String) -> Bool {
  if value.trim().is_empty() || value == "." || value == ".." {
    return false
  }
  for ch in value {
    if !((ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.') {
      return false
    }
  }
  true
}

///|
fn decode_flow_request(value : Json) -> FlowRequest raise {
  let fields = json_object(value, "request")
  let request = {
    request_id: json_string_field(fields, "request_id"),
    run_id: json_string_field(fields, "run_id"),
    book_id: json_string_field(fields, "book_id"),
    work_item_id: json_string_field(fields, "work_item_id"),
    declaration_id: json_string_field(fields, "declaration_id"),
    attempt_id: json_string_field(fields, "attempt_id"),
    idempotency_key: json_string_field(fields, "idempotency_key"),
    product_id: json_string_field(fields, "product_id"),
    operation: json_string_field(fields, "operation"),
    requested_authority: json_string_field(fields, "requested_authority"),
    acceptance_criteria: json_strings_field(
      fields,
      "acceptance_criteria",
      required=false,
    ),
    input_contracts: json_strings_field(
      fields,
      "input_contracts",
      required=false,
    ),
    output_contracts: json_strings_field(
      fields,
      "output_contracts",
      required=false,
    ),
    required_claim: json_string_field(
      fields,
      "required_claim",
      allow_empty=true,
    ),
    input_digest: json_string_field(fields, "input_digest"),
    input_artifacts: json_strings_field(
      fields,
      "input_artifacts",
      required=false,
    ),
    timeout_ms: json_int_field(fields, "timeout_ms"),
    created_at: json_string_field(fields, "created_at"),
  }
  validate_flow_request(request)
  request
}

///|
fn validate_flow_request(request : FlowRequest) -> Unit raise {
  if request.product_id != "moonchat" || request.operation != operation_ref() {
    fail("MoonChat owns only the versioned operation `\{operation_ref()}`")
  }
  if request.requested_authority != "workspace-mutation" {
    fail("MoonChat review recording requires workspace-mutation authority")
  }
  if request.input_contracts != [input_schema_ref()] ||
    request.output_contracts != [output_schema_ref()] {
    fail("MoonChat Flow request schema identities do not match the pack")
  }
  if !["research-evidence", "accepted-knowledge"].contains(
      request.required_claim,
    ) {
    fail(
      "MoonChat review requests may require research-evidence or accepted-knowledge",
    )
  }
  for
    identity in [
      request.request_id,
      request.run_id,
      request.book_id,
      request.work_item_id,
      request.declaration_id,
      request.attempt_id,
      request.idempotency_key,
    ] {
    if !safe_path_segment(identity) {
      fail("MoonChat Flow identities must be safe path segments")
    }
  }
  if !request.input_digest.has_prefix("sha256:") ||
    request.input_digest.length() != 71 {
    fail("MoonChat Flow input_digest must be sha256")
  }
  if request.input_artifacts.length() < 2 || request.timeout_ms <= 0 {
    fail(
      "MoonChat Flow request requires a bundle, source artifact and positive timeout",
    )
  }
}

///|
fn durable_receipt_ref(request : FlowRequest) -> String {
  ".moonsuite/products/moonchat/idempotency/\{request.idempotency_key}/native-receipt.json"
}

///|
fn review_version_key(request : FlowRequest) -> String {
  request.input_digest[7:].to_owned()
}

///|
fn review_version_base(request : FlowRequest, review_id : String) -> String {
  ".moonsuite/products/moonchat/reviews/\{review_id}/versions/\{review_version_key(request)}"
}

///|
fn review_record_ref(request : FlowRequest, review_id : String) -> String {
  "\{review_version_base(request, review_id)}/conversation-review-record.json"
}

///|
fn review_event_ref(
  request : FlowRequest,
  event : @review.ConversationReviewEvent,
) -> String {
  "\{review_version_base(request, event.review_id)}/events/\{event.sequence}-\{event.event_id}.json"
}
