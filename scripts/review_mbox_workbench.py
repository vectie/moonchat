#!/usr/bin/env python3
"""Local, snapshot-bound mailbox review selection workbench (no live accounts)."""
from __future__ import annotations
import argparse
import copy
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import secrets
import subprocess
import sys
import review_mbox as m

ASSETS = Path(__file__).with_name('review_mbox_workbench')
MAX_REQUEST = 1024 * 1024
DRAFT_FORMAT = 'moonchat.mailbox-review-draft.v1'


def agenda_digest(agenda):
    """Bind every agenda field, independent of JSON whitespace/object key order."""
    return m.digest(json.dumps(agenda, sort_keys=True, ensure_ascii=False,
                               separators=(',', ':'), allow_nan=False).encode('utf-8'))


class Workbench:
    def __init__(self, agenda, raw, composer, native_lock):
        m.check_shape({k: v for k, v in agenda.items() if k != 'source_digest_constraint'})
        m.require(composer.is_absolute() and composer.is_file(), 'name an absolute trusted composer executable')
        m.require(native_lock.is_absolute(), 'native lock must be absolute')
        self.agenda, self.raw = copy.deepcopy(agenda), bytes(raw)
        self.composer, self.native_lock = composer, native_lock
        self.catalog = m.parse_mailbox(self.raw)
        self.attachments = None
        self.bundle = None
        self.draft = None
        self.token = secrets.token_urlsafe(32)

    def state(self, attachments=False):
        if attachments and self.attachments is None:
            self.attachments = m.parse_mailbox(self.raw, attachment_text=True)
        return {'agenda': self.agenda, 'catalog': self.attachments if attachments else self.catalog,
                'attachment_opt_in': attachments, 'agenda_digest': agenda_digest(self.agenda)}

    def validate_draft(self, document):
        """Check identity and editable structure, without requiring completed review fields.

        Drafts carry locators and curator edits, never decoded mail, consent,
        approvals, a preview, or a server capability. Import is all-or-nothing.
        """
        m.require(isinstance(document, dict) and set(document) ==
                  {'format', 'agenda_digest', 'mailbox_digest', 'selections'}, 'invalid draft fields')
        m.require(document['format'] == DRAFT_FORMAT, 'unsupported draft format; expected ' + DRAFT_FORMAT)
        m.require(document['agenda_digest'] == agenda_digest(self.agenda), 'draft agenda digest differs')
        m.require(document['mailbox_digest'] == self.catalog['mailbox_digest'], 'draft mailbox digest differs')
        choices = document['selections']
        m.require(isinstance(choices, list) and len(choices) <= 100, 'draft allows 0–100 selected items')
        people = {p['participant_id'] for p in self.agenda['participants']}
        humans = {p['participant_id'] for p in self.agenda['participants'] if p['participant_kind'] == 'human'}
        seen = set()
        for choice in choices:
            m.require(isinstance(choice, dict), 'draft selection must be an object')
            name = 'attachment' if 'attachment' in choice else 'body'
            m.require(set(choice) == {'ordinal', 'key', 'kind', 'author', 'note', 'decisions', name}, 'invalid draft selection fields')
            ordinal = choice['ordinal']
            m.require(type(ordinal) is int and 1 <= ordinal <= len(self.catalog['messages']), 'draft message ordinal is unavailable')
            locator = choice[name]
            m.require(isinstance(locator, dict) and set(locator) == {'part', 'mode'} and
                      isinstance(locator['part'], str), 'invalid draft MIME locator')
            m.require(locator['mode'] == ('plain-text-attachment' if name == 'attachment' else 'plain-text'), 'unsupported draft selection mode')
            parts = [p for p in self.catalog['messages'][ordinal - 1]['parts'] if p['part'] == locator['part']]
            m.require(len(parts) == 1 and parts[0]['content_type'] == 'text/plain' and
                      (parts[0]['disposition'] == 'attachment' if name == 'attachment' else parts[0]['body_available']),
                      'draft MIME part is unavailable or unsupported')
            identity = (ordinal, name, locator['part'])
            m.require(identity not in seen, 'duplicate draft message/part selection')
            seen.add(identity)
            m.require(all(isinstance(choice[k], str) for k in ('key', 'kind', 'author', 'note')), 'draft edit fields must be text')
            m.require(choice['kind'] in ('question', 'objection', 'proposal'), 'unsupported draft review kind')
            m.require(choice['author'] in people or choice['author'] == '', 'draft curator author is unknown')
            decisions = choice['decisions']
            m.require(isinstance(decisions, list) and len(decisions) <= 100, 'draft allows at most 100 requests per item')
            for decision in decisions:
                m.require(isinstance(decision, dict) and set(decision) == {'reviewer', 'prompt'} and
                          all(isinstance(decision[k], str) for k in ('reviewer', 'prompt')), 'invalid draft pending request')
                m.require(decision['reviewer'] in humans or decision['reviewer'] == '', 'draft reviewer must be an existing human')
        # Bound the portable output as well as the incoming HTTP representation.
        m.require(len(m.json_text(document).encode('utf-8')) <= MAX_REQUEST, 'draft exceeds 1 MiB')
        return copy.deepcopy(document)

    def save_draft(self, document):
        self.bundle = None
        self.draft = None
        checked = self.validate_draft(document)
        self.draft = m.json_text(checked).encode('utf-8')
        return {'draft_digest': hashlib.sha256(self.draft).hexdigest(),
                'status': 'Draft prepared. Download the file to keep your unfinished edits.'}

    def open_draft(self, document):
        self.bundle = None
        self.draft = None
        checked = self.validate_draft(document)
        return {'selections': checked['selections'],
                'status': 'Draft reopened. Review your edits and preview again. Inspect attachments explicitly before including them.'}

    def preview(self, request):
        # Failed or superseded previews never leave a downloadable older result.
        self.bundle = None
        m.require(isinstance(request, dict) and set(request) == {'mailbox_digest', 'selections'}, 'invalid preview fields')
        m.require(request['mailbox_digest'] == self.catalog['mailbox_digest'], 'mailbox digest differs')
        choices = request['selections']
        m.require(isinstance(choices, list) and 1 <= len(choices) <= 100, 'select 1–100 explicit items')
        candidate = copy.deepcopy(self.agenda)
        seen = set()
        for choice in choices:
            m.require(isinstance(choice, dict), 'selection must be an object')
            is_attachment = 'attachment' in choice
            locator = choice.get('attachment' if is_attachment else 'body')
            m.require(isinstance(locator, dict), 'select an explicit MIME part')
            m.require(is_attachment or locator.get('mode') == 'plain-text', 'HTML selection is unavailable')
            identity = (choice.get('ordinal'), 'attachment' if is_attachment else 'body', locator.get('part'))
            m.require(all(isinstance(x, (str, int)) for x in identity), 'invalid selection identity')
            m.require(identity not in seen, 'duplicate message/part selection')
            seen.add(identity)
            m.require(not is_attachment or self.attachments is not None, 'inspect text attachments explicitly first')
            plan = {'format': 'moonchat.mbox-review.v4' if is_attachment else 'moonchat.mbox-review.v2',
                    'mailbox_digest': request['mailbox_digest'], 'messages': [choice]}
            candidate = m.import_messages(candidate, plan, self.attachments if is_attachment else self.catalog)
        m.require(len(m.json_text(candidate).encode('utf-8')) <= m.MAX_IMPORTED, 'candidate exceeds 8 MiB')
        # One shared lock covers both native executions, with no rebuild.
        with self.native_lock.open('a+b') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            preview = m.compile_candidate(candidate, self.raw, self.composer, 'preview')
            bundle = m.compile_candidate(candidate, self.raw, self.composer, 'bundle').encode('utf-8')
        parsed = m.load_json(bundle)
        m.require(parsed.get('decision_receipts') == [], 'composer returned non-pending decision receipts')
        self.bundle = bundle
        return {'preview': preview, 'bundle_digest': hashlib.sha256(bundle).hexdigest(),
                'selected_count': len(choices), 'status': 'pending; no human decisions recorded'}


