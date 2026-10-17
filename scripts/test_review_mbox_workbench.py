"""Actual loopback HTTP and production DOM controller/native composer tests."""
import copy
import hashlib
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from urllib.parse import urlsplit
import review_mbox as m
import review_mbox_workbench as w
from test_review_mail_attachment import eml, mbox

ROOT = Path(__file__).resolve().parents[1]
AGENDA = json.loads((ROOT / 'examples/review-mbox/agenda.json').read_bytes())
RAW = mbox(eml())
COMPOSER = os.environ.get('MOONCHAT_REVIEW_COMPOSER')
LOCK = os.environ.get('MOONCHAT_NATIVE_LOCK')


def choice(attachment=False, key='mail-review'):
    return {'ordinal': 1, 'key': key, 'kind': 'objection', 'author': 'assistant',
            'note': 'Curator asks for review; quoted claims are not approval.',
            'decisions': [{'reviewer': 'ops', 'prompt': 'Is rollback ownership clear?'}],
            'attachment' if attachment else 'body': {'part': '1.2' if attachment else '1.1',
                                                   'mode': 'plain-text-attachment' if attachment else 'plain-text'}}


def draft(choices=None):
    return {'format': w.DRAFT_FORMAT, 'agenda_digest': w.agenda_digest(AGENDA),
            'mailbox_digest': m.digest(RAW), 'selections': [choice()] if choices is None else choices}


