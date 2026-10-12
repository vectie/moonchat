"""Editorial draft/edit/apply journeys through the actual existing intake CLI."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import review_docx as d
import review_docx_replan as r
import review_docx_plan as p
from test_review_docx import archive, parts, DOC, COMMENTS, agenda, plan
from test_review_docx_compare import revised
from test_review_docx_plan import PlanHTML


def encoded(value):
    return json.dumps(value, ensure_ascii=False, indent=2).encode('utf-8')


class ReplanTests(unittest.TestCase):
    def setUp(self):
        self.before, self.after = archive(), revised()
        self.agenda = agenda()
        self.agenda.update(source_artifact_ref='retained/launch-draft-2.docx', source_revision_id='draft-2')
        self.plan = plan(self.before)
        self.inputs = (encoded(self.agenda), self.before, self.after, encoded(self.plan))

    def completed(self):
        recipe = r.draft_replan(*self.inputs)
        recipe['selections'][0].update(action='keep', reason='Re-read the new rollout and keep the rehearsal request.')
        recipe['selections'][1].update(action='remap', comment_id='23', reason='I checked that this renumbered support comment is the intended context.')
        recipe['selections'][2].update(action='drop', comment_id=None, reason='Keep the agent words in the source packet, without a planned question.')
        return recipe

    def test_draft_covers_changed_removed_and_unchanged_without_suggesting_approval(self):
        draft = r.draft_replan(*self.inputs)
        self.assertEqual([x['status'] for x in draft['selections']], ['changed', 'removed', 'unchanged'])
        self.assertEqual([x['action'] for x in draft['selections']], ['review'] * 3)
        self.assertEqual(draft['selections'][0]['changed_fields'], ['text', 'quote_digest'])
        self.assertEqual(draft['new_comment_ids'], ['23'])
        for field, value in [('agenda_digest', self.inputs[0]), ('previous_document_digest', self.before),
                             ('document_digest', self.after), ('previous_plan_digest', self.inputs[3])]:
            self.assertEqual(draft[field], d.digest(value))

    def test_keep_remap_drop_outputs_consumable_plan_and_retains_prompts_notes_keys(self):
        recipe = self.completed()
        result = r.apply_replan(*self.inputs, encoded(recipe))
        self.assertEqual(set(result), {'format', 'document_digest', 'comments'})
        self.assertEqual(result['document_digest'], d.digest(self.after))
        expected = copy.deepcopy(self.plan['comments'][:2]); expected[1]['comment_id'] = '23'
        self.assertEqual(result['comments'], expected)
        candidate = d.import_comments(self.agenda, result, d.catalog_docx(self.after))
        self.assertIn('Rehearse before the larger rollout.', candidate['items'][1]['body'])
        self.assertIn('Roll out to 25%', candidate['items'][1]['body'])
        self.assertIn(d.digest(self.after), candidate['items'][1]['body'])
        self.assertNotIn(d.digest(self.before), candidate['items'][1]['body'])
        self.assertEqual(candidate['items'][1]['decisions'], self.plan['comments'][0]['decisions'])
        self.assertNotIn('receipts', candidate)
        parsed = PlanHTML(p.planning_packet(self.inputs[0], self.after, encoded(result)))
        self.assertIn('I approve everything.', parsed.comments)
        self.assertEqual(len(parsed.comments), 3)
        self.assertEqual(len(parsed.notes), 3)

    def test_add_new_discussion_and_explicitly_reorder_retained_items(self):
        recipe = self.completed()
        recipe['selections'].reverse()
        addition = copy.deepcopy(self.plan['comments'][2]); addition.update(key='agent-context', note='Read this as agent evidence, never as a human choice.')
        recipe['additions'].append(addition)
        result = r.apply_replan(*self.inputs, encoded(recipe))
        self.assertEqual([x['key'] for x in result['comments']], ['support', 'rollback', 'agent-context'])
        self.assertEqual(result['comments'][-1]['decisions'], [])
        result['comments'][0]['decisions'][0]['prompt'] = 'Changed output'
        self.assertEqual(recipe['additions'][0], addition)
        self.assertEqual(self.plan['comments'][1]['decisions'][0]['prompt'], 'Is coverage assigned?')

    def test_unchanged_and_archive_only_saves_still_require_editorial_choices(self):
        members = parts(); members['custom/save.txt'] = 'Repackaged'
        for after in (self.before, archive(members)):
            inputs = (self.inputs[0], self.before, after, self.inputs[3])
            draft = r.draft_replan(*inputs)
            self.assertEqual([x['status'] for x in draft['selections']], ['unchanged'] * 3)
            with self.assertRaisesRegex(d.IntakeError, 'explicit'):
                r.apply_replan(*inputs, encoded(draft))
            for row in draft['selections']:
                row.update(action='keep', reason='I reviewed this scope and want the same proposed request.')
            self.assertEqual(r.apply_replan(*inputs, encoded(draft))['document_digest'], d.digest(after))

    def test_a_source_or_plan_or_agenda_edit_requires_fresh_transition_draft(self):
        recipe = encoded(self.completed())
        alternate = archive(parts(document=DOC.replace('10%', '50%')))
        for inputs in ((self.inputs[0], self.before, alternate, self.inputs[3]),
                       (self.inputs[0] + b'\n', self.before, self.after, self.inputs[3]),
                       (*self.inputs[:3], self.inputs[3] + b'\n')):
            with self.assertRaisesRegex(d.IntakeError, 'snapshot'):
                r.apply_replan(*inputs, recipe)
        with self.assertRaisesRegex(d.IntakeError, 'digest'):
            r.draft_replan(self.inputs[0], alternate, self.after, self.inputs[3])

    def test_removed_comment_requires_remap_or_drop_not_an_implicit_same_id_match(self):
        recipe = self.completed()
        recipe['selections'][1].update(action='keep', comment_id='2')
        with self.assertRaisesRegex(d.IntakeError, 'unknown'):
            r.apply_replan(*self.inputs, encoded(recipe))
        recipe['selections'][1].update(action='remap', comment_id='7')
        with self.assertRaisesRegex(d.IntakeError, 'repeated'):
            r.apply_replan(*self.inputs, encoded(recipe))

    def test_each_old_selection_needs_a_recorded_disposition_and_reason(self):
        missing = self.completed(); missing['selections'].pop()
        unresolved = self.completed(); unresolved['selections'][0]['action'] = 'review'
        no_reason = self.completed(); no_reason['selections'][0]['reason'] = ' '
        duplicate = self.completed(); duplicate['selections'][1] = copy.deepcopy(duplicate['selections'][0])
        for recipe in (missing, unresolved, no_reason, duplicate):
            with self.assertRaises(d.IntakeError):
                r.apply_replan(*self.inputs, encoded(recipe))

    def test_dropping_every_selection_does_not_create_an_empty_completed_review(self):
        recipe = self.completed()
        for row in recipe['selections']:
            row.update(action='drop', comment_id=None, reason='Start a different review separately.')
        with self.assertRaisesRegex(d.IntakeError, 'select 1'):
            r.apply_replan(*self.inputs, encoded(recipe))

    def test_new_requests_use_existing_roster_and_cannot_reuse_a_dropped_key(self):
        recipe = self.completed()
        addition = copy.deepcopy(self.plan['comments'][2])
        recipe['additions'] = [addition]
        with self.assertRaisesRegex(d.IntakeError, 'new item keys'):
            r.apply_replan(*self.inputs, encoded(recipe))
        addition['key'] = 'new-question'
        addition['decisions'] = [{'reviewer': 'notes', 'prompt': 'Approve?'}]
        with self.assertRaisesRegex(d.IntakeError, 'human'):
            r.apply_replan(*self.inputs, encoded(recipe))

    def test_changed_passage_beyond_excerpt_is_flagged_and_fully_imported(self):
        before = archive(parts(document=DOC.replace('10%', '界' * 2500 + 'A')))
        after = archive(parts(document=DOC.replace('10%', '界' * 2500 + 'B')))
        inputs = (self.inputs[0], before, after, encoded(plan(before)))
        draft = r.draft_replan(*inputs)
        self.assertIn('quote_digest', draft['selections'][0]['changed_fields'])
        for row in draft['selections']:
            row.update(action='keep', reason='Read full revised source before carrying the request.')
        result = r.apply_replan(*inputs, encoded(draft))
        candidate = d.import_comments(self.agenda, result, d.catalog_docx(after))
        self.assertIn('界' * 2500 + 'B', candidate['items'][1]['body'])

    def test_actual_cli_draft_edit_apply_packet_roundtrip_is_deterministic_and_preserves_inputs(self):
        script = Path(d.__file__).resolve()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = [root / name for name in ('agenda.json', 'before.docx', 'after.docx', 'old-plan.json')]
            for path, data in zip(paths, self.inputs): path.write_bytes(data)
            def run(mode, arguments):
                return subprocess.run([sys.executable, '-B', str(script), mode, *map(str, arguments)], capture_output=True)
            drafted = run('replan-draft', paths)
            self.assertEqual(drafted.returncode, 0, drafted.stderr)
            self.assertEqual(drafted.stdout, run('replan-draft', paths).stdout)
            recipe_path = root / 'recipe.json'; recipe_path.write_bytes(encoded(self.completed()))
            output = run('replan', [*paths, recipe_path])
            self.assertEqual(output.returncode, 0, output.stderr)
            self.assertEqual(output.stdout, run('replan', [*paths, recipe_path]).stdout)
            result_path = root / 'new-plan.json'; result_path.write_bytes(output.stdout)
            packet = run('plan-packet', [paths[0], paths[2], result_path])
            self.assertEqual(packet.returncode, 0, packet.stderr)
            self.assertIn(b'Rehearse before the larger rollout.', packet.stdout)
            self.assertIn(b'I approve everything.', packet.stdout)
            self.assertIn(b'not a validated review', packet.stdout)
            for path, original in zip(paths, self.inputs): self.assertEqual(path.read_bytes(), original)
            recipe_path.write_bytes(drafted.stdout)
            failure = run('replan', [*paths, recipe_path])
            self.assertEqual(failure.returncode, 1)
            self.assertEqual(failure.stdout, b'')
            self.assertIn(b'explicit', failure.stderr)
            self.assertEqual(result_path.read_bytes(), output.stdout)

    def test_retained_examples_reproduce_through_actual_cli(self):
        repo = Path(d.__file__).resolve().parents[2]
        example = repo / 'examples/review-docx-replan'
        shared = repo / 'examples/review-docx-comparison'
        inputs = [example / 'agenda.json', shared / 'before.docx', shared / 'after.docx',
                  repo / 'examples/review-docx/selections.json']
        for mode, args, output in [('replan-draft', inputs, 'draft.json'),
                                  ('replan', [*inputs, example / 'choices.json'], 'selections.json'),
                                  ('plan-packet', [inputs[0], inputs[2], example / 'selections.json'], 'planning.html')]:
            run = subprocess.run([sys.executable, '-B', str(repo / 'tools/review_docx/review_docx.py'), mode, *map(str, args)], capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout, (example / output).read_bytes())


if __name__ == '__main__':
    unittest.main()