def server_for(workbench, port=0):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *args):
            pass  # Do not log capability URLs or private mailbox material.

        def reply(self, code, body, content_type='application/json; charset=utf-8', download=None):
            if not isinstance(body, bytes):
                body = body.encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
            if download:
                self.send_header('Content-Disposition', 'attachment; filename="' + download + '"')
            self.end_headers()
            self.wfile.write(body)

        def route(self):
            origin = 'http://127.0.0.1:' + str(self.server.server_port)
            if self.headers.get('Host') != origin[7:]:
                raise m.IntakeError('invalid loopback Host')
            if self.headers.get('Origin') not in (None, origin):
                raise m.IntakeError('cross-origin request refused')
            if self.headers.get('Sec-Fetch-Site') not in (None, 'same-origin', 'none'):
                raise m.IntakeError('cross-site request refused')
            prefix = '/' + workbench.token + '/'
            m.require(self.path.startswith(prefix), 'unknown session')
            return self.path[len(prefix):]

        def do_GET(self):
            try:
                route = self.route()
                assets = {'': ('index.html', 'text/html; charset=utf-8'),
                          'app.js': ('app.js', 'text/javascript; charset=utf-8'),
                          'style.css': ('style.css', 'text/css; charset=utf-8')}
                if route in assets:
                    name, kind = assets[route]
                    self.reply(200, (ASSETS / name).read_bytes(), kind)
                elif route == 'catalog':
                    self.reply(200, m.json_text(workbench.state()))
                elif route.startswith('bundle/') and workbench.bundle is not None and route == 'bundle/' + hashlib.sha256(workbench.bundle).hexdigest():
                    self.reply(200, workbench.bundle, download='pending-review.json')
                elif route.startswith('draft/') and workbench.draft is not None and route == 'draft/' + hashlib.sha256(workbench.draft).hexdigest():
                    self.reply(200, workbench.draft, download='unfinished-mailbox-review.json')
                else:
                    self.reply(404, '{"error":"not found or preview unavailable"}')
            except (m.IntakeError, OSError, ValueError) as error:
                self.reply(400, m.json_text({'error': str(error)}))

        def do_POST(self):
            try:
                route = self.route()
                m.require(self.headers.get('Content-Type') == 'application/json', 'JSON content type required')
                m.require(self.headers.get('Transfer-Encoding') is None, 'chunked requests unsupported')
                length = int(self.headers.get('Content-Length', '0'))
                m.require(0 < length <= MAX_REQUEST, 'request exceeds 1 MiB or is empty')
                request = m.load_json(self.rfile.read(length))
                if route == 'attachments':
                    m.require(request == {'inspect': True}, 'explicit attachment inspection required')
                    result = workbench.state(attachments=True)
                elif route == 'preview':
                    result = workbench.preview(request)
                elif route == 'draft/save':
                    result = workbench.save_draft(request)
                elif route == 'draft/open':
                    result = workbench.open_draft(request)
                elif route == 'invalidate':
                    m.require(request == {}, 'invalid invalidation request')
                    workbench.bundle = None
                    workbench.draft = None
                    result = {'status': 'preview and draft downloads revoked'}
                else:
                    self.reply(404, '{"error":"unknown action"}')
                    return
                self.reply(200, m.json_text(result))
            except (m.IntakeError, OSError, ValueError, TypeError, UnicodeError, subprocess.TimeoutExpired) as error:
                if self.path.endswith(('/preview', '/draft/save', '/draft/open', '/invalidate')):
                    workbench.bundle = None
                    workbench.draft = None
                self.reply(400, m.json_text({'error': str(error)}))

    server = HTTPServer(('127.0.0.1', port), Handler)
    server.timeout = 1
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('agenda', type=Path)
    parser.add_argument('mailbox', type=Path)
    parser.add_argument('--composer', required=True, type=Path)
    parser.add_argument('--native-lock', required=True, type=Path)
    parser.add_argument('--port', default=0, type=int)
    args = parser.parse_args(argv)
    try:
        workbench = Workbench(m.load_json(m.read_bounded(args.agenda)), m.read_bounded(args.mailbox), args.composer, args.native_lock)
        with server_for(workbench, args.port) as server:
            print('Open your local browser: http://127.0.0.1:' + str(server.server_port) + '/' + workbench.token + '/', flush=True)
            print('Frozen local snapshots. Stop with Ctrl-C. Pending evidence only.', flush=True)
            server.serve_forever()
        return 0
    except KeyboardInterrupt:
        return 0
    except (m.IntakeError, OSError, ValueError) as error:
        print('review-mbox-workbench: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
