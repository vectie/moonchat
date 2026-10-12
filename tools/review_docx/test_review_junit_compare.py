"""Functional comparison-to-agenda workflow, without a native composer substitute."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import review_junit as j
import review_junit_compare as c
from review_docx_plan import check_shape

ROOT = Path(__file__).resolve().parents[2]
EX = ROOT / 'examples/review-junit-comparison'
CLI = ROOT / 'tools/review_docx/review_junit.py'


def encoded(value):
    return json.dumps(value, ensure_ascii=False).encode('utf-8')


def report(body):
    return ('<testsuite name="suite">' + body + '</testsuite>').encode('utf-8')


class JUnitComparisonTests(unittest.TestCase):
    def setUp(self):
        self.inputs = {name: (EX / filename).read_bytes() for name, filename in
                       [('agenda', 'agenda.json'), ('source', 'source.md'),
                        ('before', 'before.xml'), ('after', 'after.xml'), ('plan', 'selections.json')]}

    def make(self, **changes):
        inputs = {**self.inputs, **changes}
        return c.comparison_draft(*(inputs[name] for name in ('agenda', 'source', 'before', 'after', 'plan')))

    def comparison(self):
        return c.compare_reports(self.inputs['before'], self.inputs['after'])

    def test_report_changes_keep_absent_dissent_and_all_statuses(self):
        result = self.comparison()
        self.assertEqual(result['counts'], {'added': 1, 'absent': 1, 'changed': 2, 'unchanged': 1, 'ambiguous': 1})
        rows = result['rows']
        self.assertEqual(rows[0]['outcome_change'], 'failure-or-error-no-longer-reported')
        self.assertEqual(rows[0]['after_cases'][0]['status'], 'no-failure-reported')
        self.assertEqual(rows[1]['outcome_change'], 'new-failure-or-error-reported')
        self.assertEqual(rows[1]['before_cases'][0]['status'], 'skipped')
        self.assertEqual(rows[2]['before_cases'][0]['status'], 'error')
        self.assertEqual(rows[2]['after_cases'], [])
        self.assertEqual(rows[5]['after_cases'][0]['status'], 'error')
        self.assertEqual(result['before_case_count'], 6)
        self.assertEqual(result['after_case_count'], 6)  # Ignores fictional aggregate attributes.
        self.assertIn('not a proven pass', result['qualification'])

    def test_duplicate_case_identity_is_never_paired_by_occurrence(self):
        row = self.comparison()['rows'][4]
        self.assertEqual(row['change'], 'ambiguous')
        self.assertEqual(row['outcome_change'], 'not-comparable')
        self.assertEqual([v['status'] for v in row['before_cases']], ['failure', 'no-failure-reported'])
        self.assertEqual([v['status'] for v in row['after_cases']], ['no-failure-reported', 'error'])
        self.assertEqual(row['changed_fields'], [])

    def test_same_name_in_distinct_suite_paths_or_classes_stays_separate(self):
        before = report('<testcase classname="A" name="x"/><testsuite name="inner"><testcase classname="A" name="x"/></testsuite><testcase classname="B" name="x"/>')
        after = report('<testcase classname="B" name="x"/><testsuite name="inner"><testcase classname="A" name="x"/></testsuite><testcase classname="A" name="x"/>')
        result = c.compare_reports(before, after)
        self.assertEqual(result['counts']['unchanged'], 3)
        self.assertEqual(result['counts']['ambiguous'], 0)
        self.assertEqual(result['rows'][0]['after_cases'][0]['index'], 2)

    def test_empty_report_and_blank_or_duplicated_new_names(self):
        empty = report('')
        self.assertEqual(c.compare_reports(empty, empty)['rows'], [])
        result = c.compare_reports(empty, report('<testcase/><testcase name="r"/><testcase name="r"/>'))
        self.assertEqual(result['counts']['ambiguous'], 2)
        self.assertTrue(all(r['presence'] == 'after-only' for r in result['rows']))
        removed = c.compare_reports(self.inputs['before'], empty)
        self.assertEqual(removed['counts']['absent'], 4)
        self.assertEqual(removed['counts']['ambiguous'], 1)
        self.assertTrue(all(r['outcome_change'] == 'not-comparable' for r in removed['rows']))

    def test_evidence_changes_without_status_changes_are_visible(self):
        before = report('<testcase name="x" time="1"><failure message="one"/><system-out>old</system-out></testcase>')
        after = report('<testcase name="x" time="2"><failure message="two"/><system-out>new</system-out></testcase>')
        row = c.compare_reports(before, after)['rows'][0]
        self.assertEqual(row['change'], 'changed')
        self.assertEqual(row['outcome_change'], 'same-reported-status')
        self.assertEqual(row['changed_fields'], ['time_reported', 'signals', 'system_out'])
        error = report('<testcase name="x"><error>setup</error><failure>assertion</failure><skipped>partial</skipped></testcase>')
        row = c.compare_reports(before, error)['rows'][0]
        self.assertEqual(row['outcome_change'], 'reported-status-changed')
        self.assertEqual([s['kind'] for s in row['after_cases'][0]['signals']], ['error', 'failure', 'skipped'])

    def test_draft_keeps_prior_items_selection_order_and_two_report_attributions(self):
        result = self.make()
        original = json.loads(self.inputs['agenda'])
        self.assertEqual(result['items'][0], original['items'][0])
        self.assertEqual([i['key'] for i in result['items']],
                         ['release-scope', 'backup-change', 'absent-check', 'ambiguous-retry', 'invoice-evidence'])
        for item in result['items'][1:]:
            self.assertEqual(item['evidence_refs'], ['examples/review-junit-comparison/before.xml',
                                                   'examples/review-junit-comparison/after.xml'])
            body = item['body']
            for name in ('source', 'before', 'after'):
                self.assertIn(j.digest(self.inputs[name]), body)
            evidence = json.loads(body.split('JUnit comparison evidence (report claims, not human decisions):\n')[1])
            self.assertEqual(evidence['source_revision_id'], original['source_revision_id'])
            self.assertEqual(evidence['row'], self.comparison()['rows'][evidence['row']['index']])
        self.assertEqual(result['participants'], original['participants'])
        self.assertNotIn('receipts', result)
        check_shape(result)  # Existing preparation integration; not native validation.
        result['items'][1]['decisions'][0]['prompt'] = 'Edited follow-up question'
        check_shape(result)

    def test_changed_source_or_either_report_needs_fresh_selection(self):
        for name in ('source', 'before', 'after'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'digest changed'):
                self.make(**{name: self.inputs[name] + b'\n'})

    def test_request_authority_duplicate_import_and_selection_identity(self):
        result = self.make()
        with self.assertRaisesRegex(ValueError, 'unique'):
            self.make(agenda=encoded(result))
        plan = json.loads(self.inputs['plan'])
        plan['rows'][0]['decisions'][0]['reviewer'] = 'assistant'
        with self.assertRaisesRegex(ValueError, 'existing humans'):
            self.make(plan=encoded(plan))
        plan = json.loads(self.inputs['plan'])
        plan['rows'].append(copy.deepcopy(plan['rows'][0]))
        with self.assertRaisesRegex(ValueError, 'index missing or repeated'):
            self.make(plan=encoded(plan))
        plan = json.loads(self.inputs['plan'])
        plan['before_report_ref'] = plan['after_report_ref']
        with self.assertRaisesRegex(ValueError, 'distinct references'):
            self.make(plan=encoded(plan))

    def test_existing_parser_subset_and_limits_still_apply(self):
        for raw in [b'<testsuite xmlns="urn:vendor"/>', b'<!DOCTYPE x><testsuite/>', b'x' * (j.LIMIT + 1)]:
            with self.subTest(raw=raw[:30]), self.assertRaises(ValueError):
                c.compare_reports(raw, self.inputs['after'])
        with self.assertRaisesRegex(ValueError, '2 MiB'):
            self.make(plan=b' ' * (j.LIMIT + 1))
        with self.assertRaisesRegex(ValueError, '8 MiB'):
            self.make(source=b'x' * (c.MAX_DRAFT + 1))
        shared_path = ('<testsuite name="' + 'n' * 450000 + '">' +
                       ''.join('<testcase name="case' + str(n) + '"/>' for n in range(20)) +
                       '</testsuite>').encode()
        with self.assertRaisesRegex(ValueError, '16 MiB'):
            c.compare_reports(shared_path, shared_path)

    def test_actual_cli_compare_select_draft_reopen_and_input_preservation(self):
        original = {p: p.read_bytes() for p in EX.iterdir() if p.is_file()}
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary)
            output = temp / 'comparison.json'
            command = [sys.executable, '-B', str(CLI), '--output', str(output), 'compare', str(EX / 'before.xml'), str(EX / 'after.xml')]
            run = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            compared = json.loads(output.read_bytes())
            self.assertEqual(compared, self.comparison())
            # A curator can select one observed change, then feed the emitted comparison index onward.
            plan = json.loads(self.inputs['plan'])
            plan['rows'] = [plan['rows'][0]]
            plan['rows'][0]['index'] = next(r['index'] for r in compared['rows'] if r['identity']['name'] == 'restore')
            selection = temp / 'selected.json'
            selection.write_bytes(encoded(plan))
            draft = temp / 'draft.json'
            args = [sys.executable, '-B', str(CLI), '--output', str(draft), 'comparison-draft',
                    str(EX / 'agenda.json'), str(EX / 'source.md'), str(EX / 'before.xml'), str(EX / 'after.xml'), str(selection)]
            run = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(draft.read_bytes()), self.make(plan=encoded(plan)))
            self.assertEqual(json.loads(run.stdout)['receipts_created'], 0)
            saved = draft.read_bytes()
            rerun = subprocess.run(args, capture_output=True)
            self.assertEqual(rerun.returncode, 2)
            self.assertEqual(draft.read_bytes(), saved)
        self.assertEqual(original, {p: p.read_bytes() for p in original})

    def test_invalid_late_selection_does_not_create_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary)
            plan = json.loads(self.inputs['plan'])
            plan['rows'][-1]['index'] = 999
            selection, output = temp / 'bad.json', temp / 'out.json'
            selection.write_bytes(encoded(plan))
            run = subprocess.run([sys.executable, '-B', str(CLI), '--output', str(output), 'comparison-draft',
                                  str(EX / 'agenda.json'), str(EX / 'source.md'), str(EX / 'before.xml'),
                                  str(EX / 'after.xml'), str(selection)], capture_output=True)
            self.assertEqual(run.returncode, 2)
            self.assertFalse(output.exists())
            self.assertEqual(run.stdout, b'')

    def test_retained_examples_are_deterministic_actual_outputs(self):
        for path, result in [('comparison.json', self.comparison()), ('imported-agenda.json', self.make())]:
            self.assertEqual((EX / path).read_bytes(), (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))


if __name__ == '__main__':
    unittest.main()
