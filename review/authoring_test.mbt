///|
fn authoring_reviewer() -> @review.ReviewParticipant {
  {
    participant_id: "accountable-human",
    display_name: "Fixture accountable reviewer",
    participant_kind: "human",
  }
}

///|
fn authored_bundle(
  source? : Bytes = b"revision one\n",
  revision? : String = "rev-one",
) -> @review.ConversationReviewBundle raise {
  let reviewer = authoring_reviewer()
  let entries = ["question", "objection", "proposal"].map(kind => {
    @review.draft_review_entry(
      kind,
      entry_id=kind,
      author_participant_id="collaborator-agent",
      turn={
        turn_id: "turn-" + kind,
        client_turn_id: "client-" + kind,
        command_id: "command-" + kind,
      },
      body="Explicit " + kind + " about the bound collaboration source.",
      evidence_refs=["revisions/rev-one/sources/brief.md"],
    )
  })
  @review.draft_review_bundle(
    review_id="collaboration-review",
    source_artifact_ref="collaboration/source-packet.json",
    source_bytes=source,
    source_revision_id=revision,
    conversation={
      contract_id: @review.conversation_contract_id(),
      protocol: "moontown.collaboration-review.v1",
      product_id: "moontown",
      conversation_id: "collaboration-room",
    },
    participants=[
      {
        participant_id: "collaborator-agent",
        display_name: "Fixture collaborator",
        participant_kind: "agent",
      },
      reviewer,
    ],
    entries~,
    required_decisions=[
      @review.draft_required_decision(
        decision_id="objection-decision",
        subject_entry_id="objection",
        reviewer~,
        prompt="Does this source address the objection sufficiently?",
      ),
    ],
    recorded_at="2026-10-06T16:00:00Z",
  )
}

///|
fn authoring_fails(action : () -> Unit raise) -> Bool {
  action() catch {
    _ => return true
  }
  false
}

///|
fn fixture_receipt(
  bundle : @review.ConversationReviewBundle,
  decision : String,
) -> @review.HumanDecisionReceipt {
  {
    receipt_id: "fixture-" + decision,
    decision_id: "objection-decision",
    reviewer_participant_id: "accountable-human",
    reviewer_name: "Fixture accountable reviewer",
    decision,
    rationale: "Source test fixture only; no real human authority implied.",
    source_digest: bundle.source_digest,
    decided_at: "2026-10-06T16:01:00Z",
    evidence_refs: [],
  }
}

///|
test "author all entry kinds with explicit human owner distinct from objection author" {
  let bundle = authored_bundle()
  assert_eq(bundle.contract_id, "moonchat.conversation-review-bundle.v1")
  assert_eq(bundle.entries.map(e => e.entry_kind), [
    "question", "objection", "proposal",
  ])
  assert_eq(
    bundle.required_decisions[0].reviewer_participant_id,
    "accountable-human",
  )
  assert_eq(bundle.entries[1].author_participant_id, "collaborator-agent")
  assert_eq(bundle.decision_receipts, [])
  assert_eq(
    @review.bundle_issues(
      bundle,
      @review.review_source_digest(b"revision one\n"),
    ),
    [],
  )
  assert_eq(@review.review_status(bundle), "pending_review")
  assert_eq(@review.claim_class(bundle), "research-evidence")
}

///|
test "authoring rejects invalid entries and never assigns agent decision owners" {
  let good = authored_bundle()
  for kind in ["approve", "message", ""] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.draft_review_entry(
            kind,
            entry_id="entry",
            author_participant_id="collaborator-agent",
            turn=good.entries[0].turn,
            body="Text",
          ),
        )
      }),
    )
  }
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.draft_required_decision(
          decision_id="decision",
          subject_entry_id="objection",
          reviewer=good.participants[0],
          prompt="Decide",
        ),
      )
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.draft_review_entry(
          "question",
          entry_id="question",
          author_participant_id="collaborator-agent",
          turn=good.entries[0].turn,
          body=" ",
        ),
      )
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.draft_review_entry(
          "question",
          entry_id="question",
          author_participant_id="collaborator-agent",
          turn={ ..good.entries[0].turn, command_id: "", },
          body="Question",
          evidence_refs=["../outside.md"],
        ),
      )
    }),
  )
}

