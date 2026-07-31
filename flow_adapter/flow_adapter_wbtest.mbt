///|
async fn write_fixture(
  root : String,
  reference : String,
  text : String,
) -> Unit {
  let path = scoped_path(root, reference)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fs.write_file(
    path,
    text,
    create_mode=CreateOrTruncate,
    permission=0o644,
    sync=Full,
  )
}

///|
async test "execute and reconcile reuse one append-only review projection" {
  let root = @fs.tmpdir(prefix="moonchat-review-adapter-")
  let source_ref = "outputs/robot-concept.json"
  let source_text = "{\"concept\":\"bounded-inspector\",\"revision\":3}\n"
  write_fixture(root, source_ref, source_text)
  let source_digest = sha256_text(source_text)
  let bundle : @review.ConversationReviewBundle = {
    contract_id: @review.bundle_contract_id(),
    review_id: "robot-stakeholder-review",
    source_artifact_ref: source_ref,
    source_digest,
    source_revision_id: "robot-concept-v3",
    previous_bundle_ref: "",
    previous_bundle_digest: "",
    conversation: {
      contract_id: @review.conversation_contract_id(),
      protocol: "moonfind.stakeholder-review.v1",
      product_id: "moonfind",
      conversation_id: "robot-review-room",
    },
    participants: [
      {
        participant_id: "planner-agent",
        display_name: "Planner agent",
        participant_kind: "agent",
      },
      {
        participant_id: "mission-owner",
        display_name: "Lin Mei",
        participant_kind: "human",
      },
    ],
    entries: [
      {
        entry_id: "objection-thermal",
        entry_kind: "objection",
        author_participant_id: "mission-owner",
        turn: {
          turn_id: "turn-2",
          client_turn_id: "client-turn-2",
          command_id: "command-2",
        },
        body: "Thermal calibration remains unresolved.",
        evidence_refs: [source_ref],
      },
    ],
    required_decisions: [
      {
        decision_id: "thermal-go-no-go",
        subject_entry_id: "objection-thermal",
        reviewer_participant_id: "mission-owner",
        prompt: "Is the evidence sufficient to continue planning?",
      },
    ],
    decision_receipts: [],
    recorded_at: "2026-07-31T02:00:00Z",
  }
  let bundle_ref = "inputs/review-bundle.json"
  write_fixture(root, bundle_ref, bundle.to_json().stringify(indent=2) + "\n")
  let input_artifacts = [bundle_ref, source_ref]
  let input_digest = declared_input_digest(root, input_artifacts)
  let request : Json = {
    "request_id": "request-review-1",
    "run_id": "run-1",
    "book_id": "robot-book",
    "work_item_id": "stakeholder-review",
    "declaration_id": adapter_id(),
    "attempt_id": "attempt-1",
    "idempotency_key": "robot-review-v3",
    "product_id": "moonchat",
    "operation": operation_ref(),
    "requested_authority": "workspace-mutation",
    "acceptance_criteria": ["preserve objections"],
    "input_contracts": [input_schema_ref()],
    "output_contracts": [output_schema_ref()],
    "required_claim": "research-evidence",
    "input_digest": input_digest,
    "input_artifacts": input_artifacts,
    "timeout_ms": 30000,
    "created_at": "2026-07-31T02:01:00Z",
  }
  let request_ref = "runtime/request.json"
  write_fixture(root, request_ref, request.stringify(indent=2) + "\n")
  let first = execute(root, request_ref, "runtime/result.json")
  let resumed = reconcile(root, request_ref, "runtime/reconciled-result.json")
  assert_eq(first, resumed)
  let fields = json_object(first, "test result")
  assert_eq(json_string_field(fields, "status"), "succeeded")
  assert_eq(json_string_field(fields, "actual_claim"), "research-evidence")
  guard fields.get("output_artifacts") is Some(Array([String(record_ref)])) else {
    fail("expected one durable review record")
  }
  let record = @review.decode_review_record(read_json_ref(root, record_ref))
  assert_eq(record.review_status, "pending_review")
  assert_eq(record.missing_decision_ids, ["thermal-go-no-go"])
  assert_true(record.journal_evidence.length() >= 4)
  assert_true(
    @fs.exists(
      scoped_path(root, durable_receipt_ref(decode_flow_request(request))),
    ),
  )
}
