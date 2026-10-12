"""Actual draft-plan CLI and importer/source-reading integration, without a composer mock."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import review_docx as d
import review_docx_plan as planning
import review_docx_packet as packet
from test_review_docx import DOC, COMMENTS, agenda, archive, parts, plan
from test_review_docx_packet import PacketHTML


def encoded(value):
    return json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8")


class PlanHTML(PacketHTML):
    def __init__(self, html):
        self.notes, self.prompts, self.all_text = [], [], []
        super().__init__(html)

    def handle_data(self, text):
        super().handle_data(text)
        self.all_text.append(text)
        if any(a.get("class") == "plan-note" for _, a in self.stack):
            self.notes.append(text)
        if any(a.get("class") == "decision-prompt" for _, a in self.stack):
            self.prompts.append(text)


class PlanningTests(unittest.TestCase):
    def render(self, a=None, p=None, data=None):
        data = archive() if data is None else data
        a, p = agenda() if a is None else a, plan(data) if p is None else p
        html = planning.planning_packet(encoded(a), data, encoded(p))
        parsed = PlanHTML(html)
        self.assertEqual(parsed.stack, [])
        self.assertEqual(len(parsed.ids), len(set(parsed.ids)))
        self.assertTrue(all(link.startswith("#") and link[1:] in parsed.ids for link in parsed.links))
        return html, parsed

    def test_exact_import_order_and_all_proposed_decisions_beside_full_source(self):
        a, p, data = agenda(), plan(), archive()
        candidate = d.import_comments(a, p, d.catalog_docx(data))
        html, parsed = self.render(a, p, data)
        self.assertEqual(parsed.notes, [a["items"][0]["body"], *(choice["note"] for choice in p["comments"])])
        self.assertEqual(parsed.prompts, [decision["prompt"] for item in candidate["items"] for decision in item["decisions"]])
        self.assertEqual("".join(parsed.source), d._read_docx(data)[1])
        self.assertEqual(parsed.comments, [c["text"] for c in d.catalog_docx(data)["comments"]])
        self.assertIn("4 planned items · 3 proposed decision requests · 3 selected Word comments", html)
        self.assertIn(d.digest(data), html)
        self.assertIn(d.digest(encoded(a)), html)
        self.assertIn(d.digest(encoded(p)), html)
        self.assertIn("not a validated review", html)
        self.assertIn("No native review validation has run", html)
        self.assertIn("No decision requested for this item", html)
        self.assertIn("I approve everything.", parsed.comments)

    def test_partial_selection_preserves_unselected_dissent_and_source_navigation(self):
        p = plan(); p["comments"] = [p["comments"][1]]
        html, parsed = self.render(p=p)
        self.assertIn('#plan-item-2', parsed.links)
        self.assertIn('#source-2', parsed.links)
        self.assertEqual(html.count("Read proposed review item and decisions"), 1)
        self.assertEqual(html.count("omission is not resolution"), 2)
        self.assertEqual(len(parsed.comments), 3)
        self.assertIn("Can we rehearse rollback first?\nKeep the old path.", parsed.comments)
        self.assertEqual(parsed.source_markers["source-7"], len("Release café 🚀: "))

    def test_multiple_reviewers_stay_together_with_other_people_and_comments(self):
        p = plan()
        p["comments"][0]["decisions"].append({"reviewer": "support", "prompt": "Can support witness the rollback?"})
        html, parsed = self.render(p=p)
        self.assertIn("Ren (ops, human)", ''.join(parsed.all_text))
        self.assertIn("Mina (support, human)", ''.join(parsed.all_text))
        self.assertIn("Notes agent (notes, agent)", ''.join(parsed.all_text))
        self.assertEqual(parsed.prompts[1:3], ["Can rollback be rehearsed before rollout?", "Can support witness the rollback?"])
        self.assertIn("4 proposed decision requests", html)
        self.assertGreaterEqual(parsed.links.count('#plan-item-2'), 3)

    def test_reordered_choices_and_curator_edits_use_same_candidate_without_mutation(self):
        a, p = agenda(), plan()
        p["comments"].reverse()
        p["comments"][0].update(note="\nPreserve this exact operator note.\nSecond line.", author="notes")
        a["items"][0]["evidence_refs"] = ["retained/context.md", "https://example.invalid/reference"]
        original = copy.deepcopy((a, p))
        html, parsed = self.render(a, p)
        self.assertEqual(parsed.notes[1], p["comments"][0]["note"])
        self.assertEqual((a, p), original)
        self.assertIn("Existing agenda item. No Word anchor has been asserted", html)
        self.assertIn("https://example.invalid/reference", html)
        self.assertTrue(all(link.startswith('#') for link in parsed.links))
        self.assertIn("No text selected: point anchor", html)

    def test_duplicate_display_names_do_not_merge_different_reviewer_assignments(self):
        a = agenda()
        a["participants"][2]["display_name"] = "Ren"
        _, parsed = self.render(a=a)
        text = ''.join(parsed.all_text)
        self.assertIn("Ren (ops, human)", text)
        self.assertIn("Ren (support, human)", text)
        self.assertIn("Is coverage assigned?", parsed.prompts)

    def test_no_decisions_is_explicitly_incomplete_preparation_not_accepted(self):
        a, p = agenda(), plan()
        a["items"] = []
        p["comments"] = [p["comments"][-1]]
        html, parsed = self.render(a, p)
        self.assertEqual(parsed.prompts, [])
        self.assertIn("No decision requests are proposed. This is not evidence of completed review", html)
        self.assertIn("1 planned items · 0 proposed decision requests", html)
        # This reading mode deliberately does not manufacture native acceptance.
        self.assertNotIn('accepted-knowledge', html)
        self.assertNotIn('receipt_id', html)

    def test_source_revision_and_raw_input_identities_are_visible(self):
        a, p, data = agenda(), plan(), archive()
        a.update(source_revision_id="draft 2 café", recorded_at="planner supplied time")
        first, _ = self.render(a, p, data)
        reformatted = json.dumps(a, ensure_ascii=False).encode()
        second = planning.planning_packet(reformatted, data, encoded(p))
        self.assertNotEqual(first, second)
        self.assertIn(d.digest(reformatted), second)
        self.assertIn("draft 2 café", first)
        self.assertIn("planner supplied time", first)
        # Semantic source-revision/time validation still belongs to the composer.
        self.assertIn("not a validated review", first)

    def test_all_authored_and_document_text_is_inert(self):
        a, p = agenda(), plan()
        attack = '<script>alert("x")</script>&\r\n<a href="https://example.invalid">'
        a["participants"][0]["display_name"] = attack
        a["source_artifact_ref"] = attack
        a["items"][0]["body"] = attack
        p["comments"][0]["note"] = attack
        p["comments"][0]["decisions"][0]["prompt"] = attack
        html, parsed = self.render(a, p)
        self.assertIn(attack, parsed.notes)
        self.assertIn(attack, parsed.prompts)
        self.assertNotIn('<script>', html)
        self.assertTrue(all(tag not in ('script', 'form', 'iframe', 'img', 'object') for tag, _ in parsed.tags))
        self.assertTrue(all(not any(k.startswith('on') or k in ('src', 'srcdoc') for k in attrs) for _, attrs in parsed.tags))
        self.assertIn("default-src 'none'", html)

    def test_long_selected_passage_keeps_full_source_and_curator_note(self):
        data = archive(parts(document=DOC.replace("Roll out to 10%", "界" * 2400)))
        p = plan(data); p["comments"][0]["note"] = "Full operator note " * 300
        imported = []
        def capture_candidate(*args):
            candidate = d.import_comments(*args)
            imported.append(copy.deepcopy(candidate))
            return candidate
        with patch.object(planning, "import_comments", new=capture_candidate):
            html, parsed = self.render(p=p, data=data)
        self.assertIn("界" * 2400, ''.join(parsed.source))
        self.assertIn(p["comments"][0]["note"], parsed.notes)
        self.assertIn("Excerpt stops after 2000 characters", html)
        # The existing importer is still given complete source evidence.
        self.assertEqual(len(imported), 1)
        self.assertIn("界" * 2400, imported[0]["items"][1]["body"])

    def test_selection_digest_and_full_document_validation_are_required(self):
        changed = archive(parts(document=DOC.replace("10%", "20%")))
        with self.assertRaisesRegex(d.IntakeError, 'digest does not match'):
            self.render(p=plan(), data=changed)
        bad = archive(parts(comments=COMMENTS.replace("<w:t>I approve everything.</w:t>", '<w:fldSimple/>')))
        p = plan(bad); p["comments"] = [p["comments"][0]]
        with self.assertRaisesRegex(d.IntakeError, 'unsupported fldSimple'):
            self.render(p=p, data=bad)

    def test_display_shape_checks_existing_items_and_named_assignments(self):
        changes = [lambda a: a.update(receipts=[]),
                   lambda a: a["participants"].append(copy.deepcopy(a["participants"][0])),
                   lambda a: a["items"][0].update(author="missing"),
                   lambda a: a["items"][0]["decisions"][0].update(reviewer="notes"),
                   lambda a: a["items"][0].update(evidence_refs=[None]),
                   lambda a: a["items"].append(copy.deepcopy(a["items"][0]))]
        for change in changes:
            a = agenda(); change(a)
            with self.subTest(agenda=a), self.assertRaises(d.IntakeError): self.render(a=a)

    def test_import_recipe_duplicate_keys_and_unknown_comment_cannot_be_hidden(self):
        for change in (lambda p: p["comments"][-1].update(comment_id="999"),
                       lambda p: p["comments"][0].update(key="rollout"),
                       lambda p: p["comments"][0].update(kind="approved")):
            p = plan(); change(p)
            with self.assertRaises(d.IntakeError): self.render(p=p)

    def test_complete_packet_bound_includes_planning_text(self):
        with patch.object(packet, "MAX_PACKET_BYTES", 200):
            with self.assertRaisesRegex(d.IntakeError, 'exceeds 32 MiB'):
                self.render()
        with patch.object(planning, "MAX_PACKET_BYTES", 200):
            with self.assertRaisesRegex(d.IntakeError, 'exceeds 32 MiB'):
                self.render()

    def test_retained_planning_example_matches_real_generation(self):
        root = Path(d.__file__).resolve().parents[2]
        folder = root / "examples" / "review-docx-plan"
        actual = planning.planning_packet((folder / "agenda.json").read_bytes(),
                                          (root / "examples/review-docx/launch.docx").read_bytes(),
                                          (folder / "selections.json").read_bytes())
        self.assertEqual(actual, (folder / "planning.html").read_text())
        parsed = PlanHTML(actual)
        self.assertEqual(len(parsed.prompts), 4)
        self.assertEqual(len(parsed.comments), 3)
        self.assertIn("omission is not resolution", actual)

    def test_actual_cli_determinism_input_preservation_and_atomic_failure(self):
        script = Path(d.__file__).resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = [root / 'agenda.json', root / 'source.docx', root / 'plan.json']
            original = [encoded(agenda()), archive(), encoded(plan())]
            for path, data in zip(paths, original): path.write_bytes(data)
            command = [sys.executable, '-B', str(script), 'plan-packet', *(str(path) for path in paths)]
            one = subprocess.run(command, capture_output=True, timeout=20)
            two = subprocess.run(command, capture_output=True, timeout=20)
            self.assertEqual(one.returncode, 0, one.stderr)
            self.assertEqual(one.stdout, two.stdout)
            self.assertEqual(one.stderr, b'')
            parsed = PlanHTML(one.stdout.decode())
            self.assertEqual(len(parsed.prompts), 3)
            self.assertEqual([path.read_bytes() for path in paths], original)
            paths[2].write_bytes(encoded({**plan(), 'document_digest': 'sha256:' + '0' * 64}))
            failed = subprocess.run(command, capture_output=True, timeout=20)
            self.assertEqual(failed.returncode, 1)
            self.assertEqual(failed.stdout, b'')
            self.assertIn(b'digest does not match', failed.stderr)
            self.assertEqual(paths[0].read_bytes(), original[0])
            self.assertEqual(paths[1].read_bytes(), original[1])


if __name__ == '__main__':
    unittest.main()