///|
test "draft validates required decision coverage and actual participant ownership" {
  let good = authored_bundle()
  for
    requirements in [
      [],
      [
        {
          ..good.required_decisions[0],
          reviewer_participant_id: "missing-human",
        },
      ],
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.draft_review_bundle(
            review_id=good.review_id,
            source_artifact_ref=good.source_artifact_ref,
            source_bytes=b"revision one\n",
            source_revision_id=good.source_revision_id,
            conversation=good.conversation,
            participants=good.participants,
            entries=good.entries,
            required_decisions=requirements,
            recorded_at=good.recorded_at,
          ),
        )
      }),
    )
  }
}

///|
test "pending serialization reimports through production decoder deterministically" {
  let bundle = authored_bundle()
  let text = @review.serialize_review_bundle(bundle, bundle.source_digest)
  let decoded = @review.decode_review_bundle(@json.parse(text))
  assert_eq(decoded, bundle)
  assert_eq(@review.reimport_review_bundle(text, b"revision one\n"), bundle)
  assert_eq(
    @review.serialize_review_bundle(decoded, decoded.source_digest),
    text,
  )
  assert_eq(
    @review.review_events(decoded, decoded.source_digest),
    @review.review_events(bundle, bundle.source_digest),
  )
  assert_eq(
    @review.project_review_record(decoded, decoded.source_digest, []).review_status,
    "pending_review",
  )
}

///|
test "same filename with different bytes cannot reimport or serialize old approval" {
  let bundle = authored_bundle()
  bundle.decision_receipts.push(fixture_receipt(bundle, "approve"))
  let old_text = @review.serialize_review_bundle(bundle, bundle.source_digest)
  assert_true(
    authoring_fails(() => {
      ignore(@review.reimport_review_bundle(old_text, b"revision TWO\n"))
    }),
  )
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.serialize_review_bundle(
          bundle,
          @review.review_source_digest(b"revision one"),
        ),
      )
    }),
  )
  assert_eq(@review.review_status(bundle), "accepted")
}

///|
test "supersession retains exact previous bytes and never inherits any fixture decision" {
  for decision in ["approve", "reject", "defer"] {
    let previous = authored_bundle()
    previous.decision_receipts.push(fixture_receipt(previous, decision))
    let previous_text = @review.serialize_review_bundle(
      previous,
      previous.source_digest,
    )
    let next = authored_bundle(source=b"revision two\n", revision="rev-two")
    let superseded = @review.supersede_review_bundle(
      previous_text,
      previous_bundle_ref="history/rev-one/review-bundle.json",
      previous_source_bytes=b"revision one\n",
      next_bundle=next,
      next_source_bytes=b"revision two\n",
    )
    assert_eq(
      superseded.previous_bundle_digest,
      @review.review_source_digest(@utf8.encode(previous_text)),
    )
    assert_eq(
      superseded.previous_bundle_ref,
      "history/rev-one/review-bundle.json",
    )
    assert_eq(superseded.decision_receipts, [])
    assert_eq(@review.review_status(superseded), "pending_review")
    assert_eq(@review.claim_class(superseded), "research-evidence")
    assert_eq(previous.decision_receipts[0].decision, decision)
    assert_eq(
      @review.serialize_review_bundle(previous, previous.source_digest),
      previous_text,
    )
    assert_eq(next.previous_bundle_ref, "")
    assert_eq(
      @review.bundle_issues(
        superseded,
        @review.review_source_digest(b"revision two\n"),
      ),
      [],
    )
  }
}

///|
test "supersession rejects stale observed source in either scope" {
  let previous = authored_bundle()
  let text = @review.serialize_review_bundle(previous, previous.source_digest)
  let next = authored_bundle(source=b"revision two\n", revision="rev-two")
  for
    (prior_source, next_source) in [
      (b"tampered\n", b"revision two\n"),
      (b"revision one\n", b"tampered\n"),
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.supersede_review_bundle(
            text,
            previous_bundle_ref="history/rev-one/review-bundle.json",
            previous_source_bytes=prior_source,
            next_bundle=next,
            next_source_bytes=next_source,
          ),
        )
      }),
    )
  }
}

