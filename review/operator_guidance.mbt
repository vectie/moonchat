///|
fn review_outcome_message(bundle : ConversationReviewBundle) -> String {
  match review_status(bundle) {
    "accepted" =>
      "All named reviewers approved this exact version. Return to the producing application to continue the next governed handoff."
    "rejected" => {
      let rejected = rejected_decision_ids(bundle)
      let detail = if rejected.is_empty() {
        ". Return to the producing application and create a new version; do not edit this record."
      } else {
        " (\{rejected.join(", ")}). Return to the producing application and create a new version; do not edit this record."
      }
      "A named reviewer rejected this version" + detail
    }
    _ => {
      let missing = missing_decision_ids(bundle)
      let detail = if missing.is_empty() {
        ". Return to the producing application to review the deferred decision."
      } else {
        " (\{missing.join(", ")}). Return to the producing application to complete it."
      }
      "A named-human decision is still needed" + detail
    }
  }
}
