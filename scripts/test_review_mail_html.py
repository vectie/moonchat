"""Static saved-mail HTML intake, exact choices and real native consumer tests."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import review_mail_html as h
import review_mbox as m
import review_eml as e

ROOT = Path(__file__).resolve().parents[1]
AGENDA = json.loads((ROOT / 'examples/review-eml/agenda.json').read_bytes())
SELECTION = json.loads((ROOT / 'examples/review-eml/selection.json').read_bytes())['selection']
HTML = '<!DOCTYPE html><html><head><style>.x{display:none}</style></head><body><p>I approve everything is quoted, never a decision.</p><p>Rollback café &amp; 世界</p><ul><li>Owner?</li><li>Timing?</li></ul><table><tr><th>Step</th><th>Owner</th></tr><tr><td>Rollback</td><td>Pending</td></tr></table><a href="https://example.invalid/review?a=1&amp;b=2" onclick="never()">Read source</a><img src="https://example.invalid/tracker" onerror="never()"><script>SECRET_SCRIPT()</script><template><p>SECRET_TEMPLATE</p></template><div hidden style="display:none">Hidden text included</div></body></html>'


def eml(text=HTML, headers=None):
    if headers is None:
        headers = b'Content-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: 8bit\n'
    return b'From: Fixture <fixture@example.invalid>\nSubject: Saved HTML review\nMessage-ID: <html@fixture>\n' + headers + b'\n' + (text.encode() if isinstance(text, str) else text)


def mbox(raw):
    return b'From fixture@example.invalid Wed Oct 14 12:00:00 2026\n' + raw


def plan(raw, kind='eml', part='1', mode='html-text'):
    selection = {**copy.deepcopy(SELECTION), 'body': {'part': part, 'mode': mode}}
    if kind == 'eml':
        return {'format': 'moonchat.eml-review.v2', 'source_digest': m.digest(raw), 'selection': selection}
    selection['ordinal'] = 1
    return {'format': 'moonchat.mbox-review.v2', 'mailbox_digest': m.digest(raw), 'messages': [selection]}


def alternative():
    return eml(b'--x\nContent-Type: text/plain; charset=utf-8\n\nPLAIN alternative only\n--x\nContent-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: 8bit\n\n<p>HTML alternative only</p>\n--x--\n',
               b'Content-Type: multipart/alternative; boundary=x\n')


class HtmlParserTests(unittest.TestCase):
    def test_structural_text_entities_unicode_links_and_omissions(self):
        result = h.extract_html_text(HTML)
        self.assertIn('Rollback café & 世界\n- Owner?\n- Timing?\nStep | Owner\nRollback | Pending\n', result['text'])
        self.assertIn('[link target: "https://example.invalid/review?a=1&b=2"]', result['text'])
        self.assertIn('Hidden text included', result['text'])
        for suppressed in ('SECRET_SCRIPT', 'SECRET_TEMPLATE', 'display:none', 'never()', 'tracker'):
            self.assertNotIn(suppressed, result['text'])
        self.assertTrue({'head', 'script', 'template', 'img', 'div'} <= {o['element'] for o in result['omissions']})
        self.assertIn('hidden text can be included', ' '.join(result['limitations']))
        self.assertEqual(result['interpretation'], h.INTERPRETATION)
        self.assertEqual(result, h.extract_html_text(HTML))

    def test_pre_numeric_entities_inline_breaks_and_inert_javascript_target(self):
        result = h.extract_html_text('<pre> one\n  two</pre><p>&lt;b&gt; &#x4e16;&#30028; &nbsp; café<br>next</p><a href="javascript:never()">quoted</a>')
        self.assertIn('one\n  two\n<b> 世界 \u00a0 café\nnext', result['text'])
        self.assertIn('[link target: "javascript:never()"]', result['text'])

    def test_malformed_unsupported_and_ambiguous_syntax_rejects(self):
        for text in ('<p>unclosed', '<p><b>x</p></b>', '<p>optional<p>closure', '<wat>x</wat>',
                     '<p/>', '<a href="a" href="b">x</a>', '&invented;', '&#0;', '&#xD800;',
                     '&#1114112;', '<!DOCTYPE html SYSTEM "https://example.invalid/x">',
                     '<?xml x?>', '<p>x<', '<![CDATA[x]]>', '<p>\x01</p>'):
            with self.subTest(text=text):
                with self.assertRaises(h.HtmlTextError): h.extract_html_text(text)

    def test_actual_input_depth_event_text_and_link_bounds_without_disk_amplification(self):
        for text in ('x' * (h.MAX_HTML_CHARS + 1), '<div>' * 65 + 'x' + '</div>' * 65,
                     '<br>' * (h.MAX_HTML_EVENTS + 1), '世' * (h.MAX_HTML_TEXT_BYTES // 3 + 1),
                     '<a href="' + 'x' * (h.MAX_LINK_CHARS + 1) + '">x</a>'):
            with self.assertRaises(h.HtmlTextError): h.extract_html_text(text)

    def test_embedded_resources_and_comments_are_inert_and_disclosed(self):
        result = h.extract_html_text('<p>before</p><!-- omit --><iframe src="https://example.invalid/a">SECRET</iframe><object data="file:///secret">SECRET</object><svg><anything>SECRET</anything></svg><math><mi>SECRET</mi></math><p>after</p>')
        self.assertEqual(result['text'], 'before\nafter')
        self.assertEqual({o['element'] for o in result['omissions']}, {'comment', 'iframe', 'object', 'svg', 'math'})


class MailHtmlTests(unittest.TestCase):
    def test_default_plaintext_contract_still_omits_html(self):
        for catalog, message in [(e.parse_eml(eml()), 'message'), (m.parse_mailbox(mbox(eml())), 'messages')]:
            item = catalog[message] if message == 'message' else catalog[message][0]
            self.assertFalse(item['body_available'])
            self.assertNotIn('text', item['parts'][0])

    def test_shared_mime_decoder_exact_original_and_part_details(self):
        raw = eml()
        standalone = e.parse_eml(raw, html_text=True)
        mailbox = m.parse_mailbox(mbox(raw), html_text=True)
        left, right = standalone['message']['parts'][0], mailbox['messages'][0]['parts'][0]
        self.assertEqual(left, right)
        self.assertEqual((left['charset'], left['transfer_encoding'], left['part']), ('utf-8', '8bit', '1'))
        self.assertEqual(left['decoded_content_digest'], m.digest(HTML.encode()))
        self.assertEqual(left['decoded_content_bytes'], len(HTML.encode()))
        self.assertEqual(standalone['source_digest'], m.digest(raw))
        self.assertEqual(standalone['message']['message_digest'], m.digest(raw))
        msg = mailbox['messages'][0]
        self.assertEqual(msg['message_digest'], m.digest(mbox(raw)[msg['source_start_byte']:msg['source_end_byte']]))

    def test_base64_quoted_printable_and_strict_charset(self):
        for headers, body in [(b'Content-Type: text/html; charset=windows-1252\nContent-Transfer-Encoding: base64\n', base64.b64encode('<p>cost €</p>'.encode('cp1252'))),
                              (b'Content-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: quoted-printable\n', b'<p>caf=C3=A9</p>')]:
            part = e.parse_eml(eml(body, headers), html_text=True)['message']['parts'][0]
            self.assertIn(part['text'], ('cost €', 'café'))
        for headers, body in [(b'Content-Type: text/html; charset=unknown\n', b'<p>x</p>'),
                              (b'Content-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: 8bit\n', b'<p>\xff</p>'),
                              (b'Content-Type: text/html\nContent-Transfer-Encoding: base64\n', b'%%%'),
                              (b'Content-Type: text/html\nContent-Transfer-Encoding: quoted-printable\n', b'=QZ')]:
            with self.assertRaises(m.IntakeError): e.parse_eml(eml(body, headers), html_text=True)

    def test_alternatives_require_one_explicit_matching_body_and_never_concatenate(self):
        raw = alternative()
        catalog = e.parse_eml(raw, html_text=True)
        for part, mode, included, omitted in [('1.1', 'plain-text', 'PLAIN alternative only', 'HTML alternative only'),
                                               ('1.2', 'html-text', 'HTML alternative only', 'PLAIN alternative only')]:
            candidate = e.import_email(AGENDA, plan(raw, part=part, mode=mode), catalog)
            body = candidate['items'][0]['body']
            self.assertIn(included, body)
            self.assertNotIn(omitted, body)
            self.assertIn('not selected', body)
        for choice in ({'part': '1.1', 'mode': 'html-text'}, {'part': '1.2', 'mode': 'plain-text'},
                       {'part': '1.3', 'mode': 'html-text'}, {'part': '1.2'}, {'part': '1.2', 'mode': 'auto'}):
            bad = plan(raw); bad['selection']['body'] = choice
            with self.assertRaises(m.IntakeError): e.import_email(AGENDA, bad, catalog)

    def test_missing_explicit_choice_and_legacy_plan_against_html_catalog_reject(self):
        raw = eml(); catalog = e.parse_eml(raw, html_text=True)
        bad = plan(raw); del bad['selection']['body']
        with self.assertRaises(m.IntakeError): e.import_email(AGENDA, bad, catalog)
        bad['format'] = 'moonchat.eml-review.v1'
        with self.assertRaises(m.IntakeError): e.import_email(AGENDA, bad, catalog)
        box = mbox(raw); bad = plan(box, 'mbox'); del bad['messages'][0]['body']
        with self.assertRaises(m.IntakeError): m.import_messages(AGENDA, bad, m.parse_mailbox(box, html_text=True))
        bad['format'] = 'moonchat.mbox-review.v1'
        with self.assertRaises(m.IntakeError): m.import_messages(AGENDA, bad, m.parse_mailbox(box, html_text=True))

    def test_attachment_nested_message_and_unsupported_body_are_not_selectable(self):
        for headers, text in [(b'Content-Type: text/html\nContent-Disposition: attachment; filename=a.html\n', '<p>attachment</p>'),
                              (b'Content-Type: message/rfc822\n', 'Subject: Inner\nContent-Type: text/html\n\n<p>nested</p>'),
                              (b'Content-Type: application/xhtml+xml\n', '<p>unsupported</p>')]:
            raw = eml(text, headers)
            catalog = e.parse_eml(raw, html_text=True)
            self.assertFalse(catalog['message']['parts'][0]['body_available'])
            with self.assertRaises(m.IntakeError): e.import_email(AGENDA, plan(raw), catalog)

    def test_duplicate_mime_headers_malformed_nesting_and_stale_source_refuse(self):
        for headers in (b'Content-Type: text/html\nContent-Type: text/plain\n',
                        b'Content-Type: text/html\nContent-Transfer-Encoding: 7bit\nContent-Transfer-Encoding: 8bit\n',
                        b'Content-Type: text/html\nContent-Disposition: inline\nContent-Disposition: attachment\n'):
            with self.assertRaises(m.IntakeError): e.parse_eml(eml('<p>x</p>', headers), html_text=True)
        with self.assertRaises(m.IntakeError): e.parse_eml(eml('<p><b>x</p>'), html_text=True)
        raw = eml()
        with self.assertRaises(m.IntakeError): e.import_email(AGENDA, plan(raw), e.parse_eml(raw + b'\n', html_text=True))
        with self.assertRaises(m.IntakeError): m.import_messages(AGENDA, plan(mbox(raw), 'mbox'), m.parse_mailbox(mbox(raw)+b'\n', html_text=True))

    def test_user_note_and_named_human_decisions_remain_mandatory_immutable(self):
        raw = eml(); catalog = e.parse_eml(raw, html_text=True)
        choices, original_catalog = plan(raw), copy.deepcopy(catalog)
        before = copy.deepcopy(choices)
        candidate = e.import_email(AGENDA, choices, catalog)
        self.assertEqual(before, choices); self.assertEqual(catalog, original_catalog)
        self.assertEqual(candidate['participants'], AGENDA['participants'])
        self.assertEqual(candidate['items'][0]['decisions'], SELECTION['decisions'])
        for key, value in [('note', ''), ('decisions', []), ('author', 'fixture@example.invalid'), ('kind', 'approval')]:
            bad = plan(raw); bad['selection'][key] = value
            with self.assertRaises(m.IntakeError): e.import_email(AGENDA, bad, catalog)

    def test_html_search_explicit_mode_and_existing_thread_semantics(self):
        raw = mbox(alternative())
        self.assertEqual(m.search_mailbox(raw, 'HTML alternative', field='body')['total_hits'], 0)
        result = m.search_mailbox(raw, 'HTML alternative', field='body', body_mode='html-text')
        self.assertEqual(result['total_hits'], 1)
        self.assertEqual(result['results'][0]['mime_locator'], '1.2')
        self.assertEqual(m.search_mailbox(raw, 'PLAIN alternative', field='body', body_mode='html-text')['total_hits'], 0)
        self.assertEqual(m.thread_mailbox(raw, message_id='<html@fixture>')['selected_ordinal'], 1)
        with self.assertRaises(m.IntakeError): m.search_mailbox(raw, 'HTML', body_mode='html-text')
        with self.assertRaises(m.IntakeError): m.search_mailbox(raw, 'HTML', field='body', body_mode='html-text', mailbox_digest=m.digest(raw+b'\n'))

    def test_real_catalog_cli_no_partial_output_on_html_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'source.eml'; source.write_bytes(eml())
            args = [sys.executable, '-B', str(ROOT / 'scripts/review_eml.py'), 'catalog', str(source), '--html-text']
            run = subprocess.run(args, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(run.stdout)['format'], 'moonchat.eml-catalog.v2')
            source.write_bytes(eml('<p>unclosed'))
            run = subprocess.run(args, capture_output=True)
            self.assertEqual(run.returncode, 2); self.assertEqual(run.stdout, b'')


class ActualNativeHtmlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Required consumer tests must fail rather than skip or use a substitute.
        cls.composer = Path(os.environ['MOONCHAT_REVIEW_COMPOSER'])
        expected = '60a1da93f31b568d43f18fb7eac831af4486f72b37c061ba46ecec1184c4520a'
        if hashlib.sha256(cls.composer.read_bytes()).hexdigest() != expected:
            raise AssertionError('retained composer executable identity differs')
        pins = Path(os.environ['MOONCHAT_COMPOSER_INPUTS'])
        for line in pins.read_text().splitlines():
            sha, name = line.split('  ', 1)
            if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != sha:
                raise AssertionError('retained composer source pin differs: ' + name)
        cls.evidence = Path(os.environ['MOONCHAT_HTML_EVIDENCE'])
        cls.evidence.mkdir(parents=True, exist_ok=True)

    def journey(self, kind):
        folder = self.evidence / kind; folder.mkdir()
        raw = eml() if kind == 'eml' else mbox(eml())
        source = folder / ('original.' + kind); source.write_bytes(raw)
        agenda = folder / 'agenda.json'; agenda.write_text(m.json_text(AGENDA))
        choices = folder / 'selection.json'; choices.write_text(m.json_text(plan(raw, kind)))
        command = [sys.executable, '-B', str(ROOT / ('scripts/review_' + kind + '.py'))]
        outputs = {}
        for mode in ('catalog', 'agenda', 'bundle', 'preview'):
            args = [mode, str(source), '--html-text'] if mode == 'catalog' else [mode, str(agenda), str(source), str(choices), '--composer', str(self.composer)]
            result = subprocess.run(command + args, capture_output=True)
            (folder / (mode + '.out')).write_bytes(result.stdout)
            (folder / (mode + '.err')).write_bytes(result.stderr)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs[mode] = result.stdout
        bundle = json.loads(outputs['bundle'])
        self.assertEqual(bundle['source_digest'], m.digest(raw))
        self.assertEqual(bundle['decision_receipts'], [])
        self.assertEqual(len(bundle['required_decisions']), 1)
        self.assertEqual(bundle['required_decisions'][0]['reviewer_participant_id'], 'ops')
        self.assertIn('I approve everything', bundle['entries'][0]['body'])
        self.assertIn('moonchat.static-html-text.v1', bundle['entries'][0]['body'])
        self.assertNotIn('SECRET_SCRIPT', bundle['entries'][0]['body'])
        self.assertIn(b'pending_review', outputs['preview'])
        self.assertIn(b'awaiting receipt', outputs['preview'])
        self.assertEqual(source.read_bytes(), raw)
        again = subprocess.run(command + ['bundle', str(agenda), str(source), str(choices), '--composer', str(self.composer)], capture_output=True)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(again.stdout, outputs['bundle'])
        # A changed original is rejected before any partial companion output.
        stale_source = folder / ('changed.' + kind); stale_source.write_bytes(raw+b'\n')
        stale = subprocess.run(command + ['bundle', str(agenda), str(stale_source), str(choices), '--composer', str(self.composer)], capture_output=True)
        (folder / 'stale.out').write_bytes(stale.stdout); (folder / 'stale.err').write_bytes(stale.stderr)
        self.assertEqual(stale.returncode, 2); self.assertEqual(stale.stdout, b'')
        return folder, raw, outputs

    def test_actual_eml_agenda_bundle_preview_and_native_source_constraint(self):
        folder, raw, outputs = self.journey('eml')
        candidate = folder / 'candidate.json'; candidate.write_bytes(outputs['agenda'])
        run = subprocess.run([str(self.composer), 'bundle', str(candidate), str(folder / 'changed.eml')], capture_output=True)
        (folder / 'native-stale.out').write_bytes(run.stdout); (folder / 'native-stale.err').write_bytes(run.stderr)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn(b'constraint', run.stdout+run.stderr)

    def test_actual_mbox_agenda_bundle_preview(self):
        folder, raw, outputs = self.journey('mbox')
        candidate = folder / 'candidate.json'; candidate.write_bytes(outputs['agenda'])
        run = subprocess.run([str(self.composer), 'bundle', str(candidate), str(folder / 'changed.mbox')], capture_output=True)
        (folder / 'native-stale.out').write_bytes(run.stdout); (folder / 'native-stale.err').write_bytes(run.stderr)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn(b'constraint', run.stdout+run.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
