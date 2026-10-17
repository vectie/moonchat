# Explore supplied mailbox reply context

Start with an explicit local message identity. Use `catalog` or `search` to find
the original Message-ID and exact snapshot digest, then:

```sh
python3 -B scripts/review_mbox.py thread thread.mbox --message-id '<reply@example.invalid>' --mailbox-digest sha256:YOUR_SNAPSHOT_DIGEST
python3 -B scripts/review_mbox.py thread thread.mbox --ordinal 2 --mailbox-digest sha256:YOUR_SNAPSHOT_DIGEST
```

Supply exactly one selector. A Message-ID must identify one usable message;
duplicate, missing or unsupported identities require explicit ordinal selection.
The digest is optional for first discovery and recommended when returning to a
saved snapshot. Changed bytes reject the supplied digest before any output.

The result includes the selected ordinal and the connected component obtained
by following uniquely resolved parent links in both directions. This exposes
ancestors, replies and siblings. Each node retains its ordinal, exact message
SHA-256, envelope-inclusive half-open source byte span, supplied headers and
subjects. It does not include body text: use `catalog` to inspect that evidence.
Message-ID header indices count the importer's retained headers, not omitted
custom headers. Every node belongs to the result's exact mailbox digest.

Parent rules are deliberately conservative:

- One `In-Reply-To` header containing one literal ID takes precedence.
- Only when `In-Reply-To` is absent, the last ID in one `References` header is
  used, explicitly labeled `References-last`.
- Supported IDs are ASCII `<local@domain>` tokens separated by whitespace;
  comments, quoted forms, domain literals and other syntax are retained but not
  interpreted. IDs are case-sensitive. No subject or date grouping occurs.
- Multiple/repeated reply headers, duplicate Message-ID candidates, and
  unusable parent identities are reported as ambiguous. Such links do not merge
  components. Literal ID mentions in unusable identity headers are candidates,
  never unique identities. `ambiguous_incoming` shows outside messages that may
  refer to this component.
- Missing parents, no reply link and unsupported syntax remain distinct.
  `reference_links` exposes every supported reference independently, including
  missing or ambiguous older references. Contradictory references do not
  override an explicit `In-Reply-To`.
- Cycles and self-links appear in `cycles`; traversal terminates without
  inventing a root. Each cycle lists the parent-following ordinal order once.

This is supplied-header context, not verified correspondence or authorship.
The existing 4 MiB/500-message intake, MIME limits and 8 MiB result limit apply.
Thread headers additionally permit at most 10000 whitespace-separated tokens
across Message-ID, In-Reply-To and References before refusing exploration.
The command returns a complete result or an error without partial stdout.

## Choose evidence for review

Copy only the desired ordinals into the existing
`moonchat.mbox-review.v1` selection file, along with the result's exact
`mailbox_digest`. Write explicit curator author, kind, note and named decision
requests as shown in `examples/review-mbox/selections.json`. Discovery does not
make these choices. Then use the unchanged native composer:

```sh
python3 -B scripts/review_mbox.py agenda agenda.json thread.mbox selections.json --composer /absolute/trusted/review_compose
python3 -B scripts/review_mbox.py bundle agenda.json thread.mbox selections.json --composer /absolute/trusted/review_compose
python3 -B scripts/review_mbox.py preview agenda.json thread.mbox selections.json --composer /absolute/trusted/review_compose
```

Email claims such as “I approve” remain quoted evidence. No sender identity,
reviewer decision, execution or recipient acceptance is inferred. Host UI,
authenticated decisions, delivery and full-release gates remain unqualified.

Tests: `python3 -B -m unittest discover -s scripts -p 'test_review_mbox_thread.py' -v`.
Set `MOONCHAT_REVIEW_COMPOSER` to a verified unchanged native executable to
include the actual composer consumer test; otherwise that test is explicitly
skipped. Set `MOONCHAT_THREAD_EVIDENCE` to a fresh directory to retain fixtures
and outputs. The native test uses no composer mock.
