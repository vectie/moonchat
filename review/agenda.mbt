///|
/// Editable preparation input, not an approval or a serialized review bundle.
pub(all) struct ReviewAgenda {
  review_id : String
  conversation_id : String
  source_artifact_ref : String
  source_revision_id : String
  recorded_at : String
  participants : Array[ReviewParticipant]
  items : Array[ReviewAgendaItem]
} derive(Eq, ToJson, @json.FromJson)

///|
/// Keep each key stable when editing or reordering an agenda.
pub(all) struct ReviewAgendaItem {
  key : String
  kind : String
  author : String
  body : String
  evidence_refs : Array[String]
  decisions : Array[ReviewAgendaDecision]
} derive(Eq, ToJson, @json.FromJson)

///|
pub(all) struct ReviewAgendaDecision {
  reviewer : String
  prompt : String
} derive(Eq, ToJson, @json.FromJson)

///|
/// Compile an editable agenda against actual source bytes. IDs are derived from
/// explicit item keys, never array positions. All output remains pending.
pub fn compile_review_agenda(
  agenda : ReviewAgenda,
  source_bytes : Bytes,
) -> ConversationReviewBundle raise {
  let entries : Array[ReviewEntry] = []
  let decisions : Array[RequiredDecision] = []
  let keys : Map[String, Bool] = {}
  for item in agenda.items {
    if !safe_identifier(item.key) || keys.contains(item.key) {
      fail("agenda item keys must be unique safe identifiers: " + item.key)
    }
    keys[item.key] = true
    let id = "entry-" + item.key
    entries.push(
      draft_review_entry(
        item.kind,
        entry_id=id,
        author_participant_id=item.author,
        turn={
          turn_id: "turn-" + item.key,
          client_turn_id: "client-" + item.key,
          command_id: "command-" + item.key,
        },
        body=item.body,
        evidence_refs=item.evidence_refs,
      ),
    )
    for decision in item.decisions {
      let reviewer = match participant(agenda.participants, decision.reviewer) {
        Some(value) => value
        None => fail("unknown agenda reviewer: " + decision.reviewer)
      }
      // Length-prefix the item key so different key/reviewer pairs cannot collide.
      decisions.push(
        draft_required_decision(
          decision_id="decision-\{item.key.length()}-\{item.key}-\{decision.reviewer}",
          subject_entry_id=id,
          reviewer~,
          prompt=decision.prompt,
        ),
      )
    }
  }
  draft_review_bundle(
    review_id=agenda.review_id,
    source_artifact_ref=agenda.source_artifact_ref,
    source_bytes~,
    source_revision_id=agenda.source_revision_id,
    conversation={
      contract_id: conversation_contract_id(),
      protocol: "moonchat.review-agenda.v1",
      product_id: "moonchat",
      conversation_id: agenda.conversation_id,
    },
    participants=agenda.participants,
    entries~,
    required_decisions=decisions,
    recorded_at=agenda.recorded_at,
  )
}

///|
pub fn parse_review_agenda(text : String) -> ReviewAgenda raise {
  @json.from_json(@json.parse(text))
}