@unittest.skipUnless(COMPOSER and LOCK, 'set verified composer and shared native lock')
class WorkbenchTests(unittest.TestCase):
    def setUp(self):
        self.work = w.Workbench(AGENDA, RAW, Path(COMPOSER), Path(LOCK))
        self.server = w.server_for(self.work)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.prefix = '/' + self.work.token + '/'

    def tearDown(self):
        self.server.shutdown(); self.thread.join(); self.server.server_close()

    def request(self, path, payload=None, headers=None, prefix=True):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=10)
        body = None if payload is None else json.dumps(payload)
        supplied = {} if payload is None else {'Content-Type': 'application/json'}
        supplied.update(headers or {})
        connection.request('GET' if payload is None else 'POST', (self.prefix if prefix else '') + path, body=body, headers=supplied)
        response = connection.getresponse(); result = (response.status, response.read(), dict(response.getheaders()))
        connection.close(); return result

    def preview(self, choices=None):
        return self.request('preview', {'mailbox_digest': m.digest(RAW), 'selections': choices or [choice()]})

    def test_catalog_frozen_sources_and_safe_assets(self):
        code, raw, headers = self.request('catalog'); self.assertEqual(code, 200)
        catalog = json.loads(raw); self.assertEqual(catalog['agenda'], AGENDA)
        self.assertNotIn('text', catalog['catalog']['messages'][0]['parts'][1])
        self.assertEqual(headers['Cache-Control'], 'no-store')
        code, html, headers = self.request(''); self.assertEqual(code, 200)
        self.assertIn('frame-ancestors', headers['Content-Security-Policy'])
        self.assertNotIn(b'Rollback caf', html)
        for path in ('app.js', 'style.css'):
            self.assertEqual(self.request(path)[0], 200)

    def test_native_preview_and_exact_pending_bundle_download(self):
        code, raw, _ = self.preview(); self.assertEqual(code, 200, raw)
        result = json.loads(raw); self.assertIn('pending', result['preview'].lower())
        code, bundle, headers = self.request('bundle/' + result['bundle_digest'])
        self.assertEqual(code, 200); self.assertEqual(bundle, self.work.bundle)
        self.assertEqual(hashlib.sha256(bundle).hexdigest(), result['bundle_digest'])
        parsed = json.loads(bundle); self.assertEqual(parsed['decision_receipts'], [])
        self.assertEqual(parsed['source_digest'], m.digest(RAW))
        self.assertEqual(parsed['required_decisions'][-1]['reviewer_participant_id'], 'ops')
        self.assertIn('attachment;', headers['Content-Disposition'])
        self.assertEqual(self.work.agenda, AGENDA); self.assertEqual(self.work.raw, RAW)

    def test_mixed_reordered_evidence_and_explicit_attachment_opt_in(self):
        self.assertEqual(self.preview([choice(True)])[0], 400)
        code, raw, _ = self.request('attachments', {'inspect': True}); self.assertEqual(code, 200)
        self.assertTrue(json.loads(raw)['attachment_opt_in'])
        code, raw, _ = self.preview([choice(True, 'attachment-first'), choice(False, 'body-second')]); self.assertEqual(code, 200, raw)
        entries = json.loads(self.work.bundle)['entries']
        self.assertIn('Rollback', entries[-2]['body']); self.assertNotIn('UNSELECTED BODY', entries[-2]['body'])
        self.assertIn('UNSELECTED BODY', entries[-1]['body']); self.assertNotIn('Rollback', entries[-1]['body'])
        self.assertIn('<script>never()</script>', entries[-2]['body'])

    def test_invalid_preview_revokes_previous_download(self):
        code, raw, _ = self.preview(); self.assertEqual(code, 200)
        url = 'bundle/' + json.loads(raw)['bundle_digest']
        bad = choice(); bad['key'] = 'launch'
        self.assertEqual(self.preview([bad])[0], 400)
        self.assertEqual(self.request(url)[0], 404)

    def test_duplicate_unsupported_unknown_reviewer_and_stale_digest_rejected(self):
        for change in ('duplicate', 'html', 'reviewer', 'note', 'approval'):
            choices = [choice()]
            if change == 'duplicate': choices.append(choice(key='another'))
            elif change == 'html': choices[0]['body']['mode'] = 'html-text'
            elif change == 'reviewer': choices[0]['decisions'][0]['reviewer'] = 'assistant'
            elif change == 'note': choices[0]['note'] = ''
            else: choices[0]['approval'] = True
            with self.subTest(change=change): self.assertEqual(self.preview(choices)[0], 400)
        self.assertEqual(self.request('preview', {'mailbox_digest': m.digest(RAW+b'\n'), 'selections':[choice()]})[0], 400)

    def test_session_host_origin_content_type_and_path_boundaries(self):
        for headers in ({'Host':'evil.invalid'}, {'Origin':'https://evil.invalid'}, {'Sec-Fetch-Site':'cross-site'}):
            self.assertEqual(self.request('catalog',headers=headers)[0],400)
        self.assertEqual(self.request('/catalog',prefix=False)[0],400)
        self.assertEqual(self.request('../review_mbox.py')[0],404)
        self.assertEqual(self.request('attachments',{'inspect':True},{'Content-Type':'text/plain'})[0],400)
        self.assertEqual(self.request('attachments',{'inspect':False})[0],400)

    def test_native_rejection_yields_no_bundle(self):
        self.work.agenda['source_artifact_ref'] = '../outside.mbox'
        code, raw, _ = self.preview(); self.assertEqual(code,400)
        self.assertIn(b'native composer rejected',raw); self.assertIsNone(self.work.bundle)

    def test_request_bounds_and_existing_digest_constraint(self):
        self.assertEqual(self.request('preview', {}, {'Content-Length': str(w.MAX_REQUEST + 1)})[0], 400)
        self.assertEqual(self.request('preview', {'mailbox_digest':m.digest(RAW),'selections':[]})[0],400)
        self.assertEqual(self.request('preview', {'mailbox_digest':m.digest(RAW),'selections':[choice()]*101})[0],400)
        self.work.agenda['source_digest_constraint'] = m.digest(RAW+b'changed')
        code, raw, _ = self.preview(); self.assertEqual(code,400)
        self.assertIn(b'source digest constraint differs',raw)

    def test_actual_cli_launch_uses_frozen_local_snapshots(self):
        with tempfile.TemporaryDirectory(prefix='moonchat-workbench-test-') as folder:
            agenda, mailbox = Path(folder)/'agenda.json', Path(folder)/'snapshot.mbox'
            agenda.write_text(json.dumps(AGENDA)); mailbox.write_bytes(RAW)
            process = subprocess.Popen([sys.executable,'-B',str(ROOT/'scripts/review_mbox_workbench.py'),
                                        str(agenda),str(mailbox),'--composer',COMPOSER,'--native-lock',LOCK],
                                       stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                first = process.stdout.readline().strip(); self.assertTrue(first.startswith('Open your local browser: '),first)
                url = urlsplit(first.split(': ',1)[1]); self.assertEqual(url.hostname,'127.0.0.1')
                mailbox.write_bytes(RAW+b'new bytes'); agenda.write_text('{}')
                connection = http.client.HTTPConnection(url.hostname,url.port,timeout=10)
                connection.request('GET',url.path+'catalog'); response = connection.getresponse()
                self.assertEqual(response.status,200); state=json.loads(response.read()); connection.close()
                self.assertEqual(state['catalog']['mailbox_digest'],m.digest(RAW)); self.assertEqual(state['agenda'],AGENDA)
                self.assertEqual(mailbox.read_bytes(),RAW+b'new bytes'); self.assertEqual(agenda.read_text(),'{}')
            finally:
                process.terminate(); process.communicate(timeout=10)

    def test_production_dom_events_with_actual_loopback_and_composer(self):
        process = subprocess.run(['node',str(ROOT/'scripts/test_review_mbox_workbench_dom.cjs'),
                                  'http://127.0.0.1:' + str(self.server.server_port) + self.prefix],
                                 capture_output=True,text=True,timeout=60)
        self.assertEqual(process.returncode,0,process.stdout+process.stderr)
        self.assertIn('production DOM',process.stdout)

    def test_saved_unfinished_file_reopens_on_fresh_server_and_composes(self):
        attachment, body = choice(True, ''), choice(False, '')
        attachment['decisions'][0]['prompt'] = ''
        attachment['note'] = 'Unfinished café <script>never()</script>\nSecond line'
        body['note'] = ''; body['kind'] = 'question'
        document = draft([attachment, body])
        self.assertEqual(self.request('attachments', {'inspect':True})[0], 200)
        self.assertEqual(self.preview()[0], 200)
        old_bundle = 'bundle/' + hashlib.sha256(self.work.bundle).hexdigest()
        code, raw, _ = self.request('draft/save', document); self.assertEqual(code, 200, raw)
        self.assertEqual(self.request(old_bundle)[0], 404)
        code, saved, headers = self.request('draft/' + json.loads(raw)['draft_digest'])
        self.assertEqual(code, 200); self.assertEqual(json.loads(saved), document)
        self.assertIn('unfinished-mailbox-review.json', headers['Content-Disposition'])
        self.assertNotIn(b'UNSELECTED BODY', saved); self.assertNotIn(b'Rollback', saved)
        with tempfile.TemporaryDirectory(prefix='moonchat-draft-test-') as folder:
            path = Path(folder)/'unfinished.json'; path.write_bytes(saved)
            old_token = self.work.token
            self.tearDown(); self.setUp()
            self.assertNotEqual(self.work.token, old_token)
            code, raw, _ = self.request('draft/open', json.loads(path.read_bytes()))
            self.assertEqual(code, 200, raw); self.assertEqual(json.loads(raw)['selections'], document['selections'])
            self.assertIsNone(self.work.attachments); self.assertIsNone(self.work.bundle)
            state = json.loads(self.request('catalog')[1]); self.assertFalse(state['attachment_opt_in'])
            self.assertNotIn('text', state['catalog']['messages'][0]['parts'][1])
            edited = json.loads(raw)['selections']
            edited[0]['key']='attachment-first'; edited[0]['decisions'][0]['prompt']='Confirm ownership?'
            edited[1]['key']='body-second'; edited[1]['note']='Finished explicit curator note'
            self.assertEqual(self.preview(edited)[0], 400)
            self.assertEqual(self.request('attachments', {'inspect':True})[0], 200)
            code, raw, _ = self.preview(edited); self.assertEqual(code, 200, raw)
            bundle_bytes = self.request('bundle/' + json.loads(raw)['bundle_digest'])[1]
            bundle = json.loads(bundle_bytes)
            self.assertEqual(bundle['decision_receipts'], [])
            self.assertIn('Rollback', bundle['entries'][-2]['body'])
            self.assertIn('UNSELECTED BODY', bundle['entries'][-1]['body'])
            self.assertEqual(bundle['entries'][-2]['entry_kind'], 'objection')
            self.assertEqual(bundle['entries'][-1]['entry_kind'], 'question')
            evidence = os.environ.get('MOONCHAT_WORKBENCH_EVIDENCE')
            if evidence:
                output = Path(evidence); output.mkdir(parents=True, exist_ok=False)
                (output/'saved-draft.json').write_bytes(saved)
                (output/'reopened-edited-selections.json').write_text(m.json_text(edited))
                (output/'reopened-preview.json').write_bytes(raw)
                (output/'reopened-bundle.json').write_bytes(bundle_bytes)
                (output/'agenda.json').write_text(m.json_text(AGENDA))
                (output/'snapshot.mbox').write_bytes(RAW)
        self.assertEqual(self.work.agenda, AGENDA); self.assertEqual(self.work.raw, RAW)

    def test_draft_binds_whole_agenda_and_mailbox_and_is_versioned(self):
        document = draft()
        equivalent = dict(reversed(list(AGENDA.items())))
        self.assertEqual(w.agenda_digest(equivalent), document['agenda_digest'])
        changed = copy.deepcopy(AGENDA); changed['participants'][0]['display_name'] += ' changed'
        different = w.Workbench(changed, RAW, Path(COMPOSER), Path(LOCK))
        with self.assertRaisesRegex(m.IntakeError, 'agenda digest differs'): different.open_draft(document)
        different = w.Workbench(AGENDA, RAW+b'\n', Path(COMPOSER), Path(LOCK))
        with self.assertRaisesRegex(m.IntakeError, 'mailbox digest differs'): different.open_draft(document)
        for field, value in [('format','moonchat.mailbox-review-draft.v2'), ('agenda_digest','sha256:other'),
                             ('mailbox_digest','sha256:other'), ('approval',True), ('attachment_opt_in',True)]:
            bad = copy.deepcopy(document); bad[field] = value
            with self.subTest(field=field): self.assertEqual(self.request('draft/open',bad)[0], 400)
        self.assertEqual(self.request('draft/open',document)[0], 200)

    def test_draft_retains_blank_edits_and_enforces_structure_and_memory_bounds(self):
        incomplete = choice(); incomplete.update(key='', author='', note='')
        incomplete['decisions'] = [{'reviewer':'','prompt':''}]
        self.assertEqual(self.work.validate_draft(draft([incomplete]))['selections'], [incomplete])
        self.assertEqual(self.request('draft/save',draft([]))[0], 200)
        self.assertEqual(self.request('draft/open',draft([]))[0], 200)
        variants = []
        for field, value in [('ordinal',True), ('ordinal',0), ('body',{'part':'1.99','mode':'plain-text'}),
                             ('body',{'part':'1.1','mode':'html-text'}), ('kind','decision'),
                             ('author','unknown'), ('note',None), ('approval',True),
                             ('decisions',[{'reviewer':'assistant','prompt':'Approve'}]),
                             ('decisions',[{'reviewer':'ops','prompt':'Approve','approved':True}]),
                             ('decisions',[{'reviewer':'ops','prompt':''}]*101)]:
            bad = choice(); bad[field] = value; variants.append(draft([bad]))
        variants.extend([draft([choice(),choice()]), draft([choice()]*101)])
        for bad in variants:
            with self.subTest(document=bad): self.assertEqual(self.request('draft/open',bad)[0], 400)
        huge = choice(); huge['note'] = 'x' * w.MAX_REQUEST
        with self.assertRaisesRegex(m.IntakeError,'1 MiB'): self.work.validate_draft(draft([huge]))

    def test_failed_open_save_and_malformed_json_revoke_prior_links(self):
        for route in ('draft/open','draft/save'):
            self.assertEqual(self.preview()[0], 200)
            old = 'bundle/' + hashlib.sha256(self.work.bundle).hexdigest()
            self.assertEqual(self.request(route,{'format':'unknown'})[0], 400)
            self.assertEqual(self.request(old)[0], 404)
        self.assertEqual(self.request('draft/save',draft())[0], 200)
        old = 'draft/' + hashlib.sha256(self.work.draft).hexdigest()
        self.assertEqual(self.request('draft/open',{})[0], 400)
        self.assertEqual(self.request(old)[0], 404)
        connection = http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=10)
        connection.request('POST',self.prefix+'draft/open',body='{"format":1,"format":2}',headers={'Content-Type':'application/json'})
        response = connection.getresponse(); self.assertEqual(response.status,400); response.read(); connection.close()

    def test_production_dom_save_reopen_into_fresh_controller(self):
        other = w.Workbench(AGENDA, RAW, Path(COMPOSER), Path(LOCK))
        with w.server_for(other) as server:
            thread = threading.Thread(target=server.serve_forever,daemon=True); thread.start()
            try:
                process = subprocess.run(['node',str(ROOT/'scripts/test_review_mbox_workbench_dom.cjs'),
                                          'http://127.0.0.1:'+str(self.server.server_port)+self.prefix,
                                          'http://127.0.0.1:'+str(server.server_port)+'/'+other.token+'/'],
                                         capture_output=True,text=True,timeout=60)
                self.assertEqual(process.returncode,0,process.stdout+process.stderr)
                self.assertIn('fresh controller draft',process.stdout)
            finally:
                server.shutdown(); thread.join()


if __name__ == '__main__':
    unittest.main(verbosity=2)