///|
test "supersession rejects changed revision identity and unrelated review scopes" {
  let previous = authored_bundle()
  let text = @review.serialize_review_bundle(previous, previous.source_digest)
  let next = authored_bundle(source=b"revision two\n", revision="rev-two")
  for
    invalid in [
      { ..next, source_revision_id: previous.source_revision_id, },
      { ..next, review_id: "different-review", },
      {
        ..next,
        conversation: {
          ..next.conversation,
          conversation_id: "different-room",
        },
      },
      {
        ..next,
        previous_bundle_ref: "history/other.json",
        previous_bundle_digest: previous.source_digest,
      },
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.supersede_review_bundle(
            text,
            previous_bundle_ref="history/rev-one/review-bundle.json",
            previous_source_bytes=b"revision one\n",
            next_bundle=invalid,
            next_source_bytes=b"revision two\n",
          ),
        )
      }),
    )
  }
  next.decision_receipts.push(fixture_receipt(next, "approve"))
  assert_true(
    authoring_fails(() => {
      ignore(
        @review.supersede_review_bundle(
          text,
          previous_bundle_ref="history/rev-one/review-bundle.json",
          previous_source_bytes=b"revision one\n",
          next_bundle=next,
          next_source_bytes=b"revision two\n",
        ),
      )
    }),
  )
}

///|
test "draft and supersession isolate nested mutable evidence arrays" {
  let source = authored_bundle()
  let copy = @review.draft_review_bundle(
    review_id=source.review_id,
    source_artifact_ref=source.source_artifact_ref,
    source_bytes=b"revision one\n",
    source_revision_id=source.source_revision_id,
    conversation=source.conversation,
    participants=source.participants,
    entries=source.entries,
    required_decisions=source.required_decisions,
    recorded_at=source.recorded_at,
  )
  source.entries[0].evidence_refs.push("later/form-edit.md")
  source.participants.clear()
  assert_eq(copy.entries[0].evidence_refs, [
    "revisions/rev-one/sources/brief.md",
  ])
  assert_eq(copy.participants.length(), 2)
  let text = @review.serialize_review_bundle(copy, copy.source_digest)
  let superseded = @review.supersede_review_bundle(
    text,
    previous_bundle_ref="history/rev-one/review-bundle.json",
    previous_source_bytes=b"revision one\n",
    next_bundle=copy,
    next_source_bytes=b"revision one\n",
  )
  copy.entries[0].evidence_refs.clear()
  assert_eq(superseded.entries[0].evidence_refs, [
    "revisions/rev-one/sources/brief.md",
  ])
}

///|
test "import rejects malformed or unsupported portable review bundles" {
  for
    text in [
      "{", "{}", "{\"contract_id\":\"moonchat.conversation-review-bundle.v9\"}",
    ] {
    assert_true(
      authoring_fails(() => {
        ignore(@review.reimport_review_bundle(text, b"revision one\n"))
      }),
    )
  }
}

///|
test "predecessor digest covers original serialized whitespace and cannot alias a source" {
  let prior = authored_bundle()
  let original = "\n" +
    @review.serialize_review_bundle(prior, prior.source_digest) +
    " "
  let next = {
    ..authored_bundle(source=b"revision two\n", revision="two"),
    source_artifact_ref: "revisions/two/source-packet.json",
  }
  let superseded = @review.supersede_review_bundle(
    original,
    previous_bundle_ref="history/prior.json",
    previous_source_bytes=b"revision one\n",
    next_bundle=next,
    next_source_bytes=b"revision two\n",
  )
  assert_eq(
    superseded.previous_bundle_digest,
    @review.review_source_digest(@utf8.encode(original)),
  )
  assert_true(
    superseded.previous_bundle_digest !=
    @review.review_source_digest(
      @utf8.encode(@review.serialize_review_bundle(prior, prior.source_digest)),
    ),
  )
  for reference in [prior.source_artifact_ref, next.source_artifact_ref] {
    assert_true(
      authoring_fails(() => {
        ignore(
          @review.supersede_review_bundle(
            original,
            previous_bundle_ref=reference,
            previous_source_bytes=b"revision one\n",
            next_bundle=next,
            next_source_bytes=b"revision two\n",
          ),
        )
      }),
    )
  }
}
