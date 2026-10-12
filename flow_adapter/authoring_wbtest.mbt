///|
fn authored_native_fixture(
  source : String,
  revision : String,
) -> @review.ConversationReviewBundle raise {
  let reviewer : @review.ReviewParticipant = {
    participant_id: "fixture-human",
    display_name: "Fixture reviewer",
    participant_kind: "human",
  }
  @review.draft_review_bundle(
    review_id="collaboration-fixture",
    source_artifact_ref="source-packet.json",
    source_bytes=@utf8.encode(source),
    source_revision_id=revision,
    conversation={
      contract_id: @review.conversation_contract_id(),
      protocol: "moontown.collaboration-review.v1",
      product_id: "moontown",
      conversation_id: "fixture-room",
    },
    participants=[
      reviewer,
      {
        participant_id: "fixture-agent",
        display_name: "Fixture collaborator",
        participant_kind: "agent",
      },
    ],
    entries=[
      @review.draft_review_entry(
        "objection",
        entry_id="open-objection",
        author_participant_id="fixture-agent",
        turn={
          turn_id: "turn-1",
          client_turn_id: "client-1",
          command_id: "command-1",
        },
        body="Fixture dissent remains visible in every projection.",
        evidence_refs=["source-packet.json"],
      ),
    ],
    required_decisions=[
      @review.draft_required_decision(
        decision_id="fixture-decision",
        subject_entry_id="open-objection",
        reviewer~,
        prompt="Source fixture only: review the objection.",
      ),
    ],
    recorded_at="2026-10-06T16:00:00Z",
  )
}

///|
async fn authored_request(
  root : String,
  artifacts : Array[String],
  suffix : String,
) -> String {
  let request : Json = {
    "request_id": "request-" + suffix,
    "run_id": "source-fixture",
    "book_id": "source-fixture",
    "work_item_id": "source-fixture",
    "declaration_id": adapter_id(),
    "attempt_id": "attempt-" + suffix,
    "idempotency_key": "source-fixture-" + suffix,
    "product_id": "moonchat",
    "operation": operation_ref(),
    "requested_authority": "workspace-mutation",
    "acceptance_criteria": [
      "retain fixture dissent without real human authority",
    ],
    "input_contracts": [input_schema_ref()],
    "output_contracts": [output_schema_ref()],
    "required_claim": "research-evidence",
    "input_digest": declared_input_digest(root, artifacts),
    "input_artifacts": artifacts,
    "timeout_ms": 30000,
    "created_at": "2026-10-06T16:00:00Z",
  }
  let reference = "runtime/request-" + suffix + ".json"
  write_fixture(root, reference, request.stringify(indent=2) + "\n")
  reference
}

///|
fn add_fixture_decision(
  bundle : @review.ConversationReviewBundle,
  decision : String,
) -> Unit {
  bundle.decision_receipts.push({
    receipt_id: "fixture-" + decision,
    decision_id: "fixture-decision",
    reviewer_participant_id: "fixture-human",
    reviewer_name: "Fixture reviewer",
    decision,
    rationale: "Native source-test fixture only; no real human authority implied.",
    source_digest: bundle.source_digest,
    decided_at: "2026-10-06T16:01:00Z",
    evidence_refs: [],
  })
}

