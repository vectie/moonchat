///|
fn digest(ch : Char) -> String {
  "sha256:" + ch.to_string().repeat(64)
}

///|
fn pending_bundle() -> @review.ConversationReviewBundle {
  {
    contract_id: @review.bundle_contract_id(),
    review_id: "robot-stakeholder-review",
    source_artifact_ref: "outputs/robot-concept.json",
    source_digest: digest('a'),
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
        entry_id: "proposal-1",
        entry_kind: "proposal",
        author_participant_id: "planner-agent",
        turn: {
          turn_id: "turn-1",
          client_turn_id: "client-turn-1",
          command_id: "command-1",
        },
        body: "Use the bounded inspection concept.",
        evidence_refs: ["outputs/robot-concept.json"],
      },
      {
        entry_id: "objection-thermal",
        entry_kind: "objection",
        author_participant_id: "mission-owner",
        turn: {
          turn_id: "turn-2",
          client_turn_id: "client-turn-2",
          command_id: "command-2",
        },
        body: "Thermal calibration is unresolved.",
        evidence_refs: ["evidence/thermal-review.json"],
      },
    ],
    required_decisions: [
      {
        decision_id: "thermal-go-no-go",
        subject_entry_id: "objection-thermal",
        reviewer_participant_id: "mission-owner",
        prompt: "Is the thermal evidence sufficient for project planning?",
      },
    ],
    decision_receipts: [],
    recorded_at: "2026-07-31T02:00:00Z",
  }
}

///|
test "MoonLib turn identity and objections survive a pending projection" {
  let bundle = pending_bundle()
  assert_eq(@review.bundle_issues(bundle, digest('a')), [])
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(@review.claim_class(bundle), "research-evidence")
  let events = @review.review_events(bundle, digest('a'))
  assert_true(events.any(event => event.event_id == "entry-objection-thermal"))
  assert_true(
    events.any(event => {
      event.event_id == "review-projected" &&
      event.body.contains("A named-human decision is still needed") &&
      event.body.contains("thermal-go-no-go")
    }),
  )
  let record = @review.project_review_record(bundle, digest('a'), [])
  assert_eq(record.review_status, "pending_review")
  assert_false(record.accepted)
  assert_eq(record.missing_decision_ids, ["thermal-go-no-go"])
  assert_eq(record.entries[1].turn.command_id, "command-2")
}

///|
test "only the named human can create an acceptance receipt" {
  let bundle = pending_bundle()
  bundle.decision_receipts.push({
    receipt_id: "receipt-agent",
    decision_id: "thermal-go-no-go",
    reviewer_participant_id: "planner-agent",
    reviewer_name: "Planner agent",
    decision: "approve",
    rationale: "The model thinks the risk is bounded.",
    source_digest: digest('a'),
    decided_at: "2026-07-31T02:10:00Z",
    evidence_refs: [],
  })
  let issues = @review.bundle_issues(bundle, digest('a'))
  assert_true(
    issues.any(issue => {
      issue.contains("reviewer does not own decision") ||
      issue.contains("agent suggestions cannot become human decisions")
    }),
  )
}

///|
test "all named human approvals promote only the review record" {
  let bundle = pending_bundle()
  bundle.decision_receipts.push({
    receipt_id: "receipt-human",
    decision_id: "thermal-go-no-go",
    reviewer_participant_id: "mission-owner",
    reviewer_name: "Lin Mei",
    decision: "approve",
    rationale: "The attached calibration bounds are sufficient for planning.",
    source_digest: digest('a'),
    decided_at: "2026-07-31T02:10:00Z",
    evidence_refs: ["evidence/thermal-acceptance.json"],
  })
  assert_eq(@review.bundle_issues(bundle, digest('a')), [])
  let record = @review.project_review_record(bundle, digest('a'), [])
  assert_eq(record.review_status, "accepted")
  assert_true(record.accepted)
  assert_eq(record.claim_class, "accepted-knowledge")
  assert_eq(record.entries[1].entry_kind, "objection")
  let events = @review.review_events(bundle, digest('a'))
  assert_true(
    events.any(event => {
      event.event_id == "review-projected" &&
      event.body.contains("All named reviewers approved this exact version")
    }),
  )
}

///|
test "a rejected version points the consumer to immutable recovery" {
  let bundle = pending_bundle()
  bundle.decision_receipts.push({
    receipt_id: "receipt-human-reject",
    decision_id: "thermal-go-no-go",
    reviewer_participant_id: "mission-owner",
    reviewer_name: "Lin Mei",
    decision: "reject",
    rationale: "The calibration bounds are not sufficient.",
    source_digest: digest('a'),
    decided_at: "2026-07-31T02:10:00Z",
    evidence_refs: ["evidence/thermal-acceptance.json"],
  })
  let events = @review.review_events(bundle, digest('a'))
  assert_true(
    events.any(event => {
      event.event_id == "review-projected" &&
      event.body.contains("A named reviewer rejected this version") &&
      event.body.contains("thermal-go-no-go") &&
      event.body.contains("create a new version")
    }),
  )
}

///|
test "changed source evidence invalidates old receipts" {
  let issues = @review.bundle_issues(pending_bundle(), digest('b'))
  assert_true(issues.contains("source artifact is stale or has been replaced"))
}
