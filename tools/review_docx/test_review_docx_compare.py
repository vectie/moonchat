"""Production DOCX revision comparison, including actual CLI journeys."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from html.parser import HTMLParser

import review_docx as d
import review_docx_compare as c
from test_review_docx import archive, parts, DOC, COMMENTS, agenda, plan


def revised():
    document = DOC.replace('10%', '25%').replace('w:id="2"', 'w:id="23"')
    comments = COMMENTS.replace('w:id="2"', 'w:id="23"').replace('Can we rehearse rollback first?', 'Rehearse before the larger rollout.')
    return archive(parts(document=document, comments=comments))


class ComparisonTests(unittest.TestCase):
    def test_real_revision_counts_identity_and_preserved_old_dissent(self):
        old, new = archive(), revised()
        report = c.compare_docx(old, new)
        self.assertEqual(report['counts'], dict(added=1, removed=1, changed=1, unchanged=1))
        self.assertEqual(report['before']['document_digest'], d.digest(old))
        self.assertEqual(report['after']['document_digest'], d.digest(new))
        first = report['changes'][0]
        self.assertEqual(first['comment_id'], '7')
        self.assertEqual(first['changed_fields'], ['text', 'quote_digest'])
        html = c.render_comparison(report)
        self.assertIn('Who handles support?', html)
        self.assertIn('absence is not resolution', html)
        self.assertIn('Can we rehearse rollback first?', html)
        self.assertIn('Rehearse before the larger rollout.', html)
        self.assertIn('not proof of thread continuity', html)

    def test_identical_and_archive_only_save(self):
        old = archive()
        report = c.compare_docx(old, old)
        self.assertFalse(report['archive_changed'])
        self.assertFalse(report['logical_text_changed'])
        self.assertEqual(report['counts']['unchanged'], 3)
        members = parts(); members['custom/uninterpreted.txt'] = 'save metadata'
        report = c.compare_docx(old, archive(members))
        self.assertTrue(report['archive_changed'])
        self.assertFalse(report['logical_text_changed'])
        self.assertEqual(report['counts']['unchanged'], 3)

    def test_source_change_outside_any_comment_is_visible(self):
        report = c.compare_docx(archive(), archive(parts(document=DOC.replace('End.', 'New final policy.'))))
        self.assertTrue(report['logical_text_changed'])
        self.assertIn('New final policy.', report['after']['logical_text'])
        self.assertEqual(report['changes'][2]['changed_fields'], ['start_offset', 'end_offset'])

    def test_passage_change_after_excerpt_limit(self):
        before_doc = DOC.replace('Roll out to 10%', 'x' * 3000 + 'A')
        after_doc = before_doc.replace('x' * 3000 + 'A', 'x' * 3000 + 'B')
        report = c.compare_docx(archive(parts(document=before_doc)), archive(parts(document=after_doc)))
        old, new = report['before']['comments'][0], report['after']['comments'][0]
        self.assertEqual(old['quote'], new['quote'])
        self.assertNotEqual(old['quote_digest'], new['quote_digest'])
        self.assertEqual(report['changes'][0]['changed_fields'], ['quote_digest'])
        self.assertEqual(old['quote_omitted_characters'], old['quote_characters'] - 2000)
        self.assertIn('Comparison uses the complete passage digest', c.render_comparison(report))

    def test_metadata_only_changes_and_renamed_id(self):
        report = c.compare_docx(archive(), archive(parts(comments=COMMENTS.replace('w:author="Ren"', 'w:author="Jules"'))))
        self.assertEqual(report['changes'][0]['changed_fields'], ['author'])
        report = c.compare_docx(archive(), archive(parts(document=DOC.replace('w:id="11"', 'w:id="12"'), comments=COMMENTS.replace('w:id="11"', 'w:id="12"'))))
        self.assertEqual([x['status'] for x in report['changes']], ['unchanged', 'unchanged', 'removed', 'added'])

    def test_reference_order_separate_from_field_changes(self):
        doc = DOC.replace('<w:r><w:commentReference w:id="7"/></w:r>', '')
        doc = doc.replace('<w:commentReference w:id="11"/>', '<w:commentReference w:id="11"/><w:commentReference w:id="7"/>')
        report = c.compare_docx(archive(), archive(parts(document=doc)))
        self.assertTrue(report['common_comment_order_changed'])
        self.assertEqual(report['counts']['unchanged'], 3)
        self.assertEqual([x['comment_id'] for x in report['after']['comments']], ['2', '11', '7'])

    def test_point_and_empty_ranges_keep_no_invented_quote(self):
        doc = DOC.replace('<w:commentRangeEnd w:id="7"/>', '').replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeStart w:id="7"/><w:commentRangeEnd w:id="7"/>')
        report = c.compare_docx(archive(), archive(parts(document=doc)))
        self.assertEqual(report['after']['comments'][0]['quote_characters'], 0)
        self.assertEqual(report['before']['comments'][2]['quote_characters'], 0)
        self.assertIn('No neighboring words are inferred', c.render_comparison(report))

    def test_inert_html_and_all_fragment_destinations(self):
        hostile = COMMENTS.replace('Who handles support?', '&lt;script&gt;alert(1)&lt;/script&gt; &amp; issue')
        report = c.compare_docx(archive(), archive(parts(comments=hostile)))
        html = c.render_comparison(report)
        self.assertIn('&lt;script&gt;alert(1)&lt;/script&gt;', html)
        class Inspector(HTMLParser):
            def __init__(self):
                super().__init__(); self.ids = []; self.links = []; self.tags = []
            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs); self.tags.append(tag)
                if 'id' in attrs: self.ids.append(attrs['id'])
                if 'href' in attrs: self.links.append(attrs['href'])
        parser = Inspector(); parser.feed(html)
        self.assertNotIn('script', parser.tags)
        self.assertEqual(len(parser.ids), len(set(parser.ids)))
        self.assertTrue(all(link.startswith('#') and link[1:] in parser.ids for link in parser.links))

    def test_deterministic_detached_report_and_bound(self):
        report = c.compare_docx(archive(), revised()); saved = copy.deepcopy(report)
        self.assertEqual(c.render_comparison(report), c.render_comparison(report))
        self.assertEqual(report, saved)
        with patch.object(c, 'MAX_COMPARISON_BYTES', 20):
            with self.assertRaises(d.IntakeError): c.render_comparison(report)

    def test_continues_into_existing_new_digest_selection_workflow(self):
        old, new = archive(), revised()
        p = plan(old)
        with self.assertRaises(d.IntakeError): d.import_comments(agenda(), p, d.catalog_docx(new))
        p['document_digest'] = c.compare_docx(old, new)['after']['document_digest']
        p['comments'][1]['comment_id'] = '23'
        candidate = d.import_comments(agenda(), p, d.catalog_docx(new))
        self.assertIn('Rehearse before the larger rollout', candidate['items'][1]['body'])
        self.assertIn(d.digest(new), candidate['items'][1]['body'])
        self.assertNotIn('receipts', candidate)
        # This is a candidate; native composer validation is deliberately not claimed.

    def test_actual_cli_json_html_and_input_immutability(self):
        cli = Path(__file__).with_name('review_docx.py')
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory)/'before.docx', Path(directory)/'after.docx'
            old.write_bytes(archive()); new.write_bytes(revised())
            snapshots = (old.read_bytes(), new.read_bytes())
            for mode in ('compare', 'compare-packet'):
                run = subprocess.run([sys.executable, '-B', str(cli), mode, str(old), str(new)], capture_output=True)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(run.stderr, b'')
                if mode == 'compare': self.assertEqual(json.loads(run.stdout)['counts']['removed'], 1)
                else: self.assertTrue(run.stdout.startswith(b'<!doctype html>'))
            self.assertEqual((old.read_bytes(), new.read_bytes()), snapshots)

    def test_actual_cli_rejects_either_bad_snapshot_without_partial_output(self):
        cli = Path(__file__).with_name('review_docx.py')
        with tempfile.TemporaryDirectory() as directory:
            good, bad = Path(directory)/'good.docx', Path(directory)/'bad.docx'
            good.write_bytes(archive()); bad.write_bytes(b'not a DOCX')
            for mode in ('compare', 'compare-packet'):
                for paths in ((good, bad), (bad, good)):
                    run = subprocess.run([sys.executable, '-B', str(cli), mode, *map(str, paths)], capture_output=True)
                    self.assertEqual(run.returncode, 1)
                    self.assertEqual(run.stdout, b'')
                    self.assertIn(b'review_docx: DOCX ZIP', run.stderr)
                    self.assertNotIn(b'Traceback', run.stderr)

if __name__ == '__main__': unittest.main()