///|
async test "authored native fixtures retain decisions dissent retry and stale source rejection" {
  for choice in ["pending", "approve", "reject", "defer"] {
    let root = @fs.tmpdir(prefix="moonchat-authored-fixture-")
    let source = "{\"fixture\":\"collaboration\",\"revision\":1}\n"
    let bundle = authored_native_fixture(source, "source-one")
    if choice != "pending" {
      add_fixture_decision(bundle, choice)
    }
    let text = @review.serialize_review_bundle(bundle, sha256_text(source))
    assert_eq(
      @review.reimport_review_bundle(text, @utf8.encode(source)),
      bundle,
    )
    write_fixture(root, bundle.source_artifact_ref, source)
    write_fixture(root, "review-bundle.json", text)
    let request = authored_request(
      root,
      ["review-bundle.json", bundle.source_artifact_ref],
      choice,
    )
    let first = execute(root, request, "runtime/result.json")
    assert_eq(first, execute(root, request, "runtime/result.json"))
    assert_eq(first, reconcile(root, request, "runtime/reconciled.json"))
    let fields = json_object(first, "fixture result")
    guard fields.get("output_artifacts") is Some(Array([String(record_ref)])) else {
      fail("missing fixture record")
    }
    let record_bytes = @fs.read_file(scoped_path(root, record_ref)).binary()
    let record = @review.decode_review_record(read_json_ref(root, record_ref))
    assert_eq(
      record.review_status,
      if choice == "approve" {
        "accepted"
      } else if choice == "reject" {
        "rejected"
      } else {
        "pending_review"
      },
    )
    assert_eq(record.decision_receipts, bundle.decision_receipts)
    assert_eq(record.entries[0].body, bundle.entries[0].body)
    assert_eq(record.accepted, choice == "approve")
    write_fixture(root, bundle.source_artifact_ref, "{\"tampered\":true}\n")
    let refused = try execute(root, request, "runtime/result.json") catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(
      refused,
      msg="same-filename tamper must fail before prior result reuse",
    )
    assert_eq(
      @fs.read_file(scoped_path(root, record_ref)).binary(),
      record_bytes,
    )
  }
}

///|
async test "authored supersession preserves prior accepted evidence and projects new pending scope" {
  let root = @fs.tmpdir(prefix="moonchat-authored-supersession-")
  let prior_source = "{\"revision\":1}\n"
  let prior = {
    ..authored_native_fixture(prior_source, "one"),
    source_artifact_ref: "history/one/source-packet.json",
  }
  add_fixture_decision(prior, "approve")
  let prior_text = @review.serialize_review_bundle(
    prior,
    sha256_text(prior_source),
  )
  let prior_ref = "history/one/review-bundle.json"
  write_fixture(root, prior.source_artifact_ref, prior_source)
  write_fixture(root, prior_ref, prior_text)
  let prior_request = authored_request(
    root,
    [prior_ref, prior.source_artifact_ref],
    "prior",
  )
  let prior_result = execute(root, prior_request, "runtime/prior-result.json")
  let next_source = "{\"revision\":2}\n"
  let next = @review.supersede_review_bundle(
    prior_text,
    previous_bundle_ref=prior_ref,
    previous_source_bytes=@utf8.encode(prior_source),
    next_bundle=authored_native_fixture(next_source, "two"),
    next_source_bytes=@utf8.encode(next_source),
  )
  write_fixture(root, next.source_artifact_ref, next_source)
  write_fixture(
    root,
    "review-bundle.json",
    @review.serialize_review_bundle(next, sha256_text(next_source)),
  )
  let request = authored_request(
    root,
    ["review-bundle.json", next.source_artifact_ref, prior_ref],
    "next",
  )
  let result = execute(root, request, "runtime/next-result.json")
  assert_eq(
    json_string_field(json_object(result, "result"), "review_status"),
    "pending_review",
  )
  assert_eq(result, reconcile(root, request, "runtime/next-reconciled.json"))
  assert_eq(@fs.read_file(scoped_path(root, prior_ref)).text(), prior_text)
  assert_eq(
    prior_result,
    execute(root, prior_request, "runtime/prior-result.json"),
  )
  write_fixture(root, prior_ref, prior_text + " ")
  // Refreshing declared inputs still cannot conceal a predecessor digest change.
  let tampered_request = authored_request(
    root,
    ["review-bundle.json", next.source_artifact_ref, prior_ref],
    "tamper",
  )
  let refused = try
    execute(root, tampered_request, "runtime/tampered-result.json")
  catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(refused)
}
