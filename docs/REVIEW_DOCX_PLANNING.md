# Plan Word review decisions beside their source

After choosing Word comments for a MoonChat agenda, a curator needs to check
what each named reviewer is being asked, beside the passages that prompted the
questions. The original DOCX packet shows the document's comments, while the
ordinary agenda preview requires a native composer and has no binary-DOCX source
view. `plan-packet` closes this preparation step in the existing DOCX intake CLI.
It combines the explicit import recipe, existing agenda discussion and complete
logical Word text in one offline HTML reading view.

This is **draft preparation, not a validated review or a decision form**. Native
MoonChat still owns full agenda/contract validation and bundle production.
Reading the packet does not make an assignment authentic, collect a decision,
create receipts, validate evidence references or change review status.

## Try the retained synthetic planning journey

From the repository root, with Python 3.10+ and no installed packages:

```sh
python -B tools/review_docx/review_docx.py plan-packet examples/review-docx-plan/agenda.json examples/review-docx/launch.docx examples/review-docx-plan/selections.json > planning.html
```

Open the resulting file in a browser. The example asks two named humans about
the same rollback concern, keeps an existing proposal, and imports the support
question. The unselected automated comment saying “I approve everything” stays
visible as original evidence. All names and content are fictional. The retained
`examples/review-docx-plan/planning.html` is the actual command output.

1. Start with the [catalog and explicit selection recipe](REVIEW_DOCX_COMMENTS.md).
   Give each selected comment a stable item key, a curator note, a known agenda
   author, a discussion kind and any proposed named-human decision requests.
2. Generate a `plan-packet` from the original agenda, exact DOCX and that recipe.
   The recipe's digest must match the complete original DOCX archive.
3. Use **What is each reviewer being asked?** to jump to an item. Read every
   associated request together, then follow **Read anchored passage** to the
   Word text. The original comment card links back to the proposed item.
4. Edit the input agenda or recipe and regenerate the packet. Item order is the
   same as import: existing agenda items first, selected comments in recipe
   order. Existing item bodies and references stay intact; no Word anchor is
   inferred for them. Selected items show the curator note separately from the
   linked original comment, author metadata and source passage.
5. When the preparation is ready, pass those **same three files** through the
   existing importer with an absolute path to your trusted native composer:

```sh
python -B tools/review_docx/review_docx.py agenda examples/review-docx-plan/agenda.json examples/review-docx/launch.docx examples/review-docx-plan/selections.json --composer "$COMPOSER" > imported-agenda.json
python -B tools/review_docx/review_docx.py bundle examples/review-docx-plan/agenda.json examples/review-docx/launch.docx examples/review-docx-plan/selections.json --composer "$COMPOSER" > review.json
```

The native composer remains required for both of those outputs. A planning page
that rendered successfully can still fail native validation. For example, the
page may display a planner-provided time or a draft with no decision requests;
it does not establish a valid timestamp, portable reference, review identity or
complete required-decision set. A requestless draft is explicitly described as
incomplete preparation, never completed review. No native composer was run for
this delivery's new planning checks.

## What is bound and what is shown

The header retains the DOCX archive and parsed-part SHA-256 values. The plan
section retains the SHA-256 of the exact **input agenda bytes** and **selection
recipe bytes**, plus their declared review/conversation IDs, source reference,
revision and time. Reformatting either JSON input changes its displayed digest.
These hashes identify snapshots; they do not authenticate the planner or people.

The mode uses the existing `import_comments` function to construct the same
candidate as the authoring workflow. It checks the readable agenda shape,
unique participant/item identities, explicit item kinds, existing authors and
named-human decision assignments. It does not duplicate native MoonChat's
validator or create a new wire schema. Only the reading projection is new.

- The participant roster includes human and agent kinds. Reviewer navigation
  groups by participant ID, so equal display names never combine assignments.
- Every proposed decision on an item is retained. An item without a request
  remains discussion; it does not imply approval.
- Every original Word comment remains in reference order, including comments
  omitted from the selection plan. Omission is explicitly not resolution.
- All logical source text is present once in the source panel. Comments link to
  exact zero-based Unicode-code-point offsets, using the existing overlap,
  empty-range and point-anchor handling. No surrounding text is silently quoted
  for a point anchor.
- Quote previews are limited to 2,000 characters with explicit omission counts.
  Curator notes, existing item bodies and proposed prompts are not truncated.
  The import candidate still receives the full selected passage as evidence.
- HTML is escaped, script-free and self-contained. Only internal fragment links
  are generated. Evidence references are literal text and never fetched. The
  existing responsive/print styles apply; browser Find remains available.

Keep the three original inputs with the page. It is a readable planning view,
not an importable bundle or immutable review evidence. Once an imported agenda
has been edited, use the existing authoring workflow against the exact DOCX;
this command takes the **pre-import** agenda and original selection recipe, not
an already-imported agenda. Duplicate item keys are rejected rather than
creating a second copy or guessing which edited body came from Word. The mode
does not refresh an imported agenda or transfer earlier decisions across source
revisions. Use the normal explicit predecessor workflow for retained reviews.

## Bounds, failures and verification

The [existing classic-DOCX subset and input limits](REVIEW_DOCX_COMMENTS.md) apply:
16 MiB archive, 4 MiB per parsed part and each JSON input, 1,048,576 logical source
characters, 1–1,000 comments, 1–100 selections, and 16 MiB imported evidence.
Unselected ranges use bounded quote previews; only selected ranges materialize
their complete imported evidence. The entire HTML packet is capped at 32 MiB.
Processing remains local and in memory; no files are extracted or rewritten.

The command emits stdout only after the full packet has been checked and
rendered. Invalid input exits 1 with a stderr diagnostic and no partial stdout.
Redirect only to a **new** output path: the shell truncates a destination before
the program reads its inputs. There is no network, authentication, automatic
build, dependency installation, browser launch or implicit composer invocation.

```sh
PYTHONDONTWRITEBYTECODE=1 python -B -m unittest discover -s tools/review_docx -p 'test_*.py' -v
```

Focused tests exercise actual CLI generation, deterministic output, input
preservation, exact snapshot hashes, source/comment/plan navigation, partial
selection with retained dissent, multiple named reviewers, duplicate display
names, requestless drafts, reordered and edited notes, inert authored content,
long passages and the ordinary importer continuation. Existing importer,
reading-packet and comparison regressions also run. These are Python/HTML-model
checks. Native MoonBit compilation/execution, real browser and Word rendering,
accessibility devices, human decisions and receiving-product integration remain
unqualified. R50 remains last fully verified cumulative; R51–55 remain separate.
