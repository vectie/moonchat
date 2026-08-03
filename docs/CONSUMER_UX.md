# MoonChat consumer UX contract

MoonChat appears inside the application that asked for a review. The consumer
must not expose contract vocabulary as the primary task.

The ordinary review surface answers one question: **what decision does this
exact version need from me?** It shows the source title and version, the
proposal or objection, the named reviewer, and one dominant decision action.
Participant identities, turn ids, digests, event journals and claim ceilings
remain inspectable under evidence details.

Consumers render the final `review_projected` event as the outcome guidance:

- pending: return to the decision and name what remains incomplete;
- rejected: create a new source/bundle version; never edit the retained record;
- accepted: continue to the next separately governed product handoff.

Every icon-only control needs an accessible name and tooltip. Async outcomes
use a polite live region; invalid or stale evidence uses an assertive alert and
a concrete restore-or-version recovery action. The selected review and entered
rationale survive an ordinary refresh in the owning application.

This contract deliberately adds no MoonChat Rabbita application. See the
[product contract](PRODUCT_CONTRACT.md) for ownership and exclusions.
