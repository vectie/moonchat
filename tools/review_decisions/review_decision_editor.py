#!/usr/bin/env python3
"""Produce an offline, unverified choice editor from an exact native prepare form."""
from __future__ import annotations
import argparse
import base64
import hashlib
import html
import json
from pathlib import Path
import subprocess
import tempfile

MAX_BYTES = 2 * 1024 * 1024


class EditorError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise EditorError(message)


def read_input(path):
    with Path(path).open('rb') as stream:
        data = stream.read(MAX_BYTES + 1)
    require(0 < len(data) <= MAX_BYTES, 'each input must contain 1 byte through 2 MiB')
    return data


def strict_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key: ' + key)
            result[key] = value
        return result
    try:
        value = json.loads(data.decode('utf-8'), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(EditorError('non-finite JSON')))
        json.dumps(value, ensure_ascii=False, allow_nan=False).encode('utf-8')
        require(isinstance(value, dict), 'expected JSON object')
        return value
    except (ValueError, UnicodeError, RecursionError) as error:
        raise EditorError('invalid bounded UTF-8 JSON: ' + str(error)) from error


def digest(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def script_json(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')


def page(form_bytes, bundle_bytes, source_bytes, decider):
    """The actual existing native prepare is the semantic authority, never a mock."""
    require(all(0 < len(raw) <= MAX_BYTES for raw in (form_bytes, bundle_bytes, source_bytes)),
            'each input must contain 1 byte through 2 MiB')
    form, bundle = strict_json(form_bytes), strict_json(bundle_bytes)
    reviewer = form.get('reviewer_participant_id')
    require(isinstance(reviewer, str) and reviewer, 'prepared form must name a reviewer')
    try:
        source_text = source_bytes.decode('utf-8')
    except UnicodeError as error:
        raise EditorError('source must be UTF-8 text; binary source display is unsupported') from error
    require(all(ord(c) >= 32 or c in '\n\r\t' for c in source_text), 'source contains unsupported text controls')
    # Immutable private snapshots prevent a concurrent original-file change from
    # making native validation cover different bytes from those in the page.
    with tempfile.TemporaryDirectory(prefix='moonchat-decisions-') as directory:
        root = Path(directory)
        (root / 'bundle.json').write_bytes(bundle_bytes)
        (root / 'source.txt').write_bytes(source_bytes)
        try:
            result = subprocess.run([str(Path(decider).resolve()), 'prepare', str(root / 'bundle.json'),
                                     str(root / 'source.txt'), reviewer], capture_output=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise EditorError('native prepare unavailable: ' + str(error)) from error
        require(result.returncode == 0, 'native prepare refused input: ' + result.stderr.decode('utf-8', errors='replace'))
        expected = strict_json(result.stdout)
    require(form == expected, 'form must equal a fresh native prepare with blank choices; reopen saved drafts in the page')
    require(form['source_digest'] == digest(source_bytes) and form['base_bundle_digest'] == digest(bundle_bytes),
            'native form input identity mismatch')
    require(0 < len(form['choices']) <= 200 and len(form['entries']) <= 2000,
            'editor supports at most 200 choices and 2000 discussion entries')
    bootstrap = {'form': form, 'prior_receipt_ids': [r['receipt_id'] for r in bundle['decision_receipts']]}
    script = '(function () {\n"use strict";\nconst input = ' + script_json(bootstrap) + ';\n' + Path(__file__).with_suffix('.js').read_text(encoding='utf-8') + '\n})();'
    style = 'body{font:17px system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#17283a;background:#f8fafc}h1,h2{line-height:1.2}pre{white-space:pre-wrap;overflow-wrap:anywhere;padding:1rem;background:#fff;border:1px solid #ccd6df}fieldset{margin:1.3rem 0;padding:1rem;border:2px solid #a5b7c8}label{display:block;margin:.6rem 0}input,textarea,select{display:block;font:inherit;box-sizing:border-box;max-width:100%;width:100%;padding:.45rem}button{font:inherit;padding:.5rem .8rem;margin:.3rem}.notice{padding:1rem;background:#fff0cb;border:2px solid #9a6200}a{color:#134d83}:focus-visible{outline:3px solid #174dab;outline-offset:3px}[hidden]{display:none!important}#status{white-space:pre-wrap}legend{font-weight:bold}'
    hash64 = lambda text: base64.b64encode(hashlib.sha256(text.encode()).digest()).decode()
    esc = lambda value: html.escape(str(value), quote=True)
    obj = lambda value: esc(json.dumps(value, ensure_ascii=False, indent=2))
    discussion = ''.join('<article id="entry-' + str(i) + '"><h3>' + esc(e['entry_kind']) + ' · ' + esc(e['entry_id']) + '</h3><pre>' + esc(e['body']) + '</pre><details><summary>Read-only entry metadata and evidence references</summary><pre>' + obj(e) + '</pre></details></article>' for i, e in enumerate(form['entries']))
    requests = '<pre>' + obj(bundle['required_decisions']) + '</pre>'
    receipts = '<pre>' + obj(bundle['decision_receipts']) + '</pre>'
    identity = {k: v for k, v in form.items() if k not in ('choices', 'entries')}
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'sha256-' + hash64(script) + '\'; style-src \'sha256-' + hash64(style) + '\'; connect-src \'none\'; img-src \'none\'; object-src \'none\'; base-uri \'none\'; form-action \'none\'">'
            '<title>MoonChat · Unverified named-decision draft</title><style>' + style + '</style></head><body>'
            '<h1>Named review decisions</h1><p class="notice">UNVERIFIED DRAFT. This page does not authenticate a reviewer, apply a decision, create a review receipt, or deliver approval. '
            'Typing a name, timestamp or receipt ID does not prove who decided. Downloaded forms require native preview and a separately authenticated host before any application.</p>'
            '<p>No network or automatic saving. Save your draft before closing. A requested download is not proof it was saved. The page contains the complete source and review; keep it private.</p>'
            '<nav><a href="#source">Read exact source</a> · <a href="#discussion">Read all discussion and objections</a> · <a href="#requests">Read named requests</a> · <a href="#choices">Enter choices</a></nav>'
            '<section><h2>Read-only scope and reviewer</h2><pre id="scope">' + obj(identity) + '</pre></section>'
            '<section id="source"><h2>Complete source text</h2><pre>' + esc(source_text) + '</pre></section>'
            '<section id="discussion"><h2>All discussion, including objections</h2>' + discussion + '</section>'
            '<section id="requests"><h2>All named review requests</h2>' + requests + '<h3>Participants (declared metadata)</h3><pre>' + obj(bundle['participants']) + '</pre>'
            '<h3>Prior receipts (historical bundle data; never reused as new choices)</h3>' + receipts + '</section>'
            '<section id="choices"><h2>Explicit choices for ' + esc(form['reviewer_name']) + '</h2>'
            '<p>All outcomes start blank. Leave every field blank to keep a request undecided. To record a draft choice, supply an explicit outcome, rationale, unique proposed receipt ID and UTC timestamp. Evidence references are optional and are not opened or verified.</p>'
            '<noscript>JavaScript is required for choice editing. Complete read-only review remains above.</noscript><div id="choice-list"></div>'
            '<p id="status" role="status" aria-live="polite">No decisions selected.</p>'
            '<button type="button" id="preview">Preview unverified choices</button><button type="button" id="export" disabled>Export native form.json</button>'
            '<button type="button" id="save">Save unverified draft</button><pre id="preview-text" aria-label="Unverified native form preview"></pre>'
            '<label for="reopen">Reopen saved draft (2 MiB maximum)<input id="reopen" type="file" accept="application/json,.json"></label>'
            '<label for="merge-file">Merge another partial draft for this reviewer (2 MiB maximum)<input id="merge-file" type="file" accept="application/json,.json"></label>'
            '<p>Reopen your first saved draft or edit it here, then select the second draft to merge. Both must come from this exact blank native form. Merging is staged; blank choices do not erase existing text. Resolve conflicting whole choices explicitly, then confirm the merge. Incomplete text can be merged and saved but cannot pass preview/export.</p>'
            '<section id="pending" hidden><h3 id="pending-title">Review draft import</h3><p id="pending-details"></p><pre id="pending-text"></pre><div id="conflicts"></div>'
            '<button type="button" id="replace" disabled>Replace with loaded draft</button><button type="button" id="merge" disabled>Merge resolved draft</button><button type="button" id="cancel">Cancel import</button></section></section>'
            '<script>' + script + '</script></body></html>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prepared_form', type=Path)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('source', type=Path)
    parser.add_argument('--decider', type=Path, required=True, help='trusted existing native review_decide executable')
    parser.add_argument('--output', type=Path, required=True, help='new HTML path; existing paths are never replaced')
    args = parser.parse_args()
    try:
        result = page(read_input(args.prepared_form), read_input(args.bundle), read_input(args.source), args.decider)
        with args.output.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(result)
    except (EditorError, OSError) as error:
        parser.exit(1, 'review_decision_editor: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
